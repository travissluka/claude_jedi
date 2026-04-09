# SOCA (Sea-ice, Ocean, and Coupled Assimilation)

> Last updated against commit `9d89b9da` (2026-04-09). Run `cd bundle/soca && git log --oneline 9d89b9da..HEAD` to see what changed since.

## Overview

Ocean/sea-ice data assimilation interface for JEDI, coupling MOM6 (ocean) and Icepack (sea ice) with the oops DA framework. Source at `bundle/soca/`. Version 1.8.0. C++/Fortran.

## Build

```bash
# From build directory
make soca

# Tests
ctest --output-on-failure -R soca
ctest -N -R soca   # List tests
```

Dependencies: oops ≥1.10.0, saber ≥1.10.0, ioda ≥2.9.0, ufo ≥1.10.0, vader ≥1.7.0, atlas ≥0.35.0, eckit ≥1.24.4, fckit ≥0.11.0, FMS 2023.3.0 (R8), NetCDF (C+Fortran), GSL-lite, OpenMP. External models: MOM6 (`external/mom6`), Icepack (`external/icepack`). Optional: Torch (enables MLBalance SABER block).

## OOPS Traits (`src/soca/Traits.h`)

| oops Type | soca Class |
|-----------|-----------|
| Geometry | `soca::Geometry` |
| GeometryIterator | `soca::GeometryIterator` |
| State | `soca::State` |
| Increment | `soca::Increment` |
| Model | `soca::ModelOceanIceEmulator` |
| LinearModel | `soca::LinearModelOceanIceEmulator` |
| Covariance | `soca::ErrorCovariance` (empty stub — uses SABER instead) |
| VariableChange | `soca::VariableChange` |
| LinearVariableChange | `soca::LinearVariableChange` |
| LocalInterpolator | `oops::UnstructuredInterpolator` |
| ObsLocalization | `ufo::ObsLocalization<GeometryIterator>` |
| ModelAuxControl | `soca::ModelBias` |
| ModelData | `soca::ModelData` |

## Source Layout (`src/soca/`)

| Directory | Purpose |
|-----------|---------|
| `Geometry/` | Ocean grid (ATLAS NodeColumns), FMS config, vertical coords |
| `GeometryIterator/` | 3D grid point iterator (lon, lat, depth) for obs localization |
| `State/` | Full model state (extends Fields) |
| `Increment/` | Perturbation/analysis increment (extends Fields) |
| `Fields/` | Common base for State/Increment — wraps ATLAS FieldSet |
| `Model/OceanIceEmulator/` | Nonlinear model (pseudo-model, no actual MOM6 dynamics) |
| `LinearModel/OceanIceEmulator/` | TLM/ADM interface |
| `VariableChange/` | Nonlinear variable transforms (factory-based) |
| `LinearVariableChange/` | TL/AD variable transforms (factory-based) |
| `MLBalance/` | ML-based balance operator (SABER outer block, requires Torch) |
| `SaberBlocks/` | Custom SABER outer blocks (BkgErrFilt, ParametricOceanStdDev) |
| `ObsLocalization/` | Rossby radius-based obs localization |
| `Covariance/` | ErrorCovariance stub (throws NotImplemented) |
| `ModelBias/` | Model bias control variable (mostly stubs) |
| `ModelData/` | Default variable list and model metadata |
| `AnalyticInit/` | Analytic GeoVaLs initialization for testing |
| `Utils/` | Ocean smoother, QC functions, increment QC utilities |

## Core Architecture

### Geometry (`Geometry/`)

Manages the 3D ocean grid using ATLAS `NodeColumns` function space on a curvilinear Arakawa C-grid (from MOM6). Key aspects:

- **FMS integration**: `FmsInput` manages MOM6 `input.nml` namelist configuration
- **Vertical**: Z-coordinate levels, top-down (`levelsAreTopDown() = true`)
- **Staggered grids**: `tohgrid()` / `tocgrid()` for H-grid ↔ C-grid transforms
- **Iterator**: `GeometryIterator` provides 2D or 3D iteration (configurable via `IteratorDimension`)
- `FieldsMetadata` stores per-field metadata (units, levels, staggering)

### State / Increment / Fields

`Fields` is the common base class wrapping `atlas::FieldSet`. State and Increment extend it:

- **State**: read/write via FMS/NetCDF backend, `rotate2north`/`rotate2grid` for wind rotation, `logtrans`/`expontrans` for log-space variables
- **Increment**: linear algebra (`axpy`, `dot_product_with`, `schur_product_with`), `getLocal`/`setLocal` via GeometryIterator, `diff` between states, `rmsByLevel`
- **Serialization**: both support serialize/deserialize for MPI communication

### Model (`Model/OceanIceEmulator/`)

`ModelOceanIceEmulator` is a pseudo-model — it does not propagate MOM6/Icepack dynamics. Used for DA cycling where model integration happens externally. The linear model (`LinearModelOceanIceEmulator`) provides TLM/ADM wrappers with trajectory management.

### Variable Changes

Two factory hierarchies:

**Nonlinear** (`VariableChange/`):
| Registered Name | Class | Purpose |
|----------------|-------|---------|
| `"Model2GeoVaLs"` | `Model2GeoVaLs` | Model → observation space |
| `"Model2Ana"` | `Model2Ana` | Model → analysis variables |
| `"Soca2Cice"` | `Soca2Cice` | SOCA → CICE format |

VADER is used for generic transforms before falling back to soca-specific ones.

**Linear (TL/AD)** (`LinearVariableChange/`):
| Class | Purpose |
|-------|---------|
| `Balance` | Linearized balance equation (T/S → SSH coupling) |
| `LinearModel2GeoVaLs` | TL/AD version of Model2GeoVaLs |

### SABER Blocks

Three custom SABER outer blocks for background error covariance:

| YAML Name | Class | Purpose |
|-----------|-------|---------|
| `"SOCABkgErrFilt"` | `BkgErrFilt` | Depth-dependent error rescaling |
| `"ParametricOceanStdDev"` | `ParametricOceanStdDev` | Parametric standard deviation |
| `"MLBalance"` | `MLBalance` | Machine learning balance (Torch, conditional build) |

These are used in SABER outer block chains for ocean error covariance modeling.

### Obs Localization (`ObsLocalization/`)

`ObsLocRossby` — custom localization registered as `"Rossby"`. Inherits from `ufo::ObsHorLocGC99<GeometryIterator>` and scales the Gaspari-Cohn localization radius by the local Rossby radius of deformation. Has a stub `computeLocalization(Point3, Point3)` that throws ABORT (Rossby-based localization needs `GeometryIterator::getFieldValue()` which doesn't work for obs-obs point pairs — sequential EnKF support requires rework).

## Fortran Interop

Uses the **opaque handle pattern**. Integer handles defined in `Fortran.h`:

| Handle | Fortran Module |
|--------|---------------|
| `F90geom` | `soca_geom_mod` |
| `F90flds` | `soca_fields_mod` (State + Increment) |
| `F90iter` | `soca_geom_iter_mod` |
| `F90model` | `soca_model_mod` |
| `F90bmat` | `soca_covariance_mod` |

C++ ↔ Fortran bridge via `*.interface.F90` files. ATLAS FieldSet provides shared memory between C++ and Fortran.

## I/O

State/Increment read and write through FMS/NetCDF via Fortran modules (`soca_state_mod`, `soca_increment_mod`). MOM6 restart format used for state files. The `readNcAndInterp.h` utility provides generic NetCDF interpolation. The `MLBalance/KEmul/IceEmul` module uses direct NetCDF C API calls.

## Ocean Variables

Default variables (from `ModelData`): sea water temperature, salinity, SSH, eastward/northward sea water velocity, sea water cell thickness, sea ice concentration/thickness/snow thickness, sea surface temperature, surface downward eastward/northward stress, net downwelling shortwave radiation, plus biogeochemical tracers (chlorophyll, detritus, etc.).

## Executables (`src/mains/`)

23 application executables:

| Executable | oops Application |
|------------|-----------------|
| `soca_var.x` | `Variational` (3D/4D-Var) |
| `soca_letkf.x` | `LocalEnsembleDA` (LETKF/GETKF) |
| `soca_forecast.x` | `Forecast` |
| `soca_hofx.x` / `soca_hofx3d.x` | `HofX4D` / `HofX3D` |
| `soca_enshofx.x` | `EnsembleApplication<HofX4D>` |
| `soca_error_covariance_toolbox.x` | `ErrorCovarianceToolbox` |
| `soca_enspert.x` | `GenEnsPertB` |
| `soca_ensmeanandvariance.x` | `EnsembleMeanAndVariance` |
| `soca_ensrecenter.x` | `EnsRecenter` |
| `soca_anpproc.x` | `AnalysisPostProcessor` |
| `soca_hybridgain.x` | `HybridGain` |
| `soca_gridgen.x` | Grid generation |
| `soca_convertstate.x` | `ConvertState` |
| `soca_convertincrement.x` | `ConvertIncrement` |
| `soca_converttostructuredgrid.x` | Grid conversion |
| `soca_addincrement.x` | `AddIncrement` |
| `soca_diffstates.x` | `DiffStates` |
| `soca_setcorscales.x` | `SetCorScales` |
| `soca_sqrtvertloc.x` | `SqrtOfVertLoc` |
| `soca_gen_hybrid_linear_model_coeffs.x` | Hybrid TLM coefficient generation |
| `soca_tlm_toolbox.x` | `TLMToolbox` (TLM verification) |
| `soca_ice_emulator.x` | Ice emulator training (Torch, conditional) |

## Tests

```bash
ctest --output-on-failure -R soca
ctest -N -R soca
```

95+ YAML test configs in `test/testinput/`. 14 test executables in `test/executables/` covering Geometry, GeometryIterator, GetValues, State, Increment, LinearModel, VariableChange, ObsLocalization, and more. Reference outputs in `test/testref/`. Test data in `test/Data/` (36x17x25 and 72x35x25 ocean grids with MOM6 restarts).

Test categories: variational DA (3dvar, 3dhyb, 4dvar), ensemble methods (letkf, getkf, eakf), forecasts, H(x), linear model, variable transforms, diagnostics (dirac), ensemble utilities, ML balance training.
