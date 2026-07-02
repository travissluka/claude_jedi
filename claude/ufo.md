# UFO (Unified Forward Operators)

> Last updated against commit `45574b64` (2026-07-02). Run `cd bundle/ufo && git log --oneline 45574b64..HEAD` to see what changed since.
>
> **Covers:** ObsOperator, LinearObsOperator, CompositeObsOperator, GeoVaLs, SampledLocations, ObsFilters, ObsBias, ObsDiagnostics, ObsError (Diagonal/CrossVarCov/BiasCorrelated/WithinGroup), ObsLocalization (Hor/HorGC99/HorSOAR/VertLocalization), QCflags, ObsFunctions, variable transforms, FilterBase, QCmanager (see also `ufo-filter-lifecycle.md`), ObsTraits, CRTM/RTTOV integration.

## Overview

Mixed C++17/Fortran 2008 library providing observation operators, QC filters, bias correction, and related components for data assimilation. Source at `bundle/ufo/`.

UFO is not built standalone — it must be built as part of the bundle. Depends on: `oops`, `ioda`, `eckit`, `fckit`, `NetCDF`, `Eigen3`, `Boost`, `MPI`. Optional: `crtm`, `rttov`, `gsw`, `ropp-ufo`, `geos-aero`.

## Build and Tests

```bash
# Build only UFO targets
cmake --build build --target ufo -j$(nproc)

# Run all UFO tests
ctest --output-on-failure --test-dir build/ufo

# Run a single test (partial match)
ctest --output-on-failure --test-dir build/ufo -R <test_name>

# Exclude coding norms
ctest --output-on-failure --test-dir build/ufo -E 'coding_norms'

# List available tests
ctest --test-dir build/ufo -N
```

Tests are named: `ufo_test_tier1_<name>`.

## Coding Standards

- **C++**: Google style (`.clang-format`) with line length 100. Run cpplint: `tools/ufo_cpplint.py <file>`. Config in `CPPLINT.cfg` and `src/CPPLINT.cfg`.
- **Fortran**: Fortran 2008 standard, no extensions.
- Floating-point exception trapping enabled in tests by default (`OOPS_TRAPFPE=1`); disable per test with `NOTRAPFPE` in cmake.

## Architecture

### Core Abstractions (`src/ufo/`)

- **`ObsOperatorBase`** / **`ObsOperator`**: Base class and wrapper for forward operators (H(x)). Concrete operators register via a factory. Each operator also has a corresponding `LinearObsOperatorBase` for TL/AD.
- **`ObsFilterBase`** / **`ObsFilter`**: Base class for QC filters (observation quality control). Filters run in stages: `PRE`, `PRIOR`, or `POST` (relative to H(x) evaluation).
- **`ObsFilters`**: Container that runs all configured filters for an obs space. `QCmanager` (now `src/ufo/QCmanager.h`, no longer a filter and not factory-registered — ufo#4137) is held as a dedicated `qcmanager_` member that ObsFilters drives directly: `preSetQc()` before filters (mark missing obs), `postSetQc(hofx)` after POST filters (mark H(x) failures), `finalSetQc()` at the end (absorbed the deleted `FinalCheck` filter's duties).
- **`GeoVaLs`**: Model state interpolated to observation locations (C++ wrapper with Fortran implementation in `ufo_geovals_mod.F90`).
- **`ObsDiagnostics`**: Stores diagnostics produced by operators (e.g., for use by filters).
- **`ObsBias`** / **`ObsBiasOperator`**: Observation bias correction state and application.

### Observer Lifecycle

Within a DA run, each observation type goes through this pipeline:
1. **preProcess** — filters with `filter stage: PRE` run (thinning, domain check, bounds check)
2. **getValues** — model state interpolated to obs locations → `GeoVaLs`
3. **priorFilter** — filters with `filter stage: PRIOR` run (background check, buddy check)
4. **simulateObs** — `ObsOperator::simulateObs(GeoVaLs)` computes H(x)
5. **postFilter** — filters with `filter stage: POST` run (uses departures)

Filters default to PRIOR stage. Explicitly set via `filter stage:` in YAML. Note: `DerivedObsValue` group variables overshadow `ObsValue` — if a variable transform writes to `DerivedObsValue/temperature`, that value is used instead of `ObsValue/temperature` for H(x) departures.

### Operators (`src/ufo/operators/`)

Each operator subdirectory (e.g., `crtm/`, `rttov/`, `gnssro/`, `identity/`, `vertinterp/`, `radarpolarimetric/`) contains a self-contained forward operator with optional TL/AD. Mixed C++/Fortran implementations are common — C++ calls Fortran via an `interface.F90` interop layer.

**PPRO** (`operators/radarpolarimetric/ppro/`, class `ObsPPRO`, PR #4107): the Parameterized Polarimetric Radar Operator computes dual-pol radar variables (Zhh / ZDR / KDP / ρhv) from model microphysics fields. YAML param `polarimetric operator` selects the forward model — `Zhang21` (exponential PSD, T-matrix; `Zhang21Forward`) or `TCWA2` (gamma PSD, Rayleigh; `TCWA2Forward`) — and `microphysics option` selects the scheme (Thompson default), with extensive melting / Dm-tuning params. Shared microphysics config lives in `operators/radarshared/` (`MicrophysicsOptions.h`, enum `MicrophysicsOption`), also used by `radarreflectivity/directZDA`.

**RTTOV interface**: The `rttov/` operator supports both RTTOV v13 and v14. The v14 interface is under `rttov/CPP/v14/` (C++ wrapper via `rttovcpp_interface.h`) and `rttov/Fortran/v14/` (Fortran modules: `ufo_radiancerttov_mod`, `ufo_radiancerttov_tlad_mod`, `ufo_radiancerttov_utils_mod`, `ufo_reconradop_mod`). Version selection is handled at build time.

**Composite operators** (`operators/compositeoper/`): `ObsComposite` splits simulated variables across multiple operators. Each component handles a disjoint variable subset; no overlap allowed. Configured as:
```yaml
obs operator:
  name: Composite
  components:
  - name: VertInterp
    variables: [relativeHumidity, windNorthward]
  - name: Identity
    variables: [surfacePressure]
```

**Meta-operators**: Operators that wrap or dispatch to other operators:
- **Composite** (`compositeoper/`): Splits variables across multiple operators (described above)
- **Categorical** (`categoricaloper/`): Selects different operators based on a categorical variable (e.g., surface type)
- **TimeInterpolation**: Interpolates H(x) in time between model states
- **DensityReduction**: Reduces observation density before applying another operator

**SampledLocations** (`SampledLocations.h`): Represents vertical interpolation paths at observation locations. A single location may be sampled by multiple paths (e.g., GNSS-RO limb sounding). Key fields: lat/lon/time arrays, `pathsGroupedByLocation()` mapping, MPI distribution. Methods: `nlocs()`, `isInTimeWindow()`, `areLocationsSampledOnceAndInOrder()` (optimization check).

### Filters (`src/ufo/filters/`)

- General QC filters: `BackgroundCheck`, `BayesianBackgroundCheck`, `DifferenceCheck`, `Gaussian_Thinning`, `DuplicateThinning` (flags duplicates within configurable tolerances on a user-specified set of `variable names`; optional `analysis_time` + `analysis_time_tolerance` keep obs near the analysis time, with a `min_spacing` (default PT1H) temporal thinning pass and `equidistant_time_selection` (`after`/`before`) tie-breaker — PR #4086), `TrackCheck`, `MetOfficeBuddyCheck`, `HistoryCheck`, `EnsembleStatistics` (writes per-obs ensemble statistics to ObsSpace; added `IGObsStdDev` statistic in PR #4024 — writes effective inverse-gamma observation std dev to the `IGObsError` group via a new `relative variance` YAML param, paired with `ObsErrorDiagonalInvGamma`), etc.
- **`obsfunctions/`**: ~100 ObsFunction implementations. Categories: error models (ObsErrorBound*/ObsErrorFactor*/ObsErrorModel*), cloud detection (CLWRet*, CloudDetect*, CloudCostFunction), geometry (SolarZenith, TropopauseEstimate, ImpactHeight), wind (WindDirAngleDiff, SatWinds*), satellite (SymmCldImpactIR, NearSSTRetCheckIR), time (TimeBinner, `LinearTimeInterpolate` — piecewise linear time interpolation/extrapolation to a target datetime; variable-reference or literal full/time-only timestamps, multi-point bracketing, `allow gap interpolation` for missing values — PR #4049), and general purpose (DrawValueFromFile, Conditional, DateTimeOffset, CircularDifference, `Statistic` — MPI-global statistic across all ranks: arithmetic/harmonic/weighted mean, median, mode, stddev, variance, assigning the same global value to every location; typically paired with `Variable Assignment` plus a `where` clause — PR #4091, `ProfileVerticalSmoothing` — per-profile local polynomial regression with height-dependent filter widths and configurable polynomial order — PR #4032).
- **`actions/`**: Filter actions (what to do when observations fail QC: `reject`, `assign value`, `inflate error`, etc.).
- Specialized sub-filters: `gnssroonedvarcheck/`, `refractivityonedvarcheck/`, `rttovonedvarcheck/`.

### Bias Correction (`src/ufo/predictors/`)

Variational bias correction (VarBC) uses a linear combination of predictors: `bias = Σ β_i * p_i(x)`. Predictor coefficients β are updated during minimization.

Key predictor types (~25+):
- **Constant** — bias offset
- **LapseRate** — temperature lapse rate (channel-dependent)
- **Emissivity** — surface emissivity
- **CosineOfLatitudeTimesOrbitNode** — scan geometry
- **ScanAngle** / **ScanPosition** — instrument scan bias
- **CloudLiquidWater** — cloud contamination
- **OrbitalAngle** / **SineOfLatitude** / **CosineOfLatitude** — geographic bias
- **InterpolateDataFromFile** — general-purpose predictor from external data
- **Legendre** — polynomial basis
- **ThicknessPredictor** — layer thickness

VarBC state is persisted to/from files via `ObsBiasCoeffs` for cycling across DA windows.

### Supporting Components

- **`src/ufo/profile/`**: Routines for handling vertical profile data (e.g., radiosonde).
- **`src/ufo/variabletransforms/`**: ~32 variable transforms invoked via `Variables Transform` filter. Base class `TransformBase` with factory. Categories: humidity (`Cal_Humidity`), pressure/height (`Cal_PressureFromHeight`, `Cal_HeightFromPressure`, `Cal_PStar`), wind (`Cal_Wind`), satellite (`Cal_SatBrightnessTempFromRad`, `Cal_SatRadianceFromPCScores`), radar (`Cal_RadarBeamGeometry`), ocean (`OceanDensity`, `OceanTempToTheta`), surface wind scaling. Separate from ObsFunctions — transforms modify obs space and save to `DerivedObsValue` group.
- **`src/ufo/utils/`**: Shared utilities: interpolation, geometry calculations, distance calculators, bin selectors, string utilities, Met Office-specific utilities.
- **`src/ufo/obslocalization/`**: 4 localization methods for ensemble DA. `ObsHorLocalization` (box car, KD-tree search), `ObsHorLocGC99` (Gaspari-Cohn smooth taper), `ObsHorLocSOAR` (second-order autoregressive), `ObsVertLocalization` (1D vertical with box car/GC99/SOAR functions). All support configurable lengthscale, max obs count, and caching. `ObsLocalizationBase` exposes two virtual `computeLocalization` overloads: the original `(GeometryIterator, ObsVector&)` form (used by LETKF/GETKF for vector R-localization) and a scalar `(Point3, Point3) → double` form (used by `oops::SequentialEnsembleSolver`/EAKF for point-to-point localization). The Point3 overload has a default implementation that ABORTs; `ObsHorLocalization`, `ObsHorLocGC99`, and `ObsHorLocSOAR` override it.
- **`src/ufo/errors/`**: 5 observation error R matrix implementations. `ObsErrorDiagonal` (simple diagonal), `ObsErrorWithinGroupCov` (correlations within profile/record groups via GC99/Markov/Gaussian functions; supports `applyBasicReconditioning` for ridge regression conditioning of the gaussian correlation profile), `ObsErrorCrossVarCov` (cross-variable correlations from file; supports R-localisation — extracts a local cross-variable block per location from the full correlation matrix), `ObsErrorDiagonalInvGamma` (Bayesian inverse-gamma prior; reads stddev from the `IGObsError` ObsSpace group when present — written by `EnsembleStatistics` filter's `IGObsStdDev` statistic — falling back to the `ObsError` group otherwise, and saves the resulting stddev back to `ObsError` for downstream solvers), `ObsErrorDiffusion` (diffusion-based correlated obs error covariance using `oops::Diffusion`; models R = D^{1/2} C D^{1/2} where C is a Gaspari-Cohn correlation applied via diffusion, with iterative inverse via GMRESR; optional `control grid` sub-config with `grid spacing` and `remove within` parameters to create a coarser mesh for the diffusion operator. The diffusion mesh is built in `update()` (post-QC, PRs #4129/#4156 merged) — only obs passing QC (`obserr[i] != missing`) enter the mesh; the constructor asserts single-var/single-PE. Optional debug YAML toggle `output diffusion mesh` (lowercase) dumps the mesh to file). Plus `ObsErrorReconditioner` for numerical conditioning.

### C++/Fortran Interoperability Pattern

Fortran modules are wrapped with C-compatible interfaces in `*.interface.F90` / `*.interface.h` pairs. C++ classes call these C interfaces. Example: `GeoVaLs.cc` ↔ `GeoVaLs.interface.h` ↔ `GeoVaLs.interface.F90` ↔ `ufo_geovals_mod.F90`.

### OOPS Framework Integration

UFO integrates with oops via `ObsTraits` (`src/ufo/ObsTraits.h`), which bundles types from **both UFO and IODA** for template instantiation by oops:
- From **ioda**: `ObsSpace`, `ObsVector`, `ObsDataVector<T>`, `GeometryIterator` (= `ioda::ObsIterator`, used by sequential ensemble solvers)
- From **ufo**: `ObsOperator`, `LinearObsOperator`, `GeoVaLs`, `ObsFilters`, `ObsError`, `ObsBias`, `ObsDiagnostics`, `SampledLocations`

Model repos instantiate algorithms as e.g. `oops::Variational<fv3jedi::Traits, ufo::ObsTraits>`.

`GeoVaLs` receives model data interpolated to observation locations via oops `GetValues<MODEL, OBS>`. The obs operator then computes `H(GeoVaLs)` → simulated observation values.

Configuration is done via the `oops::Parameters` system — each class has a `Parameters_` typedef and a `*Parameters` or `*ParametersBase` subclass.

### Tests (`test/`)

- `test/mains/`: Test executable sources.
- `test/ufo/`: Test class headers (e.g., `TestObsOperator.h`, `TestObsFilters.h`).
- `test/testinput/unit_tests/`: YAML configs for unit tests, organized by component.
- `test/testinput/instrumentTests/`: Integration test YAMLs for specific instruments/platforms (amsua, iasi, cris, gnssro, etc.).

## Adding New Components

- **New operator**: Subclass `ObsOperatorBase` in a new subdirectory under `src/ufo/operators/`. Register in the factory using `ObsOperatorMaker`. Add `LinearObsOperatorBase` subclass for TL/AD.
- **New filter**: Subclass `ObsFilterBase` (or `FilterBase` in `src/ufo/filters/`). Register via `FilterMaker`.
- **New ObsFunction**: Subclass `ObsFunctionBase` in `src/ufo/filters/obsfunctions/`. Register via `ObsFunctionMaker`.
- All new components need entries in the relevant `CMakeLists.txt` and corresponding YAML unit tests.
