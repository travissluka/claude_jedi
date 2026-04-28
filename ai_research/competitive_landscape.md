# Competitive & Partner Landscape: AI × Weather DA

Purpose: map who is doing what in the AI-weather space, so the JCSDA strategy
memo can identify non-overlapping niches and credible partnerships.

---

## The big picture

The AI-weather ecosystem has resolved into three quasi-stable layers:

1. **Foundation-model developers** — frontier labs (DeepMind, Microsoft Research,
   IBM/NASA) + startups (Silurian) + major public centers (ECMWF). Produce the
   transformer / GNN / diffusion models that do forecasting.
2. **Framework + infrastructure providers** — NVIDIA (Modulus, PhysicsNeMo,
   torch-harmonics, Earth-2), ECMWF (Anemoi), Google (JAX-based NeuralGCM).
   Produce the open libraries everyone trains on.
3. **Operational agencies** — ECMWF, NOAA, US Navy, Météo-France, UK Met Office,
   KMA, CMA. Consume (1) and (2) and integrate with their DA and
   delivery pipelines.

**JCSDA sits across layers (2) and (3)** — JEDI is infrastructure for layer-3
agencies. That is the strategic position to defend and extend.

---

## Public / governmental actors

### ECMWF — the current leader

- **AIFS Single** operational 25 Feb 2025 as deterministic AI model alongside IFS.
  [ECMWF news](https://www.ecmwf.int/en/about/media-centre/news/2025/ecmwfs-ai-forecasts-become-operational)
- **AIFS-ENS** operational 1 Jul 2025 as 51-member ensemble.
  [ECMWF news](https://www.ecmwf.int/en/about/media-centre/news/2025/ecmwfs-ensemble-ai-forecasts-become-operational)
- **AIFS 1.1.0** (2025) — improvements, snow added, sub-seasonal coming 2026.
  [arXiv:2509.18994](https://arxiv.org/abs/2509.18994)
- **Anemoi** — open-source Python/PyTorch framework co-developed with 10 European
  NMHS. [ECMWF](https://www.ecmwf.int/en/about/media-centre/news/2024/anemoi-new-framework-weather-forecasting-based-machine-learning)
- **DestinE / Destination Earth** — EU digital-twin program; integrates AI
  forecasts, data-cube infrastructure, climate adaptation tools.
- **GraphDOP / AI-DOP** — observation-only forecasting research line.
- **Tone:** Cooperative, publishes weights and code. JCSDA has no direct
  analogue but JEDI is the American counterpart in infrastructure spirit.

### NOAA

- **10-Year Strategy for Data Assimilation (2024–2033)**. Key quotes:
  > *"Leverage new techniques such as AI to extract, to the maximum extent,
  > all information content from available environmental observations."*
  > *"JEDI infrastructure is a key tool to support the goals outlined in the
  > strategy."*
  [NOAA DA strategy summary](https://epic.noaa.gov/10-year-strategy-for-data-assimilation/)
- **Project EAGLE** (Experimental AI Global and Limited-area Ensemble).
  GraphCast fine-tuned on GDAS. Global-EAGLE-Solo + 31-member Global-EAGLE-
  Ensemble. CONUS storm-resolving and coupled versions on roadmap.
  Plans to use Anemoi.
  [EPIC article](https://epic.noaa.gov/noaa-project-eagle-to-accelerate-ai-weather-prediction-advances-for-the-united-states/) ·
  [AWS open data](https://registry.opendata.aws/noaa-nws-graphcastgfs-pds/)
- **AIGFS** — AI-based GFS replacement, 0.3% of GFS compute for a 16-day run,
  ~40 min wall-clock.
- **National Hurricane Center** — AI integration began 2025 hurricane season.
- **NOAA Center for AI (NCAI)** — cross-cutting AI institute.
  [noaa.gov/ai](https://www.noaa.gov/ai)
- **EPIC** — hosting AI short courses at AMS (2026). Focus on community ML
  weather tooling.
- **Strategic read:** NOAA is racing to stand up AI forecasting (Project EAGLE)
  and has explicitly called out AI-for-DA and JEDI as components of the
  **next-generation DA strategy**. The JCSDA–NOAA alignment opportunity is
  enormous and explicit. The gap NOAA has not filled is **a unified
  AI-for-observations platform** — they have adopted AI forecasting but
  observation-side AI (operators, bias correction, QC, obs-to-forecast
  evaluation) is scattered and owned by no single entity.

### US Navy / ONR

- **NavGEM/NavyDA** is on the JEDI side already (JCSDA partner).
- **ONR SBIR N24.1-054** — probabilistic ML forecasts, medium-range and
  sub-seasonal. [Navy SBIR](https://navysbir.us/n24_1/N241-054.htm)
- **ONR SBIR N25.2-105** — ML downscaling for environmental forecasts.
  [Navy SBIR](https://www.navysbir.com/n25_2/N252-105.htm)
- **Navy Research Lab (NRL)** — Center for Applied Research in AI (NCARAI).
  [NRL AIC](https://www.nrl.navy.mil/itd/aic/)
- **Strategic read:** Navy cares about AI-downscaling, ensembles, ocean + air-sea
  interaction. High alignment with soca (ocean) and coupled components.

### NASA

- **Prithvi-WxC (2.3B)** with IBM; MERRA-2 training; open on Hugging Face.
  [IBM/NASA release](https://newsroom.ibm.com/2024-09-23-ibm-and-nasa-release-open-source-ai-model-on-hugging-face-for-weather-and-climate-applications)
- **Fine-tuned variants:** gravity-wave parameterization, downscaling,
  hurricane track.
- **Strategic read:** NASA is the open-weights partner. Prithvi-WxC's
  MERRA-2 heritage makes it a natural target for a JCSDA-led fine-tune on
  NOAA-family analyses, or for embedding as a pretrained component in JEDI.

### Other

- **ECMWF / UK Met Office / Météo-France / DWD / KNMI / MeteoSwiss** — all on
  Anemoi; collaboration is Europe-first.
- **KMA / CMA / JMA** — all publishing AI-weather papers; CMA's FengWu and
  Fudan's FuXi are the most cited non-Western ML systems.

---

## Industry — the foundation-model developers

### Google DeepMind

- GraphCast (2022/23), GenCast (2024), NeuralGCM (2024).
- Public model weights via Google Cloud + GitHub. **Not a commercial services
  company** — they license the science and ecosystem.
- **Partnership posture:** Open, collaborative, but do not need JCSDA —
  any collaboration must bring something they don't already have (e.g.,
  observation infrastructure, or DOD-grade data).

### NVIDIA

- Earth-2 platform; FourCastNet 1/2/3; SFNO; torch-harmonics; Modulus;
  PhysicsNeMo. All PyTorch.
- [NVIDIA Earth-2 FCN NIM](https://docs.nvidia.com/nim/earth-2/fourcastnet/latest/quickstart-guide.html)
- **Stated interest** in JCSDA partnership (per user).
- **Partnership posture:** NVIDIA wants:
  (a) domain-scientific partners who will run their tools and co-author;
  (b) workloads that justify hardware; (c) open-source contributions.
  JCSDA can provide (a) and (c) directly; (b) via JEDI's operational footprint.

### Microsoft Research

- Aurora (1.3B, *Nature* 2025); ClimaX (2023, ICML); Aardvark (2025, *Nature*).
- Has pivoted some of its academic talent to Silurian (see below).
- **Partnership posture:** Publishes; open-sourced Aurora on GitHub. Probably
  less active now that the Aurora team has partly spun out.

### IBM

- Prithvi-WxC co-developer; also Prithvi-EO (Earth observation foundation
  model). Runs foundation-model work out of IBM Research.
- **Partnership posture:** Institutional, long-horizon; NASA relationship
  dominates their weather-climate agenda.

### Silurian AI

- Founded June 2024 by **Cristian Bodnar, Jayesh Gupta, Nikhil Shankar, Mark
  Baum** (ex-Aurora). Y Combinator S24.
- **GFT (Generative Forecasting Transformer)** — 1.5B param, 11 km resolution,
  14-day lead times. Claimed +30% over NOAA/ECMWF on many variables.
- **GFT-C** — tropical-cyclone-focused model. Operational API launched for
  2025 hurricane season.
  [Silurian blog: GFT-C](https://silurian.ai/blog/gft-cyclones)
- Recent partnership: Disaster Tech PRATUS platform integration.
- **Partnership posture:** Commercial; VC-funded; need hurricane / extreme-
  weather pilots and potentially DOD contracts. Observation ingestion and
  evaluation from JEDI-based analyses would be directly useful to them.

### Huawei / Fudan / Others

- Pangu-Weather (Huawei); FuXi (Fudan); FengWu (CMA). Strong publications;
  not a likely US partnership axis.

---

## Strategic geometry — where JCSDA fits

### Where JCSDA should NOT try to play

- **Training the next frontier forecast model.** DeepMind, ECMWF, Silurian,
  NVIDIA, and Huawei have a 2–5 year head start and 10–100× the GPU budget.
  Any "JCSDA GraphCast" would be a me-too effort.
- **Owning a general ML framework.** Anemoi is winning that turf; Modulus /
  PhysicsNeMo covers the other corner. JCSDA should contribute, not compete.

### Where JCSDA has defensible advantages

- **Deep observation-science expertise** — VarBC, CRTM/RTTOV operators, QC
  filters, thinning, bias correction, observation error covariance. This is
  scarce talent and the AI-weather world knows they need it.
- **JEDI as a DA framework** — a non-trivial C++/Fortran/Python framework that
  spans FV3, MPAS, MOM6, sea-ice, ionosphere. Any partner wanting to couple
  their AI forecast model to a DA system has to talk to JEDI or build one.
- **Multi-agency trust position** — JCSDA is already the US DA bridge across
  NOAA, Navy, NASA, USAF; this is structurally hard to reproduce.

### The partnership map that follows

| Partner | What they need from JCSDA | What JCSDA gets |
|---|---|---|
| **NVIDIA** | Science partner, real DA workload, open contributions | GPU tooling, torch expertise, framework interop |
| **Silurian** | Real-time observations, JEDI-quality reanalysis, evaluation against operational analysis | DOD exposure, hurricane validation, commercial pilot credibility |
| **DeepMind / Google** | Observation + DA expertise, reanalysis-grade labels | Access to pretrained models, potential NeuralGCM-JEDI hybrid |
| **NASA / IBM (Prithvi)** | Fine-tuning on GDAS / NOAA-family data; observation-operator expertise | Access to open-weights foundation model for the bottom-up pillar |
| **ECMWF / Anemoi** | Interoperability with JEDI / ATLAS; observation infrastructure | First-class membership in the European ML weather framework |
| **NOAA EPIC / EAGLE** | AI-aware DA, observation-side AI platform | Direct path to operational relevance + alignment with NOAA 10-yr DA strategy |
| **Navy / ONR** | Coupled ocean–atm AI DA, high-resolution downscaling | Sustained funding, soca/fv3-jedi coupling tests |
