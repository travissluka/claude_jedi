# MPAS-JEDI

> Last updated against commit `2aaa03e5` (2026-07-23). Run `cd bundle/mpas-jedi && git log --oneline 2aaa03e5..HEAD` to see what changed since.
>
> **Covers:** mpas::Traits, mpas::{Geometry,State,Increment,Model,LinearModel,VariableChange}, unstructured Voronoi mesh, MPAS 8.0 core_atmosphere integration, variable-resolution support, RTTOV/ROPP-UFO optional operators, opaque-handle Fortran pattern.

## Overview

Interface between JEDI and the Model for Prediction Across Scales (MPAS) atmospheric model. MPAS uses an unstructured Voronoi mesh (variable-resolution capability). Source at `bundle/mpas-jedi/`. Version 3.1.0. C++17/Fortran 2008.

Build/test quirks (MPAS 8.0 `core_atmosphere`, optional RTTOV/ROPP-UFO) in `claude/build-and-test.md`. Test categories: 3dvar, 3denvar, 4denvar, EDA, error covariance, dirac. Offline covariance processing scripts in `test/covariance/`.

## OOPS Traits (`src/mpasjedi/Traits.h`)

| oops Type | mpas-jedi Class |
|-----------|----------------|
| Geometry | `mpas::Geometry` |
| State | `mpas::State` |
| Increment | `mpas::Increment` |
| Model | `mpas::Model` |
| LinearModel | `mpas::Tlm` |
| Covariance | `mpas::ErrorCovariance` |
| VariableChange | `mpas::VariableChange` |
| LinearVariableChange | `mpas::LinearVariableChange` |
| LocalInterpolator | `oops::UnstructuredInterpolator` |
| ObsLocalization | `ufo::ObsLocalization` |

## Source Layout (`src/mpasjedi/`)

### Fortran-C++ Bridge (`Fortran.h`)

All Fortran objects accessed via opaque integer handles (`F90geom`, `F90state`, `F90inc`, `F90model`, `F90traj`, etc.). Each C++ class holds a handle and calls `extern "C"` functions with `_f90` suffix.

### Geometry (`Geometry/`)
Wraps MPAS mesh in ATLAS `NodeColumns` function space. Reads MPAS namelist/streams files. Provides domain decomposition, coordinates, and connectivity to ATLAS MeshBuilder. Levels are top-down (flipped from MPAS bottom-to-top convention). Exposes a public `isRegional() const` method (backed by `mpas_geo_is_regional_f90`) so callers can detect a regional mesh; added in mpas-jedi #1207 to replace the old unsafe `"regional check enabled": false` bypass after oops #3313 removed that interpolator flag.

### State / Increment (`State/`, `Increment/`)
State holds prognostic variables via Fortran `mpas_fields` type. Converts to/from ATLAS FieldSet for SABER/UFO interaction. Increment provides full linear algebra (`axpy`, `dot_product_with`, `schur_product_with`, `dirac`), serialization, and `getLocal`/`setLocal` for localization.

`State::add_incr` optionally refreshes the diagnostic 2 m temperature and 2 m water-vapor mixing ratio from the lowest model level after each outer-loop update — gated by Geometry YAML key `update 2mTQ between outer loops` (default `false`; mpas-jedi #1174). Enable when downstream H(x) consumes the 2 m fields and outer loops are large enough that the lowest model level drifts significantly from the post-add state.

`State::changeResolution` / `Increment::changeResolution` use the OOPS unstructured-grid global interpolator with nearest-neighbor fill for points outside the source mesh; fill radius is configurable via Geometry YAML key `regional nn fill distance in km` (default `500.0` km; mpas-jedi #1199). As of mpas-jedi #1207 the NN-fill distance is passed to the interpolator only when `isRegional()` is true (the previous `"regional check enabled": false` bypass was dropped). Tune this for regional/multi-resolution meshes where the source and target mesh boundaries don't fully overlap — too small and target points outside the source mesh stay missing, too large and edge points are pulled from far-away neighbors. Used by `3denvar_multi_resolution_regional` and `3dvar_bumpcov_rttovcpp` tests.

### Fields (`Fields/`)
Fortran `mpas_fields` type: wraps MPAS pool of fields with array operations (`axpy`, `dot_prod`, `gpnorm`, `rms`). Handles I/O via MPAS stream manager.

### Model (`Model/`)
Nonlinear forward model wrapping MPAS `core_atmosphere`. Holds `domain_type` and `core_type` pointers to MPAS C structures. Interface: `initialize()`, `step()`, `finalize()`, `saveTrajectory()`.

### Tangent Linear Model (`Tlm/`)
TL/AD model. Stores trajectory as `std::map<DateTime, F90traj>`. Methods: `setTrajectory()`, `stepTL()`/`stepAD()`.

### Variable Changes (`VariableChange/`, `LinearVariableChange/`)

**Nonlinear** (`VariableChange/`):
- **Model2GeoVars** — model variables (theta, rho, u) ↔ geophysical variables (T, qv, wind)
- Factory-based: `VariableChangeFactory` with `VariableChangeMaker<T>` registration

**Linear** (`LinearVariableChange/`):
- **Control2Analysis** — 2D surface pressure → 3D pressure/temperature (hydrostatic balance)
- **Model2GeoVars** — linear version with TL/AD
- Factory-based with trajectory support

### ErrorCovariance (`Covariance/`)
Delegates to SABER via Fortran. Supports BUMP, NICAS, VBalance.

### ModelBias (`ModelBias/`)
Empty stubs — MPAS-JEDI does not use model bias estimation. All methods are no-ops.

### GeometryIterator (`GeometryIterator/`)
3D grid point iterator (cell index + level). Used for localization in ensemble DA.

## Executables (`src/mains/`)

| Executable | Purpose |
|-----------|---------|
| `mpas_variational.x` | 3D/4D variational DA |
| `mpas_eda.x` | Ensemble Data Assimilation |
| `mpas_enkf.x` | Ensemble Kalman Filter |
| `mpas_forecast.x` | Model forecast |
| `mpas_hofx.x` / `mpas_hofx3d.x` | H(x) computation |
| `mpas_enshofx.x` | Ensemble H(x) |
| `mpas_saca.x` | Satellite cloud/aerosol analysis |
| `mpas_error_covariance_toolbox.x` | Covariance tools |
| `mpas_gen_ens_pert_B.x` | Generate ensemble perturbations |
| `mpas_rtpp.x` | Relaxation-To-Prior Perturbation |
| `mpas_convertstate.x` | State conversion |

## Key State Variables

**Prognostic**: `air_potential_temperature` (theta), `dry_air_density` (rho), `u` (edge-normal wind), `water_vapor_mixing_ratio_wrt_moist_air` (qv)

**Diagnostic/Analysis**: `air_temperature`, `air_pressure`, `eastward_wind`, `northward_wind`, `air_pressure_at_surface`

**Surface**: `skin_temperature_at_surface`, `seaice_fraction`, `snowc`, `snowh`, `vegetation_area_fraction`, `landmask`, `ivgtyp`, `isltyp`

## GetValues / Observation Integration

MPAS-JEDI does not implement GetValues directly. Instead:
1. State → `toFieldSet()` → ATLAS FieldSet
2. ATLAS NodeColumns function space on MPAS triangular mesh
3. UFO handles interpolation to observation locations
4. Variable mappings in `mpas2ufo_vars_mod` Fortran module

## Fortran vs C++ Split

- **Fortran**: field storage (`mpas_fields_mod`), model integration (`mpas_model_mod`), geometry/mesh (`mpas_geom_mod`), state/increment operations, I/O (MPAS streams), variable change physics, SABER interface
- **C++**: OOPS wrappers, configuration (Parameters), factories, ATLAS integration, main executables
- **Bridge**: `*.interface.h` with `extern "C"` + opaque integer handles
