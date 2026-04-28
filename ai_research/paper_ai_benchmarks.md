# Distillations: Community benchmarks for AI weather and climate forecasting

Target audience: internal notes feeding the JCSDA AI strategy memo.
Purpose: map the existing benchmark landscape for AI-based weather and
climate prediction, identify what those benchmarks measure well, and
identify the one thing every public benchmark fails to deliver — true
observation-space verification — which is a defensible strategic
opening for JCSDA.

**Headline observation.** Every high-profile AI-weather benchmark of the
past three years (WeatherBench 2, ChaosBench, ExtremeWeatherBench,
ClimateBench, OceanBench, TCBench, Earth2MIP) scores models against
reanalysis (ERA5, GLORYS12) or against a dynamical reference (IFS HRES,
GFS, HRRR). None verifies AI forecasts against the raw observations the
observing system actually produces at inference time. JEDI's UFO operator
library is the only mature, multi-instrument H(x) stack in the open-source
world that could close that gap.

---

## 1. WeatherBench and WeatherBench 2

The de-facto standard for deterministic and probabilistic global
medium-range AI forecasts.

- **WeatherBench 1** (Rasp et al. 2020). First open benchmark for
  data-driven global weather. 5.625° ERA5, 3 day / 5 day lead, z500 and
  t850 as headline variables.
- **WeatherBench 2** (Rasp et al., *JAMES* 2024). Google Research +
  ECMWF + DeepMind.
  [paper](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2023MS004019) ·
  [arXiv:2308.15560](https://arxiv.org/abs/2308.15560) ·
  [site](https://sites.research.google/gr/weatherbench/) ·
  [GitHub](https://github.com/google-research/weatherbench2) ·
  [docs](https://weatherbench2.readthedocs.io/).

| WB2 design choice | Value |
|---|---|
| Ground truth | ERA5, downsampled to 0.25° and 1.5° |
| Lead times | 6 h – 15 days, 6-hourly |
| Pressure levels | 13 (50, 100, 150, 200, 250, 300, 400, 500, 600, 700, 850, 925, 1000 hPa) |
| Headline variables | z500, t850, t2m, u/v (10 m and 850 hPa), mslp, total precip (24 h) |
| Deterministic metrics | RMSE, ACC, bias, stable equitable error in prob. space (SEEPS) for precip |
| Probabilistic metrics | CRPS, spread-skill ratio, rank histogram, Brier, reliability |
| Baselines | IFS HRES, IFS ENS, climatology, persistence, and registered AI models (GraphCast, Pangu, FourCastNet, GenCast, AIFS, …) |

**Known gaps** (acknowledged in the WB2 paper itself):
- **ERA5-referenced only.** WB2 verifies against a reanalysis, which is
  itself a 4D-Var analysis. AI models trained on ERA5 and scored against
  ERA5 test the model's ability to reproduce ERA5, not its ability to
  match observations. WB2 explicitly notes this as a known limitation.
- **No direct observation verification.** Surface stations (ISD) are
  included only as a secondary check on t2m, not as a primary track.
- **Atmosphere only.** No ocean, sea-ice, wave, land, or coupled variables.
- **Deterministic gridded variables dominate.** Extreme events, spatial
  structure metrics (e.g. FSS, object-based), and tropical cyclones are
  not headline tracks.

---

## 2. ChaosBench — subseasonal-to-seasonal

**Nathaniel et al.** *NeurIPS 2024 D&B Track.*
[arXiv:2402.00712](https://arxiv.org/abs/2402.00712) ·
[GitHub](https://github.com/leap-stc/ChaosBench) ·
[site](https://leap-stc.github.io/ChaosBench).

- Extends predictability horizon to **45 days** (S2S range).
- ~460 k frames, **60 variable-channels**, 45-year span. Adds ocean,
  sea-ice, and land reanalysis alongside ERA5 atmosphere — unusual for the
  AI benchmark space.
- Operational baselines from **four national agencies** (ECMWF, NCEP,
  UKMO, CMA S2S archive) alongside ViT/ClimaX, Pangu, GraphCast,
  FourCastNetV2.
- Physics-based constraints (energy, mass) as optional loss terms.
- **Headline finding**: AI models trained for weather scale collapse to
  unskilled climatology in the S2S regime. Benchmark designed specifically
  to expose that failure mode.

**Gap**: Still reanalysis-referenced. Still gridded only. No coupled DA
cycling, no real observation ingestion.

---

## 3. ExtremeWeatherBench (EWB) and related extreme-event benchmarks

- **ExtremeWeatherBench** (Brightband, NOAA GSL, community).
  [GitHub](https://github.com/brightbandtech/ExtremeWeatherBench) ·
  [AMS 2025 abstract](https://ui.adsabs.harvard.edu/abs/2025AMS...10551220M/abstract).
  Community-curated list of high-impact events (heatwaves, freezes,
  tropical cyclones, atmospheric rivers, severe storms). Event-specific
  metrics: TC intensity, rapid intensification, landfall time/place,
  associated rainfall; heatwave onset, amplitude, duration.
- **TCBench** — Tropical Cyclone Benchmark at Global Scale.
  [arXiv:2601.23268](https://arxiv.org/html/2601.23268v1). Uses IBTrACS as
  ground truth; conditions on initial vortex; scores track and intensity
  for AIFS, GraphCast, Pangu, FourCastNet v2, GenCast and TIGGE dynamical
  models. Finding: neural models skilful on tracks, poor on intensity
  without post-processing.
- **ExEBench** — Extreme Earth Events benchmark.
  [arXiv:2505.08529](https://arxiv.org/html/2505.08529v1). Seven categories:
  floods, wildfires, storms, TCs, extreme precipitation, heatwaves,
  cold waves. Foundation-model oriented.
- **Atmospheric River benchmarks** — Davis et al. 2026 GRL
  [DOI](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2025GL117609);
  *Comm. Earth Environ.* 2025
  [DOI](https://www.nature.com/articles/s43247-025-02823-y). HRES beats AI
  on AR detection at days 1–4; FuXi and PanguWeather catch up later;
  Aurora strong on RMSE but weak on AR detection — nice example of why
  variable-level RMSE misses the physics.
- **Schär et al. 2025** *numerical models outperform AI on record-breaking
  extremes* ([arXiv:2508.15724](https://arxiv.org/html/2508.15724v1)). AI
  models systematically underestimate record-breaking heat, cold, and wind.

**Gap**: Event catalogs are ERA5- or IBTrACS-referenced. The "did the AI
see the right brightness temperature during the heatwave?" question is
not asked anywhere.

---

## 4. Other relevant benchmarks

| Benchmark | Scope | Reference data | URL |
|---|---|---|---|
| **ClimateBench v1.0** (Watson-Parris et al. 2022) | CMIP6 / AerChemMIP emulator; annual T, DTR, precip vs. forcing | NorESM2 simulations (SSP scenarios) | [JAMES](https://agupubs.onlinelibrary.wiley.com/doi/abs/10.1029/2021MS002954) |
| **ClimateLearn** (Nguyen et al., NeurIPS 2023 D&B) | PyTorch library: ERA5, CMIP6, PRISM pipelines + models | ERA5, CMIP6 | [arXiv:2307.01909](https://arxiv.org/abs/2307.01909) · [GitHub](https://github.com/aditya-grover/climate-learn) |
| **NVIDIA Earth2Studio / Earth2MIP** | Inference + evaluation toolkit; S2S ensemble scoring; intercomparison harness | ERA5, configurable | [GitHub](https://github.com/NVIDIA/earth2studio) · [Earth2MIP](https://github.com/NVIDIA/earth2mip) |
| **HRRRCast evaluation set** (NOAA GSL) | Regional convective-scale AI emulator vs. HRRR; reflectivity, precip, storm objects | HRRR analyses + MRMS radar | [GSL news](https://gsl.noaa.gov/news/hrrrcast-version-3-new-release-of-noaas-experimental-regional-ai-forecast-model) |
| **OceanBench** (Mercator, NeurIPS 2025) | Global ocean AI forecasting; first benchmark with Model-to-Observations track | GLORYS12 + GLO12 analysis + CLASS-4 obs | [press](https://www.mercator-ocean.eu/press-release/mercator-ocean-international-makes-ai-ocean-forecasting-operational-with-glonet-validated-by-oceanbench-at-neurips-2025/) · [GitHub](https://github.com/mercator-ocean/oceanbench) |
| **OceanForecastBench** | Open, reanalysis-trained ocean ML benchmark; SLA, SST, T, S, currents | GLORYS12 (13 TB) | [arXiv:2511.18732](https://arxiv.org/html/2511.18732v1) |
| **WxC-Bench** (NASA IMPACT) | Multi-modal downstream tasks: aviation turbulence, TC intensity, gravity wave param, NL reports | Obs, MERRA-2, reports | [*Sci. Data* 2026](https://www.nature.com/articles/s41597-026-06839-7) · [GitHub](https://github.com/NASA-IMPACT/WxC-Bench) |

A proposed "FAIR global benchmark" does not appear to exist under that
name; claims to FAIR principles are made by most of the above, but no
single "FAIR-Bench" has emerged.

---

## 5. The observation-space verification gap — JCSDA's opening

Every benchmark in sections 1–4 shares a single structural limitation:
**the reference is a reanalysis, an analysis, or a best-track product
produced by a DA system.** This has three consequences:

1. **Self-referential scoring.** When an AI model is trained on ERA5
   and verified on ERA5, both its training target and its verification
   target are 4D-Var outputs of the same family. Errors in the reanalysis
   (known to be O(0.5–1 K) in the tropical mid-troposphere and much
   larger in the stratosphere and at mesoscale) are invisible to the
   benchmark.
2. **No instrument generalization test.** When a new instrument launches
   (MWS on MetOp-SG-A, AMSR3 on GOSAT-GW, CubeSat microwave constellations),
   benchmarks score whatever proxy ERA5 contains — not whether the AI
   forecast gets the brightness temperature right at the instrument's
   actual channel frequencies and weighting functions.
3. **No forward-operator-aware metric.** "RMSE of 500 hPa geopotential
   height" does not answer "would this forecast, run through CRTM,
   produce the correct IASI radiance?" The latter is the metric a DA
   center actually uses internally.

**What only JEDI can offer.** UFO contains ~30+ observation operators
(radiance via CRTM/RTTOV, GNSS-RO bending angle, radar reflectivity,
altimetry, ADT, sea-ice concentration, aerosol AOD, ocean color,
conventional met), ~96 obsfunctions, QC filters, and 4 R-matrix types,
all model-agnostic and all driven by YAML. A benchmark that does
`AI_forecast → UFO H(x) → compare to raw obs` would be the first
observation-space benchmark in the community. It would directly surface
the errors that RMSE-vs-ERA5 hides.

Concretely, the metrics JEDI can produce that no benchmark currently
offers:

- **Brightness-temperature RMS** by satellite, instrument, and channel
  (ATMS, IASI, CrIS, AMSUA, SEVIRI, ABI), O−B and O−A against AI
  forecasts.
- **GNSS-RO bending-angle RMS** at tropopause levels where ERA5 is
  weakest.
- **Altimetry SSH and SWH RMS** against Jason-3, Sentinel-6, SARAL,
  SWOT.
- **Sea-ice concentration RMS** against AMSR2, SSMIS, passive-microwave
  retrievals and emissivity-consistent forward models.
- **Per-observation FSOI** for AI forecasts using a cycled DA
  companion — the only way to tell which satellites an AI model "uses"
  implicitly and where it is blind.
- **New-instrument generalization**: score AI models on instruments they
  never saw in training, using UFO's plug-in H(x). DOP systems structurally
  cannot do this without retraining.

---

## 6. Verification for coupled and ocean AI models

The ocean half of the AI-weather frontier is younger and more fragmented.

- **Aurora 0.25° Wave** (Microsoft, *Nature* 2025). Fine-tuned on
  HRES-WAM. Matches or beats HRES-WAM on 86–91% of wave variables at
  3-day lead. Air-quality, cyclone-track, and high-resolution atmosphere
  also evaluated — 74%, 100%, and 92% of targets respectively.
  [Nature](https://www.nature.com/articles/s41586-025-09005-y) ·
  [GitHub](https://github.com/microsoft/aurora). Reference is HRES-WAM
  (another DA/NWP product), not buoy wave spectra.
- **SamudrACE** (Watt-Meyer et al. 2025, Ai2 + NYU + Princeton +
  M2LInES + GFDL). Coupled 3D atmosphere (ACE2) + ocean (Samudra) +
  sea-ice emulator; 145 2D fields, centuries-long stable simulations,
  800 years/day on one H100. Reproduces ENSO — component emulators
  cannot.
  [arXiv:2509.12490](https://arxiv.org/abs/2509.12490) ·
  [Ai2 blog](https://allenai.org/blog/samudrace) · trained against GFDL
  CM4, not observations.
- **FuXi-Ocean / FuXi-ONS** (Fudan 2025). Eddy-resolving 1/12°
  sub-daily ocean forecast; global 1° ensemble S2S ocean. Verified
  against GLORYS12 reanalysis.
  [arXiv:2506.03210](https://arxiv.org/html/2506.03210) ·
  [arXiv:2603.19591](https://arxiv.org/html/2603.19591).
- **GLONET / XiHe / Wenhai** — AI ocean emulators scored by OceanBench
  against GLORYS12, GLO12 analysis, and — uniquely — **CLASS-4
  in-situ observations** via Mercator's intercomparison track. This is
  the closest existing analog to what JCSDA should build for atmosphere
  + coupled.
- **What's missing**: no coupled atm–ocean–ice AI-DA benchmark exists.
  No AI ocean benchmark includes satellite altimetry radiance-equivalent
  forward operators (SSH via DOT, SWOT KaRIn), sea-ice passive-microwave
  brightness-temperature verification, or ocean-color forward operators.
  SOCA + UFO + OASIM could produce all three.

---

## 7. Strategic implications for JCSDA

1. **Position JEDI as the evaluation substrate, not a competitor to
   WeatherBench.** The world does not need another ERA5-vs-ERA5
   leaderboard. The world needs **one** observation-space verification
   service, and JEDI's H(x)+QC+bias-correction stack is uniquely suited
   to provide it.
2. **Ship a UFO-driven observation-space verification package.**
   Concrete MVP: a `jedi-eval` tool that takes an AI forecast
   (GraphCast, AIFS, Pangu, Aurora output on a standard grid), runs it
   through UFO against a held-out observation window, and emits
   per-instrument O−F statistics, FSOI, and generalization metrics for
   instruments the AI never saw during training. This alone would be a
   defining community contribution.
3. **Build a coupled ocean–atm benchmark dataset.** SOCA + fv3-jedi +
   coupling + UFO together produce everything OceanBench's Model-to-
   Observations track wants, plus atmosphere. Partner with Mercator on
   the coupled extension; they own the ocean half, JCSDA owns the
   atmosphere half, and no one yet owns the coupled half.
4. **Extreme-event obs-impact benchmark.** Use FSOI within a JEDI cycled
   DA on AI-forecast backgrounds to answer *which observations matter
   for extreme-event skill* — a question EWB asks but cannot answer
   without an adjoint.
5. **New-instrument generalization benchmark.** The single benchmark DOP
   architectures structurally cannot do: take a sensor launched after
   the AI model's training cutoff (e.g. SWOT, MWS, future CubeSat
   constellations), plug its UFO operator into the evaluation harness,
   and measure how well each AI model's forecast matches that new
   instrument. This is an asymmetric advantage for a plug-in DA
   framework.

---

## One-line for the memo

*No public AI-weather benchmark verifies against raw observations at
inference time; JEDI's UFO+CRTM+SOCA stack is the only open-source system
that could, and observation-space verification is the evaluation-layer
niche JCSDA should claim before someone else does.*
