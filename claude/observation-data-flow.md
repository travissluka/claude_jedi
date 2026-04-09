# Observation Data Flow in JEDI

End-to-end trace of how observations move from IODA files through UFO operators to the oops cost function.

## Overview

```
IODA File → ObsSpace → GetValues → ObsOperator H(x) → QC Filters → Cost Function Jo
```

Six stages, spanning three repos: ioda (stages 1, 6), ufo (stages 3, 4), oops (stages 2, 5). The `Observer<MODEL, OBS>` class in oops orchestrates stages 2-4.

## Stage 1: IODA File → ObsSpace

**Entry**: `ObsSpace` constructor (`ioda/src/ObsSpace.cc:138`)

1. **Read obs data** from HDF5/NetCDF files into either OSDF (new dataframe) or ObsGroup (legacy) containers
2. **Distribute across MPI** via `Distribution` — assigns each observation record to MPI ranks:
   - `RoundRobin` — mod(record_idx, nranks), non-overlapping
   - `NonoverlappingDistribution` — nearest rank by lat/lon
   - `Halo` — geographic radius, overlapping (uses `computePatchLocs()` for exclusive ownership)
   - `AtlasDistribution` — ATLAS mesh cells
3. **Time window filter** — discard obs outside `[window.start, window.end)`
4. **Categorize variables** — `obsvars_` (all), `initial_obsvars_` (from file), `derived_obsvars_` (computed), `assimvars_` (simulated by H(x))

**Data containers**:
- `osdf::IFrame` (new) or `ObsGroup` (legacy) for raw storage
- `ObsVector` wraps data with linear algebra ops and missing-value semantics

## Stage 2: ObsSpace → GetValues (Model Interpolation)

**Orchestrator**: `Observer<MODEL, OBS>` (`oops/src/oops/base/Observer.h`)

### Observer::initialize (once per outer loop)

1. Run `filter_->preProcess()` — pre-GetValues QC (time/domain checks)
2. Collect required variables from operator and filters
3. Create observation `Locations` object (lat/lon/time + sampling method)
4. Group variables by sampling method (different interpolation paths)
5. Create `GetValues` instances — one per variable group

### GetValues constructor (`oops/src/oops/base/GetValues.h:132`)

**Critical MPI exchange**:
1. For each obs location, call `geom.closestTask(lat, lon)` to find the owning MPI rank
2. `comm_.allToAll()` — exchange obs locations so each rank receives obs in its geographic domain
3. Create `LocalInterpolator` objects for each rank's obs

### During model integration

- `GetValues::process(State)` called at each model timestep
- Model fields interpolated along vertical paths at obs locations
- Results collected into `GeoVaLs` object

### GeoVaLs (`ufo/src/ufo/GeoVaLs.h`)

Two storage formats:
- **Sampled** — multiple profiles per location (from multiple interpolation paths)
- **Reduced** — one profile per location (averaged/reduced from sampled). Used by bias predictors and filters.

## Stage 3: GeoVaLs → ObsOperator H(x)

**Called in**: `Observer::finalize` (`oops/src/oops/base/Observer.h:185`)

### Sequence

1. `obsop_->computeReducedVars()` — reduce multi-path GeoVaLs for filters/bias
2. `filter_->priorFilter(geovals)` — background-dependent QC (before H(x))
3. `obsop_->simulateObs(geovals, yobsim, biascoeff, qcflags, ybias, ydiags)` — **compute H(x)**
4. `filter_->postFilter(geovals, yobsim, ybias, ydiags)` — post-H(x) QC

### ObsOperator contract (`ufo/src/ufo/ObsOperatorBase.h`)

```cpp
virtual const oops::Variables & requiredVars() const = 0;  // model vars needed
virtual void simulateObs(const GeoVaLs &, ioda::ObsVector & hofx,
                         ObsDiagnostics &, const QCFlags_t &) const = 0;
```

- `requiredVars()` — which model variables to interpolate
- `locations()` — sampling method (default: vertical columns at obs times)
- `simulateObs()` — compute H(x) from GeoVaLs, write to `hofx` ObsVector

### Bias correction

`ObsAuxControl` holds bias coefficients (e.g., VarBC for radiances). The bias estimate is added to H(x) during `simulateObs()`. Bias predictors read from GeoVaLs (reduced format).

## Stage 4: QC Filters

**Manager**: `ObsFilters` (`ufo/src/ufo/ObsFilters.h`)

### Three filter stages

| Stage | When | Available Data | Example Filters |
|-------|------|---------------|-----------------|
| `preProcess()` | Before GetValues | Metadata only | Time/domain checks, missing value detection |
| `priorFilter(GeoVaLs)` | After GetValues, before H(x) | GeoVaLs | Background check, buddy check |
| `postFilter(GeoVaLs, H(x), bias, diags)` | After H(x) | Everything | Gross error check on \|y - H(x)\| |

### Filter mechanics

Each filter implements `applyFilter()` → returns per-variable, per-location rejection flags. Rejections set QC flags in `ObsDataVector<int>`.

### QC flag values (`ufo/src/ufo/filters/QCflags.h`)

- `0` = pass (assimilated)
- `1` = passive (H(x) computed, not assimilated)
- `>1` = rejected: `missing=10`, `preQC=11`, `bounds=12`, `domain=13`, `Hfailed=15`, `buddy=22`, `fguess=19`, etc. (27 total flags)

### Effect on obs errors

After filtering, obs errors for rejected obs are masked:
```cpp
obserrfilter_->mask(*qcflags_);  // Set to missing where flag > 0
Rmat_->update(obserr);           // Update R matrix with modified errors
```

Filters can also inflate obs errors (e.g., Bayesian background check).

## Stage 5: Cost Function Assembly

**Class**: `CostJo` (`oops/src/oops/assimilation/CostJo.h`)

### Jo computation

1. `observers_->finalize(yeqv, qcflags)` — get H(x) and final QC flags
2. Load observations: `yobs = Observations(obspaces, "ObsValue")`
3. Compute departures: `ydep = H(x) - y`
4. Compute gradient: `gradFG = R⁻¹ · (H(x) - y)`
5. Compute cost: `Jo = 0.5 · (H(x) - y)ᵀ · R⁻¹ · (H(x) - y)`

**Rejected obs don't contribute** — they are masked as missing values, and `dot_product_with()` skips missing entries.

### Departures (`oops/src/oops/base/Departures.h`)

Container of per-obs-type `ObsVector`s. Global dot product sums across obs types with MPI reduction.

### ObsErrors / R matrix (`oops/src/oops/base/ObsErrors.h`)

- `multiply(Departures)` — apply R
- `inverseMultiply(Departures)` — apply R⁻¹
- Typically diagonal: `R[i,i] = obs_error_variance[i]`

### Integration into total cost

`CostFunction` aggregates: `J = Jb + Jo + Jc + ...`

## Stage 6: ObsVector Linear Algebra

**Class**: `ObsVector` (`ioda/src/ObsVector.h`)

### Storage

`std::vector<double> values_` — flat array `[loc0_var0, loc0_var1, ..., loc1_var0, ...]`. Size = `nlocs × nvars` per MPI rank. Missing value constant marks rejected/invalid data.

### Missing-value-aware operations

All arithmetic skips missing values:
- `operator+=`, `-=`, `*=`, `/=` — skip where either operand is missing
- `dot_product_with()` — local sum of non-missing products + `MPI_Allreduce`
- `nobs()` — count non-missing across all ranks (MPI reduction)

### Masking

```cpp
void mask(const ObsDataVector<int> & qcflags);  // Set to missing where flag > 0
```

Once masked, the observation is invisible to all subsequent operations. This is how rejected obs are excluded from Jo.

## MPI Synchronization Points

| Point | Where | What |
|-------|-------|------|
| Obs distribution | ObsSpace constructor | Obs assigned to ranks via Distribution |
| GetValues exchange | `GetValues` constructor (`allToAll`) | Obs locations sent to interpolating ranks |
| Dot product | `ObsVector::dot_product_with()` | Local sum + `MPI_Allreduce` |
| Obs count | `ObsVector::nobs()` | Local count + `MPI_Allreduce` |
| Patch ownership | `Distribution::patchObs()` | Prevents double-counting in Halo distribution |

## Rejection Flow

```
Filter sets QC flag > 0
  → mask(qcflags) applied to H(x) ObsVector
    → values set to missing constant
      → dot_product_with() skips missing
        → Jo excludes rejected obs term
```

## Key Files Reference

| Stage | Class | File |
|-------|-------|------|
| 1 | ObsSpace | `ioda/src/ObsSpace.h`, `.cc` |
| 1 | Distribution | `ioda/src/distribution/Distribution.h` |
| 2 | Observer | `oops/src/oops/base/Observer.h` |
| 2 | GetValues | `oops/src/oops/base/GetValues.h` |
| 2 | GeoVaLs | `ufo/src/ufo/GeoVaLs.h`, `.cc` |
| 3 | ObsOperatorBase | `ufo/src/ufo/ObsOperatorBase.h` |
| 4 | ObsFilters | `ufo/src/ufo/ObsFilters.h`, `.cc` |
| 4 | QCflags | `ufo/src/ufo/filters/QCflags.h` |
| 5 | CostJo | `oops/src/oops/assimilation/CostJo.h` |
| 5 | Departures | `oops/src/oops/base/Departures.h` |
| 5 | ObsErrors | `oops/src/oops/base/ObsErrors.h` |
| 6 | ObsVector | `ioda/src/ObsVector.h`, `.cc` |
