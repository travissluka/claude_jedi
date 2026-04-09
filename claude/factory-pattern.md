# Factory Pattern in JEDI

All JEDI repos use a consistent factory pattern for runtime component selection from YAML configuration. Components are registered by string name and instantiated based on YAML `name:` keys.

## Core Mechanism

Two-class design: **Factory** (registry + dispatch) and **Maker** (instantiation).

```cpp
// Factory base class — manages registry
template <typename MODEL>
class ModelFactory {
  static std::map<std::string, ModelFactory<MODEL>*> & getMakers() {
    static std::map<std::string, ModelFactory<MODEL>*> makers_;  // Singleton
    return makers_;
  }
 protected:
  explicit ModelFactory(const std::string & name) {
    getMakers()[name] = this;  // Register on construction
  }
 public:
  static ModelBase<MODEL> * create(const Geometry_ & geom,
                                    const eckit::Configuration & config) {
    const std::string id = config.getString("name");  // Read type from YAML
    auto it = getMakers().find(id);
    if (it == getMakers().end()) throw std::runtime_error(id + " not in factory");
    return it->second->make(geom, config);
  }
  virtual ModelBase<MODEL> * make(const Geometry_ &, const eckit::Configuration &) = 0;
};

// Maker template — instantiates concrete type T
template <class MODEL, class T>
class ModelMaker : public ModelFactory<MODEL> {
  explicit ModelMaker(const std::string & name) : ModelFactory<MODEL>(name) {}
  ModelBase<MODEL> * make(const Geometry_ & geom,
                           const eckit::Configuration & config) override {
    return new T(geom, config);
  }
};
```

## Registration

A single static line in the `.cc` file of a concrete class:

```cpp
static ModelMaker<fv3jedi::Traits, ModelFV3LM> maker_("FV3LM");
```

This:
1. Constructs a `ModelMaker<Traits, ModelFV3LM>` object
2. Constructor calls `ModelFactory("FV3LM")`
3. Factory constructor registers `this` in the static map under key `"FV3LM"`

## YAML Dispatch

```yaml
model:
  name: FV3LM    # ← looked up in factory map
  tstep: PT1H
```

→ `ModelFactory::create(geom, config)` reads `"FV3LM"`, finds the Maker, calls `make()`, which calls `new ModelFV3LM(geom, config)`.

## Parameters-Based Factories (Modern)

Newer factories use strongly-typed Parameters instead of raw Configuration:

```cpp
template <class T>
class ObsOperatorMaker : public ObsOperatorFactory {
  typedef typename T::Parameters_ Parameters_;

  ObsOperatorBase * make(const ioda::ObsSpace & odb,
                          const ObsOperatorParametersBase & params) override {
    const auto & typed = dynamic_cast<const Parameters_&>(params);
    return new T(odb, typed);
  }
  std::unique_ptr<ObsOperatorParametersBase> makeParameters() const override {
    return std::make_unique<Parameters_>();
  }
};
```

The factory can also create the correct Parameters subclass via `createParameters(name)`, enabling polymorphic deserialization.

## instantiate\*Factory Pattern

**Problem**: C++ static initialization order is undefined across translation units. A Maker in one `.cc` might try to register before the Factory's static map exists.

**Solution**: `instantiate*Factory()` functions defer Maker creation:

```cpp
// oops/src/oops/base/instantiateCovarFactory.h
template <typename MODEL> void instantiateCovarFactory() {
  static CovarMaker<MODEL, EnsembleCovariance<MODEL>> makerEns_("ensemble");
  static CovarMaker<MODEL, HybridCovariance<MODEL>>   makerHyb_("hybrid");
  static CovarMaker<MODEL, ErrorCovariance<MODEL>>     makerMod_(MODEL::nameCovar());
}
```

The `static` keyword inside the function ensures each Maker is created exactly once, at a well-defined time.

### Factory Chaining

Libraries chain their factory registrations:

```cpp
// saber/src/saber/oops/instantiateCovarFactory.h
template <typename MODEL> void instantiateCovarFactory() {
  oops::instantiateCovarFactory<MODEL>();         // Register oops covariances
  static oops::CovarMaker<MODEL, ErrorCovariance<MODEL>> makerSABER_("SABER");
  instantiateLocalizationFactory<MODEL>();         // Register localizations
  instantiateBlockChainFactory<MODEL>();           // Register block chains
}
```

### Executable Registration

Executables trigger the chain by template instantiation:

```cpp
// fv3-jedi/src/mains/fv3jediVar.cc
int main(int argc, char ** argv) {
  oops::Run run(argc, argv);
  saber::instantiateCovarFactory<fv3jedi::Traits>();  // Chains all factories
  ufo::instantiateObsFilterFactory();
  oops::Variational<fv3jedi::Traits, ufo::ObsTraits> var;
  return run.execute(var);
}
```

## Factories Across Repos

### oops factories

| Factory | Registered Types | YAML Key |
|---------|-----------------|----------|
| `CovarFactory<MODEL>` | `"ensemble"`, `"hybrid"`, `MODEL::nameCovar()` | `covariance model:` |
| `ModelFactory<MODEL>` | Model-specific (e.g., `"FV3LM"`, `"Identity"`) | `name:` |
| `LinearModelFactory<MODEL>` | Model-specific | `name:` |
| `LocalizationFactory<MODEL>` | `"BUMP"`, `"ID"`, etc. | `localization method:` |

### SABER factories

| Factory | Registered Types | YAML Key |
|---------|-----------------|----------|
| `SaberOuterBlockFactory` | `"StdDev"`, `"BUMP_NICAS"`, `"Diffusion"`, `"SOCABkgErrFilt"`, etc. | `saber block name:` |
| `SaberCentralBlockFactory` | `"BUMP_NICAS"`, `"spectral covariance"`, etc. | `saber block name:` |
| `SaberBlockChainFactory<MODEL>` | `"ensemble"`, `"hybrid"`, `"parametric"` | `covariance model:` |

### UFO factories

| Factory | Registered Types | YAML Key |
|---------|-----------------|----------|
| `ObsOperatorFactory` | `"CRTM"`, `"Identity"`, `"Composite"`, `"VertInterp"`, etc. | `name:` |
| `FilterFactory` | `"Background Check"`, `"Bounds Check"`, `"Domain Check"`, etc. (100+) | `filter:` |
| `ObsLocalizationFactory` | `"Horizontal Gaspari-Cohn"`, `"Horizontal SOAR"`, `"Rossby"`, etc. | `localization method:` |

### Model repo factories

Each model repo defines its own VariableChange and LinearVariableChange factories:

| Repo | Factory | Registered Types |
|------|---------|-----------------|
| fv3-jedi | `VariableChangeFactory` | `"Model2GeoVaLs"`, `"default"`, `"Control2Analysis"` |
| soca | `VariableChangeFactory` | `"Model2GeoVaLs"`, `"Model2Ana"`, `"Soca2Cice"` |
| soca | `LinearVariableChangeFactory` | `"Balance"`, `"LinearModel2GeoVaLs"` |

## Adding a New Component

### Step 1: Define Parameters (if using Parameters-based factory)

```cpp
class MyFilterParameters : public FilterParametersBase {
  OOPS_CONCRETE_PARAMETERS(MyFilterParameters, FilterParametersBase)
 public:
  oops::Parameter<double> threshold{"threshold", 3.0, this};
};
```

### Step 2: Implement the class

```cpp
class MyFilter : public FilterBase {
 public:
  typedef MyFilterParameters Parameters_;
  static const std::string classname() { return "ufo::MyFilter"; }

  MyFilter(ioda::ObsSpace &, const Parameters_ &,
           std::shared_ptr<ioda::ObsDataVector<int>>,
           std::shared_ptr<ioda::ObsDataVector<float>>);

 private:
  void applyFilter(const std::vector<bool> &, const Variables &,
                   std::vector<std::vector<bool>> &) const override;
  int qcFlag() const override { return QCflags::fguess; }
};
```

### Step 3: Register in the factory

```cpp
// In MyFilter.cc or in instantiateObsFilterFactory.h
static FilterMaker<MyFilter> maker_("My Filter");
```

### Step 4: Use in YAML

```yaml
obs filters:
  - filter: My Filter
    threshold: 5.0
```

## Debugging Factory Errors

**"X does not exist in Y factory"**: The Maker for type `X` was never registered. Check:
1. Is the `.cc` file with `static *Maker` linked into the executable?
2. Is `instantiate*Factory()` called before the factory is used?
3. Is the string name spelled correctly (case-sensitive)?

Some factories print available types on error:
```
SomeType does not exist in localization factory.
Localization Factory has 3 elements:
A Horizontal Gaspari-Cohn Localization
A Horizontal SOAR Localization
A Rossby Localization
```

## Template Specialization per MODEL

Each `instantiate*Factory<MODEL>()` creates Makers for that specific MODEL type. `instantiateCovarFactory<fv3jedi::Traits>()` and `instantiateCovarFactory<soca::Traits>()` populate separate factory maps — no name conflicts between models.

## Key Files

| File | Content |
|------|---------|
| `oops/base/ModelBase.h` | Model factory + maker |
| `oops/base/ModelSpaceCovarianceBase.h` | Covariance factory |
| `oops/generic/LocalizationBase.h` | Localization factory |
| `oops/base/instantiateCovarFactory.h` | Covariance registration |
| `ufo/ObsOperatorBase.h` | Obs operator factory |
| `ufo/ObsFilterBase.h` | Filter factory |
| `ufo/instantiateObsFilterFactory.h` | 100+ filter registrations |
| `saber/blocks/SaberOuterBlockBase.h` | SABER outer block factory |
| `saber/blocks/SaberCentralBlockBase.h` | SABER central block factory |
| `saber/oops/instantiateCovarFactory.h` | SABER covariance chaining |
