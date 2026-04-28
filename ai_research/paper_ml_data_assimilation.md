# Distillations: Machine Learning in / for Data Assimilation

Target audience: internal notes feeding the JCSDA AI strategy memo.
Coverage: the papers that matter for deciding where AI fits *inside* the DA
pipeline — i.e., the bottom-up pillar — and for the higher-risk "learn the
whole DA operator" direction.

---

## 4DVarNet (Fablet et al., 2021; Beauchamp et al., 2023)

- **References:**
  - Fablet et al., *JAMES* (2021). [DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2021MS002572)
  - Beauchamp et al., "4DVarNet-SSH", *GMD* 16, 2119–2147 (2023).
    [GMD](https://gmd.copernicus.org/articles/16/2119/2023/)
  - [GitHub (CIA-Oceanix/ocean4dvarnet)](https://github.com/CIA-Oceanix/ocean4dvarnet)
- **Idea:** Replace the dynamical prior in 4D-Var's background term with a
  **neural operator**, and replace the minimization solver with a **learned
  solver** (an LSTM-like inner network). Entire 4D-Var cost is end-to-end
  differentiable.
- **Demonstrated on:** Sea-surface height reconstruction from nadir + SWOT
  altimetry. 30–60% error reduction vs. operational OI. Resolves scales below
  70 km / 7 days.
- **Relevance to JEDI:** Most direct "learned 4D-Var" proof-of-concept. Fits
  naturally as a successor to JEDI's classical variational minimizer if JCSDA
  were to adopt a learned B or learned dynamical prior.

## GraphDOP (ECMWF, 2024)

- **Reference:** Alexe et al., arXiv:2412.15687 (Dec 2024).
  [arXiv](https://arxiv.org/abs/2412.15687) ·
  [ECMWF update](https://www.ecmwf.int/en/newsletter/182/earth-system-science/update-ai-dop-skilful-weather-forecasts-produced-directly)
- **Idea:** End-to-end GNN trained on **raw observations only** (no reanalysis).
  Produces deterministic forecasts up to 5 days directly from observation
  histories. Competitive with IFS on 2-m temperature over the Tropics at d5.
- **What it implies for DA:** Challenges the premise that a reanalysis / analysis
  is a required intermediate product at all. "The analysis as a lossy
  representation of the observations" becomes testable.
- **Important caveat from follow-up work:**
  > *"Using data assimilation tools to dissect GraphDOP"* (arXiv:2510.27388,
  > Oct 2025). FSOI and adjoint-based diagnostics applied to GraphDOP show it
  > **does learn physically meaningful structures** (storm tracks, observation
  > impacts) — i.e., the language of DA diagnostics transfers.

## Aardvark Weather (Cambridge + Alan Turing Institute + Microsoft + ECMWF)

- **Reference:** Allen et al., *Nature* (Mar 2025). arXiv:2404.00411.
  [Nature](https://www.nature.com/articles/s41586-025-08897-0) ·
  [University of Cambridge press release](https://www.cam.ac.uk/research/news/fully-ai-driven-weather-prediction-system-could-start-revolution-in-forecasting)
- **Idea:** Fully end-to-end data-to-forecast ML system. Ingests raw observations
  (surface, satellite, radiosonde) and produces both gridded global forecasts
  and station-level forecasts.
- **Result:** Outperforms NWP for multiple variables/lead times, using **~8% of
  the input observations and ~1000× less compute** than NWP baselines.
- **Significance:** The most ambitious end-to-end DA-replacement system to date.
  Demonstrates that neural-process models can handle irregular observation
  geometry — a long-standing argument in favor of DA as an intermediate
  product.

## Score-based Data Assimilation (SDA) — Rozet & Louppe (2023)

- **Reference:** NeurIPS 2023. arXiv:2306.10574.
  [arXiv](https://arxiv.org/abs/2306.10574) ·
  [GitHub](https://github.com/francois-rozet/sda)
- **Idea:** Train a **score-based diffusion model** on state trajectories; use
  the learned score as a generative prior to sample posterior trajectories
  given sparse/noisy observations. Inference does not require the dynamical
  model at all.
- **Demonstrated on:** Two-layer QG model (follow-up 2023 arXiv:2310.01853).
- **Relevance to JEDI:** A viable "learned B" / "learned prior" substitute for
  the static / climatological B matrix. Attractive for soca (ocean) and ice,
  where ensembles are expensive and static B is limiting.

## Latent-space Data Assimilation (2025)

- **Reference:** "Physically consistent global atmospheric data assimilation with
  machine learning in latent space", *Science Advances* (2025).
  [Science Advances](https://www.science.org/doi/10.1126/sciadv.aea4248) ·
  arXiv:2502.02884.
- **Idea:** Assimilate observations **inside a learned latent space** of the
  atmosphere (from an autoencoder), where the error covariance becomes near-
  diagonal. Decoder maps back to physical space.
- **Relevance to JEDI:** A dramatic simplification of the B-matrix problem if it
  generalizes. Bears watching but the JEDI B-block infrastructure (SABER's
  block-chain covariance) can already mix parametric + learned + ensemble
  components, so JEDI is well-positioned to adopt this as *one more block*.

## Learned observation operators — radiative transfer

- **References:**
  - Stegmann et al. (2022) "A Deep Learning Approach to Fast Radiative Transfer"
    — NASA/NOAA JCSDA CRTM emulator.
    [JQSRT](https://www.sciencedirect.com/science/article/abs/pii/S0022407322000255) ·
    [NOAA repo PDF](https://repository.library.noaa.gov/view/noaa/64509/noaa_64509_DS1.pdf)
  - Liang et al. (2023) "A Machine Learning Approach to the Observation Operator
    for Satellite Radiance Data Assimilation", *JMSJ*.
    [JMSJ](https://www.jstage.jst.go.jp/article/jmsj/101/1/101_2023-005/_html/)
  - "Probabilistic Emulation of the CRTM Using Machine Learning", arXiv:2504.16192
    (2025).
- **Findings:** CRTM emulators achieve ~0.3 K RMSE across channels, 10–100×
  speedup, and analytically computable Jacobians (no finite differences).
- **JEDI state:** A **CRTM-ONNX bridge is already on a feature branch**
  (`btj_ml-emulator-onnx-bridge`) with a C/Fortran interface. This is active,
  not yet merged.

## Machine learning bias correction for radiances

- **References:**
  - Zhang et al. (2024) "Impacts of Offline Nonlinear Bias Correction Schemes
    Using ML on the All-Sky Assimilation of Cloud-Affected Infrared Radiances",
    *JAMES*. [DOI](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2024MS004281)
  - Jin et al. (2023) "Nonlinear Bias Correction of FY-4A AGRI Infrared Radiance
    Data Based on the Random Forest", *Remote Sens.* 15(7), 1809.
  - Jin et al., *GMD* 19, 731 (2026) — ML bias correction for ground-based
    microwave radiometer in RTTOV-gb/WRFDA.
- **Finding:** ML (RF / NN) consistently outperforms VarBC's linear predictor
  model for bias correction, especially in cloudy / all-sky / nonlinear regimes.
- **Relevance to JEDI:** VarBC is in UFO. Drop-in replacement of VarBC's linear
  predictor model with a learned model (trained offline on O-B statistics) is
  one of the **highest-ROI, lowest-risk bottom-up ML integrations available**.

## Farchi et al. (2021) — ML to correct model error in DA

- **Reference:** Farchi et al., *QJRMS* 147 (2021).
  [QJ](https://rmets.onlinelibrary.wiley.com/doi/10.1002/qj.4116)
- **Idea:** Iterate DA step (standard EnKF/4D-Var) ↔ ML step (learn model
  residuals from analysis increments). Closes the "systematic error" feedback
  loop.
- **Relevance to JEDI:** Sets the template for JEDI-hosted **ML model-error
  correction**. Natural fit for fv3-jedi, mpas-jedi, soca — all of which have
  known systematic biases and all of which already output increments in
  FieldSet form that can be harvested as training data.

## Ensemble DA with AI forecast models

- **Reference:** "Ensemble data assimilation to diagnose AI-based weather
  prediction", arXiv:2407.17781 (2024).
- **Finding:** Running EnKF cycles using GraphCast / Pangu / FourCastNet as the
  forecast model is **feasible** — but the resulting flow-dependent covariance
  is **suboptimal at sub-synoptic scales**, likely because AI models smooth
  mesoscale physical structure.
- **Implication:** AI forecast models are not drop-in ensemble members for
  high-resolution DA. There is a real technical gap for JCSDA to fill:
  **generating AI-compatible ensembles that are physically consistent enough to
  carry flow-dependent B information.**

## Howard et al. (2024) — ML-augmented DA for high-res observations

- **Reference:** *JAMES* (2024).
  [DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2023MS003774)
- **Idea:** Train a simple ML model to assimilate very-high-resolution
  observations that are normally thinned. Improves initial conditions AND
  downstream forecast.

## ML-based QC / gross-error detection

- **Reference:** Tavolato & Isaksen (2015), classical adaptive QC foundations;
  Choi et al. (2019) ML for bias correction in dust storm DA
  ([ACP](https://acp.copernicus.org/articles/19/10009/2019/)).
- **Status:** Still dominated by classical buddy checks and first-guess checks
  in operational centers. ML-based QC is a clearly stated "should try" in the
  ECMWF newsletter (Geer 2021, "Data assimilation or machine learning?"
  [ECMWF newsletter 167](https://www.ecmwf.int/en/newsletter/167/meteorology/data-assimilation-or-machine-learning)).

## ECMWF observation-anomaly detection (Newsletter 174)

- **Reference:** ECMWF Newsletter 174 (2023), "Use of machine learning for
  the detection and classification of observation anomalies."
  [ECMWF](https://www.ecmwf.int/en/newsletter/174/earth-system-science/use-machine-learning-detection-and-classification)
- **Methods:** Autoencoder-LSTM for unsupervised anomaly detection +
  Random-Forest classifier for severity/cause classification.
- **Training signal:** **O − B (first-guess departures)** — statistical
  deviations, not forecast-skill loss.
- **Scope:** AMSU-A, IASI, GNSS-RO, AMV, in-situ — organized into geographic
  and spectral groups.
- **Implication for JCSDA:** ECMWF owns the residual-based detection niche.
  Leaves the **FSOI/EFSO-based, forecast-impact-labelled** QC niche open —
  see below.

## FSOI / EFSO and "Proactive QC" — the DA-diagnostic lineage

- **Hotta, Kalnay & Ota (2017)** *MWR* **145**, 3331–3354. "Proactive QC: A
  Fully Flow-Dependent Quality Control Scheme Based on EFSO."
  [DOI](https://journals.ametsoc.org/view/journals/mwre/145/8/mwr-d-16-0290.1.xml)
  - **Core idea:** EFSO identifies detrimental observations 6 h after an
    analysis. Remove them, rerun the analysis, reforecast. Up to 12-h
    forecast lead-time gain from rejecting just the 10% most-detrimental obs;
    improvements persist out to 5–10 days.
- **Chen & Kalnay (2020)** *MWR* **148**, 3911–3931. "Proactive Quality
  Control: Observing System Experiments Using the NCEP Global Forecast
  System." [DOI](https://journals.ametsoc.org/view/journals/mwre/148/9/mwrD200001.xml)
  - OSE follow-up to Hotta et al. (2017) on NCEP GFS.
- **Kotsuki, Sato, Miyoshi (2019)** *QJRMS*. "On the properties of ensemble
  forecast sensitivity to observations." [DOI](https://rmets.onlinelibrary.wiley.com/doi/full/10.1002/qj.3534)
- **Chen, Kalnay et al. (2017 WGNE Bluebook)** "Use of EFSO for online data
  assimilation quality monitoring and Proactive QC."

**JCSDA's own FSOI infrastructure**:
- `JCSDA-internal/FSOI` repo
  ([GitHub](https://github.com/JCSDA-internal/FSOI)) — institutional
  comparison pipeline, last active commit March 2022.
- JCSDA Impact of Observing Systems (IOS) project
  ([JCSDA](https://www.jcsda.org/jcsda-project-ios)).

## FSOI-trained ML — the direct prior art

- **Vandenberghe, Bolmier, Auligné, Mahajan & Holdaway (2019)** AMS 99th
  Annual Meeting, Paper 354865. "Predicting Forecast Sensitivity: Observation
  Impact with Machine Learning." All five authors JCSDA/Boulder.
  [Abstract](https://ams.confex.com/ams/2019Annual/webprogram/Paper354865.html)
  - **Target:** Predict FSOI (observation impact on forecast skill) from
    features available at or near analysis time.
  - **Data:** AMSU-A / NOAA-18.
  - **Methods:** Multi-dimensional linear regression (baseline); gradient
    boosting; neural networks.
  - **Result:** "Non-linear AI methods sensibly improve the prediction when
    compared to simpler approaches."
  - **Status:** No peer-reviewed follow-up identified in 6 years. Idea
    appears to have stalled past the conference stage.
- **Ensemble FSO ML diagnostic use at NASA GMAO** — mentioned in NASA
  materials ("NASA uses the FSOI diagnostic capability as metric to compute
  the loss function for the training and evaluation of the machine learning
  procedure"), but no peer-reviewed paper identified.

### Why this matters for the JCSDA strategy

The lineage is **Hotta 2017 (proof EFSO can identify detrimental obs)** →
**Vandenberghe 2019 (proof ML can predict FSOI)** → *gap* → [nothing]. The
natural next step — **operationalize predicted-FSOI as a real-time UFO QC
filter** — has not been taken by any group. JCSDA has:
- the existing FSOI infrastructure
- the existing JEDI PyTorch infrastructure (TorchBalance)
- the original 2019 ML-for-FSOI prototype (unfinished)
- the multi-agency operational DA footprint where this would matter

Nobody else has all four. This is as close to an unclaimed strategic flag
as the landscape offers.

---

## Cross-cutting observations

1. **Observation operators and bias correction are the "easiest wins."** CRTM
   emulators and learned VarBC are well-proven, plug into existing DA systems,
   and do not disrupt the cost-function math.
2. **Learned B and learned dynamical priors are the "medium-risk, high-value"
   class.** 4DVarNet, SDA, latent DA — each is a way to replace one part of the
   variational cost with a learned component while preserving the DA skeleton.
3. **End-to-end learned DA (Aardvark, GraphDOP) is the existential question.**
   If these scale, the role of a classical DA framework shrinks dramatically.
   JCSDA's response should be: **do the observation-science work that these
   models still need** (QC, bias characterization, error modeling, observation
   operators) and make JEDI the framework that can host either paradigm.
4. **There is a gap no one else owns: "AI-aware DA."** An ensemble DA system
   that is built to work against AI forecast models, with AI-consistent B,
   AI-compatible H, and AI-aware QC, is not on anyone's explicit roadmap. This
   is a defensible JCSDA niche.
