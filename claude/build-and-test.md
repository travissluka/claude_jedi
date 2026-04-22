# Build & Test (per-repo quirks)

> **Covers:** per-repo unique CMake flags (ENABLE_*/FV3_FORECAST_MODEL/IODA_BUILD_LANGUAGE_FORTRAN/...), repo-unique optional dependencies (FFTW, ECTRANS, gsibec, GSW, PyTorch, FMS, MOM6, MPAS 8.0, PyIRI, CFFI, CRTM), test-naming conventions (`ufo_test_tier1_*`, `vader_recipe_*`, MPI 6 coupling tests).

Common build commands, test invocations, and shared dependencies are in `CLAUDE.md`. This file only lists what's *unique* per repo — flags that toggle features, external dependencies beyond the common set, and test naming quirks.

**Shared across all repos** (no need to list per-repo): eckit, fckit, atlas, MPI, NetCDF, Boost, LAPACK, OpenMP. Version pins live in `bundle/CMakeLists.txt`. All repos build via `make <repo>` from the build directory and test via `ctest -R <repo>`.

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
