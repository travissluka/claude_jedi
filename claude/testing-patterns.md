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

## SABER Tier System

SABER uses tiers for test categorization:

| Tier | Tests | OpenMP |
|------|-------|--------|
| 1 (default) | MPI-only, fast baseline | Off |
| 2 | MPI + OpenMP, extended | On |

Controlled by `SABER_TEST_TIER` env variable or CMake variable. Tests listed in `testlist/saber_test_tier1.txt` and `testlist/saber_test_tier2.txt`.

Multiple MPI/OMP combinations generated automatically for each test (1/1, 2/1, 4/1, 1/2).

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
