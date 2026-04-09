# MPI and Ensemble Distribution Patterns

How JEDI organizes MPI ranks, distributes ensemble members and time windows, and manages parallel communication.

## Communicator Hierarchy

JEDI uses a **two-dimensional MPI decomposition** with independent communicators:

```
Global MPI ranks
  ├── commTime  — distributes time windows/sub-windows across ranks
  └── commEns   — distributes ensemble members across ranks
```

Each rank belongs to both communicators. Within each communicator, ranks share the same geometry (spatial domain decomposition is handled by the model via the geometry communicator).

### Rank Assignment

```cpp
localtimes_   = ntimes   / commTime.size();
localmembers_ = nmembers / commEns.size();

// Member indices for this rank:
for jm in 0..localmembers_-1:
  mymembers_[jm] = commEns.rank() * localmembers_ + jm
```

**Constraint**: Both dimensions must divide evenly:
```cpp
ASSERT(nmembers % commEns.size() == 0);
ASSERT(ntimes  % commTime.size() == 0);
```

## IncrementSet / StateSet

Distributed containers for 4D ensemble data. Store `localtimes × localmembers` objects per rank:

```cpp
dataset_[im * localtimes_ + it]   // Memory layout
(*this)(it, im)                    // Access: (time_index, member_index)
```

### Common Operations

**Ensemble mean** — local accumulation + allReduce across `commEns`:
```cpp
for each local time jt:
  for each local member jm:
    mean[jt] += (*this)(jt, jm)
  allReduceInPlace(commEns, mean[jt].fieldSet())
  mean[jt] *= 1.0 / nmembers
```

**Dot product** — local sum + sequential reductions:
```cpp
double zz = 0.0;
for jj in 0..size()-1:
  zz += dot_product((*this)[jj], other[jj])
commTime.allReduceInPlace(zz, SUM)   // Sum across time ranks
commEns.allReduceInPlace(zz, SUM)    // Sum across ensemble ranks
```

**Time boundary exchange** — point-to-point nearest-neighbor:
```cpp
// shift_forward: pass state from sub-window k to sub-window k+1
send(data[last_time], to=rank+1)
shift local times forward
receive(data[0], from=rank-1)
```

### Transpose

Converts from "one member per rank, full geometry" to "all members per rank, partial geometry":

```cpp
StateSet local = ens.transpose(globalComm, DAgeometry, ensNum);
// Input:  local_ens_size=1 on full geometry
// Output: all members on 1/N fraction of DAgeometry
```

Used by LocalEnsembleDA to collect all ensemble members locally for per-gridpoint updates.

## Observation Distribution

### IODA Distributions

Observations are distributed across ranks via `Distribution` classes:

| Distribution | Pattern | Overlap | Use Case |
|--------------|---------|---------|----------|
| `RoundRobin` | `obs % nranks` | No | Default, simple |
| `Nonoverlapping` | Nearest rank by lat/lon | No | Spatially balanced |
| `Halo` | All within radius | Yes | Local DA methods |
| `Atlas` | ATLAS mesh cells | No | ATLAS-based geometry |

### Patch Ownership (Preventing Double-Counting)

For overlapping distributions (Halo), `patchObs()` marks exclusive ownership:

```cpp
void patchObs(std::vector<bool> & isPatchObs) const;
// isPatchObs[i] = true  → this rank owns obs i (counted in reductions)
// isPatchObs[i] = false → obs i is a halo copy (excluded from reductions)
```

Accumulators and dot products automatically use patch ownership to prevent double-counting.

## GetValues MPI Exchange

The critical model-to-observation bridge uses `allToAll`:

```
1. Each rank determines which geometry rank owns each observation:
   task = geom.closestTask(obs_lat, obs_lon)

2. Group observations by destination rank

3. comm_.allToAll(my_obs_by_task, received_obs_by_task)
   - Each rank sends its obs to the correct geometry rank
   - Each rank receives obs that fall in its geometry patch

4. Create LocalInterpolator for received observations
```

After this exchange, each rank interpolates model fields at the obs locations in its domain.

## LocalEnsembleDA Workflow

```
1. Read ensemble members (distributed across commEns)
2. Compute ensemble mean (allReduce over commEns)
3. Compute perturbations: bkg_pert = members - mean
4. For each gridpoint (via GeometryIterator):
     - getLocal(): extract local column from each member
     - Run solver (LETKF/GETKF/EAKF): update perturbations
     - setLocal(): write back updated column
5. Compute analysis: mean + ana_pert
```

Gridpoints are spatially distributed via the geometry communicator. Each rank processes only its own gridpoints.

## SABER and MPI

SABER blocks access the communicator via `GeometryData`:
```cpp
innerGeometryData().comm()   // MPI communicator for spatial parallelism
```

### Hybrid parallel components

`SaberHybridBlockChain` with `run in parallel: true` splits MPI ranks across components:
```yaml
parallel covariance relative cpu weight:
  - 0.5   # Component 0 gets 50% of ranks
  - 0.5   # Component 1 gets 50%
```

Uses `redistributeToSubcommunicator()` / `gatherAndSumFromSubcommunicator()` for data exchange.

## MPI Utilities (`oops/src/oops/mpi/mpi.h`)

| Function | Purpose |
|----------|---------|
| `mpi::world()` | MPI_COMM_WORLD |
| `mpi::myself()` | Single-rank communicator |
| `mpi::clone(comm)` | Deep copy communicator |
| `mpi::allGatherv(comm, vec)` | Gather variable-size data |
| `mpi::allReduceInPlace(comm, fieldset)` | Reduce ATLAS FieldSet |
| `mpi::broadcast(comm, obj, root)` | Broadcast serializable object |
| `mpi::send/receive(comm, obj, rank, tag)` | Point-to-point |

## Key Patterns Summary

| Pattern | Where | Communicator |
|---------|-------|-------------|
| Ensemble mean | IncrementSet/StateSet | `commEns` |
| Time sync | DataSetBase | `commTime` |
| Obs distribution | GetValues | Geometry comm |
| Dot product | IncrementSet | `commTime` + `commEns` |
| Gridpoint update | LocalEnsembleDA | Geometry comm |
| Patch ownership | IODA Distribution | Obs comm |
| Hybrid B split | SaberHybridBlockChain | Sub-communicators |
