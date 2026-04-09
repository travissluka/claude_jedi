# UFO Filter/Operator Lifecycle

Detailed guide to filter stages, actions, ObsFunctions, and variable transforms in UFO.

## Filter Pipeline Stages

Filters execute in four stages, configured via separate YAML lists:

| Stage | YAML Key | When | Available Data |
|-------|----------|------|---------------|
| PRE | `obs pre filters` | Before GetValues | Metadata only |
| PRIOR | `obs prior filters` | After GetValues, before H(x) | GeoVaLs |
| POST | `obs post filters` | After H(x) | GeoVaLs + H(x) + diagnostics |
| AUTO | `obs filters` | Stage auto-determined | Based on data dependencies |

AUTO stage: if filter requires HofX → POST, if GeoVaLs → PRIOR, if neither → PRE.

Within each stage, filters run **sequentially** in YAML order. Two internal filters are injected automatically: `QCmanager` (first) and `FinalCheck` (last).

## Filter Base Class

Every filter extends `FilterBase` (`ufo/src/ufo/filters/FilterBase.h`):

```cpp
class FilterBase : public ObsProcessorBase {
  virtual void applyFilter(const std::vector<bool> & apply,
                           const Variables & filtervars,
                           std::vector<std::vector<bool>> & flagged) const = 0;
  virtual int qcFlag() const = 0;
};
```

- `apply[loc]` — true if this location passes the `where:` clause
- `filtervars` — variables this filter operates on
- `flagged[var][loc]` — set true to flag (reject) an observation
- `qcFlag()` — the QC flag value assigned to rejected obs

## Where Clause

Selects which observations a filter acts on:

```yaml
where:
  - variable: MetaData/latitude
    minvalue: -60.0
    maxvalue: 60.0
  - variable: MetaData/observation_type
    is_in: [1, 2, 10]
where_operator: and  # default; or "or"
```

Available conditions:

| Condition | Types | Purpose |
|-----------|-------|---------|
| `minvalue` / `maxvalue` | int, float, datetime | Range check (inclusive) |
| `is_in` / `is_not_in` | int, string | Membership test |
| `is_close_to_any_of` | float | Tolerance-based matching |
| `value: is_valid` / `is_not_valid` | any | Missing value check |
| `value: is_true` / `is_false` | DiagnosticFlag | Boolean flag check |
| `any_bit_set_of` / `any_bit_unset_of` | int | Bit flag testing |
| `matches_regex` | string | Regex matching |
| `matches_wildcard` | string | Wildcard (* ?) matching |

## Filter Actions

After a filter flags observations, **actions** are applied. Multiple actions can be chained:

```yaml
filter: Background Check
threshold: 3.0
actions:
  - name: inflate error
    inflation factor: 1.5
  - name: reject
```

| Action | Modifies QC? | Purpose |
|--------|-------------|---------|
| `reject` | Yes | Set QC flag to filter's `qcFlag()` value |
| `passivate` | Yes | Mark as passive (H(x) computed, not assimilated) |
| `accept` | Yes | Explicitly accept (undo prior rejection) |
| `assign error` | No | Set obs error to fixed value or ObsFunction result |
| `inflate error` | No | Multiply obs error by factor |
| `set flag` | No | Set a named diagnostic flag |

Default action (if none specified): `reject`.

## ObsFunctions

Compute derived quantities on-the-fly for use in filter conditions, thresholds, and actions.

### Interface

```cpp
template <typename FunctionValue>  // float, int, string, DateTime
class ObsFunctionBase {
  virtual void compute(const ObsFilterData &,
                       ioda::ObsDataVector<FunctionValue> &) const = 0;
  virtual const Variables & requiredVariables() const = 0;
};
```

### Usage in YAML

```yaml
filter: Background Check
function absolute threshold:
  - name: ObsFunction/Arithmetic
    options:
      variables:
        - name: ObsError/airTemperature
        - name: GeoVaLs/climatology_variance
      coefs: [1.0, 0.5]
      total coefficient: 2.0
```

### Adding an ObsFunction

1. Subclass `ObsFunctionBase<float>` (or other type)
2. Implement `compute()` and `requiredVariables()`
3. Register: `static ObsFunctionMaker<MyFunc> maker_("MyFunc");`
4. Reference in YAML as `ObsFunction/MyFunc`

## Variable Transforms

Compute and **persist** derived observation values in the ObsSpace (unlike ObsFunctions which are ephemeral).

```yaml
obs pre filters:
  - filter: Variable Transforms
    Transform: HumidityFromDewpoint
```

Transforms read inputs via `getObservation()`, compute, and write results to `DerivedObsValue/<varname>` via `putObservation()`. QC flags are automatically updated (missing input → missing output).

Base class: `TransformBase` (`ufo/src/ufo/variabletransforms/TransformBase.h`)

## ObsDiagnostics

Container for diagnostic output from the observation operator. Stores per-observation quantities like bias corrections, jacobians, and instrument-specific diagnostics.

- Allocated with operator-specific variables
- Passed to `postFilter()` so filters can use operator outputs
- Written to output files for monitoring

## Adding a New Filter

### 1. Parameters class

```cpp
class MyFilterParameters : public FilterParametersBase {
  OOPS_CONCRETE_PARAMETERS(MyFilterParameters, FilterParametersBase)
 public:
  oops::Parameter<float> threshold{"threshold", 3.0, this};
};
```

### 2. Filter class

```cpp
class MyFilter : public FilterBase {
 public:
  typedef MyFilterParameters Parameters_;
  static const std::string classname() { return "ufo::MyFilter"; }

  MyFilter(ioda::ObsSpace &, const Parameters_ &,
           std::shared_ptr<ioda::ObsDataVector<int>>,
           std::shared_ptr<ioda::ObsDataVector<float>>);

 private:
  void applyFilter(const std::vector<bool> & apply, const Variables & vars,
                   std::vector<std::vector<bool>> & flagged) const override;
  int qcFlag() const override { return QCflags::fguess; }
  Parameters_ parameters_;
};
```

### 3. Registration

In `instantiateObsFilterFactory.h`:
```cpp
static FilterMaker<MyFilter> maker_("My Filter");
```

### 4. YAML usage

```yaml
obs filters:
  - filter: My Filter
    threshold: 5.0
    where:
      - variable: MetaData/latitude
        minvalue: -45.0
        maxvalue: 45.0
```

## Iteration Control

Filters can be restricted to specific outer-loop iterations:

```yaml
obs filters:
  - filter: Background Check
    apply at iterations: [0, 3]
```

Force a filter to POST stage regardless of dependencies:
```yaml
obs filters:
  - filter: My Filter
    defer to post: true
```

## Key Files

| Component | File |
|-----------|------|
| Filter container | `ufo/src/ufo/ObsFilters.h/.cc` |
| Filter base class | `ufo/src/ufo/filters/FilterBase.h/.cc` |
| Factory | `ufo/src/ufo/ObsFilterBase.h` |
| Where clause | `ufo/src/ufo/filters/processWhere.h/.cc` |
| Actions | `ufo/src/ufo/filters/actions/FilterActionBase.h` |
| ObsFunctions | `ufo/src/ufo/filters/obsfunctions/ObsFunctionBase.h` |
| Variable transforms | `ufo/src/ufo/variabletransforms/TransformBase.h` |
| QC flags | `ufo/src/ufo/filters/QCflags.h` |
| Factory registration | `ufo/src/ufo/instantiateObsFilterFactory.h` |
