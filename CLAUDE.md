# CLAUDE.md

Guidance for Claude Code on the JEDI Skylab bundle. Detailed per-repo and cross-cutting architecture docs live in `claude/`.

## Project Overview

JEDI (Joint Effort for Data assimilation Integration) is a CMake super-build that coordinates ~25 interdependent repos for numerical weather prediction DA.

- **oops** — model-agnostic DA algorithms (variational, ensemble, hybrid)
- **ioda** — observation data access (HDF5, in-memory, ODB, BUFR backends)
- **ufo** — forward operators H(x), QC filters, bias correction
- **saber** — background error covariance (BUMP, spectral, diffusion blocks)
- **vader** — variable transforms between model and DA spaces
- **fv3-jedi** / **mpas-jedi** / **soca** / **pyiri-jedi** — model interfaces (atmosphere, ocean, ionosphere)
- **crtm** — radiative transfer (used by `ObsRadianceCRTM`)
- **coupling** — coupled atm-ocean DA via `oops::GeometryCoupled`

Architecture primer: `claude/cross-repo-interactions.md` (template contracts, GetValues, factory wiring, ATLAS data layer, impact map).

## Directory Layout

Working files go in `jedi/` or `jedi/claude/`, never `bundle/` (source) or `build/` (ephemeral).

## Environment

```bash
source ~/work/env.sh       # compilers, MPI, Python, spack-stack
```

Sets `JEDI_ROOT=~/work/jedi`; `$SPACK_STACK_VER` reports the stack version.

## Build & Test (common commands)

```bash
# Build generator is make OR ninja depending on how the user configured cmake.
# Check with: grep CMAKE_GENERATOR /home/tsluka/work/jedi/build/CMakeCache.txt
cd /home/tsluka/work/jedi/build
make -j16   # (ninja build:) ninja            # full rebuild
cd /home/tsluka/work/jedi/build/<repo> && make -j16   # (ninja build:) ninja <repo>   # single-repo rebuild; oops, ufo, saber, ...
cmake /home/tsluka/work/jedi/bundle                # reconfigure

ctest --output-on-failure -R <pat>   # run tests (append -N to list, -E coding_norms to skip lint)
ctest --output-on-failure --test-dir build/<repo>
```

1500s test timeout. Build type `RelWithDebInfo`. Lint: cpplint (Google style, 100-char, 2-space); Python pycodestyle (120-char).

Per-repo quirks (CMake flags, unique deps, test naming): `claude/build-and-test.md`.

Build is a DAG, not a chain — model-interface repos (fv3-jedi, soca, mpas-jedi, pyiri-jedi) are siblings on the same level. Full DAG with per-repo direct deps and a topologically-sorted parallel-build order: `claude/build-and-test.md` (#build-dependency-dag).

## GitHub

`gh` is authenticated for `JCSDA-internal/*`. Use it for issues, PRs, review state.

## claude/ Index

| File | Purpose |
|------|---------|
| **Per-repo** | |
| `oops.md` | source layout, FieldSet3D/IncrementSet/GeometryData, 17 minimizers, 5 cost functions, 5 local ensemble solvers (LETKF/GETKF Det/GETKF Stoch/SequentialEnsembleSolver/EAKF), generic `Diffusion` |
| `ioda.md` | two-layer engine design, storage backends, OSDF containers |
| `ufo.md` | operators (incl. composite), filters, ~100 obsfunctions, ~32 variable transforms, 5 R-matrix types, obs localization |
| `saber.md` | block/chain architecture, multiply order, QUENCH testbed, all block YAML names, BUMP, calibration, ErrorCovarianceToolbox |
| `vader.md` | recipe/cookbook pattern, planning algorithm, adding recipes |
| `fv3-jedi.md` | FV3/GEOS/GFS/UFS interface, cubed-sphere geometry, I/O backends, TLM |
| `soca.md` | MOM6/Icepack interface, Rossby localization, SABER blocks |
| `mpas-jedi.md` | MPAS interface, unstructured Voronoi mesh |
| `pyiri-jedi.md` | PyIRI ionosphere interface, LETKF, field-line tracing |
| `coupling.md` | TraitCoupled template, block-diagonal covariance |
| `jedi-docs.md` | pointer to external Sphinx docs (IODA conventions, git flow, YAML reference, JEDI-EDU) |
| **Cross-cutting** | |
| `cross-repo-interactions.md` | template contracts (full MODEL method tables), GetValues bridge, factory wiring, ATLAS layer, impact map |
| `observation-data-flow.md` | end-to-end: IODA file → ObsSpace → GetValues → H(x) → QC → Jo |
| `parameters-system.md` | type-safe YAML config (Parameter/Required/Optional/Polymorphic) |
| `atlas-fieldset-guide.md` | FieldSet as shared data layer, toFieldSet/fromFieldSet, metadata |
| `factory-pattern.md` | `*Maker` registration, `instantiate*Factory` chaining |
| `testing-patterns.md` | `ecbuild_add_test`, reference outputs, tier system, adjoint tests |
| `ufo-filter-lifecycle.md` | filter stages (PRE/PRIOR/POST), where clause, actions, ObsFunctions |
| `mpi-patterns.md` | commTime/commEns splitting, ensemble distribution, GetValues allToAll |
| `build-and-test.md` | per-repo unique build flags, optional deps, test-naming quirks, bundle quirks (`BRANCH develop UPDATE` force-reset, per-repo rebuild scope), ctest env-var gotchas (`VALIDATE_PARAMETERS`), squash-merge ancestry pitfalls |
| `maintainers.md` | per-repo GitHub handles for ping/escalation on stalled PRs (sourced from `JCSDA-internal/github-admin` terraform) |
| `pr-conventions.md` | **READ FIRST when authoring any PR.** Template structure (section headings + literal checklist), authoring workflow (gather context → draft → user review → open → assign reviewers after CI green), Dependencies section format, `build-group=` / `run-ci-on-draft=` annotation syntax, CI re-trigger, squash-merge ancestry implications, tracking-issue-lives-in-closing-repo, Resolves/bullet conventions, common mistakes |
| `INDEX.md` | keyword/symbol → file/section index |

### Keeping docs current

Each per-repo doc records the git hash it was last verified against. Use the `update-repos` skill to sync and refresh them.
