# UFO (Unified Forward Operators)

> Last updated against commit `17930e3b` (2026-04-16). Run `cd bundle/ufo && git log --oneline 17930e3b..HEAD` to see what changed since.

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
- **`ObsFilters`**: Container that runs all configured filters for an obs space. The QCmanager is now separated out as a dedicated `qcmanager_` member (manages QC flags and statistics independently from the filter pipeline).
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

Each operator subdirectory (e.g., `crtm/`, `rttov/`, `gnssro/`, `identity/`, `vertinterp/`) contains a self-contained forward operator with optional TL/AD. Mixed C++/Fortran implementations are common — C++ calls Fortran via an `interface.F90` interop layer.

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

- General QC filters: `BackgroundCheck`, `BayesianBackgroundCheck`, `DifferenceCheck`, `Gaussian_Thinning`, `TrackCheck`, `MetOfficeBuddyCheck`, `HistoryCheck`, etc.
- **`obsfunctions/`**: ~96 ObsFunction implementations. Categories: error models (ObsErrorBound*/ObsErrorFactor*/ObsErrorModel*), cloud detection (CLWRet*, CloudDetect*, CloudCostFunction), geometry (SolarZenith, TropopauseEstimate, ImpactHeight), wind (WindDirAngleDiff, SatWinds*), satellite (SymmCldImpactIR, NearSSTRetCheckIR), and general purpose (DrawValueFromFile, Conditional, DateTimeOffset).
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
- **`src/ufo/obslocalization/`**: 4 localization methods for ensemble DA. `ObsHorLocalization` (box car, KD-tree search), `ObsHorLocGC99` (Gaspari-Cohn smooth taper), `ObsHorLocSOAR` (second-order autoregressive), `ObsVertLocalization` (1D vertical with box car/GC99/SOAR functions). All support configurable lengthscale, max obs count, and caching.
- **`src/ufo/errors/`**: 5 observation error R matrix implementations. `ObsErrorDiagonal` (simple diagonal), `ObsErrorWithinGroupCov` (correlations within profile/record groups via GC99/Markov/Gaussian functions; supports `applyBasicReconditioning` for ridge regression conditioning of the gaussian correlation profile), `ObsErrorCrossVarCov` (cross-variable correlations from file; supports R-localisation — extracts a local cross-variable block per location from the full correlation matrix), `ObsErrorDiagonalInvGamma` (Bayesian inverse-gamma prior), `ObsErrorDiffusion` (diffusion-based correlated obs error covariance using `oops::Diffusion`; models R = D^{1/2} C D^{1/2} where C is a Gaspari-Cohn correlation applied via diffusion, with iterative inverse via GMRESR; optional `control grid` sub-config with `grid spacing` and `remove within` parameters to create a coarser mesh for the diffusion operator). Plus `ObsErrorReconditioner` for numerical conditioning.

### C++/Fortran Interoperability Pattern

Fortran modules are wrapped with C-compatible interfaces in `*.interface.F90` / `*.interface.h` pairs. C++ classes call these C interfaces. Example: `GeoVaLs.cc` ↔ `GeoVaLs.interface.h` ↔ `GeoVaLs.interface.F90` ↔ `ufo_geovals_mod.F90`.

### OOPS Framework Integration

UFO integrates with oops via `ObsTraits` (`src/ufo/ObsTraits.h`), which bundles types from **both UFO and IODA** for template instantiation by oops:
- From **ioda**: `ObsSpace`, `ObsVector`, `ObsDataVector<T>`
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
