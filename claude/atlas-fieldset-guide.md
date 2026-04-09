# ATLAS FieldSet as Shared Data Layer

How `atlas::FieldSet` bridges model repos, SABER, and VADER in JEDI. FieldSet is the universal data exchange format — model repos populate them, SABER/VADER operate on them in-place.

## Data Flow

```
Model Fortran code
  → keyState_ (opaque F90 handle)
    → toFieldSet()  →  atlas::FieldSet
      → SABER blocks: multiply(FieldSet3D)
      → VADER recipes: changeVar(FieldSet)
    → fromFieldSet()  →  update model state
```

## How Model Repos Create FieldSets

### FV3-JEDI pattern

State/Increment data lives in Fortran. `toFieldSet()` and `fromFieldSet()` cross the C++/Fortran boundary:

```cpp
// fv3-jedi/src/fv3jedi/State/State.cc
void State::toFieldSet(atlas::FieldSet & fset) const {
  fv3jedi_state_to_fieldset_f90(keyState_, geom_.toFortran(), vars_, fset.get());
}
void State::fromFieldSet(const atlas::FieldSet & fset) {
  fv3jedi_state_from_fieldset_f90(keyState_, geom_.toFortran(), vars_, fset.get());
}
```

### SOCA pattern

SOCA's `Fields` base class holds `atlas::FieldSet fieldSet_` as a member:

```cpp
// soca/src/soca/Fields/Fields.cc
void Fields::toFieldSet(atlas::FieldSet & fset) const {
  fset.clear();
  util::shareFields(fieldSet_, fset);  // Shallow copy — shares data pointers
}
void Fields::fromFieldSet(const atlas::FieldSet & fset) {
  // Deep copy: element-wise loop over all fields
  for (const auto & field : fset) {
    auto view = atlas::array::make_view<double, 2>(field);
    auto myView = atlas::array::make_view<double, 2>(fieldSet_.field(field.name()));
    // Copy element by element...
  }
}
```

**Key difference**: FV3-JEDI round-trips through Fortran; SOCA stores the FieldSet natively.

### Contract for toFieldSet/fromFieldSet

- `toFieldSet()` must populate fields **including halo points** (ghost nodes)
- `fromFieldSet()` should only read **interior points** (non-ghost)
- Field names must match `oops::Variable` names used elsewhere in the system
- Each field must have correct shape: `(npoints, nlevels)` as 2D array

## How SABER Consumes FieldSets

SABER blocks operate on `oops::FieldSet3D` (a thin wrapper around `atlas::FieldSet` with valid time):

```cpp
// saber/src/saber/blocks/SaberOuterBlockBase.h
virtual void multiply(oops::FieldSet3D &) const = 0;
virtual void multiplyAD(oops::FieldSet3D &) const = 0;
```

### FieldSet3D wrapper (`oops/src/oops/base/FieldSet3D.h`)

```cpp
const atlas::FieldSet & fieldSet() const { return fset_; }
atlas::Field & operator[](const std::string & name) { return fset_[name]; }
```

Initialization methods:
- `init(FunctionSpace, Variables)` — allocate uninitialized fields
- `init(FunctionSpace, Variables, value)` — allocate with fill value
- `allocateOnly()` — create empty FieldSet
- `deepCopy(FieldSet3D)` / `shallowCopy(FieldSet)` — copy strategies

Arithmetic: `operator+=`, `-=`, `*=`, `/=` on FieldSet3D (element-wise across all fields).

### What SABER expects

- Fields accessed by name: `fset["temperature"]`
- Metadata derived from fields themselves: `field.shape(1)` = levels, `field.functionspace()` = grid
- `GeometryData` provides function space, vertical coordinate direction, and geometry fields
- SABER blocks are model-agnostic — they don't know about FV3 or SOCA

## How VADER Consumes FieldSets

VADER recipes operate directly on `atlas::FieldSet`:

```cpp
// vader/src/vader/vader.h
oops::Variables changeVar(atlas::FieldSet &, oops::Variables &) const;
```

Recipes look up fields by name and extract metadata from them:

```cpp
// vader/src/vader/recipes/AirPressure_A.cc
size_t productLevels(const atlas::FieldSet & afieldset) const {
  return afieldset.field("air_pressure_levels").shape(1) - 1;
}
atlas::FunctionSpace productFunctionSpace(const atlas::FieldSet & afieldset) const {
  return afieldset.field("air_pressure_levels").functionspace();
}
void executeNL(atlas::FieldSet & afieldset) {
  atlas::Field pressure = afieldset.field("air_pressure");
  // ... element-wise computation
}
```

**Key pattern**: VADER creates output fields using metadata from input fields (levels, function space), then computes in-place.

## GeometryData (`oops/src/oops/base/GeometryData.h`)

Passes geometry information to SABER blocks via FieldSet:

```cpp
GeometryData(const atlas::FunctionSpace &, const atlas::FieldSet &,
             bool levelsAreTopDown, const eckit::mpi::Comm &);
```

**Contents**:
- `functionSpace()` — ATLAS function space (grid definition)
- `fieldSet()` — geometry fields (lat, lon, masks, KDTree indices)
- `levelsAreTopDown()` — vertical orientation
- `has(name)` / `getField(name)` — check/get specific geometry fields

Created from model Geometry:
```cpp
const oops::GeometryData gdata(geom.functionSpace(), geom.fields(),
                                geom.levelsAreTopDown(), geom.getComm());
```

## Function Space Types

ATLAS provides several function space types. The function space determines the grid structure:

| Type | Use Case | Example |
|------|----------|---------|
| `NodeColumns` | Unstructured meshes | SOCA ocean grid, MPAS Voronoi |
| `StructuredColumns` | Regular lat-lon grids | QUENCH test grids |
| `Spectral` | Spherical harmonics | SABER spectral blocks |
| `PointCloud` | Point data (no mesh) | Observation locations |

Function space is attached to each ATLAS field and propagated through operations.

## Field Naming

Fields in FieldSet use JEDI variable names (same as `oops::Variable` names):

- `"air_temperature"`, `"eastward_wind"`, `"sea_water_salinity"`, etc.
- Suffixes: `"_at_interface"` (half-levels), `"_wrt_dry_air"` (mixing ratio basis)
- Model repos set names during `toFieldSet()` based on their `FieldsMetadata`

SABER and VADER look up fields by these exact string names. Name mismatches cause crashes.

## Copy Semantics

Two utility functions in `oops/src/oops/util/FieldSetHelpers.h`:

```cpp
void copyFieldSet(const atlas::FieldSet &, atlas::FieldSet &);   // Deep copy (data)
void shareFields(const atlas::FieldSet &, atlas::FieldSet &);    // Shallow copy (pointers)
```

- **Shallow copy** (`shareFields`): SOCA uses this in `toFieldSet()`. Both FieldSets point to the same data arrays. Modifying one modifies the other.
- **Deep copy** (`copyFieldSet`): Creates independent copy. Used when original must be preserved.

**SABER/VADER modify in-place** — they receive FieldSets and mutate them directly. This is efficient but means the caller's data is modified.

## Common Pitfalls

### Missing fields
SABER blocks access fields by name. If a required field is missing, you get an ATLAS exception. SOCA checks existence before access:
```cpp
if (!fieldSet_.has(field.name())) { throw ...; }
```

### Missing value handling
Ocean models have land points with missing values. SOCA's `State::operator+=` explicitly skips missing values:
```cpp
if (v_src(i, j) == missing) continue;
```

SABER blocks generally don't handle missing values — the model repo must mask them before passing to SABER.

### Field shape conventions
All fields are 2D arrays: `(npoints, nlevels)`. Surface (2D) fields have `nlevels = 1`. Accessing `field.shape(0)` gives horizontal points, `field.shape(1)` gives vertical levels.

### Shallow copy surprise
`toFieldSet()` with `shareFields` means SABER modifications propagate back to the model state. If you need the original state preserved, deep-copy before passing to SABER.

## FieldSets (4D container) (`oops/src/oops/base/FieldSets.h`)

For ensemble and 4D operations, `FieldSets` wraps multiple `FieldSet3D` objects:

```cpp
class FieldSets : public DataSetBase<FieldSet3D, atlas::FunctionSpace> {
  template<typename MODEL> FieldSets(const IncrementSet<MODEL> &);  // Shallow from ensemble
};
```

Created from `IncrementSet` with shallow copies — ensemble members share data with their FieldSets representations. Used in SABER ensemble covariance chains.
