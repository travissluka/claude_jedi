# Cross-Repo Interactions

> Last updated 2026-09-03. Based on the same repo commits as the individual `claude/*.md` files.
>
> **Covers:** MODEL template contract (Geometry/State/Increment/Model/LinearModel/VariableChange/LinearVariableChange/ErrorCovariance/ModelAux*/LocalInterpolator/ModelData), ufo::ObsTraits, GetValues<MODEL,OBS>, saber::ErrorCovariance<MODEL>, instantiateCovarFactory, instantiateObsFilterFactory, instantiateObsLocFactory, ATLAS as shared data layer, impact map (what-changes-affects-what), C++/Fortran interop patterns (ISO_C_BINDING / opaque-handle / ATLAS bridge), coupled DA, CRTM integration.

How the JEDI repositories interact with each other. Read this to understand what changes in one repo may affect in others.

## The Two Template Parameters

All JEDI algorithms in oops are templated on `MODEL` and `OBS`:

```cpp
oops::Variational<fv3jedi::Traits, ufo::ObsTraits>
oops::LocalEnsembleDA<mpas::Traits, ufo::ObsTraits>
```

- **`MODEL`** is a Traits struct (defined in each model repo) bundling all model-specific types: Geometry, State, Increment, Model, LinearModel, VariableChange, ErrorCovariance, etc.
- **`OBS`** is `ufo::ObsTraits` (defined in `ufo/src/ufo/ObsTraits.h`), bundling observation types from both UFO and IODA: `ioda::ObsSpace`, `ioda::ObsVector`, `ufo::ObsOperator`, `ufo::GeoVaLs`, `ufo::ObsFilters`, `ufo::ObsBias`, etc.

## What MODEL Must Implement

oops `interface/` headers wrap the inner classes automatically — model repos only implement the inner types. Every implementation class needs `static const std::string classname()`.

### Geometry — `Geometry(const eckit::Configuration &, const eckit::mpi::Comm &)`

| Method | Purpose |
|--------|---------|
| `GeometryIterator begin()/end() const` | Gridpoint iteration |
| `std::vector<double> verticalCoord(std::string &) const` | Vertical coordinate values |
| `std::vector<size_t> variableSizes(const Variables &) const` | Levels per variable at one location (typically delegates to `FieldsMetadata`) |
| `bool levelsAreTopDown() const` | True if vertical levels ordered top→bottom (fv3-jedi and soca hardcode true) |
| `const eckit::mpi::Comm & getComm() const` | MPI communicator |
| `const atlas::FunctionSpace & functionSpace() const` | ATLAS function space (grid) |
| `const atlas::FieldSet & fields() const` | ATLAS fields (lat, lon, masks) |

### State

Required constructors: `(Geometry, Variables, DateTime)` (empty), `(Geometry, Configuration)` (read/analytic), `(Geometry, State)` (copy + resolution change), `(Variables, State)` (copy + variable change), `(State)` (copy).

| Method | Purpose |
|--------|---------|
| `validTime()`, `updateTime(Duration)` | Time accessors |
| `read/write(Configuration)` | File I/O |
| `norm()`, `variables()`, `zero()` | Basic queries/ops |
| `accumul(double, const State &)` | `this += w * other` |
| `toFieldSet(FieldSet &) const` / `fromFieldSet(const FieldSet &)` | **ATLAS bridge.** `toFieldSet` includes halo; `fromFieldSet` reads interior only. |
| `serialSize()`, `serialize(vec)`, `deserialize(vec, i)` | Used in 4DEnVar, weak 4DVar, Block-Lanczos |

### Increment

Required constructors: `(Geometry, Variables, DateTime)` (zero), `(Geometry, Increment)` (copy + resolution), `(Increment, bool copy=true)` (copy or zero with same shape).

| Method | Purpose |
|--------|---------|
| `diff(State, State)` | Set to `state1 - state2` |
| `zero()`/`zero(DateTime)`, `ones()`, `sqrt()` | Bulk element ops |
| `dirac(Configuration)` | Impulse response (SABER tests) |
| `+=`, `-=`, `*=(double)`, `axpy(w, dx)` | Linear algebra |
| `dot_product_with(Increment)`, `schur_product_with(Increment)` | Inner/Hadamard products |
| `random()` | Randomize (tests) |
| `accumul(double, const State &)` | `this += w * state` (WeightedDiff) |
| `getLocal(GeometryIterator)` → `LocalIncrement`, `setLocal(LocalIncrement, GeometryIterator)` | Column access — **essential for LETKF/GETKF** |
| `read/write/norm/variables/validTime/updateTime` | As State |
| `toFieldSet/fromFieldSet` | ATLAS bridge |
| `serialSize/serialize/deserialize` | Serialization support |

### Model (Nonlinear) — `Model(Geometry, Configuration)`

`initialize(State)`, `step(State, ModelAuxControl)`, `finalize(State)`, `timeResolution()`.

### LinearModel (TLM/ADM) — `LinearModel(Geometry, Configuration)`

Required for 4DVar. TL runs forward; AD runs backward.

| Method | Purpose |
|--------|---------|
| `setTrajectory(State, State, ModelAuxControl)` | Store NL trajectory |
| `initializeTL/stepTL/finalizeTL(Increment)` | TL pass |
| `initializeAD/stepAD/finalizeAD(Increment)` | AD pass (ModelAuxIncrement modified) |
| `timeResolution()`, `stepTrajectory()` | Timing |

### GeometryIterator

Forward iterator over gridpoints (LocalEnsembleDA). Methods: `operator==`, `operator!=`, `operator*` (→ `eckit::geometry::Point3(lon, lat, vert)`), `operator++`.

### VariableChange / LinearVariableChange

- **Nonlinear**: `changeVar(State, Variables)`, `changeVarInverse(State, Variables)`
- **Linear**: `changeVarTraj(State, Variables)` + TL/AD/inverse variants (`changeVarTL`, `changeVarInverseTL`, `changeVarAD`, `changeVarInverseAD`)

### ErrorCovariance — `Covariance(Geometry, Variables, Configuration, State, State)`

`randomize(Increment)`, `multiply(Increment, Increment)`, `inverseMultiply(Increment, Increment)`. Most model repos leave this as a stub — SABER registers `"SABER"` in the covariance factory instead.

### ModelAuxControl / ModelAuxIncrement / ModelAuxCovariance

Auxiliary state for model bias/parameters; minimal stubs in most repos. ModelAuxIncrement supports full linear algebra + `diff(Control, Control)`.

### ModelData — `ModelData(Geometry)`

`modelData()` (metadata as config), `defaultVariables() const` (instance method as of oops#3244, 2026-04-30 — looks up defaults from the `Geometry`'s `FieldMetaData`; model-interface repos must implement `oops::Variables defaultVariables() const`, not the previous `static`).

### LocalInterpolator — `LocalInterpolator(Configuration, Geometry, lats, lons)`

`apply(Variables, State, mask, vec)`, `apply(Variables, Increment, mask, vec)`, `applyAD(Variables, Increment, mask, vec)`. Most repos use `oops::UnstructuredInterpolator` (generic ATLAS-based); pyiri-jedi uses custom interpolators for field-aligned geometry.

## How GetValues Bridges Model to Observations

`oops::GetValues<MODEL, OBS>` (`oops/src/oops/base/GetValues.h`) is the critical bridge:

1. Takes `Geometry<MODEL>` + `oops::Locations<OBS>` (obs locations from UFO)
2. Creates `LocalInterpolator<MODEL>` instances per MPI task per sampling method
3. During time-stepping, calls `process(State)` → interpolates model fields to obs locations
4. Exchanges interpolated data across MPI ranks via `allToAll()`
5. Populates `GeoVaLs<OBS>` (UFO's container for model data at obs locations)
6. `ufo::ObsOperator::simulateObs(GeoVaLs)` then computes H(x)

As of oops PR #3202 (2026-04-22), `oops::Locations<OBS>` wraps the list of `ufo::SampledLocations` (one per sampling method) and the loop over sampling methods moved *inside* GetValues. Previously, `Observer`/`ObserverTLAD` iterated sampling methods externally and constructed a `GetValues` per method. The obs-side `ufo::SampledLocations` type is unchanged; the change is purely in how oops constructs and drives the bridge.

Both fv3-jedi and mpas-jedi use `oops::UnstructuredInterpolator` as their `LocalInterpolator`. pyiri-jedi implements custom interpolators for field-aligned geometry. soca uses the same pattern for ocean/ice observations.

## How SABER Provides Error Covariance to Any Model

`saber::ErrorCovariance<MODEL>` (`saber/src/saber/oops/ErrorCovariance.h`):

1. Inherits `oops::ModelSpaceCovarianceBase<MODEL>` — plugs into oops cost function as the B matrix
2. Converts `MODEL::Increment` → `atlas::FieldSet` using model-provided `toFieldSet()`
3. Applies SABER block chain on ATLAS FieldSets (model-agnostic)
4. Converts back via `fromFieldSet()`

**This is why all model repos must implement `toFieldSet()`/`fromFieldSet()`** — it's the bridge to SABER.

SABER also provides `Localization<MODEL>` for ensemble methods (same FieldSet conversion pattern).

## How UFO and IODA Split the OBS Contract

`ufo::ObsTraits` (`ufo/src/ufo/ObsTraits.h`) bundles types from **both** repos:

| Type | Source Repo | Purpose |
|------|------------|---------|
| `ObsSpace` | **ioda** | Observation data container, file I/O, MPI distribution |
| `ObsVector` | **ioda** | Vector of observation values |
| `ObsDataVector<T>` | **ioda** | Templated observation data |
| `ObsOperator` | **ufo** | Forward operator H(x) |
| `LinearObsOperator` | **ufo** | TL/AD of H(x) |
| `GeoVaLs` | **ufo** | Model state at obs locations |
| `ObsFilters` | **ufo** | QC filter chain |
| `ObsError` | **ufo** | Observation error covariance R |
| `ObsBias` | **ufo** | Observation bias correction |
| `ObsDiagnostics` | **ufo** | H(x) diagnostics for filters |
| `SampledLocations` | **ufo** | Interpolation paths |

**ioda** handles data I/O and storage. **ufo** handles physics (operators, filters, bias).

**Two breaking contract changes on the OBS side** (oops #3358 / #3367, ufo #4278/#4298):

- `simulateObs` takes its obs-aux argument **non-const**: `simulateObs(const GeoVaLs_ &, ObsVector_ &, ObsAuxControl_ & obsaux, const ObsDataInt_ &, ObsVector_ &, ObsDiags_ &)` in both `oops::ObsOperatorBase` and `oops::interface::ObsOperator`, mirrored by `ufo::ObsOperator::simulateObs(..., ObsBias &, ...)`. This lets an operator initialize bias coefficients while computing H(x) (the ufo VarBC cold start). Any out-of-tree `OBS::ObsOperator` must drop the `const`.
- `oops::ObsSpaces<OBS>` is constructed from the **whole `observations:` section**, not the `observers:` list. The obs-space specs must sit under `observers:` (absent key → `eckit::UserError`), and keys directly under `observations:` act as per-obs-space defaults (`detail::applyObsSpaceDefaults`; first user is `obs data container: ObsGroup|OSDF`). Every driver or application that builds `ObsSpaces` (including model-repo mains such as ufo's `RunCRTM`) and every obs YAML must follow suit.

## How VADER Integrates with Model Variable Changes

VADER is a non-template library operating on `atlas::FieldSet` directly. Model repos use it in their `VariableChange` implementations:

```
fv3jedi::VariableChange::changeVar(State, Variables)
  → VADER::changeVar(FieldSet, Variables)   // generic recipes first
  → fv3jedi-specific transforms             // model-specific fallback
```

- VADER's `planVariable()` algorithm auto-discovers recipe chains from available ingredients
- If VADER can't produce a variable, the model-specific transform handles it
- Both fv3-jedi and mpas-jedi use this pattern; pyiri-jedi has simpler variable changes

SABER also uses VADER internally via `VaderBlock` (in `saber/src/saber/vader/`) for variable transforms within covariance block chains.

## Factory Instantiation Wiring

Every model executable must register factories from multiple repos. The pattern is identical across all model interfaces:

```cpp
// In fv3jediVar.cc (or mpasVariational.cc, etc.)
saber::instantiateCovarFactory<MODEL::Traits>();    // SABER blocks + oops base covariances
saber::instantiateLocalizationFactory<MODEL::Traits>(); // SABER localization
ufo::instantiateObsFilterFactory();                  // ~80+ UFO QC filters
ufo::instantiateObsLocFactory<MODEL::GeometryIterator>(); // UFO obs localization

oops::Variational<MODEL::Traits, ufo::ObsTraits> app;
run.execute(app);
```

The `instantiate*Factory` calls register static `Maker` objects that link YAML config names to concrete classes. This is why model mains are typically ~10 lines — all the work is in factory registration.

**`saber::instantiateCovarFactory<MODEL>`** internally chains:
1. `oops::instantiateCovarFactory<MODEL>()` — registers `ensemble`, `hybrid`, model-default covariances
2. Registers `"SABER"` as a covariance model name → `saber::ErrorCovariance<MODEL>`
3. `instantiateLocalizationFactory<MODEL>()` — registers SABER localization
4. `instantiateBlockChainFactory<MODEL>()` — registers `parametric`, `ensemble`, `hybrid` chain types

## ATLAS as the Common Data Layer

ATLAS (`atlas::FieldSet`, `atlas::FunctionSpace`) is the shared data representation across all repos:

- **Model repos** store State/Increment data as ATLAS FieldSets, expose via `toFieldSet()`/`fromFieldSet()`
- **SABER** operates exclusively on ATLAS FieldSets for covariance operations
- **VADER** operates exclusively on ATLAS FieldSets for variable transforms
- **oops** uses `oops::FieldSet3D`/`FieldSet4D` wrappers around ATLAS FieldSets
- **UFO** uses its own `GeoVaLs` (Fortran-backed) for obs-location data, separate from ATLAS

The ATLAS FieldSet is the "lingua franca" that lets SABER and VADER work with any model without knowing its internals.

## Data Flow: Complete 3DVar Cycle

```
YAML config
  │
  ├─ geometry section ──────────────→ MODEL::Geometry (grid, MPI layout)
  ├─ background section ────────────→ MODEL::State (read from file)
  ├─ background error section ──────→ saber::ErrorCovariance<MODEL> (B matrix)
  │                                    └─ SaberBlockChain (BUMP/spectral/etc.)
  ├─ observations section ──────────→ ioda::ObsSpace[] (read obs files)
  │                                  → ufo::ObsOperator[] (H(x) operators)
  │                                  → ufo::ObsFilters[] (QC chains)
  │                                  → ufo::ObsBias (bias correction)
  └─ minimizer section ────────────→ oops::Minimizer (PCG, DRPCG, etc.)

Execution:
1. CostFunction<MODEL, OBS> created from config
2. GetValues<MODEL, OBS> interpolates background to obs locations
3. ObsOperator computes H(x_b) → departure d = y - H(x_b)
4. Minimizer iterates:
   a. B * dx (SABER: State → FieldSet → block chain → FieldSet → Increment)
   b. H * dx (GetValues: Increment → interpolate → GeoVaLs → ObsOperator TL)
   c. H^T * dy (adjoint of above)
   d. R^{-1} * dy (observation error)
5. Analysis: x_a = x_b + dx
6. VariableChange (VADER + model-specific) if needed
7. Write output
```

## Impact Map: What Changes Where

| If you change... | You may need to update... |
|-----------------|--------------------------|
| oops interface contract (e.g., new method on State) | All model repos (fv3-jedi, mpas-jedi, pyiri-jedi, soca, L95, QG) |
| ufo::ObsTraits (new type alias) | All model repo mains that instantiate with `ufo::ObsTraits` |
| oops `ObsOperatorBase::simulateObs` signature | Every `OBS::ObsOperator` implementation (ufo, plus any out-of-tree obs backend) |
| oops `ObsSpaces` constructor / `observations:` YAML shape | All applications constructing `ObsSpaces`; all obs YAML in every repo's tests |
| SABER block interface | All blocks in saber; model repos unaffected (ATLAS abstraction) |
| VADER recipe | No other repos need changes (auto-discovered via cookbook) |
| ioda::ObsSpace API | ufo (uses ObsSpace in operators/filters), model repo tests (YAML obs configs) |
| Model Geometry/State | Only that model repo; oops/saber/ufo are insulated by templates |
| ATLAS FieldSet format | Potentially everything — it's the shared data layer |
| YAML config schema | Tests in the affected repo; possibly downstream model repo tests |
| CRTM coefficient files or API | ufo CRTM operators; all model repo radiance tests |
| oops coupled types (GeometryCoupled, etc.) | coupling repo; soca+fv3-jedi coupled tests |

## C++/Fortran Interop Patterns (Shared Across Repos)

Three patterns used throughout JEDI:

1. **UFO pattern**: `*.cc` ↔ `*.interface.h` (C declarations) ↔ `*.interface.F90` (ISO_C_BINDING wrappers) ↔ `*_mod.F90` (Fortran modules). Used by UFO operators, SABER BUMP, ioda engines.

2. **Opaque handle pattern** (mpas-jedi, fv3-jedi): C++ holds an integer handle (`F90geom`, `F90state`), passes it to `extern "C"` functions with `_f90` suffix. Fortran side uses a registry/linked-list to look up the actual Fortran derived type.

3. **ATLAS bridge pattern**: C++ converts to `atlas::FieldSet`, Fortran accesses the same memory via ATLAS Fortran API (`atlas_FieldSet`). Used by SABER, model repos for `toFieldSet()`/`fromFieldSet()`.

## Coupled Data Assimilation

The **coupling** repo enables atmosphere-ocean coupled DA using oops coupled types:
- `oops::GeometryCoupled<fv3jedi::Traits, soca::Traits>` — manages two geometries
- `oops::StateCoupled<fv3jedi::Traits, soca::Traits>` — holds both atmosphere and ocean states
- `oops::AuxCoupledModel<fv3jedi::Traits, soca::Traits>` — coupled model bias

This enables coupled 3DVar/4DVar, coupled forecasting, and coupled H(x) with a unified state spanning both atmosphere and ocean.

## SOCA (Ocean Component)

soca follows the same Traits pattern as fv3-jedi and mpas-jedi, interfacing with MOM6 ocean model and Icepack sea ice model. Key differences: uses `ModelOceanIceEmulator` as its Model type, includes ML-based balance operators (`MLBalance/`), and has SABER-specific balance blocks (`SaberBlocks/`).

## CRTM Integration

CRTM (Community Radiative Transfer Model) provides satellite radiance simulation. UFO wraps it as observation operators: `ObsRadianceCRTM` (forward), `ObsRadianceCRTMTLAD` (TL/AD), `ObsAodCRTM` (aerosol optical depth). The UFO-side Fortran modules (`ufo_radiancecrtm_mod.F90`, `ufo_crtm_utils_mod.F90`) are substantial (~30-96KB each) and handle the mapping between JEDI GeoVaLs and CRTM atmospheric profiles.

## IncrementEnsemble/StateEnsemble Retirement (March 2026)

oops PR #3147 retired `IncrementEnsemble`, `IncrementEnsemble4D`, `StateEnsemble`, and `StateEnsemble4D`, replacing them with `IncrementSet` and `StateSet` (which extend `DataSetBase` and support both time and ensemble dimensions). This affected:
- **pyiri-jedi** (PR #149): adapted `FieldsPyiri`, `StatePyiri`, and `ensemble_io.py` to use the new types
- **Other model interfaces**: any model code that constructed or iterated over ensemble containers needs updating
- The new classes use a unified `DataSetBase` pattern with `(timeIndex, ensIndex)` access

## Filters as SaberOuterBlockChain (March 2026)

SABER PR #1159 refactored filter blocks so that localization/correlation filters are implemented as `SaberOuterBlockChain` instances wrapping a central correlation block, rather than monolithic classes. New classes:
- `NICASFilter` (central block wrapping NICAS as a filter chain)
- `DiffusionFilter` (central block wrapping diffusion as a filter chain)
- `SpectralAnalyticalCorrelation` (central block replacing the monolithic `SpectralAnalyticalFilter`)
- `DiffusionImpl` extracted from `Diffusion` as shared implementation

Cross-repo impact: **fv3-jedi** (PR #1439) and **mpas-jedi** updated their `ProcessPerts` and covariance test YAML configs to use the new filter block names and structure.
