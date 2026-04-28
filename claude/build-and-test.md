# Build & Test (per-repo quirks)

> **Covers:** build dependency DAG (find_package + subdir target_link_libraries), per-repo unique CMake flags (ENABLE_*/FV3_FORECAST_MODEL/IODA_BUILD_LANGUAGE_FORTRAN/...), repo-unique optional dependencies (FFTW, ECTRANS, gsibec, GSW, PyTorch, FMS, MOM6, MPAS 8.0, PyIRI, CFFI, CRTM), test-naming conventions (`ufo_test_tier1_*`, `vader_recipe_*`, MPI 6 coupling tests).

Common build commands, test invocations, and shared dependencies are in `CLAUDE.md`. This file only lists what's *unique* per repo — flags that toggle features, external dependencies beyond the common set, and test naming quirks.

**Shared across all repos** (no need to list per-repo): eckit, fckit, atlas, MPI, NetCDF, Boost, LAPACK, OpenMP. Version pins live in `bundle/CMakeLists.txt`. All repos build via `make <repo>` from the build directory and test via `ctest -R <repo>`.

## Build dependency DAG

The build is a DAG, not a linear chain. Below is the *true* set of inter-repo dependencies as declared in CMake, derived from each repo's top-level `find_package( <repo> ... REQUIRED )` calls plus `target_link_libraries(...)` calls in subdirs that pull in additional repos at link time.

Levels (everything in a level depends only on prior levels; within a level, repos can build in parallel):

```
L0  leaves:           gsw   crtm   mpas   fv3-jedi-lm   oops
L1  core (1 hop):     vader (←oops)        ioda (←oops)
L2  core (2 hops):    saber (←oops,vader)  ufo  (←oops,ioda)
L3  model interfaces: fv3-jedi    (←oops, saber, ufo, vader, crtm, fv3-jedi-lm)
                      soca        (←oops, saber, ufo, vader, ioda)
                      mpas-jedi   (←oops, saber, ufo, ioda, mpas)
                      pyiri-jedi  (←oops, ufo, ioda)
L4  cross-model:      coupling    (←oops; +link-time: fv3-jedi, soca, ioda)
```

The L3 model-interface repos are **siblings** — none depends on another. mpas does not depend on fv3-jedi; soca does not depend on mpas-jedi; etc.

| Repo | Direct JEDI deps (find_package REQUIRED) | Notes |
|------|------------------------------------------|-------|
| `gsw` | — | leaf (Fortran library) |
| `oops` | — | leaf |
| `crtm` | — | leaf (external CRTMv3) |
| `mpas` | — | leaf (external MPAS-Model) |
| `fv3-jedi-lm` | — | leaf; pulls in FMS/MAPL/GEOSgcm at the env level |
| `vader` | oops | optional QUIET: gsw, jedi-model-data |
| `ioda` | oops | optional QUIET: ioda-data |
| `saber` | oops, vader | optional QUIET: FFTW, ECTRANS, gsibec, jedi-model-data |
| `ufo` | oops, ioda | optional QUIET: crtm, rttov, gsw, ropp-ufo, geos-aero, oasim, ufo-data |
| `fv3-jedi` | oops, saber, ufo, vader, crtm, fv3-jedi-lm (`fv3jedilm`) | also FMS/MAPL via FV3_FORECAST_MODEL |
| `soca` | oops, vader, saber, ioda, ufo | also FMS, GSL-lite, MOM6, Icepack |
| `mpas-jedi` | oops, saber, ioda, ufo, mpas (`MPAS 8.0`) | optional rttov, ropp-ufo |
| `pyiri-jedi` | oops, ioda, ufo | bundled PyIRI submodule |
| `coupling` | oops | also depends on **fv3-jedi, soca, ioda** at link time via `coupling/test_mom6fv3/src/CMakeLists.txt` `target_link_libraries(...)` — these are *not* declared at the top-level find_package |

**Common observations:**

- Model-interface repos (`fv3-jedi`, `soca`, `mpas-jedi`, `pyiri-jedi`) are **siblings**, not a chain. None of them depend on each other; they all sit on the same level above the model-agnostic core (`oops`, `ioda`, `ufo`, `saber`, `vader`).
- `coupling` is the only repo whose effective build deps (oops + ioda + fv3-jedi + soca) exceed its declared top-level find_package deps. The extra deps live in a subdir's `target_link_libraries`, so a parallel build that doesn't have fv3-jedi+soca built first will fail at coupling's link step but pass earlier configure/find_package checks.
- `crtm` is only required by `fv3-jedi`. `ufo` and `mpas-jedi` reference it via QUIET find_package and degrade gracefully if absent.
- `mpas` (the MPAS-Model) is only required by `mpas-jedi`. The bundle pins it to a tag (currently `v8.2.1`).
- `fv3-jedi-lm` is only required by `fv3-jedi`.

**A topologically-sorted build order** (one valid linearization out of many):

```
gsw, crtm, mpas, fv3-jedi-lm, oops
  → vader, ioda
  → saber, ufo
  → fv3-jedi, soca, mpas-jedi, pyiri-jedi
  → coupling
```

Within each level, repos can build in parallel.

**To re-derive the DAG** (do this whenever a repo's CMakeLists changes):

```bash
for r in oops vader saber ioda ufo fv3-jedi-lm fv3-jedi soca mpas-jedi pyiri-jedi coupling; do
  echo "=== $r ==="
  grep -E 'find_package\([[:space:]]*(oops|vader|saber|ioda|ufo|crtm|gsw|fv3jedilm|fv3-jedi|soca|MPAS|fv3jedi)[[:space:]]' bundle/$r/CMakeLists.txt
done
```

For `coupling`, also check `bundle/coupling/test_mom6fv3/src/CMakeLists.txt` for subdir-level link-time deps.

If this section gets out of sync with CMake, refresh it as part of `/update-repos`.

## Build flags

| Repo | Unique CMake flags |
|------|---------------------|
| **oops** | `ENABLE_LORENZ95_MODEL` (ON), `ENABLE_QG_MODEL` (ON), `ENABLE_MKL` (ON), `ENABLE_GPTL` (OFF) |
| **ioda** | `IODA_BUILD_LANGUAGE_FORTRAN` (ON), `BUILD_PYTHON_BINDINGS` (ON if pybind11 found), `ENABLE_IODA_DOC` (OFF) |
| **saber** | `ENABLE_BUMP` (ON), `ENABLE_QUENCH` (ON — pseudo-model testbed), `OPENMP` (ON). Conditional blocks: Bifourier/FastLAM require FFTW; Bifourier can alternatively use ECTRANS+transi; GSI requires gsibec; SpectralB requires atlas TRANS or ECTRANS. |
| **fv3-jedi** | `FV3_FORECAST_MODEL` (GEOS \| UFS \| FV3CORE), `FV3_PRECISION` (DOUBLE default \| SINGLE) |
| **mpas-jedi** | Requires MPAS 8.0 `core_atmosphere` component |
| **pyiri-jedi** | Requires Python 3.5+ and CFFI; PyIRI included as git submodule |

## Repo-unique dependencies

| Repo | Unique / optional deps |
|------|-------------------------|
| **oops** | Eigen3, optional GPTL |
| **ioda** | optional pybind11 (Python bindings), HDF5, ODB, BUFR backends |
| **ufo** | optional crtm, rttov, gsw, ropp-ufo, geos-aero |
| **saber** | vader, optional FFTW, ECTRANS, gsibec, PyTorch/LibTorch (for TorchBalance) |
| **vader** | optional GSW (enables ocean recipes) |
| **fv3-jedi** | fv3-jedi-lm ≥1.5.0, FMS 2023.04, optional crtm/gsibec/GEOS GCM/UFS |
| **soca** | FMS 2023.3.0 (R8), GSL-lite, MOM6 (`external/mom6`), Icepack (`external/icepack`), optional PyTorch (for MLBalance) |
| **mpas-jedi** | MPAS 8.0, optional RTTOV 12.1.0, ROPP-UFO |
| **pyiri-jedi** | Python 3.5+, CFFI, PyIRI submodule |
| **coupling** | fv3-jedi, soca, saber, ioda, ufo, crtm; optional oasim |

## Test naming and structure quirks

| Repo | Notes |
|------|-------|
| **oops** | Tests in `l95/test/`, `qg/test/`, `coupled/test/`. L95 is the primary DA testbed. |
| **ufo** | Tests named `ufo_test_tier1_<name>`. |
| **saber** | Test dirs: `test/testinput/` (~250 YAMLs), `test/testref/`, `test/fctest/` (Fortran unit tests). Categories: DIRAC (impulse response), randomization, calibration/training, diagnostics, format conversion. |
| **vader** | Two test groups: `recipe_*.yaml` (~29) and `vader_*.yaml` (~27). Pattern: recipe test → NL + adjoint dot-product + planning. |
| **fv3-jedi** | ~100+ YAML configs; test CMakeLists.txt ~2700 lines. |
| **soca** | 95+ YAMLs, 14 test executables, grid sizes 36×17×25 and 72×35×25 in `test/Data/`. |
| **coupling** | 11 test targets, all using `MPI 6`. Test data symlinked from soca and fv3-jedi. |
