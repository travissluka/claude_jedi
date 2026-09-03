# SABER (System for Atmospheric and Boundary Layer Error Representation)

> Last updated against commit `9c828faa` (2026-08-27). Run `cd bundle/saber && git log --oneline 9c828faa..HEAD` to see what changed since.
>
> **Covers:** SaberCentralBlockBase, SaberOuterBlockBase, SaberParametricBlockChain, SaberEnsembleBlockChain (incl. scale-dependent localization), SaberHybridBlockChain, SaberOuterBlockChain, BUMP_NICAS, Diffusion/DiffusionImpl/DiffusionFilter, FastLAM, Bifourier (incl. BifourierCovarianceImpl/BifourierSpectralConverter/BifourierAnalyticalFilter/BifourierCovarianceSqrt), SpectralCovariance/Correlation/AnalyticalCorrelation, StdDev, VertLoc, DuplicateVariables, ID, GaussToCS, VaderBlock, TorchBalance, GSIBlockChain, QUENCH testbed, ErrorCovariance<MODEL>, ErrorCovarianceToolbox, ProcessPerts, Localization, multiply/multiplyAD/leftInverseMultiply/multiplySqrt/variance, direct/iterative calibration, dirac tests, CoupledErrorCovariance.

## Overview

C++/Fortran framework for building modular, composable error covariance models in JEDI. Source at `bundle/saber/`. Version 1.10.0.

SABER's core idea: error covariance operators are built by composing **blocks** into **chains**. Central blocks are self-adjoint (B = U U^T); outer blocks are preprocessing transforms applied before/after the central block.

**B matrix decomposition**: `B = T V K Σ C Σ Kᵀ Vᵀ Tᵀ` where T = variable transform (VADER), V = vertical balance, K = vertical localization, Σ = standard deviation scaling, C = horizontal correlation (BUMP_NICAS, Diffusion, etc.). Each factor is a SABER block. Outer blocks (T, V, K, Σ) wrap the central block (C).

Build/test quirks (flags, conditional blocks, test structure) in `claude/build-and-test.md`.

## Core Architecture

### Block Abstraction

Two base classes define the block interface:

**`SaberCentralBlockBase`** (`src/saber/blocks/`) — Self-adjoint covariance blocks:
- `randomize()` — generate random sample from covariance
- `multiply()` — apply B matrix
- `multiplySqrt()` / `multiplySqrtAD()` — square-root formulation (optional)
- `directCalibration()` / `iterativeCalibration()` — train from ensemble
- `read()` / `write()` — I/O for pre-computed parameters

**`SaberOuterBlockBase`** (`src/saber/blocks/`) — Transform/preprocessing blocks:
- `multiply()` / `multiplyAD()` — forward and adjoint application
- `leftInverseMultiply()` / `rightInverseMultiply()` — inverse transforms
- `innerGeometryData()` / `innerVars()` — geometry/variable mapping

Configuration base: `SaberBlockParametersBase` — all blocks specify `saber block name` for factory lookup.

### Block Chains

Three chain types compose blocks into full covariance operators:

**`SaberParametricBlockChain`** — Static covariance:
- Outer blocks (optional) + one central block
- Time covariance modes: univariate, duplicated multivariate
- Config keys: `saber central block`, `saber outer blocks`

**`SaberEnsembleBlockChain`** — Ensemble-based covariance:
- Outer blocks + ensemble data
- Optional localization via its own block chain
- Optional **ensemble transform**: chain of outer blocks applied via `rightInverseMultiply()` to ensemble members before covariance computation (any outer block can be used)
- Optional **inflation**: multiplicative field and/or scalar value applied to ensemble
- Optional **scaled perturbations** (PR #1240): override the default `1/(N-1)` covariance denominator via YAML key `denominator for normalizing ensemble covariance` (double). Useful when the loaded ensemble already represents perturbations from a different effective population size, or for user-tuned inflation-like scaling. Scaling is applied once at load time by `readAndScaleEnsemble` (`saber/oops/Utilities.h`), which pre-multiplies each member by `1/√denom` — so `multiply`/`randomize`/`multiplySqrt`/`multiplySqrtAD` no longer divide by `(N-1)` at apply time. Math is unchanged; this just moves the cost to load.
- Ensemble sources: states, perturbations, base+perturbations, pair differences, or on alternative geometry
- Config keys: `ensemble`, `localization`, `ensemble transform`, `inflation field`, `inflation value`, `denominator for normalizing ensemble covariance`
- **Scale-dependent localization** (PR #1177): internally the chain is now a `std::vector<ScaleData>`, one per scale, driven by an optional `scales:` YAML list — each entry may set its own `filter`, `interpolator`, `localization`, `output` (`generic write`/`model write`), `ensemble pert`, `ensemble pert on other geometry`, `use residual from filter`, and `localization at full resolution`. Filters split each member into scale bands at construction (recursive subtraction, with an optional interpolator to/from a reduced resolution) mirroring `ProcessPerts`. Top-level `multiscale strategy: separated | crossed` picks the combination rule: `separated` sums `nens × locCtlVec` sizes over scales, `crossed` requires equal per-scale control-vector sizes. `recursive perturbations processing` (renamed from `recursive filters`) and `sub-ensembles size` (per-sub-ensemble mean removal) are also chain-level keys. The ensemble may now legally be empty (a single member is still an error). `ctlVecSize()` is now cached (`ctlVecSize_`). Without `scales:`, localization must still be present (`ASSERT(!params.scales.value())` when localization is absent).

**`SaberHybridBlockChain`** — Weighted combination of multiple covariances:
- Outer blocks + weighted components (each a full covariance + weight)
- Config key: `components` (array of `covariance` + `weight`)
- Parallel-mode config key: `comm redistribution method` (string, default `"straight"`) — selects the algorithm for ATLAS field redistribution between parent and sub-communicators when running hybrid components on disjoint rank subsets. Internally calls `util::redistributeToSubcommunicator` / `util::gatherAndSumFromSubcommunicator`, which now delegate to `oops::CommRedistributionRepository` (PR #3196) so redistribution plans are constructed once and cached across multiply/adjoint/randomize calls. Public multiply API is unchanged.

**`SaberOuterBlockChain`** — Sequences outer blocks, handles reverse-order adjoint application. Also used as the implementation basis for **filter blocks**: `NICASFilter`, `DiffusionFilter`, and `SpectralAnalyticalCorrelation` are central blocks that internally wrap a `SaberOuterBlockChain` to apply localization/correlation as a self-contained filter (replacing the older monolithic filter classes).

**`SaberCentralBlock`** — Container for multivariate central blocks (wraps one or many concrete central blocks in `groupCentralBlocks_`, enabling e.g. scale-dependent localization):
- `multivariate strategy` (default `"single"`): `"single"` (one `saber block name`, no `groups:`), `"univariate"`, `"duplicated"` (replicate per variable group), `"duplicated and weighted"` (with off-diagonal weights), `"crossed"`. `"single"` and `groups:` are mutually exclusive.
- Per-group keys inside `groups:` entries are `group central block` and `group outer blocks` (PR #1284, formerly `saber central block` / `auxiliary outer blocks`). The **top-level** `saber central block` / `saber outer blocks` keys of the chain itself are unchanged.
- PR #1284 rewrote most of `SaberCentralBlock.cc` but left the **public interface untouched** (no methods added, removed, or renamed); the churn is private (`applyWeights`/`applyWeightsAD` helpers for `"duplicated and weighted"`, `groupOuterBlockChains_`).

### Chain Multiply Order

The factorization `B = Outer_N · ... · Outer_1 · Central · Outer_1ᵀ · ... · Outer_Nᵀ` drives the apply order. Outer blocks are stored innermost→outermost.

**Parametric chain**:
1. Adjoint pass (outer→inner): for `i = 0..N-1`, `outerBlock[i].multiplyAD(fset)`
2. `centralBlock.multiply(fset)`
3. Forward pass (inner→outer): for `i = N-1..0`, `outerBlock[i].multiply(fset)`

**Ensemble chain** (step 2 replaced by):
```
For each member ie:
  if localization:
    tmp = fset ⊙ ensemble[ie]           # Schur product
    locBlockChain.multiply(tmp)         # Apply localization
    tmp = tmp ⊙ ensemble[ie]            # Second Schur
  else:
    tmp = ensemble[ie] * dot_product(fset, ensemble[ie])
  result += tmp
# Default denom = N-1; user can override via "denominator for normalizing
# ensemble covariance". Applied at load time (members pre-scaled by 1/√denom
# in readAndScaleEnsemble), so no explicit divide here in the new code path.
```

**Hybrid chain** (step 2 replaced by): for each component j, apply `√wⱼ`, multiply by component B, apply `√wⱼ` again, accumulate. Gives `B_hybrid = Σⱼ √wⱼ · Bⱼ · √wⱼ` which preserves self-adjointness. Optional `run in parallel: true` splits MPI ranks across components.

### Multiply Method Reference

| Method | Direction | Use Case |
|--------|-----------|----------|
| `multiply` | Forward (inner→outer) | Normal B application |
| `multiplyAD` | Adjoint (outer→inner) | Normal B application |
| `leftInverseMultiply` | Inverse (outer→inner) | Calibration: transform ensemble to inner space |
| `rightInverseMultiply` | Right inverse (inner→outer) | Ensemble transform |
| `multiplySqrt(cv, fset)` | Apply U | Control vector → field (`B = U Uᵀ`) |
| `multiplySqrtAD(fset, cv)` | Apply Uᵀ | Field → control vector |

Control vector size:
- **Parametric**: determined by central block (e.g. diffusion length scales)
- **Ensemble, no localization**: one scalar per member
- **Ensemble with localization**: `ens_size × loc_ctlVecSize()`

### Variance (diagonal of B)

`SaberBlockChainBase` gained pure-virtual `variance()` and `randomCtlVec()` (PR #1273). `SaberCentralBlockBase::variance()` defaults to `NotImplemented`; `SaberOuterBlockBase::variance(FieldSet3D&)` (transforms an input variance fieldset in place) also defaults to `NotImplemented`. Implementations: NICAS/Diffusion/`IDCentral` report unit variance (1.0 on the diagonal); `StdDev` (both generic and BUMP variants) multiplies by σ²; `Interpolation` gives an approximate diagonal (`T diag(C)`, documented caveat, not exact); hybrid chains sum the weighted component variances (not the parallel-hybrid path); ensemble chains sum over scales (separated strategy only). `SaberOuterBlockChain::applyBackgroundVariance()` propagates the transform innermost-first. Exposed to callers as `ErrorCovariance<MODEL>::variance()`.

QUENCH gained a matching test tool: `quenchTestVariance` / `saber_quench_test_variance.x` (new `src/saber/test/Variance.h`), configured with `expected per-point variance` and an optional `monte carlo: {samples, tolerance}` block; tests registered in `test/testlist/saber_variance.cmake`.

### Built-in Validation Tests

Configurable under any block chain:
```yaml
adjoint test: true          # Verify <y, Ax> = <Aᵀy, x>
adjoint tolerance: 1.0e-10
square-root test: true      # Verify UUᵀ = B
square-root tolerance: 1.0e-10   # default as of PR #1177 (was 1.0e-12)
inverse test: true           # Verify B⁻¹B = I
```

### Chain Key Files

| File | Purpose |
|------|---------|
| `saber/blocks/SaberBlockChainBase.h` | Abstract chain interface |
| `saber/blocks/SaberParametricBlockChain.h/.cc` | Parametric implementation |
| `saber/blocks/SaberEnsembleBlockChain.h/.cc` | Ensemble implementation |
| `saber/blocks/SaberHybridBlockChain.h` | Hybrid implementation |
| `saber/blocks/SaberOuterBlockChain.h` | Outer-block sequencer (also backs filter blocks) |
| `saber/blocks/SaberOuterBlockBase.h` | Outer block interface + factory |
| `saber/blocks/SaberCentralBlockBase.h` | Central block interface + factory |
| `saber/oops/ErrorCovariance.h` | Integration with oops covariance system |

### OOPS Integration

`ErrorCovariance<MODEL>` (`src/saber/oops/`) inherits `oops::ModelSpaceCovarianceBase<MODEL>` and creates a block chain via `SaberBlockChainFactory<MODEL>::create()`. The factory examines `covariance type` in config (parametric/ensemble/hybrid/gsi).

SABER operates on `atlas::FieldSet` — it converts `MODEL::Increment` via the model's `toFieldSet()`/`fromFieldSet()` methods. This is why SABER works with any model without knowing model internals.

Other OOPS integration:
- **`Localization<MODEL>`** — wraps SABER blocks for ensemble localization
- **`ErrorCovarianceToolbox<MODEL>`** — diagnostic application: Dirac impulse-response tests, covariance profiles (1D function of separation distance), randomization (generate dx ~ B, compute variance from ensemble)
- **`ProcessPerts<MODEL>`** — processes ensemble perturbations through band filters (SABER block chains), with recursive filtering option (YAML key `recursive perturbations processing`, renamed from `recursive filters`) and multiple output modes

### Factory Pattern

- `SaberCentralBlockFactory` / `SaberCentralBlockMaker<T>` — central blocks by name
- `SaberOuterBlockFactory` — outer blocks by name
- `SaberBlockChainFactory<MODEL>` / `SaberBlockChainMaker<MODEL,T>` — chain types
- Registration via `instantiateCovarFactory.h`, `instantiateLocalizationFactory.h`

## QUENCH Testbed (`quench/`)

Not a block — a pseudo-model for testing SABER blocks with any ATLAS grid. Implements minimal OOPS model types (Geometry, State, Increment, VariableChange) to enable running `ErrorCovarianceToolbox` and `ProcessPerts` without a real atmospheric model. Main executables: `quenchErrorCovarianceToolbox`, `quenchProcessPerts`, `quenchCoupledErrorCovarianceToolbox` (for testing the coupled covariance; uses `oops::TraitsCoupled<quench::Traits, quench::Traits>`), `quenchSubCommErrorCovarianceToolbox` (runs `ErrorCovarianceToolbox` on a subset of MPI ranks while leaving the remainder idle — exercises the parallel hybrid + `CommRedistributionRepository` paths, and simulates an IO-server-style rank layout). Enabled via `ENABLE_QUENCH` CMake option.

## Block Directory Reference

### `generic/` — Universal utility blocks (C++ only)

| Block | Purpose |
|-------|---------|
| `ID` | Identity pass-through (central + outer variants) |
| `StdDev` | Standard deviation scaling; reads from profile/ATLAS/model files; supports iterative calibration |
| `DuplicateVariables` | Duplicates variables onto multiple vertical levels |
| `VertLoc` | Vertical localization (24KB impl) |
| `VertLocInterp` | Vertical localization with interpolation |
| `OrographicInterp` | Orographic interpolation |
| `ShadowLevels` | Extra/shadow level handling |
| `WriteFields` | Output intermediate fields for debugging; "Wrote file"/"Did NOT write file" messages log to the info stream, not the test stream (PR #1259). Uses `functionSpace().grid().name()` for the grid name under `ATLAS_VERSION_46_OR_GREATER` parallel IO (PR #1263) |
| `ResidualFields` | Reads a FieldSet from `input path` (optional `parallel IO`) for filtering; `multiply fset filename` debug output (PR #1244); same grid-name handling for parallel IO (PR #1263) |

### `bump/` — BUMP (Background error on Unstructured Mesh Package) — Fortran-heavy

The largest SABER component. 58 `.fypp` Fortran templates + C++ wrappers.

Key blocks:
- **`BUMP_NICAS`** — Normalized Interpolated Covariance by Analysis Statistics (ensemble-based correlation/localization)
- **`PsiChiToUV`** — Stream function/velocity potential to wind
- **`VerticalBalance`** — Vertical balance operator
- **`StdDev`** (BUMP variant) — Standard deviation from BUMP

C++ wrappers: `BUMP.h`, `NICAS.h`, `type_bump.h`. Extensive configuration via `BUMPParameters.h` (~29KB) covering: general settings, I/O, drivers (correlation/localization/balance/moments/diagnostics), sampling, and output. The `drivers: write diagnostics in yaml` flag (default false, PR #1203) emits `<prefix>diag.yaml` with per-group ensemble correlation, localization, and hybrid-coefficient profiles.

BUMP's registry now uses the shared `oops::util::linkedList_i.f`/`linkedList_c.f` (`registry_t`) instead of its own bespoke `tools_linkedlist_{interface,implementation}.fypp` (deleted, PR #1277) — the same pattern GSI already used. `registry%init()` dropped its `f_comm` argument in the switch.

`type_nicas_cmp.fypp` weight computation lists `isa` in the OpenMP `private` clause (PR #1282); omitting it raced across threads in multi-component NICAS. PR #1292 is a further internal performance rework of `type_nicas_cmp`/`type_bnda`/`type_geom`/`type_linop`/`type_samp` (cached neighbor candidates, split arc-validity checks, `balldata_pack_empty`, mask handling) — no YAML/namelist change.

### `bifourier/` — Spectral covariance via bidirectional Fourier (requires FFTW or ECTRANS)

| Block | Purpose |
|-------|---------|
| `BifourierCovariance` | Main spectral covariance block; now a thin wrapper around `BifourierCovarianceImpl` |
| `BifourierBalance` | Balance operator (48KB impl) |
| `BifourierAromeBalance` | AROME-specific balance (32KB impl) |
| `BifourierAromeCovariance` | AROME covariance variant |
| `BifourierGridToSpectral` / `BifourierSpectralToGrid` | Transform blocks |
| `BifourierID` | Identity in spectral space |
| `BifourierAnalyticalFilter` | Analytical waveband filter (outer block, new PR #1178) |
| `BifourierCovarianceSqrt` | Square-root form of the covariance (outer block, new PR #1177) |
| `BifourierSpectralConverter` | Cross-resolution spectral converter (outer block, new PR #1177) |

Transform backends: `BifourierTransformFFTW`, `BifourierTransformECTRANS`.

The biperiodization step's `inner partitioner` YAML key is **optional** (PR #1250): it is required only when the outer partitioner is `custom`; otherwise the function space and partition are copied from the outer grid (previously it defaulted to `checkerboard` and was always read).

**Covariance implementation split** (PR #1177): `BifourierCovariance` now delegates to a new `BifourierCovarianceImpl`, which holds the shared `read`/`calibration`/`profiles`/`inflation`/`correlation`/`write` params (including `sub-ensembles size`, `half life`, `cycle index`). `BifourierSpectralConverter` (new outer block) does the cross-resolution spectral alltoall, configured with `nx`/`ny`/`partitioner`. `BifourierAnalyticalFilter` (new outer block) applies an analytical waveband filter: `waveband min`/`waveband peak`/`waveband max`, `inverse mode`. `BifourierCovarianceSqrt` (new outer block) exposes the covariance's square root for use as a standalone transform. Together these back the new scale-dependent-localization multiscale dirac tests (`dirac_bifourier_multiscale_*`, `dirac_multiscale_*`, `error_covariance_training_multiscale_*`, `randomization_multiscale_1`).

### `fastlam/` — Fast Limited Area Model correlation (requires FFTW)

Main block: `FastLAM` (59KB impl). Layer types: `LayerSpec` (spectral), `LayerHalo`, `LayerRC` (regional covariance). Supports iterative calibration. As of PR #1176, square-root-based central blocks (incl. FastLAM) route randomization through a new `randomCtlVec(field, member)` virtual rather than overriding `randomize`/`multiply` directly; `randomize`/`multiply` are no longer pure-virtual on `SaberCentralBlockBase` (base defaults provided); FastLAM caches `ctlVecSize_`. Backed by the internal `saber/util/Randomization` helper (`util::randomCtlVec`). PR #1248 added a `"duplicated and weighted"` multivariate strategy (alongside `"duplicated"`/`"crossed"`) with weighted cross-variable correlations, plus YAML params `sampling horizontal length-scale`, `sampling vertical length-scale`, `inner grid-point function space from background variable`, `default off-diagonal weight`, and `specific off-diagonal weights`; internally the reduction-factor getters (`rfh`/`rfv`) gave way to sampling length-scales (`srh`/`srv`) and explicit grid dims (`nx`/`ny`/`nz`).

PR #1257 fixed the `srh`/`srv` sampling length-scale calculation: `srh` now normalizes via the average of `1/minCellSize + 1/maxCellSize` (was a straight average of the cell sizes), and `srv` (when positive) is now rescaled through the same thickness-normalization used for `rv` rather than copied raw from YAML. `"duplicated and weighted"` handling was also extended into `setupCtlVecSize`/`setupGlbIndex` (previously only `"univariate"`/`"duplicated"` were handled there). Vertical convolution/normalization in `LayerHalo`/`LayerRC`/`LayerSpec` is now gated on `zKernelSize_ > 1`, not just `nz_ > 1`.

### `diffusion/` — Diffusion localization, explicit + implicit vertical (C++ only)

`Diffusion` block (28KB impl). Better than NICAS for small correlation length-scales. Direct calibration from ensemble. Filter mode support. Implementation split: `DiffusionImpl` handles the core diffusion math, `Diffusion` wraps it as a central block. `DiffusionFilter` wraps it as a `SaberOuterBlockChain`-based filter.

**Vertical scheme selection** (saber #1234, paired with oops #3275): the YAML `vertical:` block selects between the default explicit scheme and an implicit Mirouze–Weaver scheme:
```yaml
vertical:
  method: explicit | implicit   # default explicit
  iterations: 4                  # implicit only; must be a positive even integer
```
`DiffusionImpl::configureDiffusion()` parses this and forwards to `oops::Diffusion::setParameters(..., VerticalMethod::Implicit, N)`. The input length scale is interpreted as the Daley length scale of the output kernel for both schemes; the optional GC-half-width → Daley conversion (1/3.67, `as gaussian: false`) is applied beforehand.

`Diffusion` gained `variance()` (unit-variance diagonal, per the generic Variance capability above). Bugfix (PR #1273, same commit as `variance()`): `diffusion::randomize()` was missing a normalization step — it now calls `applyNormSqrt()` after `multiplySqrtTL()`. This changes the statistics of `randomize`/dirac-random draws through Diffusion central blocks on any branch that diverged from develop before this landed (driven the soca test-ref update in soca#1255).

### `spectralb/` — Spectral balance for global models (requires atlas TRANS or ECTRANS)

| Block | Purpose |
|-------|---------|
| `SpectralCovariance` / `SpectralCorrelation` | Spectral covariance/correlation |
| `SpectralToGauss` | Spectral to Gaussian grid (31KB) |
| `SpectralAnalyticalFilter` | Analytical filter (legacy, being replaced by `SpectralAnalyticalCorrelation` + filter-as-chain) |
| `SpectralAnalyticalCorrelation` | Analytical correlation central block (new, used with `SaberOuterBlockChain` filter pattern) |
| `GaussUVToGP` | Wind to geopotential |
| `HydrostaticPressure` | Hydrostatic pressure transform |
| `SqrtOfSpectralCovariance` / `SqrtOfSpectralCorrelation` | Square-root forms |

### `vader/` — VADER variable transformation integration (40+ files)

`VaderBlock` wraps VADER transformations. Implements physical variable conversions: air temperature, dry air density, geopotential↔hydrostatic pressure, hydrostatic balance, moisture control operators. `DefaultCookbook.h` defines the default transformation chain. PR #1244 added `DryMoistIncrOp` (`mo_dry_mio`) — converts dry-air ↔ moist-air-and-condensed-water mixing ratios (water vapor / cloud liquid / cloud ice), with full inverse + direct calibration; pairs with the filtering (`ResidualFields`) and updated `SuperMoistIncrOp`/`MoistureControl` changes in the same PR.

### `gsi/` — GSI (Gridpoint Statistical Interpolation) covariance

`GSIBlockChain` wraps GSI Fortran backend via linked-list pattern. Requires `gsibec` library. Supports regional fv3-jedi and mpas-jedi analyses via the `regional mode: true` YAML flag (`GSIParameters.h`); the regional path uses 2D `lats2`/`lons2` arrays in `gsi_grid_mod.f90` for non-separable grids. Field-name resolver in `gsi_covariance_mod.f90` maps `prsl ↔ air_pressure` alongside the existing `ts ↔ sst` mapping; the surface-geopotential (`phis`) lookup now matches `geopotential_at_surface` (was `geopotential_height_times_gravity_at_surface`, following the vader/fv3-jedi rename). `get_rank2_` also resolves aerosol extinction handles `ext1`/`ext2`/`ext3` ↔ `volume_extinction_in_air_due_to_aerosol_particles_lambda{1,2,3}`. Requires `gsibec` 1.4.4.

Temperature handling (PR #1254): `svfix_` does **no** JEDI-side `tv` → `t` conversion. It only marks `tv` as `filled-tv` and lets gsibec derive sensible temperature internally from `tv`/`q` (the `gsi_tv_to_t_tl`/`gsi_tv_to_t_ad` calls and the `tsen`/`filled-tv` special case are gone). Callers therefore declare `tsen` as a real `met_guess`/`state_vector` entry in the GSI namelist rather than relying on saber to synthesize it.

### `interpolation/` — Grid interpolation blocks

`Interpolation`, `GaussToCS` (Gaussian→cubed-sphere), `Rescaling`, `VertProj` (vertical projection). Uses ATLAS interpolation wrappers. SMV variants `GaussToCSWithSMV` (here) and `GaussUVToGPWithSMV` (`spectralb/`), via `SMVInterpWrapper`, use the ATLAS ≥0.46 spherical-mean-value interpolator (saber#1241; gated by `ATLAS_VERSION_46_OR_GREATER`, the renamed `ATLAS_SCOPE_ISSUE_RESOLVED`) for better-conditioned Gauss↔cubed-sphere inverse transforms via redistribution. `setupGsiMatchingGrid` was moved out of `Geometry.cc` into the new standalone `interpolation/GsiGrid.{cc,h}` (PR #1260) so it can be called outside saber; it now exposes `GsiGridKey`/`GsiPartitionerKey` and `computeS2NCheckerboardPartition` (a south-to-north GSI-matching MPI checkerboard partition). It accepts `type: rotated_lonlat` (alongside `gaussian` and `latlon`); requires `lat_start`/`lat_end`/`lon_start`/`lon_end`/`north_pole_lat`/`north_pole_lon` YAML keys and builds an ATLAS `StructuredGrid` with a rotated-lonlat projection — used to wire regional fv3/mpas analyses to GSIbec.

### `coupled/` — Block-diagonal coupled covariance (C++ only)

`CoupledErrorCovariance` implements block-diagonal B for coupled DA (e.g. atmosphere-ocean) built on `oops::TraitsCoupled<TRAIT_1, TRAIT_2>`. Each component has its own error-covariance block configured independently, and an optional **common outer block chain** is applied to the combined state (useful for cross-component localization or balance). Parameters in `CoupledErrorCovarianceParameters`; factory registration in `instantiateCoupledCovarFactory.h`. Tested via `quenchCoupledErrorCovarianceToolbox` with the `coupled_dirac_id` reference test (registered in `test/testlist/saber_coupled.cmake`).

## Fortran vs C++ Split

- **Fortran-heavy**: BUMP (58 `.fypp` templates generating `.F90`), some spectralb and vader interfaces
- **C++ only**: blocks framework, generic blocks, bifourier, fastlam, diffusion, interpolation, torchbalance, OOPS integration
- **Interop**: C++ calls Fortran via `type_bump.h` wrapper; `.fypp` templates preprocessed to `.F90`

## YAML Configuration Pattern

```yaml
background error:
  covariance model: SABER
  saber central block:
    saber block name: BUMP_NICAS    # Factory lookup name
    calibration:                     # Training parameters
      general: { testing: true }
      io: { data directory: testdata }
      drivers: { compute correlation: true }
    read:                            # Pre-computed parameter I/O
      io: { files prefix: bump }
  saber outer blocks:                # Applied in sequence
    - saber block name: StdDev
      read:
        atlas file: { filepath: stddev.nc }
    - saber block name: VertLoc
```

## Block YAML Name Reference

Central blocks (used as `saber central block: { saber block name: "<name>" }`):

| YAML Name | Class | Directory |
|-----------|-------|-----------|
| `BUMP_NICAS` | NICAS | bump/ |
| `diffusion` | Diffusion | diffusion/ |
| `spectral analytical correlation` | SpectralAnalyticalCorrelation | spectralb/ |
| `spectral covariance` | SpectralCovariance | spectralb/ |
| `spectral correlation` | SpectralCorrelation | spectralb/ |
| `BifourierCovariance` | BifourierCovariance | bifourier/ |
| `BifourierAromeCovariance` | BifourierAromeCovariance | bifourier/ |
| `BifourierID` | BifourierID | bifourier/ |
| `FastLAM` | FastLAM | fastlam/ |
| `gsi static covariance` | Covariance | gsi/ |
| `ID` | ID | generic/ |

Outer blocks (used in `saber outer blocks: [{ saber block name: "<name>" }]`):

| YAML Name | Class | Directory |
|-----------|-------|-----------|
| `BUMP_StdDev` | StdDev | bump/ |
| `BUMP_VerticalBalance` | VerticalBalance | bump/ |
| `BUMP_PsiChiToUV` | PsiChiToUV | bump/ |
| `StdDev` | StdDev | generic/ |
| `ID` | ID | generic/ |
| `VertLoc` | VertLoc | generic/ |
| `ShadowLevels` | ShadowLevels | generic/ |
| `duplicate variables` | DuplicateVariables | generic/ |
| `OrographicInterp` | OrographicInterp | generic/ |
| `write fields` | WriteFields | generic/ |
| `residual fields` | ResidualFields | generic/ |
| `interpolation` | Interpolation | interpolation/ |
| `gauss to cubed-sphere-dual` | GaussToCS | interpolation/ |
| `gauss to cubed-sphere-dual with smv-interp` | GaussToCSWithSMV | interpolation/ |
| `simple vertical projection` | VertProj | interpolation/ |
| `spectral to gauss` | SpectralToGauss | spectralb/ |
| `spectral to spectral` | SpectralToSpectral | spectralb/ |
| `BUMP_NICASFilter` | NICASFilter | bump/ |
| `diffusion filter` | DiffusionFilter | diffusion/ |
| `spectral analytical filter` | SpectralAnalyticalFilter | spectralb/ |
| `square root of spectral covariance` | SqrtOfSpectralCovariance | spectralb/ |
| `square root of spectral correlation` | SqrtOfSpectralCorrelation | spectralb/ |
| `gauss winds to geostrophic pressure` | GaussUVToGP | spectralb/ |
| `gauss winds to geostrophic pressure with smv-interp` | GaussUVToGPWithSMV | spectralb/ |
| `mo_hydrostatic_pressure` | HydrostaticPressure | spectralb/ |
| `vader variable change` | VaderBlock | vader/ |
| `mo_air_temperature` | AirTemperature | vader/ |
| `mo_dry_air_density` | DryAirDensity | vader/ |
| `mo_hydro_bal` | HydroBal | vader/ |
| `mo_moistincrop` | MoistIncrOp | vader/ |
| `mo_moisture_control` | MoistureControl | vader/ |
| `mo_dry_mio` | DryMoistIncrOp | vader/ |
| `BifourierBalance` | BifourierBalance | bifourier/ |
| `BifourierAromeBalance` | BifourierAromeBalance | bifourier/ |
| `BifourierSpectralToGrid` | BifourierSpectralToGrid | bifourier/ |
| `BifourierGridToSpectral` | BifourierGridToSpectral | bifourier/ |
| `Biperiodization` | Biperiodization | bifourier/ |
| `BifourierAnalyticalFilter` | BifourierAnalyticalFilter | bifourier/ |
| `BifourierCovarianceSqrt` | BifourierCovarianceSqrt | bifourier/ |
| `BifourierSpectralConverter` | BifourierSpectralConverter | bifourier/ |
| `TorchBalance` | TorchBalance | torchbalance/ |

## Calibration Modes

Blocks support multiple calibration strategies:
- **Direct**: compute statistics from full ensemble in memory
- **Iterative**: stream ensemble members one at a time (lower memory)
- **Read**: load pre-computed parameters from files
- **Force write**: always save calibration results

**writeVariances** calibration block: Accumulates ensemble statistics (variances, vertical covariances, cross-variable covariances). Supports binning strategies: global horizontal average, per-grid-point, or overlapping area-weighted latitude bands. Outputs NetCDF files.

### `torchbalance/` — ML-based balance operator (requires PyTorch/LibTorch)

`TorchBalance` outer block. Loads pre-trained TorchScript emulators that compute Jacobians between variables (e.g., ∂SST/∂air_temperature). At initialization, calls each emulator's `jac_physical(inputs, mask)` method on the trajectory to compute per-grid-point Jacobian fields. `multiply()` applies `Δoutput += Σ (∂output/∂input_j) × Δinput_j`; `multiplyAD()` applies the transpose. Supports optional masking (e.g., land/ice fraction). Generalization of soca's `MLBalance` — same concept but fully configurable for any variables.

Key classes: `TorchBalance` (SABER block), `TorchBalanceSurfaceEmulator` (surface TorchScript wrapper, `setupSurfaceEmulator`; renamed from `TorchBalanceEmulator` in PR #1247) and `TorchBalanceVerticalEmulator` (`setupVerticalEmulator`, PR #1247). The vertical emulator handles full-column input profiles and emits a compact vertical-block Jacobian; per-level counts are inferred from the Atlas field shapes, so the TorchScript model needs no explicit level attributes. Training is external to JEDI; `create_test_emulator.py` shows the required model interface.

Config: `surface emulators:` and `vertical emulators:` are both optional lists under the block.
```yaml
saber outer blocks:
  - saber block name: TorchBalance
    surface emulators:
      - name: sea_water_potential_temperature
        path: ./model.ts
        jacobian wrt: [var1, var2]
        jacobian masking:
          variable: land_ice_area_fraction
          level: 0
    vertical emulators:
      - name: air_temperature
        path: ./model_vert.ts
        jacobian wrt: [var1, var2]
```

## Testing Patterns

- **DIRAC tests**: impulse response — apply covariance to delta function, verify spatial structure
- **Adjoint tests**: finite-difference verification of multiply/multiplyAD consistency
- **Inverse tests**: verify U * U^{-1} = I
- **Square-root tests**: verify U * U^T = B
- Tolerance parameters configurable per test via `adjoint tolerance` in block config
