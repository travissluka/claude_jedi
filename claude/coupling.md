# Coupling (Coupled Atmosphere-Ocean DA)

> Last updated against commit `d468220b` (2026-03-26). Run `cd bundle/coupling && git log --oneline d468220b..HEAD` to see what changed since.
>
> **Covers:** oops::TraitCoupled<Traits1,Traits2>, oops::GeometryCoupled, oops::StateCoupled, oops::AuxCoupledModel, BlockDiagonalCovarianceCoupled, YAML `covariance model: Coupled Block Diagonal`, FV3-JEDI + SOCA coupled 3D-Var, OASIM ocean color operator.

## Overview

Coupled atmosphere-ocean data assimilation using FV3-JEDI (atmosphere) and SOCA (ocean). Source at `bundle/coupling/`. Version 1.2.0. C++ only (~270 lines of core source). The repo is intentionally minimal — it leverages oops coupled template types to combine two existing model interfaces without duplicating their code.

Build/test quirks (deps on fv3-jedi, soca, crtm; optional oasim; 11 test targets all MPI 6) in `claude/build-and-test.md`.

## How Coupling Works

### Dual-Traits Template Instantiation

oops provides `TraitCoupled<Traits1, Traits2>` which automatically generates coupled types from two model traits:

```
oops::TraitCoupled<fv3jedi::Traits, soca::Traits>
```

This provides:
- `GeometryCoupled<Traits1, Traits2>` — holds both model geometries (FV3 cubed-sphere + MOM6 ocean grid)
- `StateCoupled<Traits1, Traits2>` — holds both model states, accessible via `state1()` (atm) and `state2()` (ocean)
- `AuxCoupledModel<Traits1, Traits2>` — combined model bias
- `BlockDiagonalCovarianceCoupled<Traits1, Traits2>` — block-diagonal B matrix (independent atm/ocean error covariances)

All oops algorithms (`Variational`, `Forecast`, `HofX3D`, etc.) work with the coupled trait just like a single-model trait.

### Block-Diagonal Error Covariance

The coupled 3D-Var registers a factory type `"Coupled Block Diagonal"` that constructs independent SABER-based error covariances for atmosphere and ocean:

```yaml
background error:
  covariance model: Coupled Block Diagonal
  FV3JEDI:
    covariance model: SABER
    saber central block:
      saber block name: BUMP_NICAS
  SOCA:
    covariance model: SABER
    saber outer blocks:
      - saber block name: StdDev
    saber central block:
      saber block name: BUMP_NICAS
```

## Source Layout

The repo has a single implementation directory `test_mom6fv3/`:

```
test_mom6fv3/
├── src/
│   ├── ModelUFS.h         # Coupled model class (placeholder)
│   └── ModelUFS.cc        # Step only updates time; no actual coupled dynamics
├── executables/           # 7 application entry points
│   ├── var_fv3_mom6.cc    # Coupled 3D-Var
│   ├── forecast_fv3_mom6.cc   # Coupled forecast
│   ├── hofx3d_fv3_mom6.cc    # Coupled H(x)
│   ├── interp_fv3_mom6.cc    # SOCA→FV3 state interpolation
│   ├── TestCoupledGeometry.cc
│   ├── TestCoupledModel.cc
│   └── TestCoupledModelAuxControl.cc
└── testinput/             # 12 YAML test configs
```

### ModelUFS (`test_mom6fv3/src/ModelUFS.h`)

Namespace: `coupled_mom6_fv3`. A placeholder coupled model class. Currently `step()` only calls `xx.updateTime(tstep_)` without propagating either model. The class exists to satisfy the oops Model interface for coupled forecast tests.

### Executables

| Executable | oops Application | Purpose |
|------------|-----------------|---------|
| `coupling_var_fv3_mom6.x` | `Variational<TraitCoupled, ObsTraits>` | Coupled 3D-Var |
| `coupling_forecast_fv3_mom6.x` | `Forecast<TraitCoupled>` | Coupled forecast |
| `coupling_hofx3d_fv3_mom6.x` | `HofX3D<TraitCoupled, ObsTraits>` | Coupled observation operator |
| `coupling_interp_fv3_mom6.x` | `InterpolateStateBetweenModels<soca, fv3jedi>` | SOCA → FV3 interpolation |

Each executable instantiates factories from both model repos:
```cpp
saber::instantiateCovarFactory<fv3jedi::Traits>();
saber::instantiateCovarFactory<soca::Traits>();
saber::instantiateCovarFactory<oops::TraitCoupled<fv3jedi::Traits, soca::Traits>>();
```

### Factory Registrations

One registration in `var_fv3_mom6.cc`:
- `"Coupled Block Diagonal"` → `oops::BlockDiagonalCovarianceCoupled<fv3jedi::Traits, soca::Traits>`

## YAML Configuration Patterns

### Coupled Geometry

```yaml
geometry:
  FV3JEDI:
    akbk: Data/inputs/fv3files/akbk127.nc4
    npx: 13
    npy: 13
    npz: 127
    # ... FV3 grid config
  SOCA:
    geom_grid_file: soca_gridspec.nc
    mom6_input_nml: data_static/72x35x25/input.nml
    fields metadata: data_static/fields_metadata.yml
  FV3JEDI exclude variables: [skin_temperature_at_surface_where_sea]
```

### Coupled Model

```yaml
model:
  name: Coupled
  FV3JEDI:
    name: FV3LM      # or Identity
    tstep: PT1H
  SOCA:
    name: Identity
    tstep: PT1H
```

### Coupled State Variables

Analysis variables span both domains:
- **Atmosphere** (FV3): `eastward_wind`, `northward_wind`, `air_temperature`, `water_vapor_mixing_ratio`, etc.
- **Ocean** (SOCA): `sea_water_potential_temperature`, `sea_water_salinity`, `sea_surface_height_above_geoid`, etc.

## Tests

11 test targets, all using MPI 6:

| Test | Description |
|------|-------------|
| `test_coupled_geometry_fv3_mom6` | Coupled geometry interface |
| `test_coupled_model_fv3_mom6` | Model interface (FV3LM + Identity ocean) |
| `test_coupled_modelaux_fv3_mom6` | Model bias interface |
| `test_coupled_forecast_fv3_mom6` | Forecast with FV3LM atmosphere |
| `test_coupled_forecast_coupled_fv3_mom6` | Forecast with Identity models |
| `test_interpolate_state_soca_fv3` | SOCA → FV3 state interpolation |
| `test_coupled_hofx3d_fv3_mom6` | Coupled H(x) with CRTM radiances |
| `test_coupled_hofx3d_fv3_mom6_dontusemom6` | H(x) FV3-only (ocean excluded) |
| `test_coupled_hofx3d_oasim_fv3_mom6` | H(x) with OASIM ocean color (conditional) |
| `test_coupled_var_fv3_mom6` | Coupled 3D-Var analysis |
| `test_soca_gridgen` | Grid generation prerequisite |

Test data is symlinked from soca and fv3-jedi test data directories.

## Cross-Repo Dependencies

The coupling repo sits at the top of the JEDI dependency chain:

```
gsw → oops → vader → saber → ioda → ufo → crtm → fv3-jedi-lm → fv3-jedi ─┐
                                                                    soca ──┤
                                                                coupling ──┘
```

Changes to oops coupled types (`oops/coupled/*.h`) directly affect this repo. Changes to fv3-jedi or soca Traits propagate through the template instantiations.
