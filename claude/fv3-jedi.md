# FV3-JEDI

> Last updated against commit `9ddb5c5f` (2026-04-14). Run `cd bundle/fv3-jedi && git log --oneline 9ddb5c5f..HEAD` to see what changed since.

## Overview

Interface between JEDI and FV3-based models (GEOS, GFS, UFS). Supports global and LAM (Limited Area Model) domains on cubed-sphere geometry. Source at `bundle/fv3-jedi/`. Version 1.9.0. C++17/Fortran 2008.

## Build

```bash
# From build directory
make fv3-jedi

# CMake options
# FV3_FORECAST_MODEL: GEOS | UFS | FV3CORE
# FV3_PRECISION: DOUBLE (default) | SINGLE
# OPENMP: ON (default)
```

Dependencies: oops ≥1.10.0, saber ≥1.10.0, ufo ≥1.10.0, atlas ≥0.35.0, vader ≥1.7.0, fv3-jedi-lm ≥1.5.0, FMS 2023.04, NetCDF, MPI. Optional: crtm, gsibec, GEOS GCM, UFS.

## Tests

```bash
ctest --output-on-failure -R fv3jedi
ctest -N -R fv3jedi
```

Test configs in `test/testinput/` (~100+ YAMLs). Categories: 3DVAR, 4DVAR (GEOS/GFS/LAM), ensemble methods (EnVar/EDA/LETKF), variable transforms, format conversions. Test CMakeLists.txt is ~2700 lines.

## OOPS Traits (`src/fv3jedi/Utilities/Traits.h`)

Maps all oops abstract types to fv3jedi implementations:

| oops Type | fv3jedi Class |
|-----------|--------------|
| Geometry | `fv3jedi::Geometry` |
| State | `fv3jedi::State` |
| Increment | `fv3jedi::Increment` |
| Model | `fv3jedi::ModelWrapper` |
| LinearModel | `fv3jedi::Tlm` |
| Covariance | `fv3jedi::ErrorCovariance` |
| VariableChange | `fv3jedi::VariableChange` |
| LinearVariableChange | `fv3jedi::LinearVariableChange` |
| LocalInterpolator | `oops::UnstructuredInterpolator` |
| ObsLocalization | `ufo::ObsLocalization` |

## Source Layout (`src/fv3jedi/`)

### Geometry (`Geometry/`)
Manages cubed-sphere grid: dimensions (npx, npy, npz), ntiles (6 for global), vertical hybrid coordinates (ak/bk), FMS initialization. Fortran modules handle FV3 grid generation (`fv3_control.F90`, `fv3_grid_tools.F90`, `fv3_eta.F90`, `fv3_mp_mod.F90`).

Key config: `akbk` file path, `layout` (MPI decomposition), `io_layout`, `field table`, `namelist`.

### State / Increment (`State/`, `Increment/`)
Hold variables at a datetime via ATLAS FieldSet. State supports `read()`, `write()`, `analytic_init()` (DCMIP test cases). Increment provides linear algebra (`axpy`, `dot_product_with`, `schur_product_with`, `dirac`), serialization for MPI, and `getLocal`/`setLocal` for localization.

### Fields & FieldMetadata (`Fields/`, `FieldMetadata/`)
`FieldsMetadata` describes each field: long name, levels, data kind (R4/R8), tracer flag, units, mathematical space. `FieldsMetadataDefault.h` provides defaults for GEOS/GFS.

### Model (`Model/`)
`ModelWrapper` dispatches to concrete implementations via factory:
- **`ModelFV3LM`** — linearized FV3 dynamical core (from fv3-jedi-lm)
- **`ModelGEOS`** — GEOS GCM integration
- **`ModelUFS`** — UFS ATM coupling (ATM-only, ATMAERO, S2S)
- **`ModelPseudo`** — identity/no-op (testing)

Interface: `initialize(State&)`, `step(State&, ModelBias&)`, `finalize(State&)`.

### Tangent Linear Model (`Tlm/`)
`Tlm` wraps fv3-jedi-lm for TL/AD. Stores trajectory as `std::map<DateTime, F90traj>`. Methods: `setTrajectory()`, `stepTL()`, `stepAD()`.

### Variable Changes (`VariableChange/`, `LinearVariableChange/`)
`VariableChange` chains VADER with fv3jedi-specific transforms:
- **Control2Analysis** — control variables → analysis variables
- **Model2GeoVaLs** — model grid → observation locations

Fortran helper modules in `Utils/`: `pressure_variables_mod.f90`, `temperature_variables_mod.f90`, `moisture_variables_mod.f90`, `height_variables_mod.f90`, `wind_variables_mod.f90`, `surface_variables_mod.f90`.

FEMPS (Finite Element Multigrid Pressure Solver) in `femps/` for geopotential calculation.

### I/O System (`IO/`)
`IOBase` abstract factory with three backends:
- **FV3Restart** (`IOFms`) — FMS restart files (native FV3 format)
- **CubeSphereHistory** — cube-sphere tile structure
- **StructuredGrid** (`IOStructuredGrid`) — interpolated regular lat/lon via GlobalInterpolator

Config key: `filetype` in YAML (`fv3 restart`, `cube sphere history`, `structured grid`).

### ErrorCovariance (`ErrorCovariance/`)
Delegates to SABER for background error covariance.

## Executables (`src/mains/`)

| Executable | Purpose |
|-----------|---------|
| `fv3jediVar` | 3D/4D variational DA |
| `fv3jediForecast` | Nonlinear forecast |
| `fv3jediHofX` / `fv3jediHofXNoModel` | Observation operator H(x) |
| `fv3jediEDA` | Ensemble Data Assimilation |
| `fv3jediLETKF` / `fv3jediEnsGETKF` | Local ensemble methods |
| `fv3jediAddIncrement` | Apply analysis increments |
| `fv3jediConvertState` | Variable transformations |
| `fv3jediConvertToStructuredGrid` | Cube sphere → lat/lon |
| `fv3jediDiffStates` | State difference |
| `fv3jediErrorCovarianceToolbox` | Covariance manipulation |
| `fv3jediAtoD.f90` / `fv3jediDtoA.f90` | A-grid/D-grid wind transform |

## Linear Model Package (fv3-jedi-lm)

Separate repo at `bundle/fv3-jedi-lm/`. Provides linearized FV3 dynamical core and physics:
- `src/dynamics/atmos_cubed_sphere/model_tlmadm/` — TL/AD of FV3 dynamics
- `src/physics/` — linearized moist, GWD, radiation, turbulence physics
- `src/utils/tapenade/` — automatic differentiation utilities

## Fortran vs C++ Split

- **Fortran**: I/O (FMS/NetCDF), geometry/grid setup (FV3 core), state/increment data containers, model integration, TLM/adjoint, field operations, variable change physics
- **C++**: OOPS interface layer (Traits, wrappers), configuration, variable change orchestration, factories, main executables
- **Bridge**: `*.interface.h` files with `extern "C"` functions, F90 registry pattern for object handles

## YAML Configuration Pattern

```yaml
geometry:
  akbk: Data/fv3files/akbk64.nc4
  npx: 13
  npy: 13
  npz: 64
  layout: [1, 1]
  field table: Data/fv3files/field_table_gfdl
  fms initialization:
    namelist filename: Data/fv3files/input_geos_c12.nml

background:
  datetime: 2020-12-15T00:00:00Z
  filetype: cube sphere history
  provider: geos
  datapath: Data/inputs/geos_c12
  state variables: [ua, va, t, ps, ...]

background error:
  covariance model: SABER
  saber central block: { ... }
```
