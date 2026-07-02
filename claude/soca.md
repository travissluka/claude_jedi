# SOCA (Sea-ice, Ocean, and Coupled Assimilation)

> Last updated against commit `2d43d915` (2026-07-01). Run `cd bundle/soca && git log --oneline 2d43d915..HEAD` to see what changed since.
>
> **Covers:** soca::Traits, soca::{Geometry,State,Increment,ModelOceanIceEmulator,LinearModelOceanIceEmulator,VariableChange}, ObsLocRossby, SABER SOCA blocks (BkgErrFilt, ParametricOceanStdDev, MLBalance), MOM6 restart format, Icepack sea-ice, KEmul/IceEmul ML emulators, opaque-handle Fortran pattern (F90geom/F90flds/F90iter/F90model/F90bmat), `soca_io_mod` direct-netCDF reader/writer.

## Overview

Ocean/sea-ice data assimilation interface for JEDI, coupling MOM6 (ocean) and Icepack (sea ice) with the oops DA framework. Source at `bundle/soca/`. Version 1.8.0. C++/Fortran.

Build/test quirks (FMS, GSL-lite, MOM6/Icepack externals, Torch/MLBalance) in `claude/build-and-test.md`.

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
| ModelAuxIncrement | `soca::ModelBiasIncrement` |
| ModelAuxCovariance | `soca::ModelBiasCovariance` |
| ModelData | `soca::ModelData` |

## Source Layout (`src/soca/`)

| Directory | Purpose |
|-----------|---------|
| `Geometry/` | Ocean grid (ATLAS NodeColumns), FMS config, vertical coords |
| `IO/` | Direct-netCDF reader/writer (`soca_io_mod`); replaces FMS `fms_io_mod`; used by Fields, Geometry, Balance |
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

- **FMS integration**: `FmsInput` manages MOM6 `input.nml` namelist configuration. Only `fms_init`/`fms_end` and `mpp_*` domain decomposition remain; `fms_io_init`/`fms_io_exit` and the `global_soca_geom_counter` shim were removed when `fms_io_mod` was replaced. Geometry restart (`soca_gridspec.nc`) now reads/writes through `soca_io_reader/writer`.
- **Vertical**: Z-coordinate levels, top-down (`levelsAreTopDown() = true`)
- **Staggered grids**: `tohgrid()` / `tocgrid()` for H-grid ↔ C-grid transforms
- **Iterator**: `GeometryIterator` provides 2D or 3D iteration (configurable via `IteratorDimension`)
- `FieldsMetadata` stores per-field metadata (units, levels, staggering)

### State / Increment / Fields

`Fields` is the common base class wrapping `atlas::FieldSet`. State and Increment extend it:

- **State**: read/write via `soca_io_mod` (direct netCDF; PE 0 `nf90_*` + `mpp_broadcast`/`mpp_gather`); FMS `register_restart_field` path removed. `rotate2north`/`rotate2grid` for wind rotation, `logtrans`/`expontrans` for log-space variables
- **Increment**: linear algebra (`axpy`, `dot_product_with`, `schur_product_with`), `getLocal`/`setLocal` via GeometryIterator, `diff` between states, `rmsByLevel`
- **Serialization**: both support serialize/deserialize for MPI communication

### Model (`Model/OceanIceEmulator/`)

`ModelOceanIceEmulator` is a pseudo-model — it does not propagate MOM6/Icepack dynamics. Used for DA cycling where model integration happens externally. The linear model (`LinearModelOceanIceEmulator`) provides TLM/ADM wrappers with trajectory management.

### Variable Changes

Two factory hierarchies:

**Nonlinear** (`VariableChange/`):
| Registered Name | Class | Purpose |
|----------------|-------|---------|
| `"Model2GeoVaLs"` (also `"default"`) | `Model2GeoVaLs` | Model → observation space; registered twice so it serves as the factory fallback |
| `"Model2Ana"` | `Model2Ana` | Model → analysis variables |
| `"Soca2Cice"` | `Soca2Cice` | SOCA → CICE format |

VADER is used for generic transforms before falling back to soca-specific ones.

**Linear (TL/AD)** (`LinearVariableChange/`):
| Registered Name | Class | Purpose |
|-----------------|-------|---------|
| `"BalanceSOCA"` | `Balance` | Linearized balance equation (T/S → SSH coupling) |
| `"LinearModel2GeoVaLs"` (also `"default"`) | `LinearModel2GeoVaLs` | TL/AD version of Model2GeoVaLs; also the factory fallback |

### SABER Blocks

Three custom SABER outer blocks for background error covariance:

| YAML Name | Class | Purpose |
|-----------|-------|---------|
| `"SOCABkgErrFilt"` | `BkgErrFilt` | Depth-dependent error rescaling |
| `"ParametricOceanStdDev"` | `ParametricOceanStdDev` | Parametric standard deviation |
| `"MLBalance"` | `MLBalance` | Machine learning balance (Torch, conditional build) |

These are used in SABER outer block chains for ocean error covariance modeling.

### Obs Localization (`ObsLocalization/`)

`ObsLocRossby` — custom localization registered as `"Rossby"`. Inherits from `ufo::ObsHorLocGC99<GeometryIterator>` and adds `mult * rossby_radius` (read from the geometry iterator's `rossby_radius` field) to the configured Gaspari-Cohn lengthscale, so localization grows in low-latitude / deep-ocean regions.

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

State, Geometry, and Balance restarts read/write through `soca_io_mod` (`src/soca/IO/`) — a register-then-commit API: `soca_io_reader%init(filename)` → repeated `enqueue(varname, target_ptr)` → `commit()` (and the symmetric `soca_io_writer`). Implementation opens/closes the netCDF file each commit (no handle cache — keeps LETKF memory bounded) and currently fans out via PE 0 `nf90_get_var` + `mpp_broadcast` / collects via `mpp_gather` on writes. Helpers: `soca_io_file_exists`, `soca_io_var_exists`. The writer holds raw pointers into caller buffers, so callers must keep those buffers alive (and declare them `target`) until `commit()`. `soca_genfilename` now appends `.nc` explicitly (previously implicit via FMS) — existing test/YAML names already include the suffix, so this is correctness-restoring, not a breaking change. No new YAML keys. Motivation: unblock per-PE ensemble I/O (PE i reads member i alone) that FMS's collective `fms_io_mod` semantics made impossible. MOM6 restart format is still used for state files. `readNcAndInterp.h` provides generic NetCDF interpolation; `MLBalance/KEmul/IceEmul` uses direct NetCDF C API calls.

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

As of PR #1244, `AnalysisPostproc`'s `set increment variables to zero` no longer requires the named variables to be a subset of the increment variables — variables not already present are added to the increment (via `Increment::updateFields`) before zeroing, so zero-out variables need not appear in the increment-variables list. Relatedly, `soca::State`'s increment-add path now skips (with a warning) increment variables absent from the state instead of failing.

## Tests

14 test executables in `test/executables/` (Geometry, GeometryIterator, GetValues, State, Increment, LinearModel, VariableChange, ObsLocalization, …). Test data in `test/Data/` (grids: 36×17×25 and 72×35×25, MOM6 restart format). Categories: variational DA (3dvar/3dhyb/4dvar), ensemble (letkf/getkf), forecasts, H(x), linear model, variable transforms, dirac diagnostics, ensemble utilities, ML balance training.
