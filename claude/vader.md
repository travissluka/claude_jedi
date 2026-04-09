# VADER (The VAriable DErivation Repository)

> Last updated against commit `0605133a` (2026-04-02). Run `cd bundle/vader && git log --oneline 0605133a..HEAD` to see what changed since.

## Overview

C++/Fortran library for composable variable transformations within JEDI. Source at `bundle/vader/`. Version 1.7.0.

VADER uses a **Recipe/Cookbook** metaphor: a **Recipe** transforms input variables (ingredients) into a single output variable (product). A **Cookbook** maps output variable names to available recipes. VADER's planning algorithm automatically discovers dependency chains to produce requested variables from available inputs.

## Build

```bash
# From build directory
make vader

# Tests
ctest --output-on-failure -R vader
ctest -N -R vader   # List tests
```

Dependencies: oops ≥1.10.0, atlas, NetCDF, Boost ≥1.64, MPI. Optional: GSW (enables ocean recipes), OpenMP.

## Core Architecture

### RecipeBase (`src/vader/RecipeBase.h`)

Abstract base class for all recipes. Required overrides:

- `name()` — recipe identifier (e.g., `"DryAirDensity_A"`)
- `product()` — output `oops::Variable`
- `ingredients()` — input `oops::Variables`
- `productLevels()` / `productFunctionSpace()` — output metadata from input fields

Execution methods (override as needed):
- `executeNL(atlas::FieldSet&)` — nonlinear transformation
- `executeTL(atlas::FieldSet&, const atlas::FieldSet&)` — tangent linear (uses trajectory)
- `executeAD(atlas::FieldSet&, const atlas::FieldSet&)` — adjoint (accumulates sensitivities, zeros output)
- `hasTLAD()` / `hasNL()` — flags for available modes

Factory registration: each recipe ends with `static RecipeMaker<MyRecipe> maker_(MyRecipe::Name);`

### Vader Class (`src/vader/vader.h`)

Main orchestrator. Key members:
- `cookbook_` — map of variable → vector of recipes
- `recipeExecutionPlan_` — ordered list of recipes to execute

Public API:
- `changeVar(FieldSet&, Variables&)` — nonlinear variable change; plans and executes recipes
- `changeVarTraj(FieldSet&, Variables&)` — store trajectory for TL/AD
- `changeVarTL(FieldSet&)` / `changeVarAD(FieldSet&)` — tangent linear / adjoint (AD runs in reverse order)

**`planVariable()` algorithm** — the core planning engine:
1. Check if variable already available → done
2. Search cookbook for recipes producing this variable
3. For each recipe: check if ingredients are available or recursively plannable
4. For TL/AD: also verify trajectory variables are available
5. Add recipe to execution plan if successful

### DefaultCookbook (`src/vader/DefaultCookbook.h`)

Maps each output variable to a priority-ordered list of recipe names. VADER tries the first recipe, falls back to alternatives if ingredients are unavailable.

### Multiple Recipe Variants

Many variables have \_A, \_B, \_C variants using different inputs or linearization approaches:
- **AirTemperature\_A**: from potential temperature × exner function (has TL/AD)
- **AirTemperature\_B**: from virtual temperature and specific humidity (NL only)
- **AirTemperature\_C**: from pressure and potential temperature (NL only)

This allows different models to use the variant matching their available state variables.

## Configuration Variables

VADER recipes may require external configuration parameters (passed via `VaderParameters` in YAML):
- **`nLevels`** — number of vertical levels
- **`ak`/`bk`** coefficients — hybrid sigma-pressure vertical coordinate arrays (define pressure at each level as `p = ak + bk * ps`)
- Physical constants defined in `src/vader/` and `src/mo/`: `Rd` (gas constant dry air), `Cp` (specific heat), `Lv` (latent heat of vaporization), `epsilon` (Rd/Rv ratio), `grav` (gravitational acceleration)

## Variable Naming Conventions

VADER follows JEDI naming standards (from jedi-docs conventions):
- **`wrt_dry_air`** / **`wrt_moist_air`** suffixes: mixing ratios can be expressed with respect to dry or moist air mass (e.g., `water_vapor_mixing_ratio_wrt_dry_air` vs `water_vapor_mixing_ratio_wrt_moist_air`)
- **`at_interface`** suffix: values at level interfaces (half-levels) rather than mid-levels
- **`at_surface`** / **`at_2m`** / **`at_10m`** suffixes: surface or near-surface quantities
- Recipe `_A`, `_B`, `_C` suffixes distinguish different formulas for the same output variable

## Recipe Categories (~57+ recipes)

**Temperature** (6): AirTemperature (A/B/C), AirVirtualTemperature (A/B), AirPotentialTemperature (A/B)

**Pressure** (11): AirPressure, AirPressureAtInterface (A/B/C), AirPressureThickness, AirPressureExtendedUpByOne, HydrostaticExnerLevels, HydrostaticPressureLevels, LnAirPressure, LnAirPressureAtInterface, SurfaceAirPressure

**Humidity** (8+): WaterVaporMixingRatio variants (dry/wet air, 2m), RelativeHumidity (A — special case, uses lookup tables from `src/mo/`), SaturationVaporPressure, SaturationSpecificHumidity, LogDerivativeSaturationVaporPressure

**Clouds** (8): CloudIceMixingRatio (dry/wet, 4 total), CloudLiquidWaterMixingRatio (dry/wet, 4 total)

**Geopotential** (5): GeopotentialHeight, GeopotentialAtInterface, GeopotentialHeightAtInterface, GeopotentialHeightAtSurface, HeightAboveMeanSeaLevelAtSurface

**Density** (3): DryAirDensity, DryAirDensityLevelsMinusOne, AirDensityLevelsMinusOne

**Wind** (3): EastwardWindAt10m, NorthwardWindAt10m, WindReductionFactorAt10m

**Aerosol** (4): ParticulateMatter2p5 (2), SulfateMassFraction, RainMixingRatio

**Water totals** (5): TotalWater, TotalWaterMixingRatio (dry/wet), TotalRelativeHumidity (2)

**Ocean** (2, requires GSW): SeaWaterTemperature, SeaWaterPotentialTemperature

### TL/AD Support

Most temperature, pressure, density, and geopotential `_A` variants have TL/AD. Humidity and cloud recipes are generally NL-only. `RelativeHumidity_A` is notable for using Met Office saturation vapor pressure lookup tables (`src/mo/`) rather than simple formulas, with full TL/AD support.

## Recipe Implementation Pattern

Each recipe follows this structure:

```cpp
// Static registration
const char MyRecipe_A::Name[] = "MyRecipe_A";
const oops::Variables MyRecipe_A::Ingredients{{"ingredient1", "ingredient2"}};
static RecipeMaker<MyRecipe_A> maker_(MyRecipe_A::Name);

// NL: direct formula
void MyRecipe_A::executeNL(atlas::FieldSet& fields) {
  util::for_each_value(
    [](const double in1, const double in2, double& out) {
      out = in1 / (Rd * in2);  // physics formula
    },
    fields["ingredient1"], fields["ingredient2"], fields["product"]);
}

// TL: linearized formula using trajectory
void MyRecipe_A::executeTL(atlas::FieldSet& tl, const atlas::FieldSet& traj) {
  // Perturbation fields use trajectory for linearization point
}

// AD: accumulate sensitivities, then zero output
void MyRecipe_A::executeAD(atlas::FieldSet& ad, const atlas::FieldSet& traj) {
  // ad_ingredient += f(ad_product, traj); ad_product = 0;
}
```

Key patterns:
- `util::for_each_value()` for vectorized operations over grid points
- AD always accumulates (`+=`) into ingredient adjoints, then zeros the product adjoint
- Trajectory values are stored during `changeVarTraj()` for use by TL/AD

## Source Layout

| Directory | Purpose |
|-----------|---------|
| `src/vader/` | Core: `vader.h/cc`, `RecipeBase.h/cc`, `DefaultCookbook.h`, `VaderParameters.h` |
| `src/vader/recipes/` | All recipe implementations (~47 headers + .cc files) |
| `src/mo/` | Met Office integration: lookup tables (SVP), eval functions, constants, Fortran I/O |
| `src/OceanConversions/` | GSW (Gibbs SeaWater) Fortran bindings for ocean recipes |

## Fortran vs C++ Split

- **C++**: all core framework (Vader class, RecipeBase, factory, planning), all atmospheric recipes
- **Fortran**: Met Office lookup tables and physics (`src/mo/`), ocean conversions via GSW (`src/OceanConversions/`)
- **Interop**: `OceanConversions.interface.h` / `.F90` pairs using ISO_C_BINDING

## Tests

```bash
ctest --output-on-failure -R vader_recipe   # Individual recipe tests
ctest --output-on-failure -R vader_vader    # Integration tests
ctest --output-on-failure -R vader_planvariable  # Planning algorithm
```

Test structure:
- `test/testinput/recipe_*.yaml` — individual recipe tests (~29 files)
- `test/testinput/vader_*.yaml` — integration tests (~27 files)
- `test/testdata/` — NetCDF trajectory data (symlinked from jedi-model-data)

Recipe test YAML pattern:
```yaml
recipe:
  recipe name: DryAirDensity_A
trajectory grid:
  type: regular_gaussian
  N: 12
trajectory filename: testdata/gauss_state_F12.nc
adjoint test tolerance: 1.e-12
```

Tests verify: NL execution correctness, adjoint consistency (dot product test), and planning algorithm.

## Cross-Repo Usage

VADER is used in two ways:

1. **By model repos** — in their `VariableChange` implementations. Model repos create a `vader::Vader` instance and call `changeVar()` before falling back to model-specific transforms. Both fv3-jedi and mpas-jedi use this pattern.

2. **By SABER** — via `VaderBlock` (`saber/src/saber/vader/`), which wraps VADER transformations as a SABER outer block within covariance block chains.

VADER operates on `atlas::FieldSet` directly (not templated on MODEL), so recipes are shared across all models.

## Adding a New Recipe

1. Create `src/vader/recipes/MyVar.h` with Parameters and Recipe classes inheriting from `RecipeBase`
2. Create `src/vader/recipes/MyVar_A.cc` implementing NL (and optionally TL/AD)
3. Register with `static RecipeMaker<MyVar_A> maker_(MyVar_A::Name);`
4. Add to `DefaultCookbook.h` include and cookbook map
5. Add source files to `src/CMakeLists.txt`
6. Add test YAML in `test/testinput/recipe_MyVar_A.yaml` and test target in `test/CMakeLists.txt`
