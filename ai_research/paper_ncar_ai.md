# Distillations: NCAR / NSF NCAR AI portfolio — mapping a collaboration surface

Target audience: internal notes feeding the JCSDA AI strategy memo.
Purpose: identify what NCAR is actually doing in AI/ML for atmospheric
science and data assimilation, so that JCSDA can propose concrete
collaboration — not handwaving about "community engagement" — on top of
the existing MPAS-JEDI relationship.

---

## 1. DART — the other DA framework down the road

NCAR's Data Assimilation Research Section (DAReS) maintains the
**Data Assimilation Research Testbed (DART)**, an ensemble DA facility
that has been in continuous development since 2003. DART is JEDI's
longest-standing peer in model-agnostic DA. Culturally, DART is
academic/research-community-first (university groups, CESM researchers,
Mars/space weather, subsurface hydrology), where JEDI is operational-
center-first (NOAA, Navy, NASA, USAF).

- Current release line is DART v11.x, actively maintained on GitHub.
  2025 headline feature: the **Quantile-Conserving Ensemble Filtering
  Framework (QCEFF)**, extending DART to nonlinear / non-Gaussian DA.
  [NCAR/DART](https://github.com/NCAR/DART) ·
  [DART docs](https://docs.dart.ucar.edu/en/latest/)
- 2025 overview paper: El Gharamti et al., *"The Data Assimilation
  Research Testbed: A Robust, Scalable Software Facility with
  Groundbreaking Capabilities for Model–Data Integration"* — describes
  QCEFF and newer model interfaces (Aether cube-sphere, WRF-Chem).
- **CAM6+DART Reanalysis**: 80-member ensemble global reanalysis, openly
  redistributed on AWS as a cloud-optimized dataset. Marketed explicitly
  as a *training corpus for ML/AI research* — "approximately 10 billion
  labeled observations."
  [DART reanalysis page](https://dart.ucar.edu/research/cam6-reanalysis/) ·
  [AWS registry](https://registry.opendata.aws/ncar-dart-cam6/)

**Is there a DART-JEDI integration story?** Informally, yes; formally,
no. The clearest comparison was published inside the JEDI-MPAS papers
themselves (Liu et al., *GMD* 2023; Guerrette et al., MPAS-JEDI 2.1 on
all-sky AMSU-A, *GMD* 2025): MPAS-JEDI was benchmarked against MPAS-DART
and found to give "comparable" ensemble spread, RMSE, and cycling
behavior. The two frameworks share an atmospheric model (MPAS) but have
no shared infrastructure — separate observation handling, separate
covariance machinery, separate ensemble solvers.
[GMD 2023 JEDI-MPAS](https://gmd.copernicus.org/articles/16/7123/2023/) ·
[GMD 2025 MPAS-JEDI 2.1](https://gmd.copernicus.org/articles/18/8569/2025/)

**DART's own AI story is thin.** The 2025 DART changelog and recent
DAReS work emphasize classical DA advances (QCEFF, nonlinear filters,
new model interfaces), not ML. There is no DART-native foundation model,
no neural observation operator, no learned B. The CAM6+DART reanalysis
is *consumed* by ML researchers, but DART itself is not an ML framework.
This is a gap JCSDA can note without hostility: the two frameworks have
complementary strengths and neither has "solved" AI integration.

---

## 2. AI2ES — the NSF AI Institute for Trustworthy Weather/Climate/Ocean AI

Led by **Amy McGovern** (OU, meteorology + CS). Launched 2020, one of
the original NSF National AI Research Institutes, and the only one
focused on weather/climate/coastal oceanography. NCAR is a core partner
(alongside NOAA NSSL, Colorado State, Univ. of Washington, Del Mar
College, and others). AI2ES is not a software project — it is a
**research + workforce + risk-communication consortium**. Understanding
this distinction matters for how JCSDA might engage.
[ai2es.org](https://www.ai2es.org/) · [Partners](https://www.ai2es.org/team/partners/)

Core research threads that intersect JCSDA's space:

- **Trustworthy / explainable AI.** McGovern et al., *AI Magazine* 2024,
  "AI2ES: The NSF AI Institute for Research on Trustworthy AI for
  Weather, Climate, and Coastal Oceanography."
  [Wiley](https://onlinelibrary.wiley.com/doi/full/10.1002/aaai.12160) ·
  [BAMS 2022 overview](https://journals.ametsoc.org/view/journals/bams/103/7/BAMS-D-21-0020.1.xml)
- **Convective hazards with ML** (tornado, hail, lightning U-Nets on
  WoFS output — in collaboration with NSSL). McGovern et al., *AIES*
  2023, "A Review of Machine Learning for Convective Weather."
  [AIES](https://journals.ametsoc.org/view/journals/aies/2/3/AIES-D-22-0077.1.xml)
- **Convergence research for weather/ocean hazards.** *npj Natural
  Hazards* 2024.
  [nature.com](https://www.nature.com/articles/s44304-024-00014-x)
- **Coastal oceanography** — hurricane surge, red tide, HABs. Less
  overlap with satellite DA, but of interest to NOAA sponsors.

**Honest gap for JCSDA:** AI2ES does not work on data assimilation as
such. Their "trustworthy AI" narrative is aimed at forecast products
and hazard guidance. The crossover with JCSDA is *methodological*
(uncertainty quantification, explainable-AI for DA diagnostics, bias
characterization) rather than scientific. The AI2ES funding runway is
good through at least 2027 (NSF Award 2019758 is the parent).

---

## 3. MILES — the NCAR ML group that is actually building infrastructure

The **Machine Integration and Learning for Earth Systems (MILES)** group
at NSF NCAR is led by **David John Gagne II**. MILES is housed within
CISL (Computational and Information Systems Lab) but collaborates
broadly with MMM (mesoscale/microscale), CGD (climate/global dynamics),
and ACOM (atmospheric chemistry). MILES is the operational home of
NCAR's most visible AI deliverables.
[miles.ucar.edu](https://miles.ucar.edu/) ·
[CISL MILES page](https://www.cisl.ucar.edu/capabilities/miles) ·
[Gagne staff page](https://staff.ucar.edu/users/dgagne)

What MILES produces:

- **CREDIT** (below) — their flagship AI-NWP platform.
- **CAMulator** — fast ML emulator of the CAM6 atmospheric component of
  CESM. ~350× faster than CAM6, with conservation constraints on dry
  mass, total water, and energy. Chapman et al., 2025, arXiv:2504.06007.
  [arXiv](https://arxiv.org/abs/2504.06007)
- **Warn-on-Forecast ML guidance** — overlap with AI2ES/NSSL.
- **Explainable-AI tooling** — shared with AI2ES.
- **Training / workforce** — ML tutorials, summer colloquia, visitor
  programs at NCAR.

Gagne's GitHub (`djgagne`) hosts widely used ML-for-atmosphere tooling.
MILES is structurally the NCAR group JCSDA should treat as a peer to
the "AI + forecasting" side of ECMWF, Fudan, etc.

---

## 4. CREDIT — NCAR's AI-NWP platform, and the most important thing to track

**Community Research Earth Digital Intelligence Twin (CREDIT)** is a
flexible, open-source research platform for *training, deploying, and
evaluating AI weather prediction models* on HPC. Schreck et al., 2024
arXiv preprint; published in *npj Climate and Atmospheric Science*, 2025.
[arXiv:2411.07814](https://arxiv.org/abs/2411.07814) ·
[npj CAS 2025](https://www.nature.com/articles/s41612-025-01125-6) ·
[NCAR/miles-credit](https://github.com/NCAR/miles-credit) ·
[MILES CREDIT page](https://miles.ucar.edu/software/credit/)

What CREDIT is:

- PyTorch-based end-to-end pipeline: data preprocessing → model training
  → inference → verification.
- Ships with **WXFormer** (NCAR-original multiscale vision transformer
  with U-Net-style skips) and a reimplemented **FuXi** architecture.
  Both are trained on ERA5 hybrid sigma-pressure levels and reported to
  "generally outperform IFS HRES" at 10-day lead.
- Supports physics-informed conservation (global dry mass, water,
  energy), terrain-following coordinates, hourly outputs. See the
  CREDIT-sigma-run and CREDIT-physics-run repos.
  [CREDIT-physics-run](https://github.com/NCAR/CREDIT-physics-run)
- Runs on NCAR's **Derecho** GPU-enabled HPC system; public data pipelines
  for ERA5 and CONUS404.

How CREDIT compares to peers:

| Framework | Home | Stack | Scope | DA? |
|-----------|------|-------|-------|-----|
| **CREDIT** | NSF NCAR / MILES | PyTorch, Python | Training + inference of AI NWP (global + regional via CONUS404) | No |
| **Anemoi** | ECMWF + consortium | PyTorch, Hydra | Training of AIFS-class models, fully operational-intent | Yes (Anemoi-DA in progress) |
| **NeuralGCM** | Google Research | JAX | Hybrid ML + differentiable dynamical core | No |
| **Pangu / FuXi** | Huawei / Fudan | PyTorch | Proprietary weather models | Yes (FuXi-DA at Fudan) |

The one-line summary: **CREDIT is to NCAR what Anemoi is to ECMWF**, at
an earlier maturity stage, with an explicit community/research (not
operational) emphasis. Like Anemoi, CREDIT presently has no DA loop.
Unlike Anemoi, CREDIT has not announced a DA component on its roadmap as
of April 2026.

---

## 5. CESM AI/ML — long-tailed, research-driven, not centralized

Beyond CREDIT, NCAR hosts a wide ecosystem of ML-in-CESM activity that
is harder to summarize because it is distributed across labs and PIs:

- **Hybrid ML-physics global atmosphere.** Chen et al., 2026 (*AGU
  Advances*), "Hierarchical Testing of a Hybrid Machine Learning–Physics
  Global Atmosphere Model" — places NCAR-affiliated hybrid work in a
  framework directly comparable to NeuralGCM.
  [AGU Adv.](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2025AV002075)
- **Deep-learning cloud/convection parameterizations** generalizing to
  warmer climates (Han et al., 2025, *JAMES*). Note: finds NCAM-style
  parameterizations generalize better than NeuralGCM under +4 K forcing
  — a methodologically important comparison.
  [JAMES](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2025MS005231)
- **M2LInES (Multiscale Machine Learning In coupled Earth System)** —
  Schmidt-funded, multi-institution ML parameterization effort with
  NCAR participation. [m2lines/CAM-ML](https://github.com/m2lines/CAM-ML)
- **NeuralGCM cross-pollination.** Google's NeuralGCM (Kochkov et al.,
  *Nature* 2024) is not an NCAR product, but NCAR researchers routinely
  benchmark against it and are core citers/critics.
  [NeuralGCM](https://www.nature.com/articles/s41586-024-07744-y) ·
  [GitHub](https://github.com/neuralgcm/neuralgcm)

**Honest reading:** CESM-side ML work is a portfolio, not a program.
There is no single "CESM-AI" entity to partner with. The center of
gravity for a JCSDA collaboration is MILES + CREDIT, with CESM labs as
downstream users.

---

## 6. MPAS-JEDI — the existing NCAR–JCSDA relationship, and whether it has any AI content

MPAS-JEDI is already a strong institutional bridge. The MMM Laboratory
at NCAR has co-developed global MPAS-JEDI with the JCSDA core team
since 2018, with public release 1.0.0 in September 2021 and a 2024
release 3.0.0 line tracking MPAS model v8.2.1. Funding flows include
the Air Force "PANDA-C" (Prediction AND Assimilation for Cloud) project.
[JEDI-MPAS at JCSDA](https://www.jcsda.org/jedi-mpas) ·
[MMM tutorial overview](https://www2.mmm.ucar.edu/projects/mpas-jedi/tutorial/202310NCU/lectures/2-Overview.pdf)

Recent MPAS-JEDI capability highlights (2024–2025): hybrid-4DEnVar,
all-sky AMSU-A radiance DA in gain-form LETKF, grouped ensemble
localization, non-variational cloud analysis from ABI, convective-scale
radar DA.

**Does MPAS-JEDI currently have an AI angle? No, not meaningfully.**
The 2025 MPAS-JEDI presentations at AMS (Liu et al., "Progress with
MPAS-JEDI") and the recent publication record are entirely classical-DA
focused. Ensemble localization, radiance bias correction, and
convective-scale DA are the current research thrusts. This is
simultaneously the honest gap and the opening: *there is clean white
space to propose a MILES + JCSDA AI thread on top of MPAS-JEDI*, because
no one is doing it yet.

**Governance and contacts.** The collaboration is bilateral MMM-JCSDA;
there is no formal joint-steering body above the project level. Named
contacts (from recent publications and tutorial materials): Jonathan
Guerrette, Byoung-Joo Jung, Soyoung Ha, Chris Snyder (NCAR/MMM);
Yannick Trémolet, Yali Wu, Sarah King (JCSDA) on the JEDI side. For
ML: David Gagne (MILES) and team; AI2ES contact through McGovern is OU,
not NCAR.

---

## 7. Opportunities for a JCSDA–NCAR AI collaboration

Principle for this list: every item below names a concrete deliverable,
a named NCAR counterpart, and an existing JCSDA asset. Nothing here is
"let's hold a workshop."

1. **Bridge CREDIT as an AI forecast model into a JEDI DA cycle.**
   CREDIT exposes a PyTorch training + inference interface; JEDI has a
   `MODEL` traits contract. A concrete Year-1 deliverable is an
   `oops::Model` wrapper that calls a trained WXFormer or FuXi-in-CREDIT
   for forward integration, producing a fully AI-forecast EnKF or 4D-Var
   cycle. NCAR gets an operationally plausible DA loop around their
   foundation model; JCSDA gets a concrete test of JEDI as the neutral
   DA substrate for multiple AI forecast backbones. Counterparts:
   Gagne/Schreck (MILES) + Guerrette/Trémolet (JCSDA). This mirrors
   what Anemoi-DA does for ECMWF and *avoids NCAR needing to build a DA
   loop from scratch*.

2. **MPAS-JEDI + AI hybrid track.** Nobody is running a production AI
   ensemble on an MPAS mesh. MPAS-JEDI + ensemble DA + a CREDIT-trained
   regional or global emulator is a unique niche neither ECMWF nor Fudan
   can occupy, because they don't use MPAS. Year-1 deliverable: a
   CAMulator-style emulator of MPAS-A trained on MPAS reanalysis, plugged
   in to MPAS-JEDI via the same `oops::Model` interface. Counterparts:
   Ha/Snyder (NCAR/MMM) + Chapman (MILES, CAMulator author) + JCSDA
   MPAS-JEDI team.

3. **A shared benchmark & evaluation substrate.** CREDIT ships a
   verification pipeline; JEDI ships H(x) against real observations.
   Real observation-space verification of AI models is *not* standard —
   most are scored against ERA5 analyses only. A joint CREDIT/JEDI
   observation-space evaluation would be a high-visibility paper and a
   real service to the AI-NWP community. Counterparts: Schreck (MILES) +
   JCSDA IODA/UFO team (King, Newman).

4. **Reanalysis collaboration.** The CAM6+DART reanalysis is the most
   widely advertised NCAR-hosted AI training corpus; the AWS release
   explicitly targets ML researchers. A JCSDA-produced JEDI-MPAS
   multi-decade reanalysis would add a second NCAR-area-endorsed training
   corpus with proper all-sky radiance DA (which CAM6+DART does not do).
   Counterparts: DAReS (El Gharamti) + JCSDA reanalysis PIs.

5. **Trustworthy AI for DA diagnostics.** AI2ES's methodological work on
   explainability and uncertainty-aware AI maps naturally onto JEDI
   diagnostics (FSOI-analogue for ML forecasts, uncertainty calibration,
   bias detection). A jointly-authored paper or tutorial on trustworthy-
   AI practices for DA could be a low-cost, high-credibility entry.
   Counterparts: McGovern (OU/AI2ES) + Gagne (NCAR) + JCSDA AI lead.

6. **Observation platform for NCAR's AI training pipelines.** MILES and
   CREDIT currently build bespoke observation handling for each new
   experiment. IODA's formal goal is to be the US community observation
   platform. A low-cost Year-1 deliverable is getting CREDIT users
   pointing at IODA-formatted observation datasets for evaluation (and
   eventually training). Counterparts: MILES + JCSDA IODA team.

7. **Workforce / summer students.** NCAR already runs the SIParCS
   summer program; AI2ES runs workforce programs. A shared JCSDA+MILES
   summer project — e.g., student builds a trained neural H(x) for a
   specific sensor inside UFO — is a low-risk, high-signal first step
   before heavier commitments.

---

## 8. Strategic implications for JCSDA

1. **NCAR is not a JEDI competitor in AI — it is a structural partner.**
   NCAR has a mature AI forecasting platform (CREDIT + WXFormer +
   CAMulator) and no DA loop. JCSDA has a mature DA platform and a
   growing AI strategy but no home-grown foundation model. The fit is
   unusually clean.
2. **The DART question is separate from the AI question.** DART remains
   a classical-DA research framework with limited ML uptake. Treating
   DART and JEDI as peer classical DA frameworks while pursuing
   AI-specific partnerships through MILES/CREDIT is the cleanest frame.
   A JEDI-DART *merger* has never happened and shouldn't be the goal.
3. **AI2ES is a reputational asset more than a technical asset.** The
   easiest wins are joint trustworthy-AI publications and workforce
   programs, not infrastructure integration.
4. **The unique thing JCSDA can offer NCAR** is a real, multi-agency,
   operationally-validated observation + DA platform underneath their
   AI research models. NCAR's AI work trains on and verifies against
   reanalysis; JEDI is the natural path to real-observation-space
   evaluation and real-stream DA cycling. State this explicitly in any
   JCSDA–NCAR framing document.
5. **The unique thing NCAR can offer JCSDA** is a community-standard,
   Python-first, PyTorch-native AI modeling platform (CREDIT) that
   JCSDA does not need to build. Adopt, don't reinvent.
6. **MPAS-JEDI is the existing bridge.** Every new collaboration thread
   should route through or near MPAS-JEDI at first, because the
   institutional trust already exists there. Expand outward from that
   center (MMM → MILES → CISL → DAReS → AI2ES), not the reverse.

---

## One-line for the memo

*NCAR's AI portfolio is concentrated in MILES and the CREDIT platform,
not in DART or the CESM labs; CREDIT is a mature AI-NWP training
framework with no DA loop, and MPAS-JEDI is the existing institutional
bridge with currently zero AI content — which makes NCAR the cleanest
structural partner for JCSDA in the AI-forecasting space, not a
competitor.*
