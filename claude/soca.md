# SOCA (Sea-ice, Ocean, and Coupled Assimilation)

> Last updated against commit `fae9238b` (2026-09-03). Run `cd bundle/soca && git log --oneline fae9238b..HEAD` to see what changed since.
>
> **Covers:** soca::Traits, soca::{Geometry,State,Increment,ModelOceanIceEmulator,LinearModelOceanIceEmulator,VariableChange}, ObsLocRossby, SABER SOCA blocks (BkgErrFilt, ParametricOceanStdDev, MLBalance), MOM6 restart format, Icepack sea-ice, `soca::PostProcessIce` + `soca::icephysics` CICE-restart postprocessing, `soca::incrqc::qcIncrement` increment QC, KEmul/IceEmul ML emulators, opaque-handle Fortran pattern (F90geom/F90flds/F90iter/F90model/F90bmat), `soca_io_mod` direct-netCDF reader/writer, `soca_write_jacobian_mod` balance-Jacobian dump.

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
| `PostProcess/` | C++/ATLAS CICE-restart postprocessing (`PostProcessIce`) plus pure column ice physics (`IcePhysics`) |
| `MLBalance/` | ML-based balance operator (SABER outer block, requires Torch) |
| `SaberBlocks/` | Custom SABER outer blocks (BkgErrFilt, ParametricOceanStdDev) |
| `ObsLocalization/` | Rossby radius-based obs localization |
| `Covariance/` | ErrorCovariance stub (throws NotImplemented) |
| `ModelBias/` | Model bias control variable (mostly stubs) |
| `ModelData/` | Default variable list and model metadata |
| `AnalyticInit/` | Analytic GeoVaLs initialization for testing |
| `Utils/` | Ocean smoother, QC functions, `incrqc/` increment QC (`soca::incrqc::qcIncrement`, see below) |

## Core Architecture

### Geometry (`Geometry/`)

Manages the 3D ocean grid using ATLAS `NodeColumns` function space on a curvilinear Arakawa C-grid (from MOM6). Key aspects:

- **FMS integration**: `FmsInput` manages MOM6 `input.nml` namelist configuration. Only `fms_init`/`fms_end` and `mpp_*` domain decomposition remain; `fms_io_init`/`fms_io_exit` and the `global_soca_geom_counter` shim were removed when `fms_io_mod` was replaced. Geometry restart (`soca_gridspec.nc`) now reads/writes through `soca_io_reader/writer`.
- **Function space**: `functionSpace()` returns `atlas::functionspace::NodeColumns` (not the generic `atlas::FunctionSpace`), so callers get the node-column API without a cast
- **Vertical**: Z-coordinate levels, top-down (`levelsAreTopDown() = true`)
- **Staggered grids**: `tohgrid()` / `tocgrid()` for H-grid ↔ C-grid transforms
- **Iterator**: `GeometryIterator` provides 2D or 3D iteration (configurable via `IteratorDimension`)
- `FieldsMetadata` stores per-field metadata (units, levels, staggering)

`fields_metadata.yml` templating: `categories: C` expands `<CATEGORY>`, and `layers: L` expands `<LEVEL>`, into `C*L` single-level entries. `layers` is distinct from `levels` (the array level-count of one field); it exists for CICE per-layer restart variables (`qice00N`, `sice00N`, `qsno00N`) where each layer is its own file variable. Both placeholders substitute into `io sup name` as well as `name`, `io name`, and `name surface`. Per-category ice `io name`s follow CICE restart conventions (`aice1`, `vice1`, `vsno1`) rather than the history-file `_h` suffix.

### State / Increment / Fields

`Fields` is the common base class wrapping `atlas::FieldSet`. State and Increment extend it:

- **State**: read/write via `soca_io_mod` (direct netCDF; PE 0 `nf90_*` + `mpp_broadcast`/`mpp_gather`); FMS `register_restart_field` path removed. `rotate2north`/`rotate2grid` for wind rotation, `logtrans`/`expontrans` for log-space variables. `writeCice()` is the CICE update-mode writer (see I/O)
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
| `"Soca2Cice"` | `Soca2Cice` | SOCA → CICE format (legacy Fortran path, superseded by `PostProcessIce`; still registered and used as the regression baseline) |

VADER is used for generic transforms before falling back to soca-specific ones.

**Linear (TL/AD)** (`LinearVariableChange/`):
| Registered Name | Class | Purpose |
|-----------------|-------|---------|
| `"BalanceSOCA"` | `Balance` | Linearized balance equation (T/S → SSH coupling) |
| `"LinearModel2GeoVaLs"` (also `"default"`) | `LinearModel2GeoVaLs` | TL/AD version of Model2GeoVaLs; also the factory fallback |

`Balance` can optionally dump its Kst (T→S) and Ksshts (T/S→SSH) Jacobians to NetCDF via new YAML keys `kst.jacobian_output.filename` and `ksshts.jacobian_output.filename`, written through the new `soca_write_jacobian_mod` (`write_jacobian_to_netcdf`, layered on `soca_io_writer`) — PR #1218.

### CICE-Restart Postprocessing (`PostProcess/`)

`PostProcessIce` (PR #1246) projects an aggregated SOCA sea-ice analysis (`sea_ice_area_fraction`, `sea_ice_thickness`, `sea_ice_snow_thickness`) onto a per-category CICE restart. It is the C++/ATLAS successor to the Fortran `Soca2Cice` variable change, and unlike that path it owns its own I/O rather than hiding the write inside a `changeVar` call.

One entry point, `State postprocess(const State & analysis) const`:

1. read the per-category CICE background restart, the ~115 per-cat / per-(cat,layer) variable names are auto-injected from `ncat`/`ice_lev`/`sno_lev`;
2. per-cell pass: clamp analysis bounds, dispatch on `(ai_bg, ai_an)` into LAND / ICE2NOICE / NOICE2ICE / ICE2ICE, ITD rebin, snow distribution by `aicen` weight, optional freeboard enforcement, per-cat bin clip;
3. thermo/pond pass plus new-ice seeding, donors found via a global lat/lon `atlas::util::IndexKDTree` and a sparse two-round `allToAll` halo exchange, so the per-cell donor lookup is local;
4. update-mode write (see I/O below).

Returns an aggregate-ice State on the analysis geometry carrying what was actually written to the restart (post rebin, post freeboard, post clip). Ocean variables are never read or written.

Config root is `postprocess ice:`. Required: `ncat`, `ice_lev`, `sno_lev`, `cice restart: {input, output}`, `itd: category bounds` (model-specific, length `ncat+1`; a mismatch with the receiving CICE binary silently yields a restart CICE rejects in `linear_itd`). Optional blocks `itd`, `snow`, `freeboard` (off by default), `thermo`, plus `analysis variables`, `min aice output`, `min new ice thickness`. Full schema with defaults and the per-cell algorithm: `src/soca/PostProcess/README.md`.

`IcePhysics.h` holds the pure column helpers with no ATLAS/MPI/YAML dependencies: `adjustThicknessCategories` (ITD rebin solver), `enforceFreeboard`, `snowIceFreeboard`, `iceEnthalpyBL99`, `siceLayerCice4` (BZ99 salinity profile), `snowEnthalpy`, and `icephysics::Constants` (CICE5/CICE6 densities and thermo constants, deliberately not configurable).

Callers: `soca_postproc.x` (standalone), `AnalysisPostproc` / `soca_ensanpproc.x` (per ensemble member), and `gdasapp`'s increment handler.

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

Configured under `obs localizations:` with `localization method: Rossby` and params `base value`, `rossby mult`, `min grid mult`, `min value`, `max value` (see `src/soca/ObsLocalization/README.md`, PR #1238). The realized scale is `L = base value + rossby mult · rossby_radius`, floored by `min grid mult · sqrt(cell area)`, clamped to `[min value, max value]`, then converted to a Gaspari-Cohn (GC99) cutoff as `L · 2 / sqrt(0.3)`. Works only with LETKF/GETKF ensemble solvers — it aborts under the sequential/EAKF solvers, and obs-obs localization is unsupported.

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

**CICE update-mode write**: `State::writeCice()` → `soca_state_write_cice_f90` → `soca_fields_write_cice` / `soca_fields_write_cice_rst`. Its config block takes `cice template` (the input restart, used as the template) and `output filename`. The writer byte-copies the template (`soca_io_copy_file`), then overwrites only the variables soca models, so roughly 40 unmodelled CICE variables (dynamics state, unanalysed tracers) pass through unchanged. Per-category ATLAS fields are grouped by their `io sup name` and assembled into one `(ni,nj,ncat)` buffer per CICE variable, so each restart variable is a single enqueue. Supporting `soca_io_mod` additions: `writer_init(..., template)`, `writer_commit_update`, `write_var_strided`. The generic `write_rst` path knows nothing about update mode.

## Ocean Variables

Default variables (from `ModelData`): sea water temperature, salinity, SSH, eastward/northward sea water velocity, sea water cell thickness, sea ice concentration/thickness/snow thickness, sea surface temperature, surface downward eastward/northward stress, net downwelling shortwave radiation, plus biogeochemical tracers (chlorophyll, detritus, etc.).

## Executables (`src/mains/`)

24 application executables:

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
| `soca_postproc.x` | `soca::Postproc` (standalone CICE-restart postprocessing: `analysis = bg + incr`, or an explicit `analysis` block, then `PostProcessIce`) |
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

`AnalysisPostproc`'s ice postprocessing runs `PostProcessIce` per ensemble member instead of a `Soca2Cice` variable change (PR #1246), a breaking YAML change: `analysis postprocessing:` now takes `pattern` plus a `postprocess ice:` block directly, replacing the old `sea ice variable change:` sub-block. `pattern` (e.g. `"%mem%"`) is substituted per member into `postprocess ice`, in practice only inside `cice restart: input:`/`output:`.

PR #1244: `AnalysisPostproc`'s `set increment variables to zero` no longer requires the named variables to be a subset of the increment variables: variables not already present are added to the increment (via `Increment::updateFields`) before zeroing, so zero-out variables need not appear in the increment-variables list. Relatedly, `soca::State`'s increment-add path now skips (with a warning) increment variables absent from the state instead of failing.

### Increment QC (`Utils/incrqc/`)

`soca::incrqc::qcIncrement` (used by `AnalysisPostproc`/`soca_ensanpproc.x` under `increment postprocessing: bounds check:`, and documented in `docs/postproc_application.md`) bounds/filters an increment before it's applied. PR #1262 made every stage independently optional and gated on the presence of its own YAML key — nothing runs by default:
- `steric variable change` — replaces the SSH increment with a steric-height increment, then clamps it via `absolute steric increment max` (default 10.0 m, effectively no limit)
- `coastal increment filter`
- `stability check`
- `state bounds` — now accepts **any** variable as a `[min, max]` pair (previously hardcoded to T/S and always required); bounds naming a non-increment variable are warned and ignored (typo catch), invalid pairs throw `eckit::UserError`; each enabled stage pre-validates its required increment/background variables (`sea_water_cell_thickness` always) before mutating anything, and clamp counts are MPI-reduced and logged per variable

No stage configured leaves the increment untouched (plus a warning). Full schema: `src/soca/Utils/incrqc/README.md`. Regression coverage: `testinput/ensanpproc_ensda.yml` exercises a bounds-only config.

## Tests

15 test executables in `test/executables/` (Geometry, GeometryIterator, GetValues, State, Increment, LinearModel, VariableChange, ObsLocalization, IcePhysics, …). Test data in `test/Data/` (grids: 36×17×25 and 72×35×25, MOM6 restart format). Categories: variational DA (3dvar/3dhyb/4dvar), ensemble (letkf/getkf), forecasts, H(x), linear model, variable transforms, dirac diagnostics, ensemble utilities, ML balance training.

CICE-postprocessing tests: `soca2cice_new`, `soca2cice_new_freeboard`, `soca2cice_new_seed`, `soca2cice_new_bgfallback` all run `soca_postproc.x` on 2 PEs from `testinput/soca2cice_new*.yml`. `test_soca_icephysics` unit-tests the `IcePhysics` column helpers with no YAML/MPI/Geometry. `test_soca_postprocice_vs_soca2cice` (`test/postprocice_vs_soca2cice.sh`) diffs the legacy `Soca2Cice` restart against the `PostProcessIce` one, tolerating a bounded cell count (marginal-zone donor choice differs), and checks that unmodelled variables pass through byte-identically.
