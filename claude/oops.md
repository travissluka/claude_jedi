# OOPS (Object Oriented Prediction System)

> Last updated against commit `03b99d13` (2026-09-03). Run `cd bundle/oops && git log --oneline 03b99d13..HEAD` to see what changed since.
>
> **Covers:** Variational, CostFunction, CostFct3DVar/3DFGAT/4DVar/WC4DVar/4DEnsVar, CostJo, CostJb3D/4D/Jq, Minimizer (PCG/DRPCG/FGMRES/RPCG/...), LocalEnsembleSolver, LETKF/GETKF (Deterministic/Stochastic), SequentialEnsembleSolver/EAKF, LocalEnsembleDA, Observer, Observers, Variables, FieldSet3D/4D, FieldSets, IncrementSet, StateSet, GeometryData, PseudoModel, CommRedistribution, CommRedistributionRepository, FieldSetSubCommunicators, Application runs (Forecast/HofX/EDA/GenEnsPertB/...), inflation (RTPP/RTPS/mult), cross-validation, Nerger regulation, implicit/explicit Diffusion, L95/QG toy models.

## Overview

C++/Fortran framework for model-agnostic NWP data assimilation. Source at `bundle/oops/`.

Build/test quirks in `claude/build-and-test.md`.

## Source Layout (`src/oops/`)

| Directory | Purpose |
|-----------|---------|
| `interface/` | Thin template wrappers delegating to `MODEL::*` / `OBS::*` implementations (e.g., `interface::State<MODEL>`, `interface::Geometry<MODEL>`). These enforce timing, logging, and the API contract. |
| `base/` | Higher-level OOPS objects built on `interface/` (e.g., `oops::State<MODEL>`, `FieldSet3D`, `FieldSets`, `Variables`, `GeometryData`, `IncrementSet`, `StateSet`). This is where most algorithmic logic lives. |
| `assimilation/` | DA algorithms: cost functions (`CostFunction`, `CostFct3DVar`, `CostFct4DEnsVar`), minimizers (17 total), and local ensemble solvers (5 total). |
| `runs/` | Top-level `Application` subclasses that serve as entry points: `Variational`, `Forecast`, `LocalEnsembleDA`, `HofX3D`, `HofX4D`, `EDA`, etc. Each `Application::execute()` reads a YAML config and runs end-to-end. |
| `generic/` | Model-independent implementations: `IdentityModel`, `HybridLinearModel`, `AtlasInterpolator`, `UnstructuredInterpolator` (triangulation-based; supports nearest-neighbor fill outside regional domains via YAML key `regional nn fill distance in km` — chord distance; the `regional check enabled` flag and its `isRegional()`-based bypass were removed in PR #3313), `Diffusion` (Weaver & Courtier 2001 explicit horizontal + Mirouze & Weaver 2010 implicit vertical via `VerticalMethod::{Explicit,Implicit}`; explicit is the default and bit-for-bit identical to prior behavior — PR #3275; when no area field is precomputed it estimates per-node control-volume area via median-dual (barycentric lumped) cell area and uses an `aspectRatio·inv_area` explicit-stability iteration bound, replacing the old edge-length average / `1/edgeLength²` and staying stable on irregular NodeColumns while unchanged on uniform quads — PR #3319; `calculateDerivedGeom_NodeColumns` tolerates empty partitions for multi-PE obs-space diffusion — PR #3311; public accessor `Diffusion::inverseArea()` exposes the per-node 1/area field — PR #3326), FFT utilities, HTLM tools. |
| `util/` | Utilities: `DateTime`, `Duration`, `Logger`, `ConfigFunctions` (PR #3336 reworked emptiness handling: `isVector`/`isFinal` now exclude empty configs, `seekAndReplace` no-ops on an empty pattern, and `mergeConfigs` merges vectors as `LocalConfiguration` sub-configs rather than string vectors, which had corrupted non-string sequences; when config2's entry is empty, config1's vector is copied through), MPI helpers, Fortran interop. Includes `Factory.h` (generic factory template with variadic maker args) and `FunctionSpaceHelpers.h` (`getSizeOwned`, `countOwned`, `executeFunc` dispatcher over concrete ATLAS function-space types; the `isRegional` helper was removed in PR #3313 along with the `UnstructuredInterpolator` regional-check flag). |
| `util/redistribution/` | `CommRedistribution` (abstract) for repartitioning ATLAS fields between parent/sub communicators. Concrete: `CommGatherScatterRedistribution` (gather-scatter) and `CommStraightRedistribution` (direct MPI `allToAllv` with global-index mapping, cached for reuse — uses `detail/AllToAllRouting` helper). `CommRedistributionCompatChecker` validates compatibility. `CommRedistributionRepository` (PR #3196) is a multiton cache keyed on (parent FunctionSpace, sub FunctionSpace, method string); callers obtain an existing plan via `get()` instead of reconstructing the (costly) redistribution each call. |
| `mpi/` | MPI communicator management for ensemble/model decomposition. `ColorInfo` analyzes MPI color grouping in split communicators. `Scope` provides RAII temporary communicator switching. |
| `atlas/` | Atlas-based interpolation wrappers. |

### Key Base Classes

**`oops::Variables`** (`base/Variables.h`) — Container of `Variable` objects (no duplicates). Each `Variable` has a name, `VariableMetaData` (vertical stagger: CENTER/INTERFACE/TOP_INTERFACE/BOTTOM_INTERFACE/CENTER_WITH_TOP; data type: Real64 default; domain: Atmosphere/Ocean/Land), and optional vertical level count. Supports set operations (`+=`, `-=`, `intersection`), subset check (`<=`), and STL iteration.

**`oops::FieldSet3D`** (`base/FieldSet3D.h`) — Wraps `atlas::FieldSet` with a valid time and MPI communicator. Key methods: `deepCopy()`, `shallowCopy()`, `zero()`, arithmetic (`+=`, `-=`, `*=`, `/=`), `dot_product_with()`, `norm()`, `read()`/`write()`, `serialize()`/`deserialize()`. Access fields by index, name, or `Variable` object.

**`oops::FieldSet4D`** (`base/FieldSet4D.h`) — Collection of `FieldSet3D` objects across time steps. Used for 4D increments and ensemble members. Can be constructed from `State4D` or `Increment4D`.

**`oops::FieldSets`** (`base/FieldSets.h`) — Extends `DataSetBase<FieldSet3D>` to hold a collection of `FieldSet3D` objects distributed across time and ensemble dimensions. Can be constructed from an `IncrementSet<MODEL>` (shallow-copying its field data), from YAML config for file I/O, or as an empty container populated via `emplace_back(timeIndex, ensIndex, fieldSet3D)`. Supports element-wise `operator*=` with a `FieldSet3D` or a scalar.

**`oops::IncrementSet`** (`base/IncrementSet.h`) — Collection of `Increment<MODEL>` objects distributed across time steps and ensemble members. Extends `DataSetBase<Increment<MODEL>, Geometry<MODEL>>`. Replaces the retired `IncrementEnsemble` and `IncrementEnsemble4D` classes (removed in PR #3147). Supports arithmetic (`+=`, `-=`, `*=`), `zero()`, `diff()`, `schur_product_with()`, `dot_product_with()`, and ensemble mean computation. Can be constructed from geometry + variables + times, from config (file I/O), or from a `StateSet`.

**`oops::StateSet`** (`base/StateSet.h`) — Collection of `State<MODEL>` objects distributed across time steps and ensemble members. Extends `DataSetBase<State<MODEL>, Geometry<MODEL>>`. Replaces the retired `StateEnsemble` and `StateEnsemble4D` classes (removed in PR #3147). Provides `ens_mean()` to compute ensemble mean and `transpose()` to redistribute states across communicators.

**`oops::GeometryData`** (`base/GeometryData.h`) — Provides spatial queries on model grids: `closestTask(lat, lon)`, `closestPointWithinRadius(lat, lon, radius_m)` (returns task-local index of the globally-nearest owned point within the chord-distance radius, or `nullopt`), `containingTriangleAndBarycentricCoords()`, KD-tree indexing (global node tree now keyed on `(idx, idx)` pairs to support cross-task lookups). Not a model interface — it's a utility wrapping ATLAS function spaces.

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

## Local Ensemble Solvers (5 total)

Configured via `local ensemble DA: { solver: "<name>" }`:

| Solver | Description |
|--------|-------------|
| `Deterministic LETKF` | Local Ensemble Transform Kalman Filter (Hunt et al. 2007) |
| `Stochastic LETKF` | LETKF with perturbed observations |
| `Deterministic GETKF` | Generalized ETKF with model-space localization (Lei 2018) |
| `Stochastic GETKF` | GETKF with perturbed observations |
| `EAKF` | Ensemble Adjustment Kalman Filter — sequential scalar-obs update (Anderson 2003); derives from new `SequentialEnsembleSolver` base class |

LETKF and GETKF derive from `LocalEnsembleSolver` (iterate over grid points, solve local analysis using all nearby obs at once). They drive obs-space R-localization through `ObsLocalization::computeLocalization(GeometryIterator, ObsVector)`. Optional **Nerger et al. (2012) regulation factor** for LETKF obs localization: enabled via `local ensemble DA.use nerger regulation: true` (default `false`); applies only to diagonal R; computed per-observation in `LocalEnsembleSolver::computeNergerLocalR()`. Tested with `letkf_nerger_localization` (L95).

When QC filters reject observations only for some ensemble members, that rejection is propagated to all members of the ensemble: `LocalEnsembleSolver::applyAssimilatedMask` (overload taking `Observations_`) and `GETKFSolver::computeHofX` now call `updateAssimilatedMask` to ensure the assimilated mask matches between the ensemble-mean H(x), every modulated `HZb`, and the nonlinear `Yb` member H(x) values (PR #3231).

EAKF derives from `SequentialEnsembleSolver` (iterate over observations, update one obs at a time against all model state points within localization radius). Uses the new scalar `ObsLocalization::computeLocalization(Point3, Point3) → double` (0.0–1.0) interface to evaluate point-to-point localization for each obs/state pair; both points now carry a real vertical coordinate (via ioda's `iterator vertical coordinate` YAML key, PR #3295) — but `measurementUpdate` currently has a TODO noting there's no check that the geometry-iterator and obs-iterator vertical coordinate systems are actually compatible (e.g. pressure vs. height), so mixed-coordinate localization configs can silently produce nonsense. The protected `obsEnsembleUpdate` hook that derived solvers override now takes/returns `Eigen::VectorXd` for both arguments (was `VectorXf`): double precision is the contract, no float cast. `SequentialEnsembleSolver` wires in inflation matching LETKF semantics, prior `mult` (applied as sqrt on Xa/yb) and posterior `rtpp`/`rtps`, plus a no-obs early-exit (analysis = background). Tested with `sequential_enkf` (L95, QG) and `sequential_enkf_noobs`.

`DeparturesEnsemble::packEigen()` (`base/DeparturesEnsemble.h`) now caches the member-0 `Departures` (`dep0_`) instead of reconstructing/deserializing it on every call, cutting redundant work in the sequential solver's per-gridpoint/per-obs inner loop (PR #3337); invalidated when member 0 is re-set.

Optional online **Degrees-of-Freedom-for-Signal (DFS)** estimator for LETKF/ETKF (`assimilation/DFSCalculator.h`, PR #3070, Hu et al. 2025): enabled via `local ensemble DA.dfs: true`. Computes per-obs DFS from the analysis weights (`diag((Wa·Yb)ᵀ(Wa·Yb)) ⊙ invR / (nens-1)`), logs per-block means, and writes a per-obs `DFS` variable to the obspace netCDF. Wired into `LocalEnsembleSolver` (ctor + `measurementUpdate`) and `DeterministicLETKF::measurementUpdate`. Single-task only: throws `NotImplemented` under MPI-distributed obs.

The `obs localizations` YAML subsection is now optional in `ObsLocalizations` (PR #3287): absent config yields an empty localization set rather than an error.

## Cost Functions (5 total)

Every variational cost function minimizes `J(x) = Jb + Jo [+ Jc]` where Jb is the background term, Jo the observation term, and Jc an optional constraint (e.g. `CostJcDFI` for digital filter initialization). All live in `src/oops/assimilation/`. Configured via `cost type` in YAML:

| YAML Name | Class | Control Variable | Needs TLM/ADM? | Notes |
|-----------|-------|------------------|----------------|-------|
| `3D-Var` | `CostFct3DVar` | 3D state at window midpoint | No | `J = ½(x-xb)ᵀB⁻¹(x-xb) + ½(y-H(x))ᵀR⁻¹(y-H(x))`. Fastest. |
| `3D-FGAT` | `CostFct3DFGAT` | 3D state at initial time | Yes | Background forecast to obs times, H(x) evaluated at correct time; analysis is single-time. |
| `4D-Var` | `CostFct4DVar` | Initial condition x₀ | Yes | Strong constraint: state must lie on trajectory `M(x₀)`. `J = ½(x₀-xb)ᵀB⁻¹(x₀-xb) + ½Σₜ (yₜ-Hₜ(Mₜ(x₀)))ᵀRₜ⁻¹(...)`. |
| `4D-Var-Weak` | `CostFctWC4DVar` | 4D — states at sub-window boundaries + model-error increments qₖ | Yes | Weak constraint: allows `qₖ ~ N(0,Qₖ)`. Sub-windows distributed across `commTime`. |
| `4D-Ens-Var` | `CostFct4DEnsVar` | 4D state at snapshot times | No | 4D ensemble B provides time covariance; no TLM/ADM needed. |

**Jb classes**: `CostJb3D` (single-time B, used by 3D-Var/FGAT/4D-Var), `CostJb4D` (4D-Ens-Var), `CostJbJq` (weak 4D-Var, B + model error Q per sub-window). Key ops: `linearize()`, `Bmult()`, `Bminv()`, `randomize()`.

**Jo** (`CostJo.h`): runs observers, loads `ObsValue`, computes departures `H(x)-y`, applies `R⁻¹` to get gradient, returns `½ ydep · gradFG`. Rejected obs (qcflag != 0 → obs error masked to missing) are skipped via missing-value propagation in `ObsVector` arithmetic and `dot_product_with`.

**`ObsSpaces` construction** (PR #3358, breaking): `ObsSpaces<OBS>` now takes the *whole* `observations:` section rather than the `observers:` list. The obs-space specs must sit under an `observers:` key; if it is absent the constructor throws `eckit::UserError`. Keys placed directly under `observations:` become per-obs-space defaults, applied by `detail::applyObsSpaceDefaults` in `base/ObsSpaces.h`. The first such key is `obs data container: ObsGroup|OSDF`, which sets each space's `use data frame container` bool unless that space already specifies it (obs-space-level setting wins). `CostJo`, `HofX3D`, `HofX4D`, and `LocalEnsembleDA` were all updated to pass the full section. `test/interface/ObsTestsFixture.h` still accepts the old bare-sequence form but logs a deprecation warning.

**Non-const obs aux during H(x)** (PR #3367): `ObsOperatorBase::simulateObs`, `interface::ObsOperator::simulateObs`, and `Observer(s)::initialize` take `ObsAuxControl_ &` **non-const**, so an obs operator may initialize its bias coefficients while computing H(x) (see the ufo VarBC cold start). `CostJo::setPostProc` `const_cast`s `xx.obsVar()`, and `LocalEnsembleSolver::computeHofX` drops `const` on its `ObsAux_`. `CostJbObsAux` reads `obs bias.cold start.enable` per obs space and, on the first outer loop, adopts the cold-started coefficients as the Jb background so Jb does not pull them back toward zero. This changes the `OBS::ObsOperator::simulateObs` signature every downstream implementation must match.

**Outer/inner loops** (`Variational::execute`): outer loop does NL model eval + relinearization of B/TLM/H; inner loop runs the minimizer against the linearized problem to produce δx; update `x ← x + δx`; repeat.

## Ensemble Inflation Options

Configured within `local ensemble DA` section:

- **RTPP** (`rtpp`): Relaxation To Prior Perturbation — blends analysis perturbations with prior perturbations. Value 0–1 (0 = pure analysis, 1 = pure prior).
- **RTPS** (`rtps`): Relaxation To Prior Spread — relaxes analysis spread toward prior spread. Value 0–1. Multiplier is γ = (1−α) + α·(σ_b/σ_a). For an `IncrementSet`, the inflation now uses an incremental form `dxa_i ← γ·dxa_i + (γ−1)·(xb'_i − dxa_mean)` (PR #3278) so increment- and state-based paths give equivalent results. Reference: Inverarity et al. 2023 §3 (QJRMS, doi:10.1002/qj.4431).
- **Multiplicative** (`mult`): Uniform multiplicative inflation factor applied to all perturbations.

## Observation Distribution Modes

How observations are distributed across MPI tasks (`ioda::Distribution` implementations):
- **RoundRobin** — cyclic assignment of obs to ranks (default)
- **Halo** — each rank gets obs within a geographic halo of its model domain; used for localized ensemble methods
- **InefficientDistribution** — all obs on all ranks (testing/debugging only)

## PseudoModel

`oops::PseudoModel<MODEL>` (`generic/PseudoModel.h` — `PseudoModelState4D.h` is a separate class) — model-agnostic "model" that reads pre-computed states from files at each time step instead of running a forecast. Used for H(x) and testing applications where model integration is unnecessary. Supports `states from template` for many time steps. The non-template config validators (`MultipleStateTemplateConfigValidator`, `PseudoModelConfigValidator`) live in `generic/PseudoModel.cc`.

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

See `claude/cross-repo-interactions.md` for full details.
