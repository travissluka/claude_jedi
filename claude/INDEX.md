# Keyword Index

Point from a topic/symbol/YAML key to the file(s) that cover it. When multiple files cover a topic at different depths, the deepest-detail file is listed first.

Every per-repo and cross-cutting doc also has its own `> **Covers:** ...` line at the top — grep for a symbol across `claude/*.md` for finer matches.

## DA algorithms & cost functions

| Topic | File |
|-------|------|
| 3D-Var, 4D-Var, 4D-FGAT, 4D-Ens-Var, weak 4D-Var math/YAML/TLM needs | `oops.md` (#cost-functions) |
| Minimizers (PCG/FGMRES/DRPCG/RPCG/RPLanczos/SaddlePoint/...) | `oops.md` (#minimizers) |
| LETKF / GETKF (deterministic & stochastic), local volume solver | `oops.md` (#local-ensemble-solvers) |
| Sequential EnKF (EAKF), SequentialEnsembleSolver | `active-projects.md` |
| RTPP / RTPS / multiplicative inflation | `oops.md` (#ensemble-inflation-options) |
| Nerger regulation for LETKF obs loc | `oops.md` (#local-ensemble-solvers) |
| Cross-validation (subensembles) | `oops.md` (#cross-validation-localensembleda) |
| Outer/inner-loop structure of Variational | `oops.md` (#cost-functions) |

## Observations (H(x), filters, R)

| Topic | File |
|-------|------|
| IODA ObsFile → ObsSpace → CostJo end-to-end | `observation-data-flow.md` |
| QC flag semantics, FilterBase, QCmanager, FinalCheck | `ufo-filter-lifecycle.md`, `ufo.md` |
| QC → obs error mask → missing-value propagation in Jo | `observation-data-flow.md`, `ufo-filter-lifecycle.md` |
| Filter actions (RejectObs / AssignError / InflateError / ...) | `ufo-filter-lifecycle.md` |
| ObsFunctions, ObsFilterData | `ufo-filter-lifecycle.md`, `ufo.md` |
| ObsOperator, LinearObsOperator, CompositeObsOperator | `ufo.md` |
| ObsError types (Diagonal, CrossVarCov, BiasCorrelated, WithinGroup) | `ufo.md` |
| ObsLocalization (HorGC99, HorSOAR, VertLocalization, Rossby) | `ufo.md`, `soca.md` (Rossby) |
| EffectiveError / EffectiveQC output variables | `observation-data-flow.md` |
| ObsBias / VarBC | `ufo.md` |
| GeoVaLs (model state at obs locations) | `ufo.md`, `cross-repo-interactions.md` |
| ioda::ObsSpace, ObsVector, ObsDataVector | `ioda.md` |
| ObsSpace distributions (RoundRobin / Halo / Inefficient) | `ioda.md`, `mpi-patterns.md` |
| dot_product with missing values (DistributionUtils) | `ioda.md`, `observation-data-flow.md` |

## Background error covariance (B, R, localization)

| Topic | File |
|-------|------|
| SABER block abstraction (central / outer / chain) | `saber.md` |
| Parametric / ensemble / hybrid block chains, multiply order | `saber.md` (#chain-multiply-order) |
| BUMP_NICAS, Diffusion, FastLAM, Bifourier, SpectralB | `saber.md` |
| QUENCH pseudo-model testbed | `saber.md` |
| ErrorCovarianceToolbox (dirac tests, randomization) | `saber.md` |
| ProcessPerts (ensemble band filtering) | `saber.md` |
| Localization<MODEL>, saber::ErrorCovariance<MODEL> | `saber.md`, `cross-repo-interactions.md` |
| Square-root B: multiplySqrt / multiplySqrtAD, control-vector sizing | `saber.md` (#chain-multiply-order) |
| Calibration modes (direct / iterative) | `saber.md` |
| TorchBalance (PyTorch ML balance) | `saber.md` |
| Coupled B matrix (block-diagonal) | `coupling.md`, `saber.md` |

## Variable transforms

| Topic | File |
|-------|------|
| VADER recipe/cookbook, planVariable algorithm | `vader.md` |
| Adding a new recipe | `vader.md` (#adding-a-new-recipe) |
| Met Office saturation vapor pressure lookup (`src/mo/`) | `vader.md` |
| GSW ocean conversions | `vader.md` |
| VaderBlock (SABER integration) | `saber.md`, `vader.md` |
| Model-side VariableChange / LinearVariableChange | `cross-repo-interactions.md` |

## Model interfaces (MODEL traits)

| Topic | File |
|-------|------|
| Full MODEL contract (Geometry/State/Increment/Model/...) | `cross-repo-interactions.md` (#what-model-must-implement) |
| toFieldSet / fromFieldSet halo rules | `atlas-fieldset-guide.md`, `cross-repo-interactions.md` |
| GeometryIterator (gridpoint iteration for LETKF) | `cross-repo-interactions.md` |
| fv3jedi::Traits, cubed-sphere, GEOS/GFS/UFS | `fv3-jedi.md` |
| soca::Traits, MOM6, Icepack, ML balance | `soca.md` |
| mpas::Traits, Voronoi mesh | `mpas-jedi.md` |
| pyiri::Traits, ionosphere, LETKF | `pyiri-jedi.md` |
| Coupled traits (TraitCoupled, GeometryCoupled, StateCoupled) | `coupling.md` |

## Shared infrastructure

| Topic | File |
|-------|------|
| ATLAS FieldSet, FunctionSpace, oops::FieldSet3D/4D | `atlas-fieldset-guide.md`, `oops.md` |
| Factory + Maker registration, instantiate*Factory.h | `factory-pattern.md` |
| Parameters_ / RequiredParameter / OptionalParameter / PolymorphicParameter | `parameters-system.md` |
| MPI: commTime, commEns, GetValues allToAll, patchObs | `mpi-patterns.md` |
| GetValues<MODEL,OBS> bridge | `cross-repo-interactions.md` |
| C++/Fortran interop patterns (ISO_C_BINDING / opaque handle / ATLAS bridge) | `cross-repo-interactions.md` |
| oops::Variables, VariableMetaData, vertical stagger | `oops.md` |

## Testing & build

| Topic | File |
|-------|------|
| ecbuild_add_test, MPI/OMP matrices, tier system | `testing-patterns.md` |
| Adjoint tests (dot-product), dirac, randomization | `testing-patterns.md`, `saber.md` |
| Reference outputs (testref / testoutput) | `testing-patterns.md` |
| Per-repo build flags & unique deps | `build-and-test.md` |
| Build dependency DAG (find_package + link-time deps), parallel-build levels | `build-and-test.md` (#build-dependency-dag) |
| Ctest patterns, lint (cpplint/pycodestyle) | `CLAUDE.md`, `build-and-test.md` |

## External knowledge

| Topic | File |
|-------|------|
| IODA data conventions (variable names, units, groups) | `jedi-docs.md` (→ `bundle/jedi-docs/docs/inside/conventions/`) |
| JEDI git flow / PR process | `jedi-docs.md` |
| spack-stack / JEDI version compatibility | `jedi-docs.md` |
| YAML config reference with annotated examples | `jedi-docs.md` |
| Per-repo maintainers (who to ping on stalled PRs) | `maintainers.md` |
| PR description annotations (`build-group=`, `run-ci-on-draft=`) | `pr-conventions.md` |

## Active / in-flight work

| Topic | File |
|-------|------|
| Sequential EnKF PRs, EAKF, ObsIterator, Point3 loc | `active-projects.md` |
| User-specific state (branches, followups, test subsets) | `MEMORY.md` at `~/.claude/projects/-home-tsluka-work-jedi/memory/` |

## When in doubt

1. Grep `claude/*.md` for the symbol — every doc's `Covers:` line lists its key symbols and classes.
2. If it's not in any doc, the source is authoritative. Start from `bundle/<repo>/src/<repo>/` with the closest `claude/<repo>.md` as a source-layout map.
3. `CLAUDE.md` has the one-line file index; this file has the topic index.
