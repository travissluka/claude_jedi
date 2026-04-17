# SABER (System for Atmospheric and Boundary Layer Error Representation)

> Last updated against commit `8ae1ea2b` (2026-04-16). Run `cd bundle/saber && git log --oneline 8ae1ea2b..HEAD` to see what changed since.

## Overview

C++/Fortran framework for building modular, composable error covariance models in JEDI. Source at `bundle/saber/`. Version 1.10.0.

SABER's core idea: error covariance operators are built by composing **blocks** into **chains**. Central blocks are self-adjoint (B = U U^T); outer blocks are preprocessing transforms applied before/after the central block.

**B matrix decomposition**: `B = T V K Σ C Σ Kᵀ Vᵀ Tᵀ` where T = variable transform (VADER), V = vertical balance, K = vertical localization, Σ = standard deviation scaling, C = horizontal correlation (BUMP_NICAS, Diffusion, etc.). Each factor is a SABER block. Outer blocks (T, V, K, Σ) wrap the central block (C).

## Build

```bash
# From build directory
make saber

# Build options (set in bundle CMakeLists.txt or via -D flags)
# ENABLE_BUMP (ON): BUMP correlation/localization
# ENABLE_QUENCH (ON): QUENCH testbed (pseudo-model for testing blocks with any ATLAS grid)
# ENABLE_MKL (ON): Use MKL for LAPACK
# OPENMP (ON): OpenMP parallelism
```

Conditional blocks depending on available libraries:
- **Bifourier**: requires FFTW or (ECTRANS + transi)
- **FastLAM**: requires FFTW
- **GSI**: requires gsibec
- **SpectralB**: requires atlas TRANS or ECTRANS

Dependencies: oops ≥1.10.0, vader ≥1.7.0, eckit ≥1.17.1, fckit ≥0.9.5, atlas ≥0.35.0, LAPACK, MPI, NetCDF, OpenMP.

## Tests

```bash
ctest --output-on-failure -R saber       # All SABER tests
ctest --output-on-failure -R dirac       # Impulse response tests
ctest --output-on-failure -R randomization  # Randomization tests
ctest -N -R saber                        # List tests
```

Test structure:
- `test/testinput/` — ~250 YAML configs
- `test/testref/` — reference outputs
- `test/fctest/` — Fortran unit tests

Test categories: DIRAC (impulse response), randomization, calibration/training, diagnostics, format conversion.

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
- Ensemble sources: states, perturbations, base+perturbations, pair differences, or on alternative geometry
- Config keys: `ensemble`, `localization`, `ensemble transform`, `inflation field`, `inflation value`

**`SaberHybridBlockChain`** — Weighted combination of multiple covariances:
- Outer blocks + weighted components (each a full covariance + weight)
- Config key: `components` (array of `covariance` + `weight`)

**`SaberOuterBlockChain`** — Sequences outer blocks, handles reverse-order adjoint application. Also used as the implementation basis for **filter blocks**: `NICASFilter`, `DiffusionFilter`, and `SpectralAnalyticalCorrelation` are central blocks that internally wrap a `SaberOuterBlockChain` to apply localization/correlation as a self-contained filter (replacing the older monolithic filter classes).

**`SaberCentralBlock`** — Container for multivariate central blocks:
- Strategies: "duplicated" (replicate per variable group), "duplicated and weighted" (with off-diagonal weights)

### OOPS Integration

`ErrorCovariance<MODEL>` (`src/saber/oops/`) inherits `oops::ModelSpaceCovarianceBase<MODEL>` and creates a block chain via `SaberBlockChainFactory<MODEL>::create()`. The factory examines `covariance type` in config (parametric/ensemble/hybrid/gsi).

SABER operates on `atlas::FieldSet` — it converts `MODEL::Increment` via the model's `toFieldSet()`/`fromFieldSet()` methods. This is why SABER works with any model without knowing model internals.

Other OOPS integration:
- **`Localization<MODEL>`** — wraps SABER blocks for ensemble localization
- **`ErrorCovarianceToolbox<MODEL>`** — diagnostic application: Dirac impulse-response tests, covariance profiles (1D function of separation distance), randomization (generate dx ~ B, compute variance from ensemble)
- **`ProcessPerts<MODEL>`** — processes ensemble perturbations through band filters (SABER block chains), with recursive filtering option and multiple output modes

### Factory Pattern

- `SaberCentralBlockFactory` / `SaberCentralBlockMaker<T>` — central blocks by name
- `SaberOuterBlockFactory` — outer blocks by name
- `SaberBlockChainFactory<MODEL>` / `SaberBlockChainMaker<MODEL,T>` — chain types
- Registration via `instantiateCovarFactory.h`, `instantiateLocalizationFactory.h`

## QUENCH Testbed (`quench/`)

Not a block — a pseudo-model for testing SABER blocks with any ATLAS grid. Implements minimal OOPS model types (Geometry, State, Increment, VariableChange) to enable running `ErrorCovarianceToolbox` and `ProcessPerts` without a real atmospheric model. Main executables: `quenchErrorCovarianceToolbox`, `quenchProcessPerts`, `quenchCoupledErrorCovarianceToolbox` (for testing the coupled covariance; uses `oops::TraitsCoupled<quench::Traits, quench::Traits>`). Enabled via `ENABLE_QUENCH` CMake option.

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
| `WriteFields` | Output intermediate fields for debugging |

### `bump/` — BUMP (Background error on Unstructured Mesh Package) — Fortran-heavy

The largest SABER component. 58 `.fypp` Fortran templates + C++ wrappers.

Key blocks:
- **`BUMP_NICAS`** — Normalized Interpolated Covariance by Analysis Statistics (ensemble-based correlation/localization)
- **`PsiChiToUV`** — Stream function/velocity potential to wind
- **`VerticalBalance`** — Vertical balance operator
- **`StdDev`** (BUMP variant) — Standard deviation from BUMP

C++ wrappers: `BUMP.h`, `NICAS.h`, `type_bump.h`. Extensive configuration via `BUMPParameters.h` (~29KB) covering: general settings, I/O, drivers (correlation/localization/balance/moments/diagnostics), sampling, and output.

### `bifourier/` — Spectral covariance via bidirectional Fourier (requires FFTW or ECTRANS)

| Block | Purpose |
|-------|---------|
| `BifourierCovariance` | Main spectral covariance block (39KB impl) |
| `BifourierBalance` | Balance operator (48KB impl) |
| `BifourierAromeBalance` | AROME-specific balance (32KB impl) |
| `BifourierAromeCovariance` | AROME covariance variant |
| `BifourierGridToSpectral` / `BifourierSpectralToGrid` | Transform blocks |
| `BifourierID` | Identity in spectral space |

Transform backends: `BifourierTransformFFTW`, `BifourierTransformECTRANS`.

### `fastlam/` — Fast Limited Area Model correlation (requires FFTW)

Main block: `FastLAM` (59KB impl). Layer types: `LayerSpec` (spectral), `LayerHalo`, `LayerRC` (regional covariance). Supports iterative calibration.

### `diffusion/` — Explicit diffusion localization (C++ only)

`Diffusion` block (28KB impl). Better than NICAS for small correlation length-scales. Direct calibration from ensemble. Filter mode support. Implementation split: `DiffusionImpl` handles the core diffusion math, `Diffusion` wraps it as a central block. `DiffusionFilter` wraps it as a `SaberOuterBlockChain`-based filter.

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

`VaderBlock` wraps VADER transformations. Implements physical variable conversions: air temperature, dry air density, geopotential↔hydrostatic pressure, hydrostatic balance, moisture control operators. `DefaultCookbook.h` defines the default transformation chain.

### `gsi/` — GSI (Gridpoint Statistical Interpolation) covariance

`GSIBlockChain` wraps GSI Fortran backend via linked-list pattern. Requires `gsibec` library.

### `interpolation/` — Grid interpolation blocks

`Interpolation`, `GaussToCS` (Gaussian→cubed-sphere), `Rescaling`, `VertProj` (vertical projection). Uses ATLAS interpolation wrappers.

### `coupled/` — Block-diagonal coupled covariance (C++ only)

`CoupledErrorCovariance` implements block-diagonal B for coupled DA (e.g. atmosphere-ocean) built on `oops::TraitsCoupled<TRAIT_1, TRAIT_2>`. Each component has its own error-covariance block configured independently, and an optional **common outer block chain** is applied to the combined state (useful for cross-component localization or balance). Parameters in `CoupledErrorCovarianceParameters`; factory registration in `instantiateCoupledCovarFactory.h`. Tested via `quenchCoupledErrorCovarianceToolbox` with the `coupled_dirac_id` reference test (listed in `saber_test_tier1-coupled.txt`).

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
| `interpolation` | Interpolation | interpolation/ |
| `gauss to cubed-sphere-dual` | GaussToCS | interpolation/ |
| `simple vertical projection` | VertProj | interpolation/ |
| `spectral to gauss` | SpectralToGauss | spectralb/ |
| `spectral to spectral` | SpectralToSpectral | spectralb/ |
| `BUMP_NICASFilter` | NICASFilter | bump/ |
| `diffusion filter` | DiffusionFilter | diffusion/ |
| `spectral analytical filter` | SpectralAnalyticalFilter | spectralb/ |
| `square root of spectral covariance` | SqrtOfSpectralCovariance | spectralb/ |
| `square root of spectral correlation` | SqrtOfSpectralCorrelation | spectralb/ |
| `gauss winds to geostrophic pressure` | GaussUVToGP | spectralb/ |
| `mo_hydrostatic_pressure` | HydrostaticPressure | spectralb/ |
| `vader variable change` | VaderBlock | vader/ |
| `mo_air_temperature` | AirTemperature | vader/ |
| `mo_dry_air_density` | DryAirDensity | vader/ |
| `mo_hydro_bal` | HydroBal | vader/ |
| `mo_moistincrop` | MoistIncrOp | vader/ |
| `mo_moisture_control` | MoistureControl | vader/ |
| `BifourierBalance` | BifourierBalance | bifourier/ |
| `BifourierAromeBalance` | BifourierAromeBalance | bifourier/ |
| `BifourierSpectralToGrid` | BifourierSpectralToGrid | bifourier/ |
| `BifourierGridToSpectral` | BifourierGridToSpectral | bifourier/ |
| `Biperiodization` | Biperiodization | bifourier/ |
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

Key classes: `TorchBalance` (SABER block), `TorchBalanceEmulator` (TorchScript model wrapper). Training is external to JEDI; `create_test_emulator.py` shows the required model interface.

Config:
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
```

## Testing Patterns

- **DIRAC tests**: impulse response — apply covariance to delta function, verify spatial structure
- **Adjoint tests**: finite-difference verification of multiply/multiplyAD consistency
- **Inverse tests**: verify U * U^{-1} = I
- **Square-root tests**: verify U * U^T = B
- Tolerance parameters configurable per test via `adjoint tolerance` in block config
