# PyIRI-JEDI

> Last updated against commit `dfb0b900` (2026-04-16). Run `cd bundle/pyiri-jedi && git log --oneline dfb0b900..HEAD` to see what changed since.

## Overview

Interface between JEDI and PyIRI (Python International Reference Ionosphere), providing ensemble-based ionospheric data assimilation using LETKF. Source at `bundle/pyiri-jedi/`. Mixed C++17/Fortran/Python codebase.

Unlike the atmospheric model interfaces (fv3-jedi, mpas-jedi), pyiri-jedi implements its own observation operators and interpolators rather than using UFO exclusively, though it also supports UFO integration.

## Build

```bash
# From build directory
make pyiri-jedi

# Requires Python 3.5+, CFFI for Python-Fortran bindings
```

Dependencies: oops, ioda, ufo, atlas, Eigen, Boost, NetCDF-Fortran, MPI, Python 3.5+. PyIRI is included as a git submodule.

## Tests

```bash
ctest --output-on-failure -R pyirijedi
ctest -N -R pyirijedi
```

Test categories: LETKF analysis (state index, point, VTEC obs), HofX forward operators, coordinate conversion, tracegrid interpolation, coding norms (cpplint + pycodestyle).

## Architecture

### Three-Layer Design

1. **PyIRI (Python)** — `python/PyIRI/` (git submodule)
   - International Reference Ionosphere model in Python
   - Spherical harmonics architecture for ionospheric parameters
   - Computes: electron density (foF2), peak height (hmF2), E-region parameters
   - Supports geographic, quasi-dipole, and magnetic local time coordinates

2. **Python Adapter** — `python/pyiri_jedi/`
   - Grid generation on geomagnetic L-shell geometry (`grid.py`)
   - Ensemble I/O for NetCDF restart files (`ensemble_io.py`)
   - Coordinate transformations geo ↔ magnetic (`coordconv.py`)
   - CFFI bindings to Fortran tracegrid modules
   - Forward operator implementations (`forward_operators.py`)

3. **C++ JEDI Model** — `src/pyiri-jedi/Model/`
   - Full OOPS model implementation (~35 headers, ~26 .cc files)
   - Custom observation operators (not just UFO)
   - Custom interpolators for field-aligned geometry

### Tracegrid Modules (Field-Line Tracing)

**Geomagnetic** (`src/tracegrid_geomag/`) — Fortran:
- Ray-tracing along geomagnetic field lines
- P/Q coordinates (L-shell and field-line position)
- Grid search (bisection) and interpolation

**Structured** (`src/tracegrid_structured/`) — C++:
- Interpolation on regular structured grids
- CFFI bindings to Python

Both expose Python interfaces via CFFI builders in `python/pyiri_jedi/`.

## Core C++ Classes (`src/pyiri-jedi/Model/`)

### State & Geometry
- `StatePyiri` — ionospheric state container
- `IncrementPyiri` — state increments for DA
- `FieldsPyiri` — field/variable storage
- `GeometryPyiri` — domain from restart/grid NetCDF files
- `GeometryPyiriIterator` — grid point iterator
- `PyiriDims` — grid dimensions (nlt, nft, nz, nion)

### Observation System (custom, not UFO-only)
- `ObsOperatorPyiri` — dispatcher for obs operators
- `ObsOpStateIndexPyiri` — extract state at grid indices
- `ObsOpPointPyiri` — point observations at arbitrary locations
- `ObsOpVtecPyiri` — Vertical Total Electron Content integration
- `ObsOperatorTLAD` — tangent linear/adjoint operators
- `ObsSpacePyiri`, `ObsVecPyiri`, `ObsDataPyiri` — obs containers
- `ObsLocNull` — null obs localization (returns 1.0)
- `ObsErrorPyiri` — observation error covariance
- `ObsFilter` — QC filtering
- `GeoValsPyiri` — geo-referenced values at obs locations

### Interpolation
- `InterpolatorPyiri` — dispatcher
- `InterpolatorTracegridGeomagPyiri` — geomagnetic field-aligned interpolation
- `InterpolatorTracegridStructuredPyiri` — structured grid interpolation
- `InterpolatorBasePyiri` — abstract base

### Variable Changes
- `ChangeVarPyiri` / `ChangeVarTLADPyiri` — nonlinear and linear variable transforms

## Key State Variables

| Variable | Dimensions | Description |
|----------|-----------|-------------|
| `deni` | (nion, nlt, nft, nz) | Ion density per species |
| `vsi` | (nion, nlt, nft, nz) | Ion velocity per species |
| `ti` | (nion, nlt, nft, nz) | Ion temperature per species |
| `te` | (nlt, nft, nz) | Electron temperature |
| `zalt` | (nlt, nft, nz) | Altitude |
| `dphi` | (nnyt, nnxp1) | Electrostatic potential |
| `vexbp` | (nlt, nft, nz) | ExB drift velocity |
| `f107_msis` | scalar | F10.7 solar flux index |

Grid dimensions: `nz` (~16 along field line), `nft` (~9 field lines), `nlt` (~16 longitudes), `nion` (2 species: O+, NO+).

## Executables (`src/pyiri-jedi/mains/`)

| Executable | Purpose |
|-----------|---------|
| `pyirijedi_LETKF` | LETKF without UFO (custom obs operators) |
| `pyirijedi_LETKF_ufo` | LETKF with UFO integration (ionosonde, GNSS) |
| `pyirijedi_HofX3D.x` | H(x) forward operator only |

## YAML Configuration Pattern

```yaml
geometry:
  path: members/mbr001
  restart_filename: pyiri_restart_2020275.nc
  grid_filename: pyiri_f4_2020.nc

background:
  members from template:
    template:
      imember: '%mem%'
      path: members/mbr%mem%
    pattern: '%mem%'
    nmembers: 20

observations:
  observers:
    - obs operator:
        obs type: point          # or state_index, vtec
      get values:
        interpolator: tracegrid_geomag  # or tracegrid_structured
      obs space:
        obs type: ionosonde

local ensemble DA:
  solver: Deterministic LETKF
  inflation:
    rtpp: 0.5
    mult: 1.1
```

## Source Layout Summary

| Directory | Language | Purpose |
|-----------|----------|---------|
| `src/pyiri-jedi/Model/` | C++ | OOPS model implementation (35 headers) |
| `src/pyiri-jedi/mains/` | C++ | Executable entry points |
| `src/tracegrid_geomag/` | Fortran + C wrapper | Geomagnetic field-line tracing |
| `src/tracegrid_structured/` | C++ | Structured grid interpolation |
| `python/PyIRI/` | Python (submodule) | IRI model |
| `python/pyiri_jedi/` | Python (23 modules) | Adapter layer, CFFI bindings, utilities |
| `test/testinput/` | YAML | Test configurations |
| `test/testref/` | Text | Reference outputs |
