# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JEDI (Joint Effort for Data assimilation Integration) is a data assimilation framework for numerical weather prediction. This is the **Skylab bundle** — a CMake super-build that coordinates ~25 interdependent repositories. Detailed docs for core repos are in `claude/`.

- **oops** — Model-agnostic DA algorithms (variational, ensemble, hybrid). C++/Fortran.
- **ioda** — Observation data access with pluggable storage backends (HDF5, in-memory, ODB, BUFR). C++14.
- **ufo** — Forward operators (H(x)), QC filters, bias correction. C++17/Fortran 2008.
- **saber** — Background error covariance (BUMP, spectral, diffusion blocks). C++/Fortran.
- **vader** — Variable transforms between model and DA spaces.
- **fv3-jedi** / **soca** / **mpas-jedi** — Model-specific interfaces for FV3, ocean (MOM6), and MPAS.
- **crtm** — Community Radiative Transfer Model (satellite radiance simulation). Used by UFO's `ObsRadianceCRTM` operator.
- **coupling** — Coupled atmosphere-ocean DA using `oops::GeometryCoupled<fv3jedi::Traits, soca::Traits>`.

## Directory Layout

```
jedi/
├── bundle/          # Source repos (git-managed, version controlled)
│   ├── CMakeLists.txt   # Bundle-level ecbuild configuration
│   ├── oops/        # Core DA framework
│   ├── ioda/        # Observation data access
│   ├── ufo/         # Forward operators and QC
│   ├── saber/       # Error covariance
│   └── ...          # vader, fv3-jedi, soca, mpas-jedi, crtm, coupling, etc.
└── build/           # Out-of-source build (ephemeral, do not edit)
    ├── bin/         # Compiled executables
    ├── lib/         # Shared libraries
    └── <repo>/      # Per-repo build artifacts and test configs
```

**Important**: `build/` is ephemeral. `bundle/` is version-controlled — do not add Claude-generated files there. Place working files in `jedi/` or `jedi/claude/`.

## Environment Setup

Before building or running anything, load the spack-stack environment:

```bash
source ~/work/env.sh
```

This loads GCC 13.3.0, MPICH 4.2.3, Python 3.11.7, and all JEDI dependencies (ATLAS, eckit, NetCDF, HDF5, etc.). It also sets `JEDI_ROOT=~/work/jedi` and `SPACK_STACK_VER=1.9.2`.

**Verify the environment is active**: `echo $SPACK_STACK_VER` should print `1.9.2`.

## Build Commands

The build system is CMake + **ecbuild** (ECMWF's CMake wrapper). Build type is `RelWithDebInfo`. Compiler: GCC 13.3.0.

```bash
# Full rebuild from build directory
cd /home/tsluka/work/jedi/build
make -j$(nproc)

# Rebuild a single component (e.g., oops, ioda, ufo, saber, fv3-jedi)
make oops
make ufo

# Reconfigure CMake
cmake /home/tsluka/work/jedi/bundle

# Update all git repos in the bundle
make update
```

### Build Dependency Order

gsw → oops → vader → saber → ioda → ufo → crtm → fv3-jedi-lm → fv3-jedi → soca → mpas → mpas-jedi → coupling

Bundle version 8.0.0. Optional repos (off by default): gsibec, rttov, oasim, ropp-ufo, iodaconv, pyiri-jedi. Test data repos (auto-downloaded): ioda-data, ufo-data, fv3-jedi-data, mpas-jedi-data, jedi-model-data.

## Running Tests

There are ~2742 CTest tests. Timeout is 1500 seconds per test.

```bash
cd /home/tsluka/work/jedi/build

# Run all tests
ctest --output-on-failure

# Run tests for a specific component
ctest --output-on-failure -R oops
ctest --output-on-failure -R ioda
ctest --output-on-failure -R ufo

# Run a specific test by name
ctest --output-on-failure -R l95_3dvar
ctest --output-on-failure -R ufo_test_tier1_backgroundcheck

# Run tests from a component subdirectory
ctest --output-on-failure --test-dir build/ufo

# List tests matching a pattern
ctest -N -R <pattern>

# Exclude coding norms (lint) tests
ctest --output-on-failure -E coding_norms
```

### ecbuild Test Configuration

Tests are registered via `ecbuild_add_test()` with optional `MPI <n>` and `OMP <n>` parameters. Common patterns:
```cmake
ecbuild_add_test( TARGET test_name MPI 4 OMP 2
                  COMMAND executable ARGS testinput/config.yaml
                  DEPENDS executable TEST_DEPENDS prereq_test )
```
SABER uses a tier system: TIER 1 = MPI tests only, TIER 2 = MPI + OpenMP. Tests are generated for multiple MPI/OMP combinations (1/1, 2/1, 4/1, 1/2).

## Linting

All repos use **cpplint** (Google C++ style, 100-char line limit, 2-space indent). Configuration is in `CPPLINT.cfg` files at repo roots and `src/` directories.

```bash
# Run lint checks for a specific repo
ctest -R oops_coding_norms
ctest -R ioda_coding_norms
ctest -R ufo_coding_norms
```

Python code (ioda): pycodestyle, 120-char line limit.

## Architecture Notes

### Two Template Parameters

oops algorithms are templated on `MODEL` and `OBS`:
- `MODEL` — a Traits struct from a model repo (e.g., `fv3jedi::Traits`) bundling Geometry, State, Increment, Model, etc.
- `OBS` — `ufo::ObsTraits`, bundling types from both UFO (operators, filters, GeoVaLs) and IODA (ObsSpace, ObsVector)

Model executables instantiate as e.g. `oops::Variational<fv3jedi::Traits, ufo::ObsTraits>`.

### ATLAS as Shared Data Layer

`atlas::FieldSet` is the common data representation across repos. Model repos convert State/Increment to FieldSets via `toFieldSet()`/`fromFieldSet()`. SABER and VADER operate exclusively on FieldSets, making them model-agnostic.

### Factory Pattern

All repos use factory registration. Components are registered by name and instantiated from YAML config at runtime. Look for `*Maker` classes and `instantiate*Factory.h` headers. Model executables chain factory registration from multiple repos (saber, ufo, oops) in their `main()`.

### YAML-Driven Configuration

All applications and tests are driven by YAML configuration files. Test configs live in `<repo>/test/testinput/`. The `oops::Parameters` system provides type-safe configuration — each class has a `Parameters_` typedef.

### C++/Fortran Interop

Three patterns used throughout JEDI:
1. **UFO pattern**: `*.cc` ↔ `*.interface.h` ↔ `*.interface.F90` ↔ `*_mod.F90` (ISO_C_BINDING)
2. **Opaque handle pattern** (fv3-jedi, mpas-jedi): C++ holds integer handle, passes to `extern "C"` functions with `_f90` suffix
3. **ATLAS bridge**: C++ and Fortran share memory via ATLAS FieldSet API

### Toy Models for Testing

oops includes L95 (Lorenz 1995, 1D) and QG (quasi-geostrophic, 2D) toy models in `oops/l95/` and `oops/qg/`. These are the primary test beds for DA algorithms — most oops tests use L95.

## GitHub CLI

The `gh` CLI is configured and authenticated. Use it to browse issues and PRs for the JEDI repos (under the JCSDA org on GitHub):

```bash
gh issue list -R JCSDA-internal/oops
gh pr list -R JCSDA-internal/ufo
gh issue view 123 -R JCSDA-internal/ioda
gh pr view 456 -R JCSDA-internal/saber
```

## Per-Repo Architecture Docs

Detailed architecture docs are in `claude/`, organized into three groups:

**Core JEDI repos** (model-agnostic infrastructure):
- `claude/oops.md` — source layout, Variables/FieldSet3D/GeometryData classes, 17 minimizers, 6 ensemble solvers, DA data flows
- `claude/ioda.md` — two-layer engine design, storage backends, OSDF containers
- `claude/ufo.md` — operators (incl. composite), filters, ~96 obsfunctions, ~32 variable transforms, 4 R-matrix types, 4 obs localization methods
- `claude/saber.md` — block/chain architecture, QUENCH testbed, all block YAML names, BUMP, calibration modes, ErrorCovarianceToolbox, ProcessPerts
- `claude/vader.md` — recipe/cookbook pattern, variable transforms, adding new recipes

**Model interfaces** (built on top of core repos, implement oops `MODEL` traits):
- `claude/fv3-jedi.md` — FV3/GEOS/GFS/UFS interface, cubed-sphere geometry, I/O backends, TLM
- `claude/soca.md` — MOM6/Icepack ocean interface, Rossby localization, SABER blocks, variable changes
- `claude/mpas-jedi.md` — MPAS interface, unstructured Voronoi mesh, variable changes
- `claude/pyiri-jedi.md` — PyIRI ionosphere interface, LETKF, field-line tracing, Python/C++/Fortran
- `claude/coupling.md` — coupled atm-ocean DA, TraitCoupled template, block-diagonal covariance

**Documentation**:
- `claude/jedi-docs.md` — official Sphinx docs repo: build/environment guides, IODA data conventions, git flow, YAML config reference, tutorials. **Caution: may be out of date — trust code over jedi-docs when they disagree.**

**Cross-repo architecture**:
- `claude/cross-repo-interactions.md` — how repos interact: template contracts, GetValues bridge, factory wiring, ATLAS data layer, impact map for changes
- `claude/observation-data-flow.md` — end-to-end: IODA file → ObsSpace → GetValues → H(x) → QC filters → cost function Jo
- `claude/model-interface-contract.md` — all virtual methods model repos must implement (Geometry, State, Increment, Model, etc.)
- `claude/parameters-system.md` — type-safe YAML config: Parameter/Required/Optional/Polymorphic types, validation, nesting
- `claude/atlas-fieldset-guide.md` — ATLAS FieldSet as shared data layer, toFieldSet/fromFieldSet, metadata, copy semantics
- `claude/factory-pattern.md` — *Maker registration, instantiate*Factory chaining, adding new components
- `claude/testing-patterns.md` — ecbuild_add_test, reference outputs, tier system, adjoint tests, adding tests
- `claude/cost-functions.md` — 3D-Var, 3D-FGAT, 4D-Var, weak 4D-Var, 4D-Ens-Var: math, config, TLM requirements
- `claude/ufo-filter-lifecycle.md` — filter stages (PRE/PRIOR/POST), where clause, actions, ObsFunctions, variable transforms
- `claude/saber-block-chains.md` — B = Outer·Central·Outerᵀ decomposition, parametric/ensemble/hybrid chains, multiply order
- `claude/mpi-patterns.md` — commTime/commEns splitting, ensemble distribution, GetValues allToAll, patchObs

### Keeping Docs Current

Each `claude/*.md` file records the git commit hash it was last updated against. After pulling new repo versions, check for changes:
```bash
# Example: check what changed in oops since docs were written
cd bundle/oops && git log --oneline 792d377a..HEAD
```
If significant changes are found (new classes, renamed files, changed APIs), update the corresponding `.md` file and the commit hash at its top.
