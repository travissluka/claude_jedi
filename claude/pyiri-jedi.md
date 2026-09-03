# PyIRI-JEDI

> Last updated against commit `7e61efad` (2026-08-27). Run `cd bundle/pyiri-jedi && git log --oneline 7e61efad..HEAD` to see what changed since.
>
> **Covers:** pyiri::Traits, PyIRI Python submodule, ObsSpacePyiri, ObsIterator, FieldsPyiri/StatePyiri, LETKF for ionosphere, field-line tracing, VTEC/slant TEC/electron density obs, CFFI Python↔Fortran bindings, custom interpolators for field-aligned geometry.

## Overview

Interface between JEDI and PyIRI (Python International Reference Ionosphere), providing ensemble-based ionospheric data assimilation using LETKF. Source at `bundle/pyiri-jedi/`. Mixed C++17/Fortran/Python codebase.

Unlike the atmospheric model interfaces (fv3-jedi, mpas-jedi), pyiri-jedi implements its own observation operators and interpolators rather than using UFO exclusively, though it also supports UFO integration.

Build/test quirks (Python 3.5+, CFFI, PyIRI submodule) in `claude/build-and-test.md`. Test categories: LETKF analysis (state index, point, VTEC obs), HofX forward operators, coordinate conversion, tracegrid interpolation.

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
   - Forward operator implementations (`forward_operators.py`). Path integration is `integrate_geovals(integrand, interpolated_values, lower_limit, upper_limit)` (renamed and generalized from `integrate_vertical`, which took `alts`/`min_alt`/`max_alt`): trapezoidal rule with linear interpolation to the limits, returning `None` when the path has fewer than 2 points or lies entirely outside the limits, rather than asserting an exact limit match
   - Geovals/H(x) file writers: `geovals_writer.py` (`get_vtec`, `get_slant_tec`, `get_path_latitude`/`get_path_longitude`, `read_obslocs_from_file`, `get_times_and_tinds`, `add_tracer_args`, `get_obs_parameters`) and `ensemble_tec_writer.py`, which writes an ensemble TEC/H(x) file for slant-path obs so LETKF can run with `read HX from disk`

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
- Interpolation on regular structured grids by ray-tracing cell-face (triangle) intersections with `atlas::Triag3D`
- Vertical tracers: `trace_vertical_ray_through_structured_latlon_grid`, `..._cartesian_grid`
- **Slant path** (PR #161): `trace_slant_ray_through_structured_cartesian_grid(origin, endpoint, …)` traces an arbitrary line segment (GNSS RO / slant TEC geometry), not just a radial ray
- CFFI bindings to Python (`.cxx` was renamed to `.cc` in the same PR)

Key C++ types in `tracegrid_structured.h`:
- `StructuredGrid` — flattened 3D x/y/z coordinate arrays plus variable pointers; dims held in a `size_t dims[3]`
- `GridPoint3` — 3D index triple; default-constructs to `size_t` max (a "no point" sentinel, not `{0,0,0}`) and has `==`/`!=`
- `GridTriangle3D` — cell-face triangle in index space (`GridPoint3 vertices[3]`)
- `FaceIntersection` — one ray/triangle intersection test result (`grid_tri`, `tri`, `tri_isect`, `cell_corner`, `success`)
- `TracerSettings` — ray-tracing tunables: `epsilon`/`edgeEpsilon` passed to `Triag3D::intersects`, `distance_check_tolerance_scaling`/`_min_t` for the intersection-distance sanity check, `duplicate_points_tolerance`, `max_segment_gap` (if the ray exits the grid and re-enters within this distance, tracing continues), `local_search_radius` (cells beyond the current one to search for the next intersection), and per-stage message toggles (`initial_intersection_messages`, `intersection_quality_messages`, `successful_/failed_intersection_messages`, `store_intersection_info`)
- `RayTraceResult` — `values` plus `path_length` (signed distance along the ray for each intersection) and, when `store_intersection_info` is set, `isects`

Both expose Python interfaces via CFFI builders in `python/pyiri_jedi/`. `python/pyiri_jedi/tracegrid_structured.py` wraps the C API with `RayTraceResult` (`nlevels`, `nvars`, `path_length`, `intersections`, `get_values()`), `FaceIntersection`, `GridTriangle3D`, `GridPoint3`, and the `prep_trace_vars()` helper. `tracegrid_vertical()` now returns `(path_length, values)` — previously values only — and `tracegrid_slant(origin, endpoint, grid_x, grid_y, grid_z, varlist)` is the slant-path entry point.

## Core C++ Classes (`src/pyiri-jedi/Model/`)

### State & Geometry
- `StatePyiri` — ionospheric state container; declares `friend class IncrementPyiri` so `accumul()` can reach `xx.fields_`
- `IncrementPyiri` — state increments for DA. As of PR #177 this is no longer a stub: `+=`, `-=`, `*=`, `=`, `zero()`, `zero(DateTime)`, `ones()`, `random()`, `norm()`, `sqrt()`, `accumul()`, `schur_product_with()`, `dot_product_with()`, `write()`, and serialize/deserialize are all implemented; only `dirac()` still throws `NotImplemented`. There is also a geometry-resize-style constructor `IncrementPyiri(const GeometryPyiri&, const IncrementPyiri&)` that only asserts the dimensions match — it does **not** interpolate.
- `FieldsPyiri` — field/variable storage; backs the Increment methods above. `norm()` is an MPI-allReduced RMS (`sqrt(sum/count)`, not a plain L2 norm) and `dot_product_with()` also allReduces. `random()` uses `util::NormalDistribution<float>` with a fixed seed 7, mean 1.0, sdev 1.0. `sqrt()` throws on negative input. Serialization packs `data_` followed by `time_`. `FieldsPyiri(other, copy=false)` zeroes; new `getData()` accessor. `write()` no longer throws `BadValue` on a `member` mismatch — `member` defaults to `imember_` and `zero padding` to 3, so ensemble output paths silently follow config.
- `GeometryPyiri` — domain from restart/grid NetCDF files. Gridded vars include `height_wrt_surface` plus (PR #161) `path_length` and `pathsum_weights`, all sized from `zalt`. `getVarInterpolatedSize()` for gridded vars returns `2*nz + 2*nft + nlt` (theoretical max cell-face intersections for a straight line through the grid), up from `nz + nft`; the interpolator fill-pads unused elements.
- `GeometryPyiriIterator` — grid point iterator
- `PyiriDims` — grid dimensions (nlt, nft, nz, nion); now a `class` (was a `struct`) with a public `operator==`, used by the geometry-checking constructors

### Observation System (custom, not UFO-only)
- `ObsOperatorPyiri` — dispatcher for obs operators
- `ObsOpStateIndexPyiri` — extract state at grid indices
- `ObsOpPointPyiri` — point observations at arbitrary locations
- `ObsOpVtecPyiri` — Vertical Total Electron Content integration
- `ObsOperatorTLAD` — tangent linear/adjoint operators
- `ObsSpacePyiri`, `ObsVecPyiri`, `ObsDataPyiri` — obs containers (ObsSpacePyiri exposes `begin()`/`end()` returning `ObsIterator` for range-based iteration)
- `ObsIterator` — forward iterator over observations, dereferences to `eckit::geometry::Point3` locations (stub)
- `ObsLocNull` — null obs localization (returns 1.0) via both `GeometryPyiriIterator` and `Point3`/`Point3` overloads, matching the ufo/oops `ObsLocalization` interface
- `ObsErrorPyiri` — observation error covariance
- `ObsFilter` — QC filtering
- `GeoValsPyiri` — geo-referenced values at obs locations

### Interpolation
- `InterpolatorPyiri` — dispatcher
- `InterpolatorTracegridGeomagPyiri` — geomagnetic field-aligned interpolation
- `InterpolatorTracegridStructuredPyiri` — structured grid interpolation
- `InterpolatorBasePyiri` — abstract base

Both tracegrid interpolators take `max_levels` per variable from `GeometryPyiri::variableSizes()` (was a single `nft + nz` for all variables) and `ASSERT(nlevels <= max_levels)` before copying into the output.

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
| `python/pyiri_jedi/` | Python (24 modules) | Adapter layer, CFFI bindings, utilities |
| `test/mains/` | C++ | oops-interface test drivers |
| `test/testinput/` | YAML | Test configurations |
| `test/testref/` | Text | Reference outputs |

**Split observer/solver test** (PR #161): `test_pyirijedi_split_solver_letkf` runs `pyirijedi_LETKF_ufo` on `testinput/letkf_split_solver.yaml`, which reads a pre-computed ensemble H(x) file (`ens_tec_with_geovals.nc`, produced by `ensemble_tec_writer.py`) via `driver: {read HX from disk: true, do posterior observer: false}`, uses the UFO `Identity` operator on `totalElectronContent` with an empty `obs localizations` list, and updates only `state_vars: [ion_density, f107a_msis]`. Companion tests: `test_pyirijedi_split_observer_tec_writer` (Python) and `test_pyirijedi_grid_points_equal` (C++, `test/mains/grid_points_equal_test.cc`, exercises `GridPoint3` equality).

**oops-interface tests**: `pyirijedi_increment` (PR #177, `test/mains/TestIncrement.cc`) runs the standard `oops::test::Increment<PyiriTraits>` suite from `test/testinput/increment.yaml` — the repo's first oops-interface test. The YAML sets `skip dirac test: true`, `skip atlas: true`, `test atlas interface: false`, tolerance `1e-5`, and the test runs with `OOPS_TRACE=1`.
