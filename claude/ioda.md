# IODA (JEDI Interface for Observation Data Access)

> Last updated against commit `7acc53ad` (2026-09-03). Run `cd bundle/ioda && git log --oneline 7acc53ad..HEAD` to see what changed since.
>
> **Covers:** ObsSpace, ObsVector, ObsDataVector, Distribution (RoundRobin/Halo/Inefficient), ObsIterator, DistributionUtils (dot_product, missing-value handling), ioda_engines two-layer design, ObsGroup, ObsStore, HDF5/in-memory/ODB/BUFR backends, OSDF containers, `observations:`/`observers:` YAML shape, Fortran/Python bindings.

## Overview

C++14 library providing unified observation data storage with multiple backends, MPI-parallel I/O, and interfaces to C, Fortran, and Python. Source at `bundle/ioda/`.

Build/test quirks in `claude/build-and-test.md`. `make -j ioda ioda_engines` to build both layers.

## Code Style

- **C++**: Google style via clang-format, 100 char line limit, 2-space indent. `clang-format -i <file>`
- **Lint**: cpplint (100 char limit). Run via `ioda_coding_norms` CTest target.
- **Python**: pycodestyle, 120 char line limit. `pycodestyle <file.py>`
- **Exceptions**: `ioda/Exception.h` and `Exception.cpp` were **deleted** (PR #1796). `ioda::Exception` and the `ioda_Here()` macro no longer exist — throw `eckit::Exception` subclasses with `Here()` from `eckit/exception/Exceptions.h` instead. The same PR purged unused includes across ~200 files, so new code cannot rely on transitively-included headers.

## Architecture

### Two-layer library design

**`ioda_engines`** (`src/engines/`) — Low-level storage abstraction:
- `ioda::Group` — hierarchical container (analogous to HDF5 groups)
- `ioda::Variable` — typed multi-dimensional data arrays with attributes
- `ioda::Attribute` — metadata attached to Groups or Variables
- `ioda::ObsGroup` — observation-specific Group subclass with dimension management

Storage backends (engines):
- **HH** (`src/ioda/Engines/HH/`) — HDF5 backend (parallel HDF5 preferred)
- **ObsStore** (`src/ioda/Engines/ObsStore/`) — in-memory backend
- **ODC** (`src/ioda/Engines/ODC/`) — ODB (ODB API/ODC) backend; requires `odc` package
- **BUFR** (`src/ioda/Engines/Bufr/`) — BUFR backend; requires `bufr_query`

Reader/Writer factory pattern: `ReaderBase`/`WriterBase` with `ReaderFactory`/`WriterFactory` for engine selection at runtime. `missing file action` (`"error"` default, or `"warn"`) lives on `ReaderParametersBase`, so every reader backend honors it (PR #1812), including the OSDF reader path (`reader/ObsReader.cpp`, `load/loadObsFromNetcdf.cpp`, `load/loadObsFromOdb.cpp`, which raise `eckit::ReadError`); it is not an H5File-only key.

**`ioda`** (`src/`) — Higher-level JEDI/oops interface:
- `ioda::ObsSpace` — main class; extends `oops::ObsSpaceBase`; manages the full lifecycle of obs data in a DA run (read on construction, optional write on destruction). Exposes `begin()`/`end()` returning `ioda::ObsIterator` for location-based traversal. Supports continuous/cycling DA via `updateObsSpace(cdaConfig)`: shifts the time window forward, appends a new obs directory, and drops obs falling outside the shifted window via `reduce()`. Attached `ObsSpaceAssociated` consumers (`ObsVector`, `ObsDataVector<T>`) stay in sync through `attach()` plus the `reduce()`/`append()`/`syncAppend()` virtuals.
- `ioda::ObsIterator` — forward iterator over obs locations; dereferences to `eckit::geometry::Point3(lon, lat, z)`. `z` defaults to `0` but is read from `MetaData/<verticalCoordinate>` when the obs space's `iterator vertical coordinate` YAML key names a variable — enables 3D (vertical) localization for the sequential EnKF/EAKF solver via `GeometryIterator` (PR #1734). `ObsSpace::verticalCoordinate()` exposes the configured name as `boost::optional<std::string>`. Aliased as `IodaTrait::GeometryIterator`. Copy-constructible but **not** copy-assignable (`operator=` is explicitly deleted, PR #1810, because of the reference member): rebind by copy-construction, not assignment.
- `ioda::ObsVector` — observation vector for DA algorithms
- `ioda::ObsDataVector<T>` — templated obs data container
- `ioda::Distribution` (`src/distribution/`) — MPI distribution strategies: `RoundRobin`, `Halo`, `InefficientDistribution`, etc.
- `ioda::IoPool` (`src/ioPool/`) — parallel I/O pool management; decouples MPI ranks from I/O tasks
- `src/containers/` — OSDF (Observation Space Data Format) container classes under `namespace osdf`: `IFrame`, `FrameCols`, `FrameRows`, `FrameMetadata`, `Data<T>`, etc.
- `src/reader/` — obs reading pipeline: load → filter → distribute
- `src/writer/` — obs writing utilities

### Data Layout and Group Conventions

Variables in ObsGroup are organized by a `DataLayoutPolicy`. The default layout stores variables as `Group/varname` (e.g., `ObsValue/brightnessTemperature`). The ODB layout (`Layout_ObsGroup_ODB`) maps ODB column names to IODA variable paths.

Standard groups in an ObsSpace:

| Group | Purpose |
|-------|---------|
| `ObsValue` | Original observed values |
| `MetaData` | Location metadata (latitude, longitude, datetime, station_id, etc.) |
| `ObsError` | Original observation error estimates |
| `HofX` | Model-simulated observation values H(x) |
| `EffectiveError` | Observation errors after QC adjustments (filters may inflate) |
| `EffectiveQC` | QC flags (0 = pass, non-zero = rejection reason) |
| `DerivedObsValue` | Values computed by variable transforms (can overshadow ObsValue) |
| `DerivedMetaData` | Metadata computed during processing |
| `GsiEffectiveQC` | GSI-compatible QC flags (optional) |
| `PreQC` | Pre-existing QC flags from data provider |

Missing value conventions: `util::missingValue<T>()` — `9.969209968e+36` for float, `2147483647` for int32.

### Backend Details

**HDF5 (HH)**: Default file I/O backend. Supports parallel HDF5 for multi-rank writes. Files use `.nc4` or `.nc` extensions with HDF5 format underneath. The H5File reader supports **multiple input files** via the `obsfiles` YAML parameter — observations from all listed files are appended along the Location dimension. As of PR #1753, `Read{H5,Odb,Bufr}FileParameters::getFileName()` falls back to `obsfiles[0]` when `obsfile` is empty — a temporary fix so CDA / `updateObsSpace` workflows work against multi-file input; the callers that need a single name should eventually handle the whole list.

**BUFR**: Reads BUFR files using `bufr_query` library. Requires a **mapping file** (YAML) that defines how BUFR descriptors map to IODA variables/groups. Mapping files live alongside test data.

**ODB (ODC)**: Reads ODB-2 files via `odc` library. Uses a **varno system** (variable number codes) to identify observation types. The ODB layout policy maps ODB column names to IODA group/variable paths. On write (ODC.cpp), missing values are emitted as ODB `Null` rather than a sentinel: detection now recognizes multiple missing conventions (HDF5 fill, IODA missing-value constants, NaN floats) and unifies them on output (#1733).

**ObsStore**: In-memory backend for intermediate processing. No file I/O — data exists only during the run. Used as an intermediate buffer in the reader pipeline.

**Script**: Python-based backend for custom data processing. A Python script implements `create_obs_group()` returning an `ioda.ObsGroup`. Useful for wrapping custom readers or generating synthetic observations.
```yaml
obs space:
  obsdatain:
    engine:
      type: script
      script file: "make_obs.py"
      args:
        varname: "airTemperature"
```

### I/O Pool Modes

`ioda::IoPool` manages how MPI ranks participate in file I/O. Factory keys: `SinglePool`, `SinglePoolAllTasks`, `PrepInputFiles`, `NonoverlappingPool` (there is no `NonIoPool`):
- **SinglePool** — a subset of ranks handle I/O, others send/receive data via MPI
- **SinglePoolAllTasks** — like SinglePool but all ranks participate in the I/O pool
- **PrepInputFiles** — preprocessing mode that splits large input files for parallel reads
- **NonoverlappingPool** — I/O ranks each own a disjoint file/rank range; `NonoverlappingReaderPool` must MPI-all-reduce `globalNlocs_` *before* `ioReadGroup` (it drives Location chunk sizing, passed to `readerCreateVariable`), while `sourceNlocs_` stays per-rank until after — getting this order wrong hung nc4 file close on `obsdataout` (PR #1838).

### OSDF containers

The `osdf` namespace (`src/containers/`) provides column- and row-oriented data containers (`FrameCols`, `FrameRows`) behind the `IFrame` interface. These are used in the new reader pipeline as an intermediate representation before data lands in `ObsGroup`.

**`ContainerFacade` interface growth** (PRs #1822, #1824): `ContainerFacade` gained pure virtuals `numberOfLocations()`, `channelNumbers()`, and `variableUnits(name)`, and `ObsGroupFacade`'s constructor now takes an `Engines::FacadeMode` (`ReaderMode` / `WriterMode`) — in `WriterMode` it populates its members from the existing container contents rather than expecting to fill them. Any out-of-tree `ContainerFacade` implementation must add these overrides. `OsdfFrameFacade` moved from `src/reader/` to `src/` (it now serves both read and write paths) and its constructor gained an `allowNonEmptyFrame` flag.

**`ContainerFacade` channel count** (PR #1814): `numberOfChannels()` returns `0`, not `1`, when the container was initialized without channel indices; both implementations (`Engines::ObsGroupFacade`, `OsdfFrameFacade`) report the raw count. Call sites that want a multiplier must write `hasChannelAxis ? numberOfChannels() : 1` (see `ObsGroupFacade::addTypedVariable`, `ODC/VariableCreator`), and `ObsGroupFacade::addTypedVariable` throws `eckit::UserError` if a channel-axis variable is added to a channel-less container.

**Column metadata with units**: Each OSDF column carries metadata via `osdf::ColumnMetadatum`, which stores the column name, data type, permission, and **units** (string). Units are accessed via `getUnit()`/`setUnit()` on `ColumnMetadatum`, or via `IFrame::getColumnUnits(columnName)`.

**IFrame slicing** (PR #1768): `IFrame::sliceFrame()` virtual overloads (typed comparison on a named column) return a filtered copy as `std::unique_ptr<IFrame>`; implemented by both `FrameCols` and `FrameRows` via private `sliceRowsImpl()` templates. Also, `ObsSpace::put_db` to an OSDF backend is a **no-op for empty data vectors** (PR #1767) instead of calling `setColumn()` with zero rows.

**OSDF writer** (`src/writer/`): The write pipeline has two stages: `collectObs()` (`collect/collectObs.hpp`) gathers observations from all ranks onto designated I/O pool ranks, then `obsWrite()` (`ObsWriter.hpp`) handles the full output pipeline (accepts output parameters, MPI communicator, distribution info, source OSDF frame, statistics, and metadata). Under the hood, `saveObs()` (`save/`) dispatches on engine type: `H5File` → `saveOsdfToNetcdf()`, which writes directly to NetCDF (using netcdf-cxx4, not the HDF5/HH engine), and `ODB` → `saveOsdfToOdb()` (`save/saveObsToOdb.{cpp,hpp}`, PR #1822), which builds an ODB-layout `OsdfFrameFacade` and calls the re-signatured `Engines::ODC::createFile(params, ContainerFacade&)` (no longer returns a `Group`); with `write multiple files: false` rank 0 binary-concatenates the per-rank ODB files. The OSDF writer is therefore no longer NetCDF-only. The writer handles Location and Channel dimensions, creates hierarchical group/variable structures matching IODA conventions, sets `_FillValue` and `units` attributes, and supports multi-file output (one file per I/O pool rank). Also handles **empty ObsSpace output**: when no obs survive filtering, `saveOsdfToNetcdf()` still writes a NetCDF file with `Location` dimension of size 0 (recognized on read to reconstruct an empty ObsSpace), so OSDF-only workflows can run without the legacy HDF5 engine fallback.

**Non-destructive save** (PR #1755): `ObsSpace::save(bool preserveDistribution=false)` accepts a flag that flows through `obsWrite(..., preserveInputs=false)` to a new `collectObs` overload (`collect/collectObs.hpp`). When `true`, the writer keeps the caller's `Distribution`, `ObsSourceStats`, and source OSDF frame intact and produces *separate* post-`SelectedRanks`-distribution output objects rather than overwriting in place; cost is the extra memory for the duplicate frame. Default (`false`) preserves the legacy in-place behavior. Use the flag when the in-memory ObsSpace must remain usable after `save()` — e.g., writing mid-cycle diagnostics in OSDF-based workflows.

**OSDF-backed `extendObsSpace`** (PR #1757): `ObsSpace::extendObsSpace()` now works with the OSDF backend. Because `IFrame` has no row-resize API, the OSDF path uses a "companion frame" approach — it builds a separate frame holding the new (extended) rows and `append()`s it to the existing frame, rather than resizing the Location dimension in place. `IFrame::append()` gains an `addOffsetToSourceLocationIndices` flag controlling whether appended source location indices are offset to avoid overlap. The fill logic was factored out of `extendVariable()` into a reusable `fillCompanionLocations()` template shared by the ObsGroup and OSDF backends.

**Channeled-variable Derived-group resolution** (PR #1749): `ObsSpace::groupToUse()` now picks the right group for OSDF-backed channelled variables. When `osdfMetadata_.varHasChannels(fullName)` is true, it tests for the first-channel-suffixed column (`name + "_" + chan0`) when deciding whether to fall back from `DerivedObsValue` → `ObsValue` / `DerivedMetaData` → `MetaData`. The ObsGroup-backed code path is unchanged. Without this, radiance/channelled variables in OSDF ObsSpaces failed Derived-group lookups, which broke `ufo_variabletransforms_btfromradiance` and any similar transform.

**1D Channel-dimensioned variables in OSDF `put_db`/`get_db`** (PR #1773): `ObsSpace::loadVar()`/`saveVar()` now handle Channel-only variables (`dimNames == {"Channel"}`, one value per channel) as a distinct code path from Location×Channel channelled variables (numLocs×numChans, standard `i + j*numChans` index). Channel-only values are broadcast across all rows on write and read back from the first row. Callers select this via a `dim_list` YAML override (see the test harness); without it the value would be mis-shaped as Location-dimensioned.

**General 2D variables in `FrameMetadata`** (PR #1775): `FrameMetadata` is generalized from channel-specific to **arbitrary named second dimensions** (e.g. `"Channel"`, `"Level"`, `"nfactors"`). The channel-only API is replaced by generic accessors keyed on a dimension name: `setDimNums(dimName, nums)` / `getDimNums(dimName)` / `hasDim(dimName)` / `getDimNames()`, backed by `std::unordered_map<std::string, std::vector<int>> dimNums_` (was `chanNums_` + `varsWithChans_`). New helpers: `varSliceDimName(varName)` (the first non-`Location` dim, or `""` for 1D), and `getMultiSliceVars()` (all vars with any non-`Location` dim). Terminology throughout is now "slice dimension" rather than "second dimension". As of the phase-4 completion (PR #1779) the old channel-specific backward-compat wrappers (`setChanNums`/`getChanNums`/`varHasChannels`/`getVarsWithChans`) are **removed**; callers use the generic `setDimNums`/`getDimNums`/`hasDim`/`getDimNames` API directly. Correspondingly, `OsdfFrameFacade::setTypedIodaVariableValues` takes `const std::string& sliceDimName` in place of the old `bool hasChannelAxis`. Matching renames landed in `ObsSpace`: `chanSelect`→`sliceSelect`, `createChannelSelections`→`createSliceSelections`, `splitChanSuffix`→`splitSliceSuffix` (affects `get_db`/`loadVar` signatures); OSDF trailing-numeric-suffix handling is now aligned with `ObsGroup` behavior (PR #1794). Follow-up fix (PR #1840): `ObsSpace::has()` no longer falls back to the base name when a requested name carries a spurious numeric suffix — `has("MetaData/latitude_1")` is now `false` — while `dtype()`/`get_db`/`splitSliceSuffix` still strip it; this avoids a 1D `var_1` colliding with a channelled `var` stored as columns `var_1..var_N` (the collision is only partly solved upstream).

**Consolidated OSDF variable-existence checks** (PR #1848): two new free functions in `core/IodaUtils.h` are now the single source of truth for mapping a variable name to its OSDF columns. `osdfVarColumnNames(frameMetadata, fullVarName)` returns the column names — one `<name>_<slice>` per registered slice-dimension value, or the verbatim name for a 1D variable — and is never empty. `osdfVarColumns(frame, metadata, fullVarName)` returns the actual columns (empty means absent), testing a representative column. `ObsSpace::osdfVarNameToUse()` is **gone**, replaced by the private `osdfColumnsFor(group, name)`; `has()`, `dtype()`, and `groupToUse()` are all built on it so they can no longer disagree. `groupToUse()` deliberately does not go through `has()`, which reports everything as present on an empty ObsSpace. `OsdfFrameFacade::hasVariable`/`variableType`/`removeVariable` use the same helpers. The 1D `var_1` vs. 2D `var` slice-1 storage collision remains an open TODO.

**Serial single-file netCDF write** (PR #1818): with `write multiple files: false`, the OSDF netCDF writer produces one shared file *without* parallel HDF5. Rank 0 creates the full schema sized to the pool-wide `totalNlocs`, then each pool rank writes its slab at its own `nlocsStart` offset, in rank order, coordinated by a token handshake. This is the OSDF path's answer to workflows that need a single output file on stacks without parallel HDF5.

**Save messaging + names** (PR #1824): `saveObs()` takes the obs-space name and logs `"<obs space>: save database to <file> (io pool size: N)"`, mirroring the ObsGroup writer's messaging. `ObsIoPool::poolSize()` is new and valid on *all* ranks (`commPool().size()` is misleading off-pool). `ObsSpace::containerName()` reports which container backs the space (`FrameRows` / `FrameCols` / ObsGroup) at construction.

**2D (Layer) variables** (PR #1764): `ObsDimensionId` gains a `Layer` member (`core/ObsDimInfo.{h,cc}`) alongside `Nlocs`/`Channel`. `ObsSpace::loadVar` treats a variable's second dimension as either Channel or Layer (Channel wins if both are present), and `fillChanNumToIndexMap()` synthesizes a 1-based sequential index map for Layer so YAML `layers: 1-N` (see the matching `ufo::Variable` support) selects retrieval levels. The OSDF path is unchanged and remains Channel-only.

**Generator backends + type coercion in OSDF** (PRs #1784, #1791, #1797, #1792, #1801, #1804): the OSDF reader can now drive the in-memory `Generate.List`/`Generate.Random` backends. `reader/load/loadObsFromGenerators.{cpp,hpp}` (with `storeGenDataInFrame.{cpp,hpp}`) load generated obs into OSDF frames, sharing a container-agnostic `Engines::GeneratedObsData` / `generateObsList` / `generateObsRandom` refactor in `EngineUtils`; `loadObs`/`obsRead` gained `obsVarNames` + `timeWindow` arguments. `containers/FrameUtils.h` adds missing-value-aware `coerce<T,S>` / `withCoercionType` type coercion for `getColumn`/`setColumn` (PR #1791). Robustness fixes: `_FillValue` re-read directly from the variable's attribute map (#1797), float dimension coordinates allowed in the OSDF netCDF reader (#1792), inf/nan values handled on ingest (#1801), and `ObsSpace::dtype` fixed for the OSDF datetime-column case (#1804). (An OSDF ODB writer #1774 was added then reverted #1798 — net no change.)

## Tools

`tools/ioda_compare_obs.py` (PR #1830): row-order-independent comparator for OSDF vs. ObsGroup output files. Canonically sorts full rows before comparing, normalizes `NC_CHAR`/`NC_UBYTE` booleans against string representations without widening integer types, treats coordinate-variable and attribute diffs as non-fatal unless `--strict`, accepts `--tolerance` for float comparisons, and handles multi-file (`_0000`-suffixed) output sets. Self-tested by the `ioda_compare_obs_selftest` ctest target, which needs no test data.

## Test Data

Tests require the `ioda-data` repo checked out alongside the bundle, or test data downloaded from a tarball. In the bundle build, test data is at:
```
/home/tsluka/work/jedi/build/ioda/test/Data/testinput_tier_1/
```

The `IODA_TESTFILES` environment variable can point to a local test data directory to avoid downloading.

PR #1848 adds `ioda_osdf_var_columns` (`test/containers/OsdfVarColumns.h`, `test/mains/containers/TestOsdfVarColumns.cc`), which covers the OSDF column-naming rule for 1D, channelled, and absent variables.

### YAML Configuration

The `observations:` node is a **mapping**, not a bare sequence: the per-obs-space specs live under a required `observers:` list, and keys placed directly under `observations:` are section-wide defaults inherited by every obs space (PR #1825, oops #3358). Currently the only such default is `obs data container: OSDF|ObsGroup`, which sets each space's `use data frame container` unless that space overrides it. A missing `observers` key throws `eckit::UserError` from `oops::ObsSpaces`.

```yaml
observations:
  obs data container: OSDF        # section-wide default; per-space setting wins
  observers:
    - obs operator: { ... }
      obs space:
        name: Aircraft
        # ... (see below)
```

The obs-space block itself:

```yaml
obs space:
  name: Aircraft
  obsdatain:
    engine:
      type: H5File       # or ODB, BUFR, Script
      obsfile: aircraft.nc4
      # obsfiles: [file1.nc4, file2.nc4]  # multiple input files (appended along Location)
      # missing file action: warn          # or "error" (default); valid for any reader type
  obsdataout:
    engine:
      type: H5File
      obsfile: aircraft_out.nc4
    # empty obs space action: "skip output"  # or "create output" (default)
  simulated variables: [airTemperature, windEastward]
  observed variables: [airTemperature, windEastward]
  # iterator vertical coordinate: pressure   # optional: enables 3D obs-iterator localization
  obsgrouping:                    # Optional: group obs into records
    group variables: [stationIdentification]
    sort variable: pressure       # Sort within groups
    sort order: descending
```

### Fortran API

Key Fortran interfaces (used by UFO and model repos via `obsspace_get_db`/`obsspace_put_db`):
- `obsspace_get_db(obsspace, group, varname, data)` — read data from a group/variable
- `obsspace_put_db(obsspace, group, varname, data)` — write data to a group/variable
- `obsspace_get_nlocs(obsspace)` — number of locations
- `obsspace_get_gnlocs(obsspace)` — global number of locations

## Cross-Repo Role

IODA provides the data-side of the `OBS` template parameter via `ufo::ObsTraits`:
- `ioda::ObsSpace` — observation data container (extends `oops::ObsSpaceBase`)
- `ioda::ObsVector` — observation value vectors used by oops cost functions
- `ioda::ObsDataVector<T>` — templated data containers used by UFO filters

UFO depends on IODA for all observation data access. Model repos never call IODA directly — they interact through oops/UFO.

## Key Dependencies

- **HDF5** (parallel): primary file format
- **eckit / fckit**: ECMWF toolkit (config, MPI, logging)
- **oops**: JEDI algorithmic framework (`ObsSpaceBase`, `Parameters`, etc.)
- **Eigen3 / gsl-lite / Boost**: math and utility headers
- **udunits**: unit conversion
- **odc** (optional): ODB file support
- **bufr_query** (optional): BUFR file support
- **pybind11** (optional): Python bindings
