# Parameters System

Type-safe YAML configuration system used across all JEDI repos. Located in `oops/src/oops/util/parameters/`.

## Class Hierarchy

```
ParameterBase (abstract)
├── Parameter<T>                          — optional with default value
├── RequiredParameter<T>                  — mandatory, throws if missing
├── OptionalParameter<T>                  — optional, no default (boost::optional)
├── RequiredPolymorphicParameter<P, F>    — factory-dispatched, mandatory
├── OptionalPolymorphicParameter<P, F>    — factory-dispatched, optional
├── PolymorphicParameter<P, F>            — factory-dispatched with default
├── ConfigurationParameter                — captures raw eckit::Configuration
├── IgnoreOtherParameters                 — suppresses unknown-key errors
└── Parameters (abstract base for collections)
    └── [User-defined Parameters subclasses]
```

## Parameter Types

### Parameter\<T\> — Optional with Default

```cpp
oops::Parameter<int> maxIterations{"max iterations", 100, this};
// YAML: max iterations: 50    → value() returns 50
// YAML: (key absent)          → value() returns 100
```

### RequiredParameter\<T\> — Must Be Present

```cpp
oops::RequiredParameter<std::string> fileName{"file name", this};
// YAML: file name: data.nc    → value() returns "data.nc"
// YAML: (key absent)          → throws eckit::BadParameter
```

### OptionalParameter\<T\> — No Default

```cpp
oops::OptionalParameter<double> tolerance{"tolerance", this};
// YAML: tolerance: 1.0e-8     → value() returns boost::optional with 1.0e-8
// YAML: (key absent)          → value() returns boost::none
```

### RequiredPolymorphicParameter\<PARAMS, FACTORY\> — Factory Dispatch

```cpp
oops::RequiredPolymorphicParameter<ObsOperatorParametersBase, ObsOperatorFactory>
  obsOperator{"obs operator", this};
// YAML: obs operator:
//         name: CRTM          → creates CRTMParameters, deserializes sub-keys
// Access: params.obsOperator.value()  → returns strongly-typed Parameters subclass
//         params.obsOperator.id()     → returns "CRTM"
```

### ConfigurationParameter — Raw Config Capture

```cpp
oops::ConfigurationParameter rawConfig{this};
// Captures the entire YAML block without schema validation
// Useful for configuration passed through to other components
```

### IgnoreOtherParameters — Allow Unknown Keys

```cpp
oops::IgnoreOtherParameters ignoreRest{this};
// Without this, unknown YAML keys cause validation errors
```

## Defining a Parameters Class

```cpp
#include "oops/util/parameters/Parameters.h"
#include "oops/util/parameters/Parameter.h"
#include "oops/util/parameters/RequiredParameter.h"

class MyBlockParameters : public saber::SaberBlockParametersBase {
  OOPS_CONCRETE_PARAMETERS(MyBlockParameters, saber::SaberBlockParametersBase)
 public:
  oops::RequiredParameter<std::string> fileName{"file name", this};
  oops::Parameter<int> maxIter{"max iterations", 100, this};
  oops::OptionalParameter<double> tol{"tolerance", this};
  oops::Parameter<std::vector<std::string>> vars{"variables", {}, this};
};
```

**Key rules**:
- Always use `OOPS_CONCRETE_PARAMETERS(ClassName, BaseClass)` macro
- Declare parameters as **member variables**, not in constructor
- Always pass `this` as the last constructor argument (registers with parent)
- Use `OOPS_ABSTRACT_PARAMETERS` for base classes that shouldn't be instantiated

## Nesting Parameters

Parameters can nest arbitrarily:

```cpp
class InnerParams : public oops::Parameters {
  OOPS_CONCRETE_PARAMETERS(InnerParams, oops::Parameters)
 public:
  oops::RequiredParameter<int> levels{"levels", this};
};

class OuterParams : public oops::Parameters {
  OOPS_CONCRETE_PARAMETERS(OuterParams, oops::Parameters)
 public:
  oops::Parameter<InnerParams> inner{"inner", InnerParams(), this};
  oops::RequiredParameter<std::vector<InnerParams>> groups{"groups", this};
};
```

```yaml
inner:
  levels: 50
groups:
  - levels: 30
  - levels: 60
```

## Deserialization Flow

1. User calls `params.deserialize(config)` or `params.validateAndDeserialize(config)`
2. `Parameters::deserialize()` iterates `children_` vector
3. Each child calls `ParameterTraits<T>::get(path, config, name)`
4. For scalars: delegates to `eckit::Configuration::get()`
5. For Parameters subclasses: recursive `deserialize()`
6. For polymorphic: factory creates appropriate Parameters subclass, then deserializes

## Validation & Constraints

### Numeric constraints

```cpp
oops::Parameter<double> weight{"weight", 0.5, this,
  {oops::exclusiveMinConstraint(0.0), oops::exclusiveMaxConstraint(100.0)}};
```

Available: `minConstraint(v)`, `exclusiveMinConstraint(v)`, `maxConstraint(v)`, `exclusiveMaxConstraint(v)`

### Array constraints

```cpp
oops::RequiredParameter<std::vector<std::string>> vars{"variables", this,
  {oops::nonEmptyConstraint<std::vector<std::string>>()}};
```

Available: `minItemsConstraint(n)`, `maxItemsConstraint(n)`, `nonEmptyConstraint()`

### JSON schema validation

`validateAndDeserialize()` first generates a JSON schema from all registered parameters and validates against it, then deserializes. Provides detailed error paths on failure.

## Supported Types

Scalars: `int`, `float`, `double`, `bool`, `std::string`

Time: `util::DateTime`, `util::Duration`, `util::PartialDateTime`

Collections: `std::vector<T>`, `std::set<T>`, `std::map<K,V>`

JEDI types: `oops::Variables`, `oops::ObsVariables`

Enums (via specialization): `ParameterTraits<MyEnum>` with `NamedEnumerator` list

Parameters subclasses: automatic recursive deserialization

## Enum Registration

```cpp
enum class Strategy { UNIVARIATE, DUPLICATED };

struct StrategyTraitsHelper {
  typedef Strategy EnumType;
  static constexpr char enumTypeName[] = "Strategy";
  static constexpr util::NamedEnumerator<Strategy> namedValues[] = {
    { Strategy::UNIVARIATE, "univariate" },
    { Strategy::DUPLICATED, "duplicated" }
  };
};

namespace oops {
  template <> struct ParameterTraits<Strategy>
    : public EnumParameterTraits<StrategyTraitsHelper> {};
}
```

## Factory Integration

Polymorphic parameters connect to factories. The factory must provide:

```cpp
static std::unique_ptr<PARAMETERS> createParameters(const std::string & id);
static Container getMakerNames();  // returns iterable of registered names
```

When deserializing, `RequiredPolymorphicParameter` reads the type name from YAML, asks the factory to create the correct Parameters subclass, then recursively deserializes it.

## Key Files

| File | Purpose |
|------|---------|
| `Parameters.h` | Base class, deserialize/serialize/validate |
| `Parameter.h` | `Parameter<T>` — optional with default |
| `RequiredParameter.h` | `RequiredParameter<T>` — mandatory |
| `OptionalParameter.h` | `OptionalParameter<T>` — optional, no default |
| `RequiredPolymorphicParameter.h` | Factory-dispatched (required) |
| `PolymorphicParameterTraits.h` | Traits for polymorphic deserialization |
| `ParameterTraits.h` | Type traits for scalar/collection serialization |
| `NumericConstraints.h` | Min/max constraints |
| `ArrayConstraints.h` | Array length constraints |
| `ConfigurationParameter.h` | Raw config capture |
| `IgnoreOtherParameters.h` | Unknown-key suppression |
| `ObjectJsonSchema.h` | JSON schema generation |
