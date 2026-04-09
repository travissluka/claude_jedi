# MODEL Template Contract

What each model repo must implement to work with oops. All interface wrappers are in `oops/src/oops/interface/`. Model repos implement only the inner classes — oops wraps them automatically.

Every implementation class must provide `static const std::string classname()`.

## Geometry

**Constructor**: `Geometry(const eckit::Configuration &, const eckit::mpi::Comm &)`

| Method | Purpose |
|--------|---------|
| `GeometryIterator begin() const` | First gridpoint iterator |
| `GeometryIterator end() const` | Past-the-end iterator |
| `std::vector<double> verticalCoord(std::string &) const` | Vertical coordinate values |
| `std::vector<size_t> variableSizes(const Variables &) const` | Number of levels per variable at a single location |
| `bool levelsAreTopDown() const` | True if vertical levels ordered top→bottom |
| `const eckit::mpi::Comm & getComm() const` | MPI communicator |
| `const atlas::FunctionSpace & functionSpace() const` | ATLAS function space (grid definition) |
| `const atlas::FieldSet & fields() const` | ATLAS fields (lat, lon, masks) |

**Notes**: FV3-JEDI and SOCA both hardcode `levelsAreTopDown() = true`. `variableSizes()` typically delegates to `FieldsMetadata`.

## State

**Constructors** (all required):
```cpp
State(const Geometry &, const Variables &, const util::DateTime &)  // empty state
State(const Geometry &, const eckit::Configuration &)               // from config (read/analytic)
State(const Geometry &, const State &)                              // copy + resolution change
State(const Variables &, const State &)                              // copy + variable change
State(const State &)                                                 // copy
```

| Method | Purpose |
|--------|---------|
| `const util::DateTime validTime() const` | Time of this state |
| `void updateTime(const util::Duration &)` | Advance time by duration |
| `void read(const eckit::Configuration &)` | Read from file |
| `void write(const eckit::Configuration &) const` | Write to file |
| `double norm() const` | State norm (for tests) |
| `const Variables & variables() const` | Variables in this state |
| `void zero()` | Zero all values |
| `void accumul(const double &, const State &)` | `this += w * other` |
| `void toFieldSet(atlas::FieldSet &) const` | Copy to ATLAS FieldSet (with halo) |
| `void fromFieldSet(const atlas::FieldSet &)` | Copy from FieldSet (interior points only) |
| `size_t serialSize() const` | Size when serialized |
| `void serialize(std::vector<double> &) const` | Serialize to vector |
| `void deserialize(const std::vector<double> &, size_t &)` | Deserialize from vector |

**Notes**: Serialization is used in 4DEnVar, weak-constraint 4DVar, and Block-Lanczos minimizer. `toFieldSet` must include halo points; `fromFieldSet` should only read interior.

## Increment

**Constructors** (all required):
```cpp
Increment(const Geometry &, const Variables &, const util::DateTime &)  // zero increment
Increment(const Geometry &, const Increment &)                          // copy + resolution change
Increment(const Increment &, const bool copy=true)                      // copy or zero with same structure
```

| Method | Purpose |
|--------|---------|
| `void diff(const State &, const State &)` | Set to `state1 - state2` |
| `void zero()` / `void zero(const util::DateTime &)` | Zero out (optionally set time) |
| `void ones()` | Set all values to 1.0 |
| `void sqrt()` | Element-wise square root |
| `void dirac(const eckit::Configuration &)` | Impulse response from config |
| `operator+=`, `operator-=`, `operator*=(double)` | Linear algebra |
| `void axpy(const double &, const Increment &, bool check=true)` | `this += w * dx` |
| `double dot_product_with(const Increment &) const` | Dot product |
| `void schur_product_with(const Increment &)` | Element-wise (Hadamard) product |
| `void random()` | Randomize (for tests) |
| `void accumul(const double &, const State &)` | `this += w * state` (WeightedDiff) |
| `LocalIncrement getLocal(const GeometryIterator &) const` | Get local column at gridpoint |
| `void setLocal(const LocalIncrement &, const GeometryIterator &)` | Set local column |
| `void read/write(const eckit::Configuration &)` | File I/O |
| `double norm() const` | Increment norm |
| `const Variables & variables() const` | Variables |
| `const util::DateTime validTime() const` | Valid time |
| `void updateTime(const util::Duration &)` | Advance time |
| `void toFieldSet/fromFieldSet(atlas::FieldSet &)` | ATLAS FieldSet conversion |
| `size_t serialSize() const` | Serialization support |
| `void serialize/deserialize(...)` | Serialization support |

**Notes**: `getLocal/setLocal` are essential for LocalEnsembleDA (LETKF/GETKF). `dirac` is used by SABER for impulse response tests.

## Model (Nonlinear)

**Constructor**: `Model(const Geometry &, const eckit::Configuration &)`

| Method | Purpose |
|--------|---------|
| `void initialize(State &) const` | Prepare state before forecast |
| `void step(State &, const ModelAuxControl &) const` | One timestep |
| `void finalize(State &) const` | Cleanup after forecast |
| `const util::Duration & timeResolution() const` | Timestep duration |

## LinearModel (TLM/ADM)

**Constructor**: `LinearModel(const Geometry &, const eckit::Configuration &)`

| Method | Purpose |
|--------|---------|
| `void setTrajectory(const State &, State &, const ModelAuxControl &)` | Store NL trajectory |
| `void initializeTL(Increment &) const` | Prepare TL increment |
| `void stepTL(Increment &, const ModelAuxIncrement &) const` | TL timestep (forward) |
| `void finalizeTL(Increment &) const` | Finalize TL |
| `void initializeAD(Increment &) const` | Prepare AD increment |
| `void stepAD(Increment &, ModelAuxIncrement &) const` | AD timestep (backward) |
| `void finalizeAD(Increment &) const` | Finalize AD |
| `const util::Duration & timeResolution() const` | Timestep |
| `const util::Duration & stepTrajectory() const` | Forecast window |

**Notes**: Required for 4DVar. TL runs forward in time, AD runs backward. ModelAuxIncrement is modified in AD step.

## GeometryIterator

Forward iterator over gridpoints. Used in LocalEnsembleDA.

| Method | Purpose |
|--------|---------|
| `bool operator==(const GeometryIterator &)` | Equality |
| `bool operator!=(const GeometryIterator &)` | Inequality |
| `eckit::geometry::Point3 operator*() const` | Dereference → (lon, lat, vert) |
| `GeometryIterator & operator++()` | Advance to next gridpoint |

## ModelAuxControl / ModelAuxIncrement / ModelAuxCovariance

Auxiliary state for model bias/parameters. Currently minimal stubs in most model repos.

**ModelAuxControl**: Constructor, copy, read/write, norm, serialize/deserialize.

**ModelAuxIncrement**: Full linear algebra (`+=`, `-=`, `*=`, `axpy`, `dot_product_with`, `zero`), plus `diff(ModelAuxControl, ModelAuxControl)`, serialize/deserialize.

**ModelAuxCovariance**: `linearize`, `multiply`, `inverseMultiply`, `randomize`.

## VariableChange (Nonlinear)

**Constructor**: `VariableChange(const eckit::Configuration &, const Geometry &)`

| Method | Purpose |
|--------|---------|
| `void changeVar(State &, const Variables &)` | Transform state to target variables |
| `void changeVarInverse(State &, const Variables &)` | Inverse transform (legacy) |

## LinearVariableChange

**Constructor**: `LinearVariableChange(const Geometry &, const eckit::Configuration &)`

| Method | Purpose |
|--------|---------|
| `void changeVarTraj(const State &, const Variables &)` | Store trajectory for linearization |
| `void changeVarTL(Increment &, const Variables &) const` | Tangent linear transform |
| `void changeVarInverseTL(Increment &, const Variables &) const` | TL of inverse |
| `void changeVarAD(Increment &, const Variables &) const` | Adjoint transform |
| `void changeVarInverseAD(Increment &, const Variables &) const` | Adjoint of inverse |

## ErrorCovariance

**Constructor**: `Covariance(const Geometry &, const Variables &, const eckit::Configuration &, const State &, const State &)`

| Method | Purpose |
|--------|---------|
| `void randomize(Increment &) const` | Sample from N(0, B) |
| `void multiply(const Increment &, Increment &) const` | `y = B · x` |
| `void inverseMultiply(const Increment &, Increment &) const` | `y = B⁻¹ · x` |

**Notes**: Most model repos use SABER for B matrix and leave this as a stub. SABER registers `"SABER"` in the covariance factory.

## ModelData

**Constructor**: `ModelData(const Geometry &)`

| Method | Purpose |
|--------|---------|
| `const eckit::LocalConfiguration modelData() const` | Model metadata as config |
| `static const Variables defaultVariables()` | Default variable set |

## LocalInterpolator

**Constructor**: `LocalInterpolator(const eckit::Configuration &, const Geometry &, const std::vector<double> & lats, const std::vector<double> & lons)`

| Method | Purpose |
|--------|---------|
| `void apply(const Variables &, const State &, const std::vector<bool> &, std::vector<double> &) const` | Interpolate state to obs points |
| `void apply(const Variables &, const Increment &, const std::vector<bool> &, std::vector<double> &) const` | Interpolate increment |
| `void applyAD(const Variables &, Increment &, const std::vector<bool> &, const std::vector<double> &) const` | Adjoint interpolation |

**Notes**: Most model repos use `oops::UnstructuredInterpolator` (generic ATLAS-based). The mask vector controls which obs are active. Used by GetValues during H(x) computation.
