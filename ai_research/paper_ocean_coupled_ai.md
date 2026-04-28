# Distillations: AI / ML in Ocean and Coupled Atm–Ocean–Ice DA

Target audience: internal notes feeding the JCSDA AI strategy memo.
Rationale: the strategy's author (Travis Sluka) has ocean + coupled DA as a
personal focus; this domain is also the single clearest defensible niche
against the atmosphere-dominated AI-weather frontier.

**Headline observation:** Every frontier AI-weather model (GraphCast,
GenCast, Pangu, AIFS, Aurora 0.25°) is fundamentally an *atmospheric* model.
Ocean and sea-ice coverage is shallow. Coupled atm–ocean–ice DA is *owned by
no AI-weather lab*. The academic ocean-ML community is strong but scattered
across half a dozen groups with no unifying framework. JCSDA + SOCA + the
coupling repo is one of the few organizations globally with the pieces to
assemble a coupled AI-DA story.

---

## Active prior art — ocean DA and ML

### Sea-ice DA and ML — the most developed sub-domain

- **Gregory et al. (2023)** *JAMES* — "Deep Learning of Systematic Sea Ice
  Model Errors From Data Assimilation Increments."
  [DOI](https://agupubs.onlinelibrary.wiley.com/doi/abs/10.1029/2023MS003757).
  Trains a U-Net to predict sea-ice model errors from analysis increments
  derived from real satellite DA. **Exactly the "learn model error from
  increments" template** proposed in the strategy memo §4.2. A SOCA-native
  analog is the obvious follow-on.
- **Gregory et al. (2025)** *Science Advances* — "Advancing global sea ice
  prediction capabilities using a fully coupled climate model with integrated
  machine learning."
  [Science Advances](https://www.science.org/doi/10.1126/sciadv.ady8957).
  Embeds ML inference into a fully coupled climate model for online sea-ice
  bias correction. >2× error reduction in 4–6 month lead forecasts of
  Antarctic winter sea ice extent.
- **Andersson et al. (2021)** *Nat. Commun.* "Seasonal Arctic sea ice
  forecasting with probabilistic deep learning" — IceNet. 25 km, 6-month
  lead, outperforms physics models on extreme summer events.
  [Nature](https://www.nature.com/articles/s41467-021-25257-4).
- **ECMWF Newsletter 177** (2023) — "Combining machine learning and data
  assimilation to estimate sea ice concentration."
  [ECMWF](https://www.ecmwf.int/en/newsletter/177/earth-system-science/combining-machine-learning-and-data-assimilation-estimate).
  **Jointly learns sea-ice state and empirical sea-ice surface emissivity
  model** inside a DA framework. Directly transferable to JEDI's UFO ice
  emissivity problem.
- **"Improving short-term sea ice concentration forecasts using deep
  learning"** — Palerme et al. (2024), *The Cryosphere* 18.
  [TC](https://tc.copernicus.org/articles/18/2161/2024/). DL forecasts
  outperform TOPAZ4 by 41% RMSE.
- **npj Clim Atmos Sci (2025)** — "Assimilating summer sea ice thickness
  enhances predictions of Arctic sea ice and surrounding atmosphere within
  two months."
  [npj](https://www.nature.com/articles/s41612-025-01050-8). Establishes
  that sea-ice thickness DA has a 2-month atmospheric footprint — coupled
  DA relevance.

### Physical ocean — SSH, eddies, circulation

- **Agabin & Prochaska (2024)** — NN for short-term SSH prediction from
  SST.
  [Cambridge](https://www.cambridge.org/core/journals/environmental-data-science/article/neural-network-approaches-for-sea-surface-height-predictability-using-sea-surface-temperature/B63BEA76AAEB5218C627B1E1F1FDF21E).
- **"Forecasting the eddying ocean with a deep neural network"** — Nguyen
  et al. (2025) *Nat. Commun.*
  [Nature](https://www.nature.com/articles/s41467-025-57389-2).
  Eddy-resolving global ocean forecast DNN with bulk air-sea fluxes built in.
- **George et al. (2021)** *Nat. Commun.* — "Deep learning to infer eddy
  heat fluxes from sea surface height."
  [Nature](https://www.nature.com/articles/s41467-020-20779-9).
- **StrAss-PINN** (Cavalcanti et al., arXiv:2503.19160, 2025) —
  "Deep learning in the abyss: a stratified Physics Informed Neural
  Network for data assimilation." Separate NN per ocean layer with trained
  inter-layer interactions. Ocean flow reconstruction.
- **"A Framework for Hybrid Physics-AI Coupled Ocean Models"** —
  arXiv:2510.22676 (2025).
- **"Applications of deep learning in physical oceanography"** — Liu et al.,
  *Frontiers in Marine Science* (2024). Comprehensive review.
  [Frontiers](https://www.frontiersin.org/journals/marine-science/articles/10.3389/fmars.2024.1396322/full).

### Coupled climate emulators

- **SamudrACE** — Watt-Meyer et al., arXiv:2509.12490 (2025). Coupled global
  climate model emulator with 3D atmosphere and ocean components.
- **Aurora 0.25° Wave** (Microsoft, *Nature* 2025). Fine-tuned on HRES-WAM.
  Matches or beats HRES-WAM on 91% of variables at 3-day lead; 96%
  competitive overall.
  [microsoft/aurora](https://github.com/microsoft/aurora).
- **"Coupled Seasonal Data Assimilation of Sea Ice, Ocean, and Atmospheric
  Dynamics over the Last Millennium"** — arXiv:2501.14130 (2025). Coupled
  paleoclimate DA; relevant methodology for seasonal-to-interannual
  coupled DA.

### Ocean biogeochemistry and color

- **BGC-UNet / Black Sea emulator** — Frontiers in Marine Science (2026).
  [Frontiers](https://www.frontiersin.org/journals/marine-science/articles/10.3389/fmars.2026.1760162/full).
- **Neural emulator of surface chlorophyll in ESM** — Progress in
  Oceanography (2024).
- **WOMBAT ML surrogate** — optimization of ocean biogeochemistry model
  with ML surrogate.
- **Hybrid ML DA for marine BGC** — arXiv:2504.05218 (2025). Directly
  addresses BGC DA via ML.
- **Mediterranean chlorophyll vertical profile inference** — NN using
  altimetry + surface chlorophyll + SST.

---

## OceanPredict and community governance

- **OceanPredict Data Assimilation Task Team (DA-TT)** — international
  coordinating group for operational ocean DA, GOFS, Mercator, BlueLink,
  PSY4, etc. Meetings publish open abstracts tracking the ML-DA frontier.
- **Copernicus Marine Service (CMEMS)** — primary European operational
  ocean product pipeline; increasingly ML-augmented (data-interpolation,
  gap-filling, correction).

---

## Where JCSDA / SOCA fits

### Unique capabilities

1. **JEDI + SOCA is among the few operational-quality coupled atm-ocean-ice
   DA frameworks available as open-source software** (alongside GDAS-JEDI
   inside NOAA, Mercator's internal stack, and ECMWF's emerging coupled
   IFS). The `coupling/` repo with `oops::GeometryCoupled` is a real
   enabler.
2. **SABER's block-chain covariance + TorchBalance** already demonstrates
   atmosphere–ocean–ice cross-variable ML balance. The TorchBalance pattern
   is literally the world's most mature publicly-documented learned
   covariance operator spanning three fluid components.
3. **Ocean color / biogeochemistry DA via OASIM** — the Year-1 pilot in
   the main strategy memo directly lives in this domain and has no direct
   competitor at scale.

### Unique gaps

- No equivalent of IceNet or Gregory's sea-ice-bias-from-increments work
  currently runs in SOCA production.
- No learned air-sea flux correction (a key lever for coupled forecasts).
- No learned H-operator for ocean color beyond the proposed OASIM work.
- No torch-compatible ocean subgrid parameterization (equivalent of
  NeuralGCM subgrid for atmosphere).

### Suggested concrete ocean/coupled deliverables to emphasize in the memo

- **Sea-ice model-error correction (SOCA analog of Gregory 2023).** Train a
  U-Net on SOCA DA increments to learn systematic model errors in sea-ice
  concentration / thickness / snow depth. Deploy as an online correction.
- **Learned sea-ice emissivity operator.** The ECMWF Newsletter 177 template
  is directly adaptable to UFO — learn emissivity inside the DA cost
  function from microwave radiances.
- **OASIM Mode-A/Mode-B/Enzyme bake-off.** Already the proposed §6.4. Gets
  ocean color into 4D-Var for the first time.
- **Air-sea flux learned correction.** Fluxes between fv3-jedi and soca
  pass through the coupling layer; a learned correction at that boundary
  has immediate impact on both atmosphere and ocean analyses.
- **Coupled ensemble AI-DA evaluation.** Fine-tune or adapt Aurora 0.25°
  Wave + GraphCast / AIFS as the atmosphere → soca ensemble member
  generator; cycle a coupled DA experiment. Nobody has done this with an
  operational coupled DA framework.

---

## Cross-cutting observations

1. **Sea-ice is the best-developed ML-DA sub-domain in the ocean world.**
   Gregory, IceNet, ECMWF Newsletter 177, and 2024–2026 TC papers collectively
   constitute a strong prior-art pattern. JCSDA's contribution here should
   focus on operationalizing these patterns inside SOCA.
2. **Coupled atm-ocean-ice AI-DA is genuinely unclaimed territory.** The
   AI-weather frontier stops at the ocean surface for most labs. Aurora
   Wave is the biggest exception, and it's a decoupled wave model, not a
   fully coupled DA system.
3. **OceanPredict / CMEMS / BlueLink / Mercator are the natural international
   collaborators.** None of them have a JEDI-equivalent; SOCA is more
   portable.
4. **The US Navy is the natural domestic sponsor** for coupled ocean–atm
   AI-DA (see competitive_landscape.md § ONR).
