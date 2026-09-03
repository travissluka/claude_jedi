# VADER (The VAriable DErivation Repository)

> Last updated against commit `b28834d3` (2026-09-03). Run `cd bundle/vader && git log --oneline b28834d3..HEAD` to see what changed since.
>
> **Covers:** Vader, RecipeBase, DefaultCookbook, VaderParameters, planVariable algorithm, _A/_B/_C recipe variants, changeVar/changeVarTraj/changeVarTL/changeVarAD, AirTemperature, DryAirDensity, HydrostaticPressure, RelativeHumidity, MoistureControl, Met Office SVP lookup tables (`src/mo/`), DustBin1MassConcentration_A, DustBin2MassConcentration_A, eval_dust_bin_mass_concentration_nl, the dust 2-mode recipes and `eval_dust_2mode_variables`, the GSI-flavor `_B` cloud recipes, `util::for_each_column`, GSW OceanConversions, adjoint dot-product test pattern, adding a new recipe.

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
6. **Rollback on failure** (PR #413): before each top-level variable and before each candidate recipe attempt, a `PlanningState` (anonymous namespace in `vader.cc`) snapshots `plan`/`trajPlan` sizes plus `neededVars`, `ingredientVars`, and `trajectoryVars`; a failed attempt restores all five. Rollback is per-recipe-attempt, not just per-target, so a rejected recipe cannot leave stray intermediates or spurious variable-list entries behind for the next candidate — and a product that was planned as an intermediate of a since-failed target still survives if it was independently requested.

### DefaultCookbook (`src/vader/DefaultCookbook.h`)

Maps each output variable to a priority-ordered list of recipe names. VADER tries the first recipe, falls back to alternatives if ingredients are unavailable.

### Multiple Recipe Variants

Many variables have \_A, \_B, \_C variants using different inputs or linearization approaches:
- **AirTemperature\_A**: from potential temperature × exner function (has TL/AD)
- **AirTemperature\_B**: from virtual temperature and specific humidity (has TL/AD as of PR #417)
- **AirTemperature\_C**: from pressure and potential temperature (NL only)

This allows different models to use the variant matching their available state variables.

## Configuration Variables

VADER recipes may require external configuration parameters (passed via `VaderParameters` in YAML):
- **`nLevels`** — number of vertical levels
- **`ak`/`bk`** coefficients — hybrid sigma-pressure vertical coordinate arrays (define pressure at each level as `p = ak + bk * ps`)
- Physical constants defined in `src/vader/` and `src/mo/`: `Rd` (gas constant dry air), `Cp` (specific heat), `Lv` (latent heat of vaporization), `epsilon` (Rd/Rv ratio), `grav` (gravitational acceleration), `k_B` (Boltzmann)
- GLOMAP dust constants in `src/mo/constants.h` (used by DustBin recipes): `glomap_dust_density`, `sigma_acc`, `sigma_coarse`, `Dmin_bin1/Dmax_bin1`, `Dmin_bin2/Dmax_bin2`
- 6-bin dust constants in `src/mo/constants.h` (used by the dust 2-mode recipes, which route through a 6-bin intermediate): `volconst` (mass-to-number volume constant), `drep6c` (representative diameters of the 6 bins), `p1`/`p2` (fraction of CLASSIC bin 1 / bin 2 dust in each of the 6 bins, each summing to 1), `p1_scale`/`p2_scale` (chosen to preserve AOD between 2-bin and 6-bin dust, so mass is **not** conserved; set to 1 for mass conservation)

## Variable Naming Conventions

VADER follows JEDI naming standards (from jedi-docs conventions):
- **`wrt_dry_air`** / **`wrt_moist_air`** suffixes: mixing ratios can be expressed with respect to dry or moist air mass (e.g., `water_vapor_mixing_ratio_wrt_dry_air` vs `water_vapor_mixing_ratio_wrt_moist_air`)
- **`at_interface`** suffix: values at level interfaces (half-levels) rather than mid-levels
- **`at_surface`** / **`at_2m`** / **`at_10m`** suffixes: surface or near-surface quantities
- Recipe `_A`, `_B`, `_C` suffixes distinguish different formulas for the same output variable
- **`_percentage`** suffix: an input variable carried in non-standard units, converted to the standard (fraction) form by a dedicated unit-conversion recipe — e.g. `relative_humidity_at_2m_percentage` → `relative_humidity_at_2m` via `RelativeHumidityAt2m_A`

## Recipe Categories (~90+ recipes)

**Temperature** (6): AirTemperature (A/B/C), AirVirtualTemperature (A/B), AirPotentialTemperature (A/B). The two AirPotentialTemperature variants are different conventions, not interchangeable formulas: `_A` is the sigma-coordinate form `theta_sigma = T * (p0/ps)^kappa` off surface pressure (bounded near `T`, diverging from standard theta above the boundary layer), `_B` is standard meteorological theta `T * (p0/p)^kappa` off level pressure. `_A` uses `util::for_each_column` so the single-level `ps` broadcasts as `ps(0)` across the multi-level product.

**Pressure** (13): AirPressure (A/B), AirPressureAtInterface (A/B/C/D), AirPressureThickness, AirPressureExtendedUpByOne, HydrostaticExnerLevels, HydrostaticPressureLevels, LnAirPressure, LnAirPressureAtInterface, SurfaceAirPressure. `AirPressure_B` (→ `air_pressure`, mid-level) and `AirPressureAtInterface_D` (→ `air_pressure_levels`, interface) derive pressure directly from `air_pressure_at_surface` via hybrid-sigma `ak`/`bk` coefficients (`sigma_pressure_hybrid_coordinate_a/b_coefficient`): `ak[k] + bk[k]*ps` at interfaces, layer-averaged for mid-levels. This is a distinct ingredient path from the Phillips interface-based recipes (PR #356).

**Humidity** (9+): WaterVaporMixingRatio variants (dry/wet air, 2m), RelativeHumidity (A — special case, uses lookup tables from `src/mo/`; B — q/qsat fraction with full TL/AD, PR #332), RelativeHumidityAt2m_A, SaturationVaporPressure (A; B — Murphy-Koop 2005 liquid/ice, TL/AD), SaturationSpecificHumidity (A; B — exact `qsat = 0.622·es/(p − 0.378·es)`, TL/AD), LogDerivativeSaturationVaporPressure

**RH is a fraction, not a percentage** (PR #372): `relative_humidity`, `relative_humidity_at_2m`, and `total_relative_humidity` are now in fraction units (0-1), matching CCPP; the old "Warning! ... percents" comments in `src/mo/eval_relative_humidity.{h,cc}` are gone and the TL/AD dropped their `100.0` factors. `RelativeHumidityAt2m_A` (`src/vader/recipes/RelativeHumidityAt2m.h`, `_A.cc`) is the bridge recipe for percentage-unit input files: ingredient `relative_humidity_at_2m_percentage` → product `relative_humidity_at_2m`, divide by 100, full TL/AD, backed by `mo::eval_relative_humidity_at_2m_percentage_to_fraction_{nl,tl,ad}`. Matching MIO constants in `src/mo/constants.h` were rescaled to fraction units: `rHTBin` 5.0→0.05, `MaxRhRef` 150.0→1.5, `effectiveRNegative` 5.0→0.05 (`rHTLastBinLowerLimit` follows) — relevant if anything downstream hardcodes RH bin edges. The paired ufo change is `observation relative humidity units` (ufo #4221). Its ctest target is `vader_recipe_RelativeHumidityAt2M_A` (capital `M` in the target and YAML name, lowercase `m` in the recipe class — easy to mistype).

**Clouds** (8): CloudIceMixingRatio (dry/wet, 4 total), CloudLiquidWaterMixingRatio (dry/wet, 4 total)

**Geopotential** (6): GeopotentialHeight (A/B — B is fv3-jedi-compatible, PR #379), GeopotentialLevels (A), GeopotentialHeightLevels (A/B), GeopotentialHeightAtSurface, HeightAboveMeanSeaLevel (A, PR #381), HeightAboveMeanSeaLevelAtSurface. The `*AtInterface` recipes were renamed to `*Levels` (`GeopotentialAtInterface`→`GeopotentialLevels`, `GeopotentialHeightAtInterface`→`GeopotentialHeightLevels`) and the ingredient `surface_geopotential` was renamed to `geopotential_at_surface` (PR #355). `GeopotentialHeight_B` gained a `use empirical formula` YAML option (default `true`, PR #387): when `true` it applies the empirical compressibility correction as before; when `false` it skips `compressibilityFactor()` (treated as 1.0) and uses the standard hypsometric formula instead — set `false` to match older/non-empirical hypsometric conventions.

**Ozone** (1): MoleFractionOfOzoneInAir (A) → `mole_fraction_of_ozone_in_air` (PR #377)

**Density** (3): DryAirDensity, DryAirDensityLevelsMinusOne, AirDensityLevelsMinusOne

**Wind** (3): EastwardWindAt10m, NorthwardWindAt10m, WindReductionFactorAt10m

**Aerosol** (10): ParticulateMatter2p5 (2), SulfateMassFraction, RainMixingRatio, DustBin1MassConcentration_A, DustBin2MassConcentration_A (NL-only; LFRIC UKCA/GLOMAP 2-mode → CLASSIC 2-bin dust; products `mass_fraction_of_dust00{1,2}_in_air`; eval in `src/mo/eval_dust_2bin_mass_concentration.{h,cc}`), plus four **dust 2-mode** recipes running the opposite direction (CLASSIC 2-bin → UKCA/GLOMAP 2-mode, via a 6-bin intermediate), all with **full TL/AD**, eval in `src/mo/eval_dust_2mode_variables.{h,cc}`, ingredients drawn from `mass_fraction_of_dust00{1,2}_in_air`:
- `DustAccumulationModeMassFraction_A` → `mass_fraction_of_dust_accumulation_aerosol_particles_in_air` (bin 1 only)
- `DustCoarseModeMassFraction_A` → `mass_fraction_of_dust_coarse_aerosol_particles_in_air` (bins 1 and 2)
- `DustAccumulationModeNumberFraction_A` → `number_fraction_of_accumulation_aerosol_particles_in_air` (bin 1 only)
- `DustCoarseModeNumberFraction_A` → `number_fraction_of_coarse_aerosol_particles_in_air` (bins 1 and 2)

Like the CRTM-convention recipes, these register only via `RecipeMaker` and are absent from `DefaultCookbook.h`. Their tests live under `test/mo/testinput/`.

**Water totals** (5): TotalWater, TotalWaterMixingRatio (dry/wet), TotalRelativeHumidity (2)

**Ocean** (2, requires GSW): SeaWaterTemperature, SeaWaterPotentialTemperature

**CRTM convention** (~55, `src/vader/betaNames_CRTMRecipes/`, PRs #332 + #382): recipes producing CRTM-convention variable names for the radiance forward operator — CloudLiquidWater/CloudLiquidIce, Graupel, Hail, RainWater, SnowWater, MassContentOf{CloudIce,CloudLiquidWater,Graupel,Hail,Rain,Snow}InAtmosphereLayer, EffectiveRadiusOf{CloudIce,CloudLiquidWater,Graupel,Hail,Rain,Snow}Particle, SkinTemperatureAtSurface (renamed from SkinTemperature in #382; + WhereLand/Sea/Ice/Snow area-fraction blends), {Ice,Land,Water}AreaFraction (with `_B` variants), SurfaceSnowAreaFraction (+ `_B`), {Eastward,Northward}WindAtSurface, WindSpeedAtSurface, WindFromDirectionAtSurface, TropopausePressure. PR #382 (CRTM Surface Variable Transforms) added a batch of surface recipes — WindSpeedAt10m (`_A`/`_B`), WindToDirectionAtSurface, AverageSurfaceTemperatureWithinFieldOfView — plus a new `GSI_Specific/` subdirectory of GSI-convention surface recipes: GsiSnowWaterEquivalent, GsiSurfaceTypeIndex, LandTypeIndexIgbp, LandTypeIndexNpoess, LeafAreaIndex, SoilTemperature, SoilType, SurfaceSnowThickness, VegetationAreaFraction, VegetationTypeIndex, VolumeFractionOfCondensedWaterInSoil. **TL/AD is no longer uniformly absent**: SkinTemperatureAtSurface*, {Ice,Land,Water}AreaFraction, SurfaceSnowAreaFraction, WindFrom/ToDirectionAtSurface, WindSpeedAtSurface, and AverageSurfaceTemperatureWithinFieldOfView now carry TL/AD; the `GSI_Specific/` recipes remain NL-only `_A`. These register only via `RecipeMaker` (factory) — `DefaultCookbook.h` is unchanged, so they are factory-available but **not** wired into the default cookbook.

`GSI_Specific/` is not surface-only: it also holds four NL-only `_B` cloud recipes that reproduce the fv3-jedi/GSI `crtm_ade_efr` calculation bit-for-bit, all applying a `min_qx = 1e-8` mixing-ratio threshold (cells below it are set to 0):
- `EffectiveRadiusOfCloudLiquidWaterParticle_B` (from `air_temperature` and `cloud_liquid_water`): `max(1, 5 + 5*min(1, (tice - T)*0.05))`
- `EffectiveRadiusOfCloudIceParticle_B` (from `air_temperature`, `cloud_liquid_ice`, `air_pressure`, `water_vapor_mixing_ratio_wrt_moist_air`): a four-band `T - tice` power law on `qi * rho_air`, floored at 5
- `MassContentOfCloudLiquidWaterInAtmosphereLayer_B` / `MassContentOfCloudIceInAtmosphereLayer_B` (from the mixing ratio, `air_pressure_thickness`, and `slmsk`): both take a **`mask over`** YAML option (`none` default, `land` zeros where `slmsk != 0`, `sea` zeros where `slmsk == 0`), mirroring the fv3-jedi `use_mask` option and its `seamask = slmsk == 0` rule

All `EffectiveRadiusOf*_A` recipes output **microns**, not metres (their header doc comments still say "Output units: m").

### TL/AD Support

Most temperature, pressure, density, and geopotential `_A` variants have TL/AD. Humidity and cloud recipes are generally NL-only. `RelativeHumidity_A` is notable for using Met Office saturation vapor pressure lookup tables (`src/mo/`) rather than simple formulas, with full TL/AD support. `AirPressureThickness_A` gained full TL/AD support in PR #370. `AirPressure_A`, `AirPressure_B`, and `AirPressureAtInterface_D` have full TL/AD (PR #356) — `AirPressure_A` is no longer NL-only Phillips. `AirTemperature_B` gained TL/AD in PR #417, linearizing `T = Tv / (1 + epsilon_star*q)` with `epsilon_star = 1/epsilon - 1` and declaring `trajectoryVars() = {virtual_temperature, water_vapor_mixing_ratio_wrt_moist_air}`, so the whole temperature family has TL/AD except `AirTemperature_C`.

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
- `util::for_each_column()` when a recipe mixes single-level and multi-level fields: the lambda receives per-column views, so a surface field is indexed `field_col(0)` while the product loops over `col.shape(0)` levels
- AD always accumulates (`+=`) into ingredient adjoints, then zeros the product adjoint
- Trajectory values are stored during `changeVarTraj()` for use by TL/AD

## Source Layout

| Directory | Purpose |
|-----------|---------|
| `src/vader/` | Core: `vader.h/cc`, `RecipeBase.h/cc`, `DefaultCookbook.h`, `VaderParameters.h` |
| `src/vader/recipes/` | Core recipe implementations (~50 headers + .cc files) |
| `src/vader/betaNames_CRTMRecipes/` | ~55 recipes producing CRTM-convention variable names (PRs #332, #382), incl. a `GSI_Specific/` subfolder of NL-only GSI-convention surface and `_B` cloud recipes; several surface recipes have TL/AD; `RecipeMaker`-registered only, not in `DefaultCookbook.h` (see CRTM convention category) |
| `src/mo/` | Met Office integration: lookup tables (SVP), eval functions, constants, Fortran I/O |
| `src/mo/recipes/` | Met Office-derived recipes (e.g., `DustBin{1,2}MassConcentration`, `Dust{Accumulation,Coarse}Mode{Mass,Number}Fraction`) |
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

**Inline-data recipe test** (PR #374, `test/vader/RecipeInline.h` + `TestRecipeInline.cc`): an NL-only test family where ingredient and expected-product values are defined directly in the YAML (`columns:` / `expected:` / `nonlinear test tolerance`) on a hard-coded grid, with a single column broadcast to all nodes, rather than read from a NetCDF reference file. Inputs live in `test/testinput/recipe_inline_*.yaml`. Use this for recipes that lack a versioned reference state. `AirTemperature_B` now has both an inline NL target (`vader_recipe_inline_AirTemperature_B`) and a full-Vader target (`vader_vader_AirTemperature_B`), the latter exercising its new TL/AD. PR #418 compiles `test/vader/TestUtils.cc` once as the `vader_test_utils` OBJECT library and shares it via `OBJECTS` across `test_recipe.x`, `test_vader.x`, and `test_recipe_inline.x` — relevant when adding a new test executable.

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
