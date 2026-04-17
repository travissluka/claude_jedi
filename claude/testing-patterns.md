# Testing Patterns in JEDI

How tests are structured, registered, and run across JEDI repos.

## ecbuild_add_test Macro

All tests are registered via `ecbuild_add_test()`:

```cmake
ecbuild_add_test( TARGET  test_name
                  MPI     4
                  OMP     2
                  COMMAND executable
                  ARGS    testinput/config.yaml
                  DEPENDS executable_target
                  TEST_DEPENDS prerequisite_test
                  LABELS  tier2 )
```

| Parameter | Purpose |
|-----------|---------|
| `TARGET` | Test name (used with `ctest -R`) |
| `COMMAND` | Executable to run |
| `SOURCES` | Source files to compile (alternative to COMMAND) |
| `ARGS` | Arguments passed to executable (usually YAML config path) |
| `MPI` | Number of MPI processes |
| `OMP` | Number of OpenMP threads |
| `DEPENDS` | Build targets that must be built first |
| `TEST_DEPENDS` | Tests that must pass before this one runs |
| `LIBS` | Libraries to link against (when using SOURCES) |
| `LABELS` | Test labels for filtering |
| `WORKING_DIRECTORY` | Where to run the test |
| `ENVIRONMENT` | Environment variables (key=value) |

## Test Executable Pattern

Tests use the oops `Run` harness. A typical test executable:

```cpp
#include "oops/runs/Run.h"
#include "oops/runs/ConvertState.h"
#include "fv3jedi/Utilities/Traits.h"

int main(int argc, char ** argv) {
  oops::Run run(argc, argv);
  oops::ConvertState<fv3jedi::Traits> app;
  return run.execute(app);
}
```

`Run` handles MPI init, YAML config loading, and test environment setup. The application reads config from `TestEnvironment::config()`.

## oops Test Fixtures

Interface tests (Geometry, State, Increment, etc.) use a singleton fixture pattern:

```cpp
// oops/src/test/interface/Geometry.h
template <typename MODEL> class Geometry : public oops::Test {
  void register_tests() const override {
    std::vector<eckit::testing::Test>& ts = eckit::testing::specification();
    ts.emplace_back(CASE("interface/Geometry/testConstructor") {
      testConstructor<MODEL>();
    });
    ts.emplace_back(CASE("interface/Geometry/testAtlasInterface") {
      testAtlasInterface<MODEL>();
    });
  }
};
```

Model repos register these by creating an executable that instantiates the test with their Traits:
```cpp
oops::Test & testGeometry = oops::Geometry<soca::Traits>::instance();
```

## Reference Output Comparison

Tests compare stdout against reference files:

```yaml
# In test YAML
test:
  reference filename: testoutput/3dvar.test
```

The `TestReference` utility (`oops/src/test/util/TestReference.h`) parses floating-point numbers from both actual and expected output, then compares:
- **Relative tolerance**: `|a - b| < tol * max(|a|, |b|)`
- **Absolute tolerance**: `|a - b| < tol`
- **Integers**: exact match

### Generating reference output

1. Run the test: `ctest -R test_name -VV`
2. Save stdout to the reference file
3. Commit to version control

## Test Data Management

Test data repos (ioda-data, ufo-data, fv3-jedi-data, etc.) are registered in `bundle/CMakeLists.txt`:

```cmake
ecbuild_bundle( PROJECT ioda-data GIT "https://github.com/..." BRANCH develop )
```

Data is downloaded at build time and referenced via symlinks from test working directories.

### SOCA test directory pattern

SOCA wraps `ecbuild_add_test` in `soca_add_test()` which:
1. Creates `test_workdir/<name>/` per test
2. Symlinks `data_static/`, `data_generated/`, `testinput/`, `testref/`
3. Prevents parallel test output conflicts

## Tier System (Bundle-wide Standardization, 2026)

Most repos have converged on a **label-based** tier system:

| Tier | Marker | When it runs |
|------|--------|--------------|
| 1 (default) | no label (implicit) | Every CI run; fast baseline |
| 2 | `LABELS tier2` | Nightly / extended; slow tests, coding norms, extra-detail checks |

Register with:
```cmake
ecbuild_add_test( TARGET   <repo>_<name>
                  COMMAND  <executable>
                  LABELS   tier2 )
```

Filter with CTest:
```bash
ctest -L tier2              # run only tier2
ctest -LE tier2             # exclude tier2 (i.e., tier1 only)
```

**Repos using labels**: oops, ufo, ioda, vader, saber, fv3-jedi, mpas-jedi, pyiri-jedi, soca, coupling. `FV3JEDI_TEST_TIER` and `SABER_TEST_TIER` env variables were removed in favor of labels.

**Coding-norms tests are tier2** by convention (they're slow and run nightly, not per-commit).

### Other bundle-wide labels

| Label | Purpose |
|-------|---------|
| `tier2` | Extended / nightly tests |
| `ci_oneapi_disable` | Tests to skip on the Intel oneAPI CI runner (fv3-jedi, mpas-jedi) — replaced older `CI_exclude_fv3jedi` |
| `ufo_data_validate` | UFO data-validation-only tests |

### Test name prefix standardization

Test names now start with the repo slug (no `test_` prefix, no `tier1_` in the name since tier is expressed via labels):

| Repo | Prefix |
|------|--------|
| oops | `oops_` |
| ioda | `ioda_` |
| ufo | `ufo_` |
| saber | `saber_` |
| vader | `vader_` |
| fv3-jedi | `fv3jedi_` |
| mpas-jedi | `mpasjedi_` |
| pyiri-jedi | `pyirijedi_` |
| soca | `soca_` |
| coupling | `coupling_` |

### SABER: component-gated `.cmake` include files

SABER registers tests directly via `saber_add_test(...)` calls (wrapper around `ecbuild_add_test`) in per-component `.cmake` files under `test/testlist/`, which `test/CMakeLists.txt` `include()`s conditionally based on `SABER_TEST_<COMPONENT>` flags (auto-set from feature detection, overridable via env vars):

- `saber_base.cmake` — always included; dirac / diffusion / interpolation / rescaling core tests
- `saber_bump.cmake` — gated by `SABER_TEST_BUMP`
- `saber_spectralb.cmake`, `saber_spectralb-vader.cmake` — gated by `SABER_TEST_SPECTRALB`
- `saber_bifourier.cmake`, `saber_bifourier-ectrans.cmake` — gated by `SABER_TEST_BIFOURIER` (+ ECTRANS detection)
- `saber_fastlam.cmake`, `saber_fastlam-fftw.cmake`, `saber_fastlam-regional_interpolation.cmake` — gated by `SABER_TEST_FASTLAM`
- `saber_gsi-geos.cmake`, `saber_gsi-gfs.cmake` — gated by `SABER_TEST_GSI_GEOS` / `SABER_TEST_GSI_GFS`
- `saber_vader.cmake`, `saber_vader_with_trans.cmake` — gated by `SABER_TEST_VADER`
- `saber_coupled.cmake` — coupled-covariance tests
- `saber_torchbalance.cmake` — gated by `SABER_TEST_TORCHBALANCE`

Tier is expressed via `LABELS tier2` on individual test entries (MPI+OpenMP expansions, tutorial tests, etc.) — same convention as the other repos. Each test is still generated for multiple MPI/OMP combinations (1/1, 2/1, 4/1, 1/2); the 1/2 OMP-2 variants get `LABELS tier2`.

## Adjoint Tests (Dot-Product Test)

The standard TL/AD verification pattern:

```
1. Generate random dx (forward perturbation)
2. Run TL: dy = M · dx
3. Generate random dy' (adjoint input)
4. Run AD: dx' = Mᵀ · dy'
5. Verify: <dy, dy'> ≈ <dx, dx'>  (within tolerance)
```

Implementation in `oops/src/test/interface/LinearModel.h`:
```cpp
const double dot1 = dot_product(dx_initial, dx_adjoint);
const double dot2 = dot_product(dx_forward, dy_adjoint);
EXPECT(oops::is_close(dot1, dot2, tolerance));
```

Related linear model tests:
- `testLinearModelZeroLength` — identity for zero duration
- `testLinearModelZeroPert` — zero in → zero out
- `testLinearModelLinearity` — TL scales linearly with input
- `testLinearApproximation` — TL approximates NL for small perturbations

## Adding a New Test

### Step 1: Create YAML config

Place in `<repo>/test/testinput/<name>.yaml`:
```yaml
geometry:
  # ... grid config
background:
  # ... input file
test:
  reference filename: testoutput/<name>.test
```

### Step 2: Register in CMakeLists.txt

```cmake
ecbuild_add_test( TARGET  <repo>_<name>
                  MPI     4
                  COMMAND <executable>
                  ARGS    testinput/<name>.yaml
                  DEPENDS <executable>
                  TEST_DEPENDS <prerequisite> )
```

### Step 3: Generate reference output

```bash
cd build && ctest -R <repo>_<name> -VV 2>&1 | tee testoutput/<name>.test
```

Edit the reference file to keep only the relevant numerical output.

### Step 4: Add to file lists

```cmake
list(APPEND test_input testinput/<name>.yaml)
list(APPEND test_output testoutput/<name>.test)
```

## Test Directory Layout

```
<repo>/test/
├── CMakeLists.txt        # Test definitions
├── testinput/            # YAML configs
├── testoutput/           # Reference outputs (*.test)
├── testref/              # Alternative reference location
├── executables/          # Test source files (*.cc)
└── Data/                 # Static test data (grids, restarts)
```
