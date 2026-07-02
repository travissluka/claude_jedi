# VADER (The VAriable DErivation Repository)

> Last updated against commit `d413aa52` (2026-07-01). Run `cd bundle/vader && git log --oneline d413aa52..HEAD` to see what changed since.
>
> **Covers:** Vader, RecipeBase, DefaultCookbook, VaderParameters, planVariable algorithm, _A/_B/_C recipe variants, changeVar/changeVarTraj/changeVarTL/changeVarAD, AirTemperature, DryAirDensity, HydrostaticPressure, RelativeHumidity, MoistureControl, Met Office SVP lookup tables (`src/mo/`), DustBin1MassConcentration_A, DustBin2MassConcentration_A, eval_dust_bin_mass_concentration_nl, GSW OceanConversions, adjoint dot-product test pattern, adding a new recipe.

## Overview

C++/Fortran library for composable variable transformations within JEDI. Source at `bundle/vader/`. Version 1.7.0.

VADER uses a **Recipe/Cookbook** metaphor: a **Recipe** transforms input variables (ingredients) into a single output variable (product). A **Cookbook** maps output variable names to available recipes. VADER's planning algorithm automatically discovers dependency chains to produce requested variables from available inputs.

Build/test quirks in `claude/build-and-test.md`. GSW is the only unique optional dep (enables ocean recipes).

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
- Physical constants defined in `src/vader/` and `src/mo/`: `Rd` (gas constant dry air), `Cp` (specific heat), `Lv` (latent heat of vaporization), `epsilon` (Rd/Rv ratio), `grav` (gravitational acceleration), `k_B` (Boltzmann)
- GLOMAP dust constants in `src/mo/constants.h` (used by DustBin recipes): `glomap_dust_density`, `sigma_acc`, `sigma_coarse`, `Dmin_bin1/Dmax_bin1`, `Dmin_bin2/Dmax_bin2`

## Variable Naming Conventions

VADER follows JEDI naming standards (from jedi-docs conventions):
- **`wrt_dry_air`** / **`wrt_moist_air`** suffixes: mixing ratios can be expressed with respect to dry or moist air mass (e.g., `water_vapor_mixing_ratio_wrt_dry_air` vs `water_vapor_mixing_ratio_wrt_moist_air`)
- **`at_interface`** suffix: values at level interfaces (half-levels) rather than mid-levels
- **`at_surface`** / **`at_2m`** / **`at_10m`** suffixes: surface or near-surface quantities
- Recipe `_A`, `_B`, `_C` suffixes distinguish different formulas for the same output variable

## Recipe Categories (~90+ recipes)

**Temperature** (6): AirTemperature (A/B/C), AirVirtualTemperature (A/B), AirPotentialTemperature (A/B)

**Pressure** (13): AirPressure (A/B), AirPressureAtInterface (A/B/C/D), AirPressureThickness, AirPressureExtendedUpByOne, HydrostaticExnerLevels, HydrostaticPressureLevels, LnAirPressure, LnAirPressureAtInterface, SurfaceAirPressure. `AirPressure_B` (→ `air_pressure`, mid-level) and `AirPressureAtInterface_D` (→ `air_pressure_levels`, interface) derive pressure directly from `air_pressure_at_surface` via hybrid-sigma `ak`/`bk` coefficients (`sigma_pressure_hybrid_coordinate_a/b_coefficient`): `ak[k] + bk[k]*ps` at interfaces, layer-averaged for mid-levels. This is a distinct ingredient path from the Phillips interface-based recipes (PR #356).

**Humidity** (8+): WaterVaporMixingRatio variants (dry/wet air, 2m), RelativeHumidity (A — special case, uses lookup tables from `src/mo/`; B — q/qsat fraction with full TL/AD, PR #332), SaturationVaporPressure (A; B — Murphy-Koop 2005 liquid/ice, TL/AD), SaturationSpecificHumidity (A; B — exact `qsat = 0.622·es/(p − 0.378·es)`, TL/AD), LogDerivativeSaturationVaporPressure

**Clouds** (8): CloudIceMixingRatio (dry/wet, 4 total), CloudLiquidWaterMixingRatio (dry/wet, 4 total)

**Geopotential** (6): GeopotentialHeight (A/B — B is fv3-jedi-compatible, PR #379), GeopotentialLevels (A), GeopotentialHeightLevels (A/B), GeopotentialHeightAtSurface, HeightAboveMeanSeaLevel (A, PR #381), HeightAboveMeanSeaLevelAtSurface. The `*AtInterface` recipes were renamed to `*Levels` (`GeopotentialAtInterface`→`GeopotentialLevels`, `GeopotentialHeightAtInterface`→`GeopotentialHeightLevels`) and the ingredient `surface_geopotential` was renamed to `geopotential_at_surface` (PR #355).

**Ozone** (1): MoleFractionOfOzoneInAir (A) → `mole_fraction_of_ozone_in_air` (PR #377)

**Density** (3): DryAirDensity, DryAirDensityLevelsMinusOne, AirDensityLevelsMinusOne

**Wind** (3): EastwardWindAt10m, NorthwardWindAt10m, WindReductionFactorAt10m

**Aerosol** (6): ParticulateMatter2p5 (2), SulfateMassFraction, RainMixingRatio, DustBin1MassConcentration_A, DustBin2MassConcentration_A (NL-only; LFRIC UKCA/GLOMAP 2-mode → CLASSIC 2-bin dust; products `mass_fraction_of_dust00{1,2}_in_air`; eval in `src/mo/eval_dust_2bin_mass_concentration.{h,cc}`)

**Water totals** (5): TotalWater, TotalWaterMixingRatio (dry/wet), TotalRelativeHumidity (2)

**Ocean** (2, requires GSW): SeaWaterTemperature, SeaWaterPotentialTemperature

**CRTM convention** (~30, `src/vader/betaNames_CRTMRecipes/`, all NL-only `_A`, PR #332): recipes producing CRTM-convention variable names for the radiance forward operator — CloudLiquidWater/CloudLiquidIce, Graupel, Hail, RainWater, SnowWater, MassContentOf{CloudIce,CloudLiquidWater,Graupel,Hail,Rain,Snow}InAtmosphereLayer, EffectiveRadiusOf{CloudIce,CloudLiquidWater,Graupel,Hail,Rain,Snow}Particle, SkinTemperature (+ WhereLand/Sea/Ice/Snow area-fraction blends), {Ice,Land,Water}AreaFraction, SurfaceSnowAreaFraction, {Eastward,Northward}WindAtSurface, WindSpeedAtSurface, WindFromDirectionAtSurface, TropopausePressure. These register only via `RecipeMaker` (factory) — `DefaultCookbook.h` is unchanged, so they are factory-available but **not** wired into the default cookbook.

### TL/AD Support

Most temperature, pressure, density, and geopotential `_A` variants have TL/AD. Humidity and cloud recipes are generally NL-only. `RelativeHumidity_A` is notable for using Met Office saturation vapor pressure lookup tables (`src/mo/`) rather than simple formulas, with full TL/AD support. `AirPressureThickness_A` gained full TL/AD support in PR #370. `AirPressure_A`, `AirPressure_B`, and `AirPressureAtInterface_D` have full TL/AD (PR #356) — `AirPressure_A` is no longer NL-only Phillips.

**Level ordering** (PR #370, extended in #356): recipes that depend on vertical orientation honor a `levels_are_top_down` config flag. It controls the pressure-thickness sign (so `AirPressureThickness_A` returns always-positive thickness either way), the surface-level index selected by the 10m wind recipes (`EastwardWindAt10m`/`NorthwardWindAt10m` pick `0` for bottom-up vs `nLevels-1` for top-down), the integration direction in `AirPressureAtInterface_B`, and the upper/lower level selection in `AirPressure_A`.

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
| `src/vader/recipes/` | Core recipe implementations (~50 headers + .cc files) |
| `src/vader/betaNames_CRTMRecipes/` | ~30 NL-only `_A` recipes producing CRTM-convention variable names (PR #332); `RecipeMaker`-registered only, not in `DefaultCookbook.h` (see CRTM convention category) |
| `src/mo/` | Met Office integration: lookup tables (SVP), eval functions, constants, Fortran I/O |
| `src/mo/recipes/` | Met Office-derived recipes (e.g., `DustBin1MassConcentration`, `DustBin2MassConcentration`) |
| `src/OceanConversions/` | GSW (Gibbs SeaWater) Fortran bindings for ocean recipes |

## Fortran vs C++ Split

- **C++**: all core framework (Vader class, RecipeBase, factory, planning), all atmospheric recipes
- **Fortran**: Met Office lookup tables and physics (`src/mo/`), ocean conversions via GSW (`src/OceanConversions/`)
- **Interop**: `OceanConversions.interface.h` / `.F90` pairs using ISO_C_BINDING

## Test YAML pattern

```yaml
recipe:
  recipe name: DryAirDensity_A
trajectory grid: { type: regular_gaussian, N: 12 }
trajectory filename: testdata/gauss_state_F12.nc
adjoint test tolerance: 1.e-12
```

Test groups (`vader_recipe_*`, `vader_vader_*`, `vader_planvariable_*`) verify NL correctness, adjoint consistency (dot-product test), and the planning algorithm.

**Inline-data recipe test** (PR #374, `test/vader/RecipeInline.h` + `TestRecipeInline.cc`): an NL-only test family where ingredient and expected-product values are defined directly in the YAML (`columns:` / `expected:` / `nonlinear test tolerance`) on a hard-coded grid, with a single column broadcast to all nodes, rather than read from a NetCDF reference file. Inputs live in `test/testinput/recipe_inline_*.yaml`. Use this for recipes that lack a versioned reference state.

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
