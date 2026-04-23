# Active Projects

> **Covers:** SequentialEnsembleSolver<MODEL,OBS>, EAKFSolver<MODEL,OBS> (Anderson & Collins 2007), ioda::ObsIterator, ObsLocalization::computeLocalization(Point3, Point3), QG GC99 localization switch, soca ObsLocRossby Point3 stub. PR links across oops/ioda/ufo/soca/pyiri-jedi.

## Sequential EnKF Feature (feature/sequential_enkf)

**Status**: ioda merged; oops/ufo/soca/pyiri-jedi PRs open, under review
**Branch**: `feature/sequential_enkf` across 4 repos (ioda uses `develop`)

### PRs

| Repo | PR | Title | Key Changes |
|------|----|-------|-------------|
| oops | [#3193](https://github.com/JCSDA-internal/oops/pull/3193) | Add sequential kalman filter framework, and EAKF | Core framework + EAKF solver |
| ioda | [#1674](https://github.com/JCSDA-internal/ioda/pull/1674) | Add sequential kalman filter framework, and EAKF | `ioda::ObsIterator` class — **MERGED** |
| ufo | [#4027](https://github.com/JCSDA-internal/ufo/pull/4027) | Add sequential kalman filter framework, and EAKF | `computeLocalization(Point3, Point3)` on obs localization |
| soca | [#1224](https://github.com/JCSDA-internal/soca/pull/1224) | Add sequential kalman filter framework, and EAKF | EAKF test, ObsLocRossby stub for Point3 interface |
| pyiri-jedi | [#166](https://github.com/JCSDA-internal/pyiri-jedi/pull/166) | Add ObsIterator class stubs, and update ObsLocalization | Stubs only (not fully implemented) |

### What Was Built

#### New oops classes
- **`SequentialEnsembleSolver<MODEL, OBS>`** (`assimilation/SequentialEnsembleSolver.h`) — Abstract base class for sequential ensemble DA. Processes observations one at a time (not local volume). Inherits from `LocalEnsembleSolver` (acknowledged as a TODO to refactor into a shared `EnsembleSolver` superclass). Key virtual method: `obsEnsembleUpdate()`.
- **`EAKFSolver<MODEL, OBS>`** (`assimilation/EAKFSolver.h`) — Concrete EAKF implementation (Anderson & Collins 2007). Implements scalar obs update: Kalman gain K = Pb/(Pb+R), posterior perturbation scaling, mean shift.

#### Algorithm (Anderson & Collins 2007 parallel sequential EnKF)
1. Initialize analysis ensemble = background ensemble
2. Pack all obs departures, ensemble priors (Yb), and obs error into vectors
3. For each observation k:
   a. Compute localization weights between obs k and all other obs
   b. Call `obsEnsembleUpdate()` to get observation ensemble increment `delta_y_k`
   c. For each other obs j: regress obs increment onto obs j using localized sample covariance
   d. For each grid point: regress obs increment onto state using localized sample covariance
4. Apply inflation (RTPP, RTPS, multiplicative)

#### New oops interface: `ObsLocalization::computeLocalization(Point3, Point3)`
- New overload returning a scalar `double` localization weight between two arbitrary 3D points
- Used for obs-obs and grid-obs localization in sequential EnKF
- **Existing** `computeLocalization(GeometryIterator, ObsVector)` unchanged

#### New ioda class: `ioda::ObsIterator`
- Forward iterator over observation locations
- Dereferences to `eckit::geometry::Point3` (lon, lat, 0)
- Constructed from `ObsSpace::begin()`/`end()`
- Added `typedef ioda::ObsIterator GeometryIterator` to `IodaTrait.h` (naming acknowledged as abusive)

#### UFO obs localization updates
- `ObsLocalizationBase`, `ObsHorLocalization`, `ObsHorLocGC99`, `ObsHorLocSOAR` all got `computeLocalization(Point3, Point3)` overload
- New test in `test/ufo/ObsLocalization.h`

#### QG obs localization changed to GC99
- Was Heaviside (sharp cutoff), changed to Gaspari-Cohn
- Reason: sequential EnKF produces O-A > O-B with sharp cutoff localization
- Some QG test reference outputs updated as a result

#### soca changes
- `ObsLocRossby` got a stub `computeLocalization(Point3, Point3)` that throws ABORT (Rossby-based localization needs `GeometryIterator::getFieldValue()` which doesn't work for obs/obs localization)
- EAKF test added

> Review-comment status and per-PR TODO lists are transient — fetch them live via `gh pr view <N> -R JCSDA-internal/<repo> --comments`. Open TODOs that outlast the PRs live in user MEMORY (see `project_sequential_enkf_followups.md`).

### YAML Config
```yaml
local ensemble DA:
  solver: EAKF
  inflation:
    rtpp: 0.5
    rtps: 0.5
    mult: 1.1
```
Uses the same `LocalEnsembleDA` application and same YAML structure as LETKF/GETKF, just with `solver: EAKF`.
