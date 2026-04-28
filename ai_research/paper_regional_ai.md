# Distillations: Regional and convection-allowing AI weather models and DA

Target audience: internal notes feeding the JCSDA AI strategy memo.
Purpose: establish that regional and convection-allowing scales are where
the DOP / global-AI critique of DA is structurally weakest, where NOAA's
HRRR and RRFS operational territory lives, and therefore where JEDI's
near-term relevance is strongest. Global AI weather (GraphCast, AIFS,
Aurora) and DOP (GraphDOP, Aardvark, FuXi Weather) get the headlines, but
the regional/storm-scale ecosystem is a fundamentally different problem —
one in which DA, radar, and sub-hourly cycling are first-class.

See `paper_ai_dop.md` for the DOP argument and `paper_foundation_weather_models.md`
for the global-AI landscape.

---

## 1. StormCast — NVIDIA's convection-allowing emulator

**StormCast** (Pathak et al., NVIDIA, 2024) is a generative diffusion
model that emulates NOAA's 3-km HRRR. It autoregressively predicts 99
state variables at kilometer scale on a 1-hour timestep, conditioned on
26 synoptic variables from a coarser outer forecast. Trained on ~3.5
years of HRRR analyses over the central US, it produces physically
realistic moist updrafts, cold pools, and convective cluster evolution.
Reported composite-reflectivity skill at 1–6 h lead is competitive with,
and in some regimes up to ~10% better than, the operational HRRR.

- arXiv:2408.10958 (Aug 2024). [arxiv.org/abs/2408.10958](https://arxiv.org/abs/2408.10958)
- NVIDIA blog: [blogs.nvidia.com/blog/stormcast-generative-ai-weather-prediction](https://blogs.nvidia.com/blog/stormcast-generative-ai-weather-prediction/)
- PhysicsNeMo reference: [docs.nvidia.com/physicsnemo/.../stormcast](https://docs.nvidia.com/physicsnemo/25.11/physicsnemo/examples/weather/stormcast/README.html)

Note: StormCast is a **forecast-model emulator**, not a DA system. It
ingests an HRRR analysis (produced by GSI/RRFS-DA today, JEDI tomorrow)
as initial condition. Without a DA-produced analysis, StormCast has
nothing to start from. This is the same pattern as AIFS/GraphCast at
global scale: the AI replaces integration, not assimilation.

---

## 2. HRRRCast and Project EAGLE — NOAA's regional AI push

**HRRRCast** (Chhabra et al., NOAA GSL, 2025) is NOAA's first in-house
regional AI forecast system. Two architectures: ResHRRR (ResNet +
squeeze-and-excitation + FiLM) and GraphHRRR (GNN), both trained on HRRR
analyses, with a DDIM-based probabilistic variant. V3 (March 2026)
matches HRRR's 3-km resolution and 20 vertical levels. Reported to match
or beat experimental RRFS configurations on grid-, neighborhood-, and
object-based storm metrics. 2–3 orders of magnitude faster than the
operational HRRR.

- arXiv:2507.05658. [arxiv.org/abs/2507.05658](https://arxiv.org/abs/2507.05658)
- GSL announcement (V3, Mar 2026): [gsl.noaa.gov/news/hrrrcast-version-3](https://gsl.noaa.gov/news/hrrrcast-version-3-new-release-of-noaas-experimental-regional-ai-forecast-model)
- GSL original (Jul 2025): [gsl.noaa.gov/news/hrrr-cast-unleashes-noaas-ai-weather-forecasting](https://gsl.noaa.gov/news/hrrr-cast-unleashes-noaas-ai-weather-forecasting)

**Project EAGLE** (Experimental AI Global and Limited-area Ensemble,
NOAA EPIC, 2024–) is the umbrella program that now includes AIGFS,
AIGEFS, HGEFS at global scale, and HRRRCast plus future CONUS-wide
storm-resolving and nested AI models at regional scale. HRRRCast is the
LAM component.

- EPIC overview: [epic.noaa.gov/ai/eagle-overview](https://www.epic.noaa.gov/ai/eagle-overview/)
- EPIC on regional EAGLE: [epic.noaa.gov/noaa-project-eagle-to-accelerate-ai-weather-prediction-advances-for-the-united-states](https://epic.noaa.gov/noaa-project-eagle-to-accelerate-ai-weather-prediction-advances-for-the-united-states/)

EAGLE explicitly calls out "CONUS-wide, storm-resolving, nested, and
coupled" future components — all of which require initial conditions
that today come from GSI and tomorrow come from JEDI (RRFS-JEDI,
MPAS-JEDI, GDAS-JEDI).

---

## 3. Regional modes of global models — ECMWF, MET Norway, stretched grids

ECMWF's **AIFS v1.1** (arXiv:2509.18994, 2025) adds a stretched-grid
regional mode jointly developed with MET Norway, producing ~2.5 km
forecasts over the Nordic "MEPS" domain while keeping a single global
model. MET Norway's **Neural-LAM** (arXiv:2309.17370, Oskarsson et al.
2023) is a stand-alone GNN LAM trained on MEPS analyses; a diffusion
variant (**Diffusion-LAM**, arXiv:2502.07532, 2025) produces
probabilistic forecasts at LAM scale. ECMWF's AIFS blog names this
family as the path to "data-driven regional modeling."

- AIFS 1.1 update: [arxiv.org/abs/2509.18994](https://arxiv.org/html/2509.18994v1)
- Neural-LAM: [arxiv.org/abs/2309.17370](https://arxiv.org/abs/2309.17370) · [github.com/mllam/neural-lam](https://github.com/mllam/neural-lam)
- Stretched-grid regional AIFS: [arxiv.org/abs/2409.02891](https://arxiv.org/html/2409.02891v1)
- ECMWF AIFS blog on LAM: [ecmwf.int/en/about/media-centre/aifs-blog/2024/data-driven-regional-modelling](https://www.ecmwf.int/en/about/media-centre/aifs-blog/2024/data-driven-regional-modelling)

These systems are all **analysis-initialized**. They do not do DA.
Their relevance to DA policy is that they set expectations for what AI
regional forecasts can do *given an analysis*, and they generate
pressure to modernize the DA engine underneath.

---

## 4. China's regional AI — FuXi, Pangu, and typhoon specialization

Chinese groups have invested heavily in regional and tropical-cyclone
applications of AI forecasting:

- **FuXi-Extreme** (2024) adds a diffusion post-processor to FuXi for
  extreme rainfall and wind, improving typhoon track and intensity.
- **FuXi-TC** (arXiv:2508.16168, 2025) fuses a physics-based regional
  model with FuXi for TC forecasting.
- **FuXi-Nowcast** (arXiv:2512.08974, 2025) predicts composite radar
  reflectivity + surface precipitation at 1-km, fusing radar, stations,
  and ML-model fields — convective initiation is the named target.
- **Pangu-Weather** (arXiv:2211.02556) has been operationally trialed
  over Hong Kong for TCs with 34% lower track error and 20% lower
  intensity error than IFS-driven runs. Also fine-tuned for South China
  in a 2025 *Meteorological Applications* paper.
- **Hybrid Pangu + Shanghai Typhoon Model** (arXiv:2408.12630) uses
  spectral nudging + DA to combine AI global fields with a regional
  physics model.
- **OneForecast** (arXiv:2502.00338, 2025) — a single framework
  spanning global + regional AI forecasting.

Pattern: Chinese groups treat regional/TC as a first-class target
distinct from global deterministic. Every system assumes an analysis
exists (from ERA5, the Chinese CMA analysis, or an operational DA
system) and none replaces DA.

Citations: [npj Clim. Atmos. 2024 eval.](https://www.nature.com/articles/s41612-024-00769-0) ·
[FuXi-TC](https://arxiv.org/html/2508.16168) ·
[FuXi-Nowcast](https://arxiv.org/html/2512.08974v1) ·
[Pangu-HK TC trial](https://rmets.onlinelibrary.wiley.com/doi/10.1002/met.70114).

---

## 5. NVIDIA Earth-2 CorrDiff — generative regional downscaling

**CorrDiff** (Mardani, Pathak, et al., NVIDIA, 2024; *Nature Comms Earth
& Env* 2025) is a two-stage diffusion model: a UNet regressor produces
a mean, then a diffusion model samples the residual. Downscales 25-km
input fields to 2-km output for the continental US, Taiwan, and other
domains, with ~100 samples per forecast for uncertainty. Notably,
CorrDiff can *synthesize* variables not in the input (e.g., radar
reflectivity from surface/upper-air predictors), which makes it
directly relevant to diagnostics that need high-resolution fields from
a coarser analysis. Taiwan's NSTC has deployed it operationally for
disaster alerts.

- *Nature Comms ESE* 2025: [nature.com/articles/s43247-025-02042-5](https://www.nature.com/articles/s43247-025-02042-5)
- NVIDIA blog: [blogs.nvidia.com/blog/earth-2-ai-high-resolution-forecasts](https://blogs.nvidia.com/blog/earth-2-ai-high-resolution-forecasts/)
- PhysicsNeMo reference: [docs.nvidia.com/physicsnemo/latest/physicsnemo/examples/weather/corrdiff](https://docs.nvidia.com/physicsnemo/latest/physicsnemo/examples/weather/corrdiff/README.html)

CorrDiff is complementary to DA, not competitive. It takes a
*completed* analysis (or short-range forecast) as input and produces a
richer, higher-resolution output. If JEDI produces the CONUS analysis,
CorrDiff-style post-processing is a natural consumer.

---

## 6. Storm-scale DA meets AI — WoFS and WoFSCast

**Warn-on-Forecast System (WoFS)** (Stensrud, Yussouf, Flora et al.,
NSSL) is the operational vision for storm-scale DA: a 3-km,
36-member EnKF ensemble assimilating **radar reflectivity and radial
velocity** + satellite every 15 min, running 6-h forecasts every 30 min.
WoFS is the apex of convection-allowing DA: sub-hourly cycling, radar
assimilation, ensemble-based, and entirely focused on severe weather
warnings. This is JEDI's structural territory.

- WoFS: [nssl.noaa.gov/projects/wof](https://www.nssl.noaa.gov/projects/wof/) · [wof.nssl.noaa.gov](https://wof.nssl.noaa.gov/)
- WoFS vision paper (Skinner et al., *Weather and Forecasting* 2024):
  [journals.ametsoc.org/view/journals/wefo/39/1/WAF-D-23-0147.1.xml](https://journals.ametsoc.org/view/journals/wefo/39/1/WAF-D-23-0147.1.xml)

**WoFSCast** (Flora et al., *GRL* 2025) is a GraphCast-framework
adaptation trained on archived WoFS forecasts. Predicts 105 variables
at 5-min cadence; matches 70–80% of WoFS storms at 2-h lead with
modest blurring. 18-member 6-h forecast in ~30 s on a single GPU vs
~10 min on ~1100 CPUs for WoFS. Planned for the 2026 NOAA Hazardous
Weather Testbed.

- *GRL* 2025: [agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2024GL112383](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2024GL112383)
- NSSL repo: [github.com/NOAA-National-Severe-Storms-Laboratory/frdd-wofs-cast](https://github.com/NOAA-National-Severe-Storms-Laboratory/frdd-wofs-cast)
- **WoFS ML Severe** suite: watch-to-warning ML hazard probabilities
  from WoFS fields. [wpo.noaa.gov/predicting-thunderstorm-hazards-with-wofs-and-machine-learning](https://wpo.noaa.gov/predicting-thunderstorm-hazards-with-wofs-and-machine-learning/)

Key observation: WoFSCast **emulates WoFS forecasts**; it does not
replace the WoFS EnKF radar DA. WoFS-DA is the producer of WoFSCast's
training data and initial conditions. No published DOP-style system
handles storm-scale radar DA.

---

## 7. Convective-scale AI nowcasting — DGMR, MetNet-3, NowcastNet, FuXi-Nowcast

A parallel thread — conceptually close to DOP but at nowcasting scale:

- **DGMR** (Ravuri et al., DeepMind, *Nature* 2021). Deep generative
  model of radar. Probabilistic precipitation nowcasts at 1536×1280 km,
  5–90 min lead. Ranked first in Met Office forecaster evaluation in 88%
  of cases. [nature.com/articles/s41586-021-03854-z](https://www.nature.com/articles/s41586-021-03854-z)
- **NowcastNet** (Zhang et al., Tsinghua/DeepMind, *Nature* 2023).
  Physics-conditioned generative network, 3-h lead, 2048×2048 km.
  Outperforms HRRR on extreme rain nowcasting. [nature.com/articles/s41586-023-06184-4](https://www.nature.com/articles/s41586-023-06184-4)
- **MetNet-3** (Andrychowicz et al., Google, 2023). 24-h, 1-km, 2-min
  cadence. Inputs: radar, sparse station observations, GOES imagery,
  "assimilated weather state." Outperforms HRRR and IFS ENS over CONUS
  to 24 h. Key technique: "densification" — learning to fill from sparse
  station reports. Deployed in Google Search and Pixel Weather.
  [arxiv.org/abs/2306.06079](https://arxiv.org/abs/2306.06079) ·
  [research.google/blog/metnet-3](https://research.google/blog/metnet-3-a-state-of-the-art-neural-weather-model-available-in-google-products/)
- **FuXi-Nowcast** (2025). 1-km radar + surface precipitation, fuses
  observations and ML fields. [arxiv.org/abs/2512.08974](https://arxiv.org/html/2512.08974v1)

MetNet-3 is the most DOP-adjacent of these: it ingests raw radar and
station data plus an assimilated field, and produces a forecast. But
the "assimilated weather state" input is still needed — it comes from
HRRR-DA. Even at nowcasting, removing DA entirely has not been
demonstrated operationally.

---

## 8. ML radar observation operators and QC — JEDI-adjacent opportunities

Recent work puts ML directly inside the DA stack at convective scales:

- **NN radar observation operator** (arXiv:2512.18289, 2025). CNN
  encoder-decoder maps model atmospheric state to radar reflectivity;
  deployed inside a 3DVar DA framework. Directly substitutable for the
  parameterized radar operator in JEDI/UFO's `ObsRadar*` operator family.
- **Airborne radar ML QC** (DesRosiers & Bell, *AIES* 2024). Random
  forest classifies weather vs non-weather gates with 96/93% accuracy.
  [journals.ametsoc.org/view/journals/aies/3/1/AIES-D-23-0064.1.xml](https://journals.ametsoc.org/view/journals/aies/3/1/AIES-D-23-0064.1.xml)
- **SRViT** (arXiv:2406.16955). Vision transformer produces radar
  reflectivity from satellite imagery — a learned cross-instrument
  operator relevant for regions with sparse radar.
- **Hybrid physics-AI nowcasting** (*npj CAS* 2024). Fuses NWP and ML
  for extreme precipitation. [nature.com/articles/s41612-024-00834-8](https://www.nature.com/articles/s41612-024-00834-8)

These are candidate UFO operators or QC filters — exactly the kind of
component JEDI's plug-in architecture was designed for. None of the
published implementations are in JEDI yet.

---

## 9. Why regional matters for JCSDA strategy

The DOP critique ("classical DA is obsolete") is weakest at regional
and convection-allowing scales, for specific reasons:

1. **Training data is sparse at storm scale.** GraphDOP has decades
   of global satellite archives. For 3-km CONUS convection, there is
   ~10 y of HRRR analyses and ~5 y of WoFS archives. DOP-style
   "learn the forecast from raw observations" needs ensembles of
   training cases that do not exist at storm scale.
2. **Fast evolution defeats long training-data averaging.** Convective
   initiation, cold-pool dynamics, and supercell evolution are
   per-event phenomena. The large-training-set, in-distribution
   assumption that DOP leans on at global medium-range is violated.
3. **Ensemble-based DA is the dominant paradigm at storm scale.** WoFS,
   HREF, HRRR-DA are ensemble systems. JEDI/oops has 6 ensemble
   solvers (LETKF, GETKF, sequential EnKF, etc.). DA algorithms at
   storm scale are not a solved problem that AI can replace — they
   are an active research frontier where JEDI is a leading platform.
4. **Radar is uniquely regional and uniquely un-DOP-ed.** No DOP
   system ingests radar reflectivity or radial velocity as a training
   input at operational cadence. JEDI/UFO has operational radar
   operators (`ObsRadarReflectivity`, `ObsRadarRadialVelocity`) and
   MPAS-JEDI has demonstrated EnKF radar DA at RRFS scale
   (Park et al., *GRL* 2023). [agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2022GL102709](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2022GL102709)
5. **Sub-hourly cycling is pure DA territory.** WoFS cycles every
   15 min. HRRR-DA every hour. RRFS-JEDI targets hourly cycling. No
   DOP system operates at this cadence, and the observation latency /
   retraining cost of DOP at sub-hourly scales would be prohibitive.
6. **RRFS-JEDI and GDAS-JEDI are already the US path forward.** The
   GSL regional roadmap calls for MPAS+JEDI to replace RAP, HRRR,
   HREF, and NAM in a single unified system. This transition is not
   threatened by DOP; it is the DA substrate that AI forecasts and
   downscalers will layer on top of.

| Regional/storm-scale capability | DOP (GraphDOP, Aardvark, FuXi Wx) | AI forecast emulators (StormCast, HRRRCast, WoFSCast) | JEDI/RRFS-JEDI/MPAS-JEDI |
|---|---|---|---|
| Radar reflectivity DA | No | Consumes DA-produced analyses | **Yes (operational)** |
| Radar radial velocity DA | No | Consumes DA-produced analyses | **Yes (operational)** |
| Satellite + conventional DA | Implicit (no analysis output) | Consumes DA-produced analyses | **Yes** |
| Sub-hourly cycling | No | Inherits cycling of source DA | **Yes (WoFS-style)** |
| Storm-scale ensemble DA | No | Emulates existing ensembles | **Yes (EnKF, GETKF)** |
| Coupled regional (ocean + atm + ice) | No | No | **Yes (soca + fv3-jedi)** |
| New-instrument agility | Retrain | Retrain | **Plug-in UFO operator** |
| Analysis as a product | No | No | **Yes** |

---

## 10. Concrete opportunities for JCSDA

Four concrete R&D directions that fit JEDI's structural strengths and
address the AI-era gap:

1. **ML radar QC filter in UFO.** Replace or augment heuristic
   dealiasing / ground-clutter rejection with a learned classifier
   (cf. DesRosiers & Bell 2024). Deploy as a new `ufo::ObsFilter`
   registered in the factory; no oops changes required. Low-risk,
   high-visibility first demo.
2. **Learned radar observation operator.** Replace the parameterized
   reflectivity operator with a CNN forward + adjoint in UFO
   (cf. arXiv:2512.18289). Tests the "differentiable-programming
   forward operator" pattern inside a DA system and is a published
   proof-of-concept that has not been implemented in an operational
   framework. Pairs with the radar operator work already in MPAS-JEDI.
3. **CorrDiff-style downscaling of JEDI regional analyses.** Chain
   the JEDI RRFS analysis → CorrDiff → 1-km reflectivity + cloud +
   surface wind. Hand-off through ATLAS FieldSet makes this a one-way
   post-processing chain with minimal JEDI refactor. Reads as
   "JEDI produces the analysis that NVIDIA Earth-2 consumes" — a
   concrete cross-ecosystem collaboration.
4. **AI storm-object tracking to inform cycling cadence.** Use a
   learned storm-object tracker on the analysis to drive *adaptive*
   cycling — dense cycling (5-min WoFS-style) over active convection,
   sparser cycling elsewhere. This is a scheduling layer outside oops,
   but it connects JEDI cycling cadence to AI nowcasting outputs.
5. (Stretch.) **Learned convective parameterization for the forecast
   model**, fed by JEDI analyses. Not JEDI-core but relevant to the
   RRFS transition and to coupled DA experiments.

---

## 11. Strategic one-liner

*Global AI weather models and DOP compete most credibly for the medium-
range deterministic forecast. At convection-allowing and storm scale —
where HRRR, RRFS, WoFS, and radar DA live — AI appears as emulators
and post-processors that consume DA-produced analyses, not as
replacements for them. The US regional DA transition (RRFS-JEDI,
MPAS-JEDI) is the substrate that StormCast, HRRRCast, WoFSCast, and
CorrDiff-over-CONUS all depend on. JCSDA's near-term opportunity is to
make that substrate the best in the world, and to integrate ML
operators, ML QC, and generative downscaling as first-class JEDI
components.*
