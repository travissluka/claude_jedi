# UFO (Unified Forward Operators)

> Last updated against commit `48d5d832` (2026-09-03). Run `cd bundle/ufo && git log --oneline 48d5d832..HEAD` to see what changed since.
>
> **Covers:** ObsOperator, LinearObsOperator, CompositeObsOperator, GeoVaLs, SampledLocations, ObsFilters, ObsBias, ObsDiagnostics, ObsError (Diagonal/CrossVarCov/BiasCorrelated/WithinGroup), ObsLocalization (Hor/HorGC99/HorSOAR/VertLocalization), QCflags, ObsFunctions, SuperOb filter + superob algorithms, VarBC cold start, variable transforms, FilterBase, QCmanager (see also `ufo-filter-lifecycle.md`), ObsTraits, CRTM/RTTOV integration.

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

Filters default to PRIOR stage. Explicitly set via `filter stage:` in YAML. Note: `DerivedObsValue` group variables overshadow `ObsValue` — if a variable transform writes to `DerivedObsValue/temperature`, that value is used instead of `ObsValue/temperature` for H(x) departures. `getScalarOrFilterData` (used across obs functions/filters to resolve a variable that may be scalar or per-obs) gained an optional `skipDerived` flag (default `false`, PR #4235) to bypass this shadowing when a caller genuinely wants the un-derived value.

### Operators (`src/ufo/operators/`)

Each operator subdirectory (e.g., `crtm/`, `rttov/`, `gnssro/`, `identity/`, `vertinterp/`, `radarpolarimetric/`) contains a self-contained forward operator with optional TL/AD. Mixed C++/Fortran implementations are common — C++ calls Fortran via an `interface.F90` interop layer.

**PPRO** (`operators/radarpolarimetric/ppro/`, class `ObsPPRO`, PR #4107): the Parameterized Polarimetric Radar Operator computes dual-pol radar variables (Zhh / ZDR / KDP / ρhv) from model microphysics fields. YAML param `polarimetric operator` selects the forward model — `Zhang21` (exponential PSD, T-matrix; `Zhang21Forward`) or `TCWA2` (gamma PSD, Rayleigh; `TCWA2Forward`) — and `microphysics option` selects the scheme (Thompson default), with extensive melting / Dm-tuning params. Shared microphysics config lives in `operators/radarshared/` (`MicrophysicsOptions.h`, enum `MicrophysicsOption`), also used by `radarreflectivity/directZDA`.

**ObsExtCoeffProfCRTM** (`operators/crtm/ObsExtCoeffProfCRTM.{cc,h}`, registered `"ExtinctionCoefficientProfileCRTM"`, PR #4163): lidar-style extinction-coefficient profile operator built on CRTM (`ufo_extcoeffprofcrtm_mod.F90`). Params inherit `ObsRadianceCRTMParameters` plus a required `nProfileLevels`. Forward-only, no TL/AD.

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

**PathSum** (`operators/pathsum/`, class `PathSumOper`, registered `"PathSum"`): weighted summation of a GeoVaLs variable (`geoval variable`) along a path; with path-length weights the sum approximates a path integral (e.g. electron density to Total Electron Content via `scaling factor`). `path type: vertical` (default) or `slant`; slant paths take their geometry from GeoVaLs named by `path point latitude variable` / `path point longitude variable` / `path point height variable` (defaults `pathPointLatitude` / `pathPointLongitude` / `pathPointHeight`). Weights come from `weight variable` (GeoVaLs), a YAML `weights` vector, or internal trapezoidal integration over segment lengths. Also `height range: [zmin, zmax]` (units set by GeoVaLs) and `use km for height`; interpolation to the exact height bounds at the path end points is vertical-path only. Tests: `opr_pathsum_vertical`, `opr_pathsum_slant`.

**BackgroundError operators** (`operators/backgrounderroridentity/`, `operators/backgrounderrorvertinterp/`): interpolate background-error GeoVaLs to obs locations. `ObsBackgroundErrorVertInterp` gained optional `error scaling field` / `error scaling field group` params, which scale the interpolated error by a named obs-space variable; the vertical-interpolation path now propagates missing values instead of multiplying through them (`ufo_backgrounderrorvertinterp_mod.F90`, `ufo_vertinterp_mod.F90`).

**ObsADT** (`operators/marine/adt/ObsADT.cc`, PR #4142): the along-track sea-surface-height-anomaly (ADT) operator's global mean-offset accumulation now excludes QC-failed and non-finite observations, changing the computed answer for any config that reached this path with un-filtered/`NaN` obs still present.

**SampledLocations** (`SampledLocations.h`): Represents vertical interpolation paths at observation locations. A single location may be sampled by multiple paths (e.g., GNSS-RO limb sounding). Key fields: lat/lon/time arrays, `pathsGroupedByLocation()` mapping, MPI distribution. Methods: `nlocs()`, `isInTimeWindow()`, `areLocationsSampledOnceAndInOrder()` (optimization check).

### Filters (`src/ufo/filters/`)

- General QC filters: `BackgroundCheck`, `BayesianBackgroundCheck`, `DifferenceCheck`, `Gaussian_Thinning`, `DuplicateThinning` (flags duplicates within configurable tolerances on a user-specified set of `variable names`; optional `analysis_time` + `analysis_time_tolerance` keep obs near the analysis time, with a `min_spacing` (default PT6H as of PR #4178, was PT1H) temporal thinning pass and `equidistant_time_selection` (`after`/`before`) tie-breaker — PR #4086; #4178 also adds single-observation thinning), `Percentile` (flags obs outside a central percentile range per group: `lower percentiles`/`upper percentiles` in [0,100], `inclusive central range`; numpy-style linear interpolation; registered `"Percentile"`, sets new `QCflags::percentile` — PR #4092), `StuckCheck` (reworked in PR #4100), `TrackCheck`, `MetOfficeBuddyCheck`, `HistoryCheck`, `EnsembleStatistics` (writes per-obs ensemble statistics to ObsSpace; added `IGObsStdDev` statistic in PR #4024 — writes effective inverse-gamma observation std dev to the `IGObsError` group via a new `relative variance` YAML param, paired with `ObsErrorDiagonalInvGamma`), etc.
- **`Step Check`** (`filters/StepCheck.{h,cc}`, `StepCheckParameters.h`, registered `"Step Check"`, new `QCflags::step`, PR #4106): per-station step-magnitude check built on `TrackCheckUtilsParameters`/`ObsAccessor` record grouping. Keys: `step threshold`, `inclusive step threshold`, mutually exclusive `number step tolerance` / `percentage step tolerance` / `use average step`, `circular period` for periodic data, plus chunked-averaging options (`chunk size`, `ignore last chunk if incomplete`, `remove stuck chunks`, `chunk stuck tolerance`).
- **`Record Threshold Rejection`** (`filters/RecordThresholdRejection.{h,cc}`, registered `"Record Threshold Rejection"`, new `QCflags::recordthreshold`, PR #4190): within each record, rejects all entries before or after the first entry that crosses a threshold. Keys: `threshold value` (scalar or variable), `threshold variable`, `rejection type` (`less than`/`less than or equal to`/`greater than`/`greater than or equal to`), `data order` (`ascending`/`descending`).
- **`Use Nearest Neighbors`** (`filters/UseNearestNeighbors.{h,cc}`, `UseNearestNeighborsParameters.h`, registered `"Use Nearest Neighbors"`, PR #4114): consumes `Find Nearest Neighbors` output via a polymorphic `algorithm` sub-config over a new `src/ufo/usenearestneighbors/` factory — `gather and match timestamp`, `reference point variables mean`, `local plane fit`. Keys: `identifier variable`, `nearest neighbor identifier variables`.
- **`FindNearestNeighbors`** (`filters/FindNearestNeighbors.{h,cc}`, registered `"Find Nearest Neighbors"`): not a QC filter (`qcFlag()` returns `QCflags::pass`); it rearranges obs-space data by nearest-neighbor lookup, moving values from reference-point locations to query-point locations. Locations are selected by non-missing values of `query point variable` / `reference point variable`; coordinates come from `MetaData/latitude` and `MetaData/longitude`. `output assignment` names the source variable; `output variables` and `distance output variables` (same length, one entry per neighbor rank) receive the transferred values and their distances. `algorithm` (`brute force`), `distance method` (`haversine`), `distance units` (`m`/`km`/`mi`/`nmi`, conversions via new `Constants::m_per_mile` / `m_per_nautical_mile`). Reference points are MPI-gathered across all ranks and de-duplicated on lat/lon before the search, so results are rank-independent (tested serially and on 3 PEs).
- **`obsfunctions/`**: ~100 ObsFunction implementations. Categories: error models (ObsErrorBound*/ObsErrorFactor*/ObsErrorModel* — `ObsErrorFactorTopoRad` was reworked in PR #4253 from hardcoded per-instrument branches (IASI/AMSU-A/MHS) to a required `sensor: infrared | microwave` plus optional `height groups` list of `{channels, height}` entries, with channels in no group left at factor 1), cloud detection (CLWRet*, CloudDetect*, CloudCostFunction), geometry (SolarZenith, TropopauseEstimate, ImpactHeight), wind (WindDirAngleDiff, SatWinds*), satellite (`SymmCldImpact` — symmetric cloud impact, dual formulation: Harnisch et al. (2016) when `btlim` is set, else Okamoto et al. (2014); registered `"SymmCldImpact"`, replaces the removed `SymmCldImpactIR` — PR #4148; NearSSTRetCheckIR), time (TimeBinner, `LinearTimeInterpolate` — piecewise linear time interpolation/extrapolation to a target datetime; variable-reference or literal full/time-only timestamps, multi-point bracketing, `allow gap interpolation` for missing values — PR #4049), and general purpose (DrawValueFromFile, Conditional, DateTimeOffset, CircularDifference, `Statistic` — MPI-global statistic across all ranks: arithmetic/harmonic/weighted mean, median, mode, stddev, variance, assigning the same global value to every location; typically paired with `Variable Assignment` plus a `where` clause — PR #4091, `ProfileVerticalSmoothing` — per-profile local polynomial regression with height-dependent filter widths and configurable polynomial order — PR #4032). `ModelLevelIndex` gained `select closest model index`, `invert model index`, and `index model levels from one` (PR #4161). `StableLayersCloudTopPressure` renamed its YAML keys `stable density` → `stable denominator` and `relative humidity density as a fraction` → `relative humidity denominator as a fraction` (PR #4256, breaking for existing configs).
  - `abort if invalid operation` controls whether invalid/unsupported arithmetic throws or yields missing values. `ElementMultiply` defaults to `true` (throw); `Arithmetic` (registered `LinearCombination`) defaults to `false` (warn, set missing). Both route failures through a `warnOrThrow<ExceptionType>()` helper.
  - `ModelHeightAdjustedSpecificHumidity` (PR #4266) adjusts observed specific humidity for the difference between station and model surface height by holding relative humidity fixed as the temperature is height-adjusted. Params: `observed specific humidity variable`, `observed temperature variable`, `adjusted temperature variable`, `station pressure variable`, `model surface pressure variable`; falls back to the model surface pressure where station pressure is missing.
  - `ModelHeightAdjustedAirTemperature` takes configurable lapse rates via three optional sub-configs: `observed variable` (`name`, default `ObsValue/airTemperatureAt2M`), `model height` (`from: terrain` or `lowestModelLevel`, `offset in meters`), and `temperature lapse rate in K/km` (`scheme: constant` with `value` in K/km default 6.5, or `scheme: local` computing the rate from the model temperature profile between `level1`/`level2`, 1-based from the surface, optionally clamped by `bounds: {minvalue, maxvalue}`).
- **`actions/`**: Filter actions (what to do when observations fail QC: `reject`, `assign value`, `inflate error`, etc.). PR #4057 adds an `apply to whole record` option to `FilterActionBase` (new `RecordActionUtils`): when set, `AcceptObs`/`RejectObs`/`SetFlag` apply per-record (all locations in a record together) instead of per-location.
- **`SharedListCheck`** (`filters/SharedListCheck.{h,cc}`, registered `"SharedListCheck"`, flags with `QCflags::black`, PR #4262): rejects (or keeps) obs based on an external list file — GSL aircraft rejectlist, mesonet uselist, provider lists. YAML: `shared list file`, `list to use` (named sublist within the file), and either `variable to check` or `compound check` (a list of `obs variable` / `sublist to use` pairs); `flag mode: flag matched` (default) or `flag unmatched`. Parsed lists are cached in the `SharedListStore` singleton (`filters/SharedListStore.{h,cc}`) keyed by file path, so repeated filters and multiple obs types share one parse per rank. Example lists ship in `resources/sharedListCheck/`.
- **Filter `identifier`** (`FilterParametersBase`, PR #4241): every filter accepts an optional `identifier` sub-config with `name` (required), `logging`, `diagnostic flag`, and `diagnostic flag new`. When diagnostic flags are enabled the filter writes `DiagnosticFlags/<name><iteration>[_new]/<var>`, making per-filter rejections traceable through outer-loop iterations. `ObsFilterBase` gained `setIteration()`/`getIteration()`, set by `ObsFilters::appendToFiltersList`.
- **Inline variable maps** (PR #4259): `FilterParametersBase` and `ObsOperatorParametersBase` accept a `variable maps` list (of `VariableNameParameters`) as an alternative or override to the file-based `observation alias file`, so a single YAML can remap variable names without shipping an alias file.
- **2D / layer variables** (PR #4166): `ufo::Variable` accepts a `layers:` key using the same range syntax as `channels:` (e.g. `1-34`), aliased onto the internal `channels_` list. Pairs with `ioda`'s new `ObsDimensionId::Layer` for retrieval-level obs. Test: `qc_boundscheck_layers`.
- **`SuperOb`** (`filters/SuperOb.{h,cc}`, params in `filters/SuperObParameters.h`, algorithms under `src/ufo/superob/` behind `SuperObFactory`/`SuperObMaker`): collapses each record to a single superobservation. The algorithm is polymorphic under `algorithm: {name: ...}`; registered names are `"mean obs"` (`SuperObMeanO`), `"mean OmB"` (`SuperObMeanOmB`), `"radar"` (`SuperObRadar`), and, new in PR #4110, `"circular mean obs"` (`SuperObCircularMeanO`, scipy-`circmean`-equivalent, with `lower bound` / `exclusive upper bound` defaulting to 0..2π), `"count obs"` (`SuperObCount`), `"max obs"` (`SuperObMaxO`), and `"range obs"` (`SuperObRangeO`, max − min).
  - `GenericSuperObParameters` (all algorithms): `assign to all values in record` (default `false`; when `true` the superob value is written to every location in the record and non-superob locations are not rejected) and `grouping variable` (de-duplicates identical values within a record before computing; throws if grouped values or their QC flags disagree).
  - Filter-level `SuperObParameters` keys are all optional vectors with one entry per filter variable: `set values outside where clause to missing` (default `true`), `increment if non-missing`, `variables to increment` (integer ObsSpace variables), `increment values`, `increment whole record`, and `increment whole record respects where` (default `true`). These are parsed and length-checked into `ValidatedSuperObParameters`; `SuperObBase::runAlgorithm()` takes the `SuperObParameters` and `computeSuperOb()` returns a `bool` so a record can decline to produce a superob.
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
- **SymmCldImpact** — VarBC predictor from symmetric cloud impact (Harnisch et al. 2016 GEOIR cloud predictor), registered `"SymmCldImpact"`, with `order`, `btlim`, and sigmoid parameters (PR #4148)

VarBC state is persisted to/from files via `ObsBiasCoeffs` for cycling across DA windows.

**VarBC cold start** (PR #4298, `ObsBiasColdStartParameters` in `ObsBiasParameters.h`): seeds coefficients that have no prior value, following step 1 of WRFDA's `da_varbc_coldstart`. YAML:

```yaml
obs bias:
  cold start:
    enable: true               # default false
    force: false               # re-seed every (record, variable), not just all-zero ones
    histogram bins: 200
    histogram half width: 10.0
    minimum obs number: 10
```

`ObsBias::coldStart()` is called from `ObsOperator::simulateObs` on the first uncorrected H(x) — which is why `simulateObs` now takes `ObsBias &` **non-const** (oops #3367 made the corresponding `ObsAuxControl_ &` non-const all the way up the template contract). For each (record, variable) whose coefficients read back all-zero (or every one under `force`), it sets *only* the `constant` variational predictor to the mode of the `y − H(x)` histogram and zeroes the rest. Channels with fewer than `minimum obs number` valid departures globally (counted with an `ioda` `Accumulator` plus a `commTime` reduction) are left untouched. With cold start enabled, variables absent from `input file` are tolerated rather than fatal, the same relaxation `variables without bc` gives. Throws `eckit::BadParameter` if combined with `bc by record`.

### Supporting Components

- **`src/ufo/profile/`**: Routines for handling vertical profile data (e.g., radiosonde).
- **`src/ufo/variabletransforms/`**: ~32 variable transforms invoked via `Variables Transform` filter. Base class `TransformBase` with factory. Categories: humidity (`Cal_Humidity`), pressure/height (`Cal_PressureFromHeight`, `Cal_HeightFromPressure`, `Cal_PStar`), wind (`Cal_Wind`), satellite (`Cal_SatBrightnessTempFromRad`, `Cal_SatRadianceFromPCScores`), radar (`Cal_RadarBeamGeometry`), ocean (`OceanDensity`, `OceanTempToTheta`), surface wind scaling. **RH units are now explicit** (PR #4221, the UKMO RH sprint): `Cal_Humidity` gained a `RelativeHumidityUnits` enum exposed as `observation relative humidity units: percentage | fraction`, and it throws if the key is unset when RH is in play. The same key is a *required* parameter on the `ModelHeightAdjustedRelativeHumidity` and `MetOfficeRelativeHumidityCorrection` ObsFunctions. This is a breaking YAML change for any config touching relative humidity, and it pairs with vader switching `relative_humidity` to fractions. `Cal_SurfaceWindScalingHeight` / `Cal_SurfaceWindScalingPressure` request the GeoVaL `ratio_of_wind_at_surface_adjacent_layer_to_wind_at_10m` (`var_sfc_fact10` in `ufo_variables_mod.F90`, formerly `wind_reduction_factor_at_10m`); model interfaces must supply it under that name. Separate from ObsFunctions — transforms modify obs space and save to `DerivedObsValue` group.
- **`src/ufo/utils/`**: Shared utilities: interpolation, geometry calculations, distance calculators, bin selectors, string utilities, Met Office-specific utilities.
- **`src/ufo/obslocalization/`**: 4 localization methods for ensemble DA. `ObsHorLocalization` (box car, KD-tree search), `ObsHorLocGC99` (Gaspari-Cohn smooth taper), `ObsHorLocSOAR` (second-order autoregressive), `ObsVertLocalization` (1D vertical with box car/GC99/SOAR functions). All support configurable lengthscale, max obs count, and caching. `ObsLocalizationBase` exposes two virtual `computeLocalization` overloads: the original `(GeometryIterator, ObsVector&)` form (used by LETKF/GETKF for vector R-localization) and a scalar `(Point3, Point3) → double` form (used by `oops::SequentialEnsembleSolver`/EAKF for point-to-point localization). The Point3 overload has a default implementation that ABORTs; `ObsHorLocalization`, `ObsHorLocGC99`, `ObsHorLocSOAR`, and `ObsVertLocalization` override it. Factory names: `"Horizontal Box car"`, `"Horizontal Gaspari-Cohn"`, `"Horizontal SOAR"`, `"Vertical localization"`. `ObsVertLocalization`'s Point3 form takes the vertical coordinate from `p[2]`, applies the optional `log transform`, and tapers with Box Car / Gaspari Cohn / SOAR, returning 0 beyond `vertical lengthscale`. `ObsHorLocalization`'s half-chord angle is now clamped to π/2 (PR #4274), fixing a bug where the effective search radius shrank instead of growing for very large localization lengthscales. `vertical lengthscale > 0` and a `soar decay` value for `localization function: SOAR` are validated in the constructor so both compute paths can assume valid options. `test/ufo/ObsLocalization.h` drives the scalar form through a `point pair tests` list (`p1`, `p2`, `reference value`, `tolerance`).
- **`src/ufo/errors/`**: 5 observation error R matrix implementations. `ObsErrorDiagonal` (simple diagonal), `ObsErrorWithinGroupCov` (correlations within profile/record groups via GC99/Markov/Gaussian functions; supports `applyBasicReconditioning` for ridge regression conditioning of the gaussian correlation profile), `ObsErrorCrossVarCov` (cross-variable correlations from file; supports R-localisation — extracts a local cross-variable block per location from the full correlation matrix), `ObsErrorDiagonalInvGamma` (Bayesian inverse-gamma prior; reads stddev from the `IGObsError` ObsSpace group when present — written by `EnsembleStatistics` filter's `IGObsStdDev` statistic — falling back to the `ObsError` group otherwise, and saves the resulting stddev back to `ObsError` for downstream solvers), `ObsErrorDiffusion` (diffusion-based correlated obs error covariance using `oops::Diffusion`; models R = D^{1/2} C D^{1/2} where C is a Gaspari-Cohn correlation applied via diffusion, with iterative inverse via GMRESR; optional `control grid` sub-config with `grid spacing` and `remove within` parameters to create a coarser mesh for the diffusion operator. The diffusion mesh is built in `update()` (post-QC, PRs #4129/#4156 merged) — only obs passing QC (`obserr[i] != missing`) enter the mesh. Optional debug YAML toggle `output diffusion mesh` (lowercase) dumps the mesh to file. PR #4176 reworked it in three ways: (1) **lengthscale convention** — `correlation lengthscale` is now interpreted as a Gaspari-Cohn cutoff radius and divided by 3.67 to get the Daley lengthscale `oops::Diffusion` expects; set `as gaussian: true` to pass the value through unconverted (mirrors the SABER diffusion block flag). (2) **`diagonal loading`** (α ∈ [0,1], default 0.0) blends α·D into R, accelerating GMRESR convergence at wide L_R/Δx. (3) **multi-PE support** — the single-PE assert is gone; `allow any distribution` (default false) permits non-Atlas but geographically contiguous distributions on >1 PE. The mesh and normalization are built once on the first `update()` and reused (`meshAndNormBuilt_`, with a `builtObsCount_` tripwire), with `localObs2node_` mapping obs to mesh nodes (-1 = QC-failed)). Plus `ObsErrorReconditioner` for numerical conditioning.

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
