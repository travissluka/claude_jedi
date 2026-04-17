# OOPS (Object Oriented Prediction System)

> Last updated against commit `8c752b37` (2026-04-17). Run `cd bundle/oops && git log --oneline 8c752b37..HEAD` to see what changed since.

## Overview

C++/Fortran framework for model-agnostic NWP data assimilation. Source at `bundle/oops/`.

## Build

```bash
# From build directory
make oops

# Build options
# ENABLE_LORENZ95_MODEL (ON): Build Lorenz95 toy model
# ENABLE_QG_MODEL (ON): Build quasi-geostrophic toy model
# ENABLE_MKL (ON): Use MKL for LAPACK
# ENABLE_GPTL (OFF): GPTL profiling
```

Dependencies: eckit ≥1.24.4, fckit ≥0.11.0, atlas ≥0.35.0, Eigen3, MPI, NetCDF (parallel), Boost ≥1.64, LAPACK/MKL, OpenMP.

## Tests

```bash
ctest --output-on-failure -R l95_3dvar    # Single test
ctest --output-on-failure -R 3dvar        # Pattern match
ctest --output-on-failure -E coding_norms # Skip lint
```

Tests defined in `l95/test/CMakeLists.txt`, `qg/test/CMakeLists.txt`, `coupled/test/CMakeLists.txt`. Each runs an executable with a YAML config and compares output to a reference file.

## Source Layout (`src/oops/`)

| Directory | Purpose |
|-----------|---------|
| `interface/` | Thin template wrappers delegating to `MODEL::*` / `OBS::*` implementations (e.g., `interface::State<MODEL>`, `interface::Geometry<MODEL>`). These enforce timing, logging, and the API contract. |
| `base/` | Higher-level OOPS objects built on `interface/` (e.g., `oops::State<MODEL>`, `FieldSet3D`, `FieldSets`, `Variables`, `GeometryData`, `IncrementSet`, `StateSet`). This is where most algorithmic logic lives. |
| `assimilation/` | DA algorithms: cost functions (`CostFunction`, `CostFct3DVar`, `CostFct4DEnsVar`), minimizers (17 total), and local ensemble solvers (4 total). |
| `runs/` | Top-level `Application` subclasses that serve as entry points: `Variational`, `Forecast`, `LocalEnsembleDA`, `HofX3D`, `HofX4D`, `EDA`, etc. Each `Application::execute()` reads a YAML config and runs end-to-end. |
| `generic/` | Model-independent implementations: `IdentityModel`, `HybridLinearModel`, `AtlasInterpolator`, FFT utilities, HTLM tools. |
| `util/` | Utilities: `DateTime`, `Duration`, `Logger`, `ConfigFunctions`, MPI helpers, Fortran interop. Includes `Factory.h` (generic factory template with variadic maker args). |
| `util/redistribution/` | `CommRedistribution` (abstract) for repartitioning ATLAS fields between parent/sub communicators. Concrete: `CommGatherScatterRedistribution` (gather-scatter) and `CommStraightRedistribution` (direct MPI `allToAllv` with global-index mapping, cached for reuse — uses `detail/AllToAllRouting` helper). `CommRedistributionCompatChecker` validates compatibility. |
| `mpi/` | MPI communicator management for ensemble/model decomposition. `ColorInfo` analyzes MPI color grouping in split communicators. `Scope` provides RAII temporary communicator switching. |
| `atlas/` | Atlas-based interpolation wrappers. |

### Key Base Classes

**`oops::Variables`** (`base/Variables.h`) — Container of `Variable` objects (no duplicates). Each `Variable` has a name, `VariableMetaData` (vertical stagger: CENTER/INTERFACE/TOP_INTERFACE/BOTTOM_INTERFACE/CENTER_WITH_TOP; data type: Real64 default; domain: Atmosphere/Ocean/Land), and optional vertical level count. Supports set operations (`+=`, `-=`, `intersection`), subset check (`<=`), and STL iteration.

**`oops::FieldSet3D`** (`base/FieldSet3D.h`) — Wraps `atlas::FieldSet` with a valid time and MPI communicator. Key methods: `deepCopy()`, `shallowCopy()`, `zero()`, arithmetic (`+=`, `-=`, `*=`, `/=`), `dot_product_with()`, `norm()`, `read()`/`write()`, `serialize()`/`deserialize()`. Access fields by index, name, or `Variable` object.

**`oops::FieldSet4D`** (`base/FieldSet4D.h`) — Collection of `FieldSet3D` objects across time steps. Used for 4D increments and ensemble members. Can be constructed from `State4D` or `Increment4D`.

**`oops::FieldSets`** (`base/FieldSets.h`) — Extends `DataSetBase<FieldSet3D>` to hold a collection of `FieldSet3D` objects distributed across time and ensemble dimensions. Can be constructed from an `IncrementSet<MODEL>` (shallow-copying its field data), from YAML config for file I/O, or as an empty container populated via `emplace_back(timeIndex, ensIndex, fieldSet3D)`. Supports element-wise `operator*=` with a `FieldSet3D` or a scalar.

**`oops::IncrementSet`** (`base/IncrementSet.h`) — Collection of `Increment<MODEL>` objects distributed across time steps and ensemble members. Extends `DataSetBase<Increment<MODEL>, Geometry<MODEL>>`. Replaces the retired `IncrementEnsemble` and `IncrementEnsemble4D` classes (removed in PR #3147). Supports arithmetic (`+=`, `-=`, `*=`), `zero()`, `diff()`, `schur_product_with()`, `dot_product_with()`, and ensemble mean computation. Can be constructed from geometry + variables + times, from config (file I/O), or from a `StateSet`.

**`oops::StateSet`** (`base/StateSet.h`) — Collection of `State<MODEL>` objects distributed across time steps and ensemble members. Extends `DataSetBase<State<MODEL>, Geometry<MODEL>>`. Replaces the retired `StateEnsemble` and `StateEnsemble4D` classes (removed in PR #3147). Provides `ens_mean()` to compute ensemble mean and `transpose()` to redistribute states across communicators.

**`oops::GeometryData`** (`base/GeometryData.h`) — Provides spatial queries on model grids: `closestTask(lat, lon)`, `containingTriangleAndBarycentricCoords()`, KD-tree indexing. Not a model interface — it's a utility wrapping ATLAS function spaces.

## Toy Models

| Directory | Description |
|-----------|-------------|
| `l95/` | Lorenz 1995 1D model — primary test bed for all DA algorithms |
| `qg/` | Quasi-geostrophic 2D model |
| `coupled/` | Coupled L95+QG tests for coupled model DA |

Toy model source lives in `l95/src/lorenz95/` and implements all required `MODEL::*` types (State, Geometry, ErrorCovariance, Model, etc.).

## Minimizers (17 total)

Three families, all configured via `variational: { algorithm: "<name>" }` in YAML:

**Primal** (minimize in model space): `PCG`, `FGMRES`, `MINRES`, `GMRESR`, `PLanczos`, `PFF`

**Dual** (minimize in observation space): `IPCG`, `RPCG`, `RPLanczos`, `SaddlePoint`

**DR (Derber-Rosati)** — uses auxiliary variable with B⁻¹x: `DRPCG`, `DRIPCG`, `DRPLanczos`, `DRPBlockLanczos`, `DRPFOM`, `DRGMRESR`, `LBGMRESR`

## Local Ensemble Solvers (4 total)

Configured via `local ensemble DA: { solver: "<name>" }`:

| Solver | Description |
|--------|-------------|
| `Deterministic LETKF` | Local Ensemble Transform Kalman Filter (Hunt et al. 2007) |
| `Stochastic LETKF` | LETKF with perturbed observations |
| `Deterministic GETKF` | Generalized ETKF with model-space localization (Lei 2018) |
| `Stochastic GETKF` | GETKF with perturbed observations |

All 4 solvers use `LocalEnsembleSolver` (iterate over grid points, solve local analysis). The `ObsLocalization::computeLocalization(GeometryIterator, ObsVector)` interface drives observation-space R-localization. Optional **Nerger et al. (2012) regulation factor** for LETKF obs localization: enabled via `local ensemble DA.use nerger regulation: true` (default `false`); applies only to diagonal R; computed per-observation in `LocalEnsembleSolver::computeNergerLocalR()`. Tested with `letkf_nerger_localization` (L95).

## Cost Functions (5 total)

Configured via `cost type` in YAML:

| YAML Name | Class | Description |
|-----------|-------|-------------|
| `3D-Var` | `CostFct3DVar` | Standard 3D variational — single time window, no model integration |
| `3D-FGAT` | `CostFct3DFGAT` | 3D First Guess at Appropriate Time — obs evaluated at their valid time against propagated background, but analysis is single-time |
| `4D-Ens-Var` | `CostFct4DEnsVar` | 4D ensemble-variational — localized ensemble B matrix with 4D obs, no TLM/ADM needed |
| `4D-Var` | `CostFct4DVar` | Full 4D variational — uses TLM/ADM for propagating increments |
| `4D-Var-Weak` | `CostFctWC4DVar` | Weak-constraint 4D-Var — allows model error term |

## Ensemble Inflation Options

Configured within `local ensemble DA` section:

- **RTPP** (`rtpp`): Relaxation To Prior Perturbation — blends analysis perturbations with prior perturbations. Value 0–1 (0 = pure analysis, 1 = pure prior).
- **RTPS** (`rtps`): Relaxation To Prior Spread — relaxes analysis spread toward prior spread. Value 0–1.
- **Multiplicative** (`mult`): Uniform multiplicative inflation factor applied to all perturbations.

## Observation Distribution Modes

How observations are distributed across MPI tasks (`ioda::Distribution` implementations):
- **RoundRobin** — cyclic assignment of obs to ranks (default)
- **Halo** — each rank gets obs within a geographic halo of its model domain; used for localized ensemble methods
- **InefficientDistribution** — all obs on all ranks (testing/debugging only)

## PseudoModel

`oops::PseudoModel<MODEL>` (`generic/PseudoModelState4D.h`) — model-agnostic "model" that reads pre-computed states from files at each time step instead of running a forecast. Used for H(x) and testing applications where model integration is unnecessary. Supports `states from template` for many time steps.

## Cross-Validation (LocalEnsembleDA)

Reduces ensemble inbreeding by splitting the ensemble into subensembles:
```yaml
cross validation:
  number of subensembles: 5
  splitting method: Contiguous  # or Random
```
Each member is updated using statistics computed from other subensembles only.

## Helper Applications (`runs/`)

Beyond the main DA applications, oops provides:
- `GenEnsPertB` — generate ensemble with random perturbations from B matrix
- `AddIncrement` — add analysis increment to model state
- `DiffStates` — compute difference between two states
- `EnsRecenter` — recenter ensemble around a provided state
- `EnsMeanAndVariance` — compute ensemble mean and variance
- `GenHybridLinearModelCoeffs` — generate H-TLM (Hybrid Tangent Linear Model) coefficients

## LocalEnsembleDA Driver Options

```yaml
driver:
  read HX from disk: false        # compute or read H(x) at runtime
  do posterior observer: true      # compute posterior H(x) for oma stats
  run as observer only: false      # only compute HX offline
  save posterior mean: false
  save posterior ensemble: true
  save prior variance: false
  save posterior variance: false
```

## Factory Pattern

New minimizers, cost functions, covariances, inflation methods, and local ensemble solvers are registered via factory macros and instantiated by name from YAML config. The `instantiate*Factory.h` headers in each subsystem trigger factory registration.

## YAML Configuration

All applications are driven by YAML files. Test configs live in `l95/test/testinput/`, `qg/test/testinput/`, and `coupled/test/testinput/`. Reference outputs for comparison are in `testref/` or `testoutput/`.

## Data Flow (Variational DA)

1. `Variational` application reads config → constructs `CostFunction` (via factory)
2. `IncrementalAssimilation` runs outer loops calling a `Minimizer` (via factory)
3. Minimizer solves in the control space using `HessianMatrix` (applies `HMatrix`, `HtMatrix`, `BMatrix`, `RinvMatrix`)
4. Analysis increment applied back to background state

## Data Flow (Local Ensemble DA)

1. `LocalEnsembleDA` application runs forecast ensemble → computes `HofX` for each member
2. `LocalEnsembleSolver` (e.g., `LETKFSolver`) iterates over `GeometryIterator` grid points
3. At each point: localize observations, solve local analysis, update ensemble

## Cross-Repo Interfaces

oops defines the `MODEL` and `OBS` template contracts that all other repos implement:

- **Model repos** (fv3-jedi, mpas-jedi, pyiri-jedi) implement `MODEL` traits: Geometry, State, Increment, Model, etc.
- **UFO/IODA** implement `OBS` traits via `ufo::ObsTraits`: ObsSpace (ioda), ObsOperator (ufo), GeoVaLs (ufo)
- **SABER** registers as a covariance model via `saber::instantiateCovarFactory<MODEL>()`
- **GetValues** (`base/GetValues.h`) bridges MODEL state to OBS operators by interpolating to obs locations

See `.claude/cross-repo-interactions.md` for full details.
