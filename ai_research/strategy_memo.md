# Strategic Plan: AI Integration in JEDI / JCSDA

**To:** JCSDA Director
**From:** Travis Sluka
**Date:** 16 April 2026
**Status:** Draft v1 — internal / pre-decisional
**Classification:** Technical strategy (no organizational, hiring, or budget
content)

---

## Executive summary

The AI-weather landscape has resolved in the last 18 months. ECMWF's AIFS has
been operational since 25 February 2025 as a deterministic model and since
1 July 2025 as a 51-member ensemble. NOAA's Project EAGLE is running a
GraphCast-based global ensemble fine-tuned on GDAS. Microsoft has published
Aurora (*Nature* May 2025) and its team has spun out Silurian, which is
claiming +30% forecast skill over NOAA/ECMWF on a 1.5 B-parameter model. The
frontier of *forecasting* now sits in industry and in Europe. JCSDA cannot and
should not try to out-forecast them.

But the NOAA 10-Year Strategy for Data Assimilation (2024–2033) explicitly names
JEDI as "a key tool to support the goals outlined in the strategy" and calls
out AI as essential to extract all information content from observations. That
sentence is JCSDA's opening. The defensible JCSDA niche is not building the
biggest forecast model; it is owning **AI-for-observation-science** — the
observation operators, bias correction, quality control, error modeling, and
DA algorithms that every AI-weather system depends on but none owns.

**Ocean and coupled DA is identified as the flagship domain.** Every
frontier AI-weather model — GraphCast, GenCast, Pangu, AIFS, NeuralGCM — is
fundamentally an atmospheric model. Aurora Wave (Microsoft) is a decoupled
wave fine-tune. Coupled atmosphere–ocean–sea-ice DA is *owned by no
AI-weather lab*, and SOCA + the coupling repo + JEDI collectively constitute
one of the few open-source frameworks globally with the pieces to assemble a
coupled AI-DA story. This is the single most defensible niche in the entire
landscape.

This memo proposes a two-pillar strategy:

- **Pillar 1 (top-down).** Position JEDI as the US neutral meeting-point for
  foundation-model partners. Bring observation infrastructure, reanalysis-
  grade analyses, and DA expertise to NVIDIA, Silurian, NASA/IBM (Prithvi-WxC),
  DeepMind, and ECMWF — none of which independently own this stack.

- **Pillar 2 (bottom-up).** Systematically replace bounded subsystems of JEDI
  with PyTorch-based learned components: radiative-transfer emulators for CRTM,
  learned VarBC, learned ensemble B blocks, ML-based QC/gross-error filtering,
  learned model-error correction, and eventually differentiable adjoints for
  coupled components. The foundation for this pillar is already in the
  codebase (TorchBalance in SABER, MLBalance in SOCA, CRTM-ONNX on a feature
  branch) — we need to standardize it, grow it, and make it a recognizable
  JCSDA technology stack.

Year 1 commits JCSDA to ten deliverables (§6), grouped as:

- **Infrastructure (6.1, 6.2).** PyTorch-in-JEDI standards and the
  CRTM-ONNX merge.
- **Flagship science (6.3, 6.4, 6.6).** FSOI-trained real-time ML-QC
  — reviving a 2019 JCSDA line that never productized. An OASIM
  differentiability pilot that bakes off torch-autograd, Enzyme, and
  ML emulation on a JEDI operator that currently has no TLM. An
  ocean-and-coupled flagship combining learned sea-ice model-error
  correction in SOCA with a learned sea-ice emissivity operator in UFO.
- **Partnerships and community (6.5, 6.7, 6.9, 6.10).** A learned-VarBC
  proof-of-concept; an NVIDIA `oops::hofx`-against-FourCastNet
  demonstration; **`jedi-eval`** — an observation-space verification
  tool that fills the gap left by WeatherBench 2; and an
  MPAS-JEDI × NCAR-CREDIT joint pilot that cycles a CREDIT-trained AI
  forecast model inside a JEDI DA loop.
- **Governance (6.8).** An AI-DA Strategy Working Group chartered to
  produce the FY28 technical roadmap.

By FY30, JCSDA should be the organization every AI-weather partner calls when
they need observation operators, DA diagnostics, and trustworthy analyses;
JEDI should be able to run classical 4D-Var, ensemble DA against AI forecast
models, and learned-component DA from the same YAML configuration file.

---

## 1. Strategic context

### 1.1 The AI-weather landscape today

In the last 36 months, AI weather forecasting has gone from research curiosity
to operational reality. The key milestones:

- **Pangu-Weather** (Huawei, *Nature* 2023) became the first AI model to beat
  ECMWF HRES on deterministic targets at 1 h–7 day lead times.[^pangu]
- **GraphCast** (DeepMind, *Science* 2023) matched HRES on ~90% of 1380
  verification targets and runs a 10-day forecast in under 1 minute on a
  single TPU.[^graphcast]
- **GenCast** (DeepMind, *Nature* 2024) delivered 50-member probabilistic
  forecasts that beat ECMWF ENS on 97.2% of targets.[^gencast]
- **Aurora** (Microsoft, arXiv 2024 / *Nature* 2025) — 1.3 B-parameter Earth-
  system foundation model covering atmosphere, chemistry, and waves.[^aurora]
- **AIFS** (ECMWF) went operational as a deterministic model on 25 Feb 2025 and
  as a 51-member ensemble on 1 Jul 2025.[^aifs] [^aifs-ens]
- **NeuralGCM** (Google + ECMWF, *Nature* 2024) demonstrated a **hybrid
  physics + ML, end-to-end differentiable** GCM written in JAX.[^neuralgcm]
- **Prithvi-WxC** (IBM + NASA, 2024) — a 2.3 B-parameter foundation model
  trained on MERRA-2, open-weight on Hugging Face.[^prithvi]
- **Project EAGLE / AIGFS** (NOAA, 2025–26) brought GraphCast-based forecasting
  into NOAA's operational experimentation loop.[^eagle]

Three structural observations follow:

1. **Every one of these models trains on a reanalysis.** GraphCast, Aurora,
   AIFS, Prithvi — all trained on ERA5 or MERRA-2. A reanalysis is a DA
   product. The AI forecasting era is built on top of the DA era, and will
   remain so for the foreseeable horizon.
2. **PyTorch dominates; JAX is second.** No current frontier model is written
   in Fortran. JEDI's C++/Fortran/Python stack is the odd one out. But JEDI's
   own torch integrations prove the bridge is already viable.
3. **Differentiability is becoming a first-class requirement.** NeuralGCM,
   SFNO, Aurora fine-tuning, 4DVarNet — all depend on end-to-end gradients.
   JEDI's classical TLM/adjoint infrastructure is not directly compatible with
   torch autograd. This is the single biggest technical gap this strategy
   must address.

### 1.2 What the frontier is *not* doing

For all its speed, the foundation-model ecosystem has systematically avoided
the hardest parts of operational weather prediction:

- **Observation ingestion from raw instrument output** (with the partial
  exception of GraphDOP and Aardvark, both of which are research-stage).
- **Bias correction, QC, and observation-error characterization** — tacitly
  delegated to the reanalysis center that produces the training labels.
- **Coupled atmosphere–ocean–sea-ice–land DA** at operational resolution.
- **Handling of new instruments** where no historical training signal exists.
- **Explainable DA diagnostics** — e.g., observation impact studies.

Every one of these is JCSDA core competency.

### 1.3 Where JCSDA fits

JCSDA sits at the intersection of crowded and sparsely populated regions:

| Axis | Who is already there | Strategic opening |
|------|----------------------|-------------------|
| Forecast models | DeepMind, ECMWF, NVIDIA, Silurian, Huawei, Microsoft | None — cede this frontier |
| ML frameworks | NVIDIA (Modulus, PhysicsNeMo), ECMWF (Anemoi), Google (JAX) | None — interoperate, don't compete |
| Observation infrastructure | RTTOV (Met Office / NWP SAF), JEDI (JCSDA), GSI (NOAA legacy) | **Operational AI-for-observations platform — vacant** |
| Coupled DA systems | JEDI, GSI-coupled, Mercator (private) | **AI-augmented coupled DA — vacant** |
| Open-source DA frameworks | JEDI, DART (NCAR), PDAF | JEDI is the most actively developed |

The two "vacant" rows are where the strategy concentrates.

---

## 2. The JCSDA niche and operating hypothesis

**Working hypothesis (to be validated by the work of Year 1):**
*JCSDA's strategic advantage against DeepMind, ECMWF, and Silurian is not a
bigger forecast model. It is the ability to treat the observation → analysis
→ AI-forecast pipeline as a single, coherent, AI-augmented, differentiable
system, and to do so across multiple agencies (NOAA, Navy, NASA) that no
single commercial actor can serve.*

Three concrete implications:

1. **JEDI becomes the framework that hosts either DA paradigm** — classical
   variational/ensemble DA, and learned-component DA — against either
   forecast paradigm — classical NWP and AI forecast models.
2. **Observation-science becomes the export.** CRTM emulators, learned
   bias-correction, ML-QC, differentiable observation operators — these are
   what JCSDA sells to the frontier labs.
3. **Coupled DA becomes the unique offering.** No AI-weather lab has a credible
   coupled ocean–atmosphere–ice–chemistry DA stack. fv3-jedi + soca + coupling
   is it. This is treated as the flagship domain throughout the rest of this
   memo: every Year-1 deliverable has an ocean or coupled variant called
   out, and the FY28–31 vision terminates in an operational coupled AI-DA
   system. See `paper_ocean_coupled_ai.md` for the literature review
   motivating this emphasis — in particular Gregory et al. (2023/2025) on
   sea-ice model-error learning from DA increments, ECMWF Newsletter 177 on
   learned sea-ice emissivity inside a DA framework, and IceNet on
   seasonal probabilistic sea-ice forecasting.

---

## 3. Pillar 1 — Top-down: partnerships and foundation models

### 3.1 Posture

JCSDA should not announce its own frontier forecasting model. Instead, it
should position as the **neutral US partner** for foundation-model developers
who need operational-grade observations, analyses, DA diagnostics, and
evaluation infrastructure — things that are out of scope or out of reach for
them.

### 3.2 Specific partnership targets

| Target | Posture | Year-1 artifact |
|--------|---------|-----------------|
| **NVIDIA** | Joint technical demonstration; torch/Modulus interop; GPU tooling | Working FourCastNet/SFNO integration in a JEDI H(x) evaluation test |
| **NASA + IBM (Prithvi-WxC)** | Fine-tune Prithvi on GDAS and NOAA-family analyses; embed as pretrained encoder in JEDI H(x) | Publicly releasable JEDI + Prithvi fine-tune checkpoint |
| **Google DeepMind (GraphCast / GenCast / NeuralGCM)** | Drive an AI-forecast + JEDI-DA cycle experiment; run EnVar with GraphCast ensemble members as the B ensemble | Whitepaper on flow-dependent B statistics from AI ensembles |
| **Silurian AI (GFT / GFT-C)** | Evaluation and hurricane-case partnership; provide JEDI-quality reanalysis verification against commercial API | Joint hurricane retro-analysis study (Dorian-class event) |
| **ECMWF (AIFS / Anemoi)** | First-class interoperability with Anemoi data / model formats; cross-framework evaluation | JEDI ↔ Anemoi data-format converter + shared WeatherBench 2 benchmark entries |
| **NOAA EPIC / Project EAGLE** | Formal JCSDA role in the DA portion of EAGLE; own the observation-side AI workstream | AI-aware EnKF cycling experiment using EAGLE ensemble |
| **NSF NCAR (MILES + MMM)** | Extend the existing MPAS-JEDI bilateral to cover AI; wrap NCAR's **CREDIT** PyTorch training platform[^credit] as an `oops::Model` so CREDIT-trained AI models become drop-in AI-NWP options inside JEDI cycling | MPAS-JEDI + CREDIT prototype: one AI forecast model cycled inside mpas-jedi EnKF |
| **AI2ES / NSF AI Institute** (McGovern et al.)[^ai2es] | Methodological collaboration on trustworthy / explainable AI-DA diagnostics; joint paper on uncertainty calibration for AI-forecast ensembles | Co-authored paper on trustworthy AI-DA metrics using JEDI FSOI + AI2ES UQ tooling |
| **ONR / Navy** | Coupled atm–ocean AI DA demonstration using fv3-jedi + soca + AI forecast perturbations | Sub-seasonal coupled retro |

### 3.3 What JCSDA brings to the table

- **The best operational-quality observation pipeline in the US.** IODA's
  multi-backend architecture (HDF5, ODB, BUFR, in-memory) is arguably
  best-in-class for research-to-operations.
- **Observation operators.** UFO's ~96 obsfunctions and ~30+ variable
  transforms, CRTM/RTTOV coverage, and 4+ R-matrix types.
- **DA diagnostics.** FSOI (forecast sensitivity observation impact),
  O-B/O-A statistics, adjoint-based tools that work on any pluggable model.
- **A coupled atmosphere–ocean–sea-ice DA framework.** SOCA + `coupling/` +
  a mature ecosystem of ocean/sea-ice observation operators. No
  AI-weather lab has an equivalent capability; the ML-for-ocean-DA
  literature is active but fragmented across many groups with no unifying
  framework. This is the comparative advantage most relevant to partner
  agencies with ocean missions (Navy, NOAA, NASA).
- **Multi-agency neutrality.** Unique in the US.

### 3.4 Foundation-model evaluation and red-team role

The community does not have a rigorous, operationally grounded way to answer
"how good is model X at representing extreme events in region Y, conditional
on observation Z?" The existing community benchmarks (WeatherBench 2[^wb2],
ChaosBench[^chaosbench], ExtremeWeatherBench[^extremewx]) are all valuable
but share one structural weakness: **they verify AI forecasts against
reanalyses (ERA5, MERRA-2), not against raw observations at inference
time.** Reanalyses are themselves DA products; using them to judge AI
models that were *trained* on them risks a circular evaluation. Mercator's
OceanBench[^oceanbench] is the only existing benchmark with a
model-to-observations track, and it is ocean-only.

JCSDA is uniquely positioned to close this gap because UFO + CRTM + SOCA is
the only open-source stack that can produce observation-space verification
at operational scale. Concrete moves:

- Build **`jedi-eval`** — a standalone tool that runs AI-forecast outputs
  through UFO observation operators against a held-out window of real
  observations, producing per-instrument O−F statistics, FSOI-style
  observation-impact scores, and new-instrument generalization metrics
  (a structural DOP weakness). Year 1 deliverable (see §6.9).
- A standing **AI Weather Model Evaluation Protocol** that extends
  WeatherBench 2 with observation-space metrics, FSOI-style diagnostics
  against ML models, extreme-event case studies, and (uniquely) coupled
  ocean–atm–ice verification against in-situ ocean/ice observations that
  WB2 does not cover.
- Publish quarterly evaluations of public-weight models (GraphCast, AIFS,
  Aurora, Prithvi, NeuralGCM) against JEDI-produced analyses and against
  raw observations.
- Over time, this becomes a gravitational artifact: frontier labs seek out
  JCSDA evaluations to validate their claims, and new instruments land in
  JEDI first because that is where they get verified.

---

## 4. Pillar 2 — Bottom-up: AI inside JEDI

### 4.1 What is already in the codebase

Before proposing new work, the strategy has to take an accurate inventory of
existing JEDI AI/ML infrastructure, because it is more mature than it looks
from outside:

- **TorchBalance (SABER)** — generic libtorch variable balance operator
  using TorchScript models. Atmosphere/ocean/ice tested, documented in
  jedi-docs. ~400 LOC C++; PyTorch 2.8–2.10. Promoted from SOCA into SABER
  in January 2026 (commit `52748226`) as a generic replacement for
  MLBalance. The SOCA-specific **MLBalance** predecessor is now legacy.
  This lineage — niche ocean component generalized to framework-wide
  capability inside twelve months — is the proof point that the bottom-up
  pattern works.
- **CRTM ONNX bridge** — feature branch `btj_ml-emulator-onnx-bridge`;
  C/Fortran interface for ONNX Runtime radiative-transfer inference. Not
  merged.
- **PyIRI-JEDI** — Python ionospheric model integrated as a JEDI model;
  establishes the Python-in-JEDI interop pattern.
- **ModelOceanIceEmulator (SOCA)** — lightweight test emulator.
- **FSOI infrastructure (`JCSDA-internal/FSOI`)** — existing repo for
  Forecast-Sensitivity Observation Impact diagnostics; last active 2022.
  Reactivating this repo is the foundation for the FSOI-QC flagship
  (see §4.4 and §6.3).

The honest read: **JEDI already has a working, multi-repo PyTorch story at
the covariance-block level**, and the radiative-transfer story is 60% done on
a feature branch. The strategy's bottom-up pillar should not invent a new
paradigm — it should generalize the paradigm that is already working.

### 4.2 Component-level opportunity map

The table below is the single most important artifact of this memo. Each row
is a bounded, testable ML integration target inside JEDI.

| Target location | ML integration | Risk | ROI | JEDI repo(s) | Prior art |
|---|---|---|---|---|---|
| **Radiative transfer (CRTM / RTTOV)** | NN / ONNX emulator; analytic K-matrix | Low | Very high | crtm, ufo | Stegmann et al. (2022)[^stegmann]; CRTM-ONNX branch |
| **VarBC** (bias correction) | Replace linear predictor model with learned model | Low | High | ufo | Zhang et al. 2024[^zhang]; Jin et al. 2023 |
| **QC / gross-error filters** | Learned outlier / inconsistency detector (replacing first-guess checks) | Low–Med | High | ufo | Choi et al. 2019; Geer 2021[^geer] |
| **Static B / block chains (SABER)** | Additional learned covariance block | Med | High | saber | TorchBalance (in tree) |
| **Vertical balance** (fv3-jedi, mpas-jedi) | Torch-based learned vertical balance | Med | High | fv3-jedi, mpas-jedi | TorchBalance pattern |
| **Ocean balance** | Extend MLBalance to more variable pairs | Low | Med | soca | MLBalance (in tree) |
| **Ensemble localization / inflation** | ML-learned localization radius from flow | Med | Med | oops | Literature sparse |
| **Real-time ML QC trained on FSOI/EFSO** | Learned classifier that flags likely-detrimental obs *before* assimilation, trained against FSOI/EFSO labels from retrospective cycles | Low–Med | Very high | ufo, oops, FSOI repo | Hotta et al. 2017[^hotta]; Vandenberghe et al. 2019[^vandenberghe]; Chen & Kalnay 2020 |
| **Observation operator for complex instruments** (e.g., all-sky microwave, GNSS-RO nonlinear bending angle) | Learned H, differentiable | Med | High | ufo | Liang et al. 2023[^liang] |
| **OASIM (ocean biogeochemistry)** — Mode A: NN emulation | Train NN surrogate for OASIM radiative transfer; gets forward + Jacobian at once | Med | High | ufo (optional), soca | BGC-UNet (2026)[^bgcunet]; WOMBAT ML surrogate |
| **OASIM — Mode B: physics-in-torch** | Reimplement (or wrap) forward in libtorch; autograd supplies TLM/adjoint | Med | Very high | ufo (optional), soca | PhiFlow[^phiflow]; MITgcm-AD[^mitgcmad] |
| **TLM-missing UFO operators** (wind speed, pathsum, surface-corrected, variant vertical interps) | Mode B template from OASIM generalized | Low–Med | High | ufo | See `paper_differentiable_programming.md` |
| **Model-error correction** | Learn residuals between analysis increments and a priori model | High | Very high | fv3-jedi, mpas-jedi, soca | Farchi et al. 2021[^farchi] |
| **Coupled state inference** (atm–ocean, atm–ice) | Learned constraint surface between coupled states | High | Very high | coupling, soca, fv3-jedi | Aurora-style pretraining |
| **TLM / adjoint replacement** | Torch-differentiable surrogate for expensive TLMs | High | Very high | fv3-jedi, mpas-jedi | 4DVarNet[^fablet]; NeuralGCM[^neuralgcm] |
| **Latent-space analysis** | Assimilate in a learned latent space | High | Unknown | oops, saber | Chen et al. 2025[^latent] |
| **Radar QC and H-operator (regional / convection-scale)** | ML classifier for radar QC in UFO; learned radar reflectivity H-operator with differentiable forward | Low–Med | High | ufo, mpas-jedi | NN radar operator (Liu et al. 2025)[^nnradar]; airborne radar ML QC (Hu et al. 2024)[^radarqc]; WoFSCast[^wofscast] |
| **Diffusion-based downscaling of JEDI analyses** | CorrDiff-style two-stage diffusion to produce km-scale fields from JEDI global/regional analyses | Med | Med | fv3-jedi, mpas-jedi | CorrDiff (Mardani et al. 2025)[^corrdiff] |

**Year 1 execution** takes the low-risk, high-ROI rows: radiative-transfer
emulation, VarBC, QC filters, learned balance, FSOI-QC, OASIM (both
modes), and radar QC / H-operator. **Year 2–3 research** takes the
high-risk rows: model-error correction, coupled state inference,
TLM/adjoint replacement, and latent-space analysis.

### 4.3 The enabling abstraction: a JEDI-wide torch substrate

The TorchBalance and MLBalance work has already solved most of the hard
plumbing problems: how to load a PyTorch model from a YAML config, how to run
forward + adjoint against a TorchScript graph, how to keep the JEDI test and
CI pipeline healthy with a torch dependency. But each integration is
idiomatic to its home repo.

The strategy commits to a **shared `oops::TorchOperator` (or equivalent)
base abstraction** that provides:

- standardized YAML schema for learned-model config (path, version, input/
  output variables, masking, device);
- unified forward / TL / AD interface that plays with the existing oops
  template contracts;
- a model registry with versioning so production runs are reproducible;
- uncertainty-quantification hooks (ensemble-of-models, MC-dropout, or
  deep-ensembles);
- `torch::jit::load` and `onnxruntime` both as backends.

Every other bottom-up integration in section 4.2 plugs into this substrate
instead of reinventing it.

### 4.4 FSOI-trained real-time ML QC — a flagship bottom-up initiative

Of the rows in §4.2, the real-time ML QC entry deserves to be singled out
because it uniquely combines three capabilities JCSDA already owns and no one
else can replicate at JCSDA's level of operational credibility:

- **FSOI / EFSO observation-impact diagnostics.** Hotta, Kalnay & Ota (2017,
  *MWR*)[^hotta] demonstrated "Proactive QC" — identifying detrimental
  observations 6 hours after analysis via EFSO, then re-running the analysis
  with them removed, yielding up to 12-h forecast lead-time gains from
  rejecting as little as the most-detrimental 10% of observations. Chen &
  Kalnay (2020, *MWR*) extended this with NCEP GFS OSEs. JCSDA already
  maintains the `JCSDA-internal/FSOI` repository that hosts the
  community-standard FSOI comparison pipeline.

- **A learned classifier target.** Vandenberghe, Bolmier, Auligné, Mahajan &
  Holdaway (2019, AMS)[^vandenberghe] — a JCSDA in-house effort — showed that
  gradient-boosting and neural-network models trained against FSOI as a label
  can *predict* observation impact for AMSU-A/NOAA-18 better than linear
  baselines, opening the door to applying that prediction at O(ms) latency
  before assimilation rather than O(hours) after. That effort did not
  appear to continue past the conference stage, and no peer-reviewed
  successor has emerged in the six years since. The line of work is wide
  open.

- **JEDI PyTorch infrastructure.** TorchBalance already provides the
  libtorch / TorchScript plumbing, adjoint-compatible Jacobians, YAML-driven
  model loading, and CI pattern needed to host a UFO filter that runs a
  learned model per observation.

**The proposed initiative (FSOI-QC).** Train a supervised learner whose
inputs are the features available *at assimilation time* (observation value,
innovation `d = y − H(x_b)`, observation metadata, nearby background state,
neighbor statistics) and whose label is the sign and magnitude of FSOI /
EFSO computed from retrospective cycles 6+ hours later. Deploy the trained
model as a new UFO filter stage (between `PriorCheck` and the final
selection) that rejects or down-weights observations predicted to be
detrimental with high confidence. Validate by running standard Observing
System Experiments against a control cycle.

**Why this is a good strategic bet:**

- Turns a retrospective diagnostic into a real-time control — a capability
  classical DA literally cannot provide.
- Sits exactly on the "AI-for-observation-science, not AI-for-forecasting"
  positioning from §2.
- Requires a few FTE for one year to produce a publishable result, not a
  multi-year foundation-model investment.
- The training data (FSOI-labelled obs from past GDAS cycles) is already
  available or easy to generate.
- Unlike ECMWF's anomaly-detection ML (Newsletter 174, 2023), which trains
  against O-B residuals, this trains against **actual forecast-skill loss** —
  a strictly better learning signal.
- Produces observation-impact metrics as a by-product, useful for every other
  partnership (NOAA, Navy, NASA, NVIDIA).

This initiative is elevated to a Year-1 deliverable in §6.3.

### 4.5 Torch as an autograd substrate — the "free TLM/adjoint" lever

A subtle but important technology decision sits underneath the bottom-up
pillar: **what does JEDI use to obtain tangent-linear and adjoint operators**
in the next decade? Today, JEDI hand-codes TLM/adjoint for nearly every
operator that has them (`*TLAD.cc/h` throughout UFO, SOCA, FV3-JEDI). This
is correct but carries a permanent maintenance tax and makes *new* operators
(notably OASIM, and several UFO operators) costly to add.

There are two distinct uses of learned / differentiable technology worth
separating:

- **Mode A — ML emulation.** Train a neural network to approximate an
  existing operator H. Use the trained surrogate's autograd for TLM/adjoint.
  Trades accuracy for speed. Well-established for CRTM[^stegmann] and under
  active exploration for ocean biogeochemistry (BGC-UNet[^bgcunet]).

- **Mode B — Physics-in-torch.** Reimplement (or wrap) an operator using
  `torch::Tensor` operations. **No neural network, no training.** Just by
  being written against libtorch, the operator gets forward, TLM, and adjoint
  from `torch::autograd::grad()`. Prior art: PhiFlow[^phiflow] (Holl &
  Thuerey, ICML 2024), torch-md, lcp-physics, differentiable particle
  physics, and — at larger scale — the JAX-based NeuralGCM[^neuralgcm].

**Critical observation:** JEDI's existing torch integrations (TorchBalance,
the retired MLBalance) use libtorch in *inference-only* mode with Jacobians
baked into the exported TorchScript module. No call to
`torch::autograd::grad` exists in the JEDI tree today. Adopting live
autograd for physics operators is therefore a **genuinely new capability** —
not an incremental extension of existing torch work.

**The decisive strategic argument for Mode B:** physics operators written in
torch compose with learned operators in the *same autograd graph*. A hybrid
operator — exact physics where we trust it, learned correction where we
don't — becomes trivially expressible. Tapenade, Enzyme, and hand-coded TLM
cannot do this.

**But Mode B is not the only answer.** Two alternatives deserve equal first
evaluation:

- **Tapenade** — source-to-source AD for Fortran. MITgcm-AD v2[^mitgcmad]
  uses Tapenade to differentiate a full production ocean model including
  sea-ice and biogeochemistry. Zero intrusion on existing JEDI Fortran code,
  no GPU, no ML interop.
- **Enzyme** — LLVM-level AD. Works on C, C++, Fortran, Julia, Rust. Used
  by the Oceananigans.jl + Enzyme.jl / DJ4Earth stack. Minimal intrusion,
  GPU support, but newer and less operationally proven.

**OASIM is the ideal pilot.** See §6.4. One operator, one repo, no TLM
exists today, complex enough to stress the technology, small enough to
finish in one year. Run all three tracks (Mode-A emulation, Mode-B
torch-autograd, Enzyme-on-Fortran) against the same physics. Decide the
JEDI AD standard at end of Year 1 on evidence, not speculation.

### 4.6 Physics-informed and hybrid operators — where torch-in-operators earns its keep

A natural question is whether physics-informed neural networks (PINNs) are
a reason to rewrite JEDI operators in torch. The answer requires
disambiguating what "physics-informed" means — the term covers at least
four distinct techniques, with very different requirements on the
surrounding code stack. Full discussion lives in
`paper_pinn_and_piml.md`; the executive summary for this memo:

| Flavor | Physics-in-torch needed? | Value for JEDI |
|--------|--------------------------|----------------|
| Classical PINN (NN-as-PDE-solution, Raissi 2019[^raissi]) | No | Low |
| Physics-constrained emulator training | Sometimes | Medium |
| **Jacobian-matching emulation** (Li et al. 2023 NOAA[^licrtm]) | Online: yes | High |
| **Hybrid physics + NN in one autograd graph** (PhiFlow, NeuralGCM) | **Yes — decisively** | **Very high** |
| DeepONet / FNO / PINO (operator learning) | No | Low near-term |

**The strategic reason to write forward operators in torch is not PINN per
se — it is the fourth row.** Hybrid operators (`H = H_physics(x) +
NN_residual(x)` or more sophisticated compositions) cannot be expressed as
a single differentiable function unless the physics and the NN share the
same autograd substrate. Neither hand-coded TLM, Tapenade, nor Enzyme
provides an equivalent capability.

**Immediate opportunities this unlocks for JEDI once the §4.5 bake-off is
done:**

- **Hybrid CRTM operator.** Physics core (fast path) in torch; NN residual
  for cloud-affected / all-sky channels; one autograd graph. Trains
  end-to-end against brightness temperatures. Related to but strictly
  broader than the learned-VarBC deliverable (§6.5).
- **Online Jacobian-matched CRTM emulator.** Li et al. (2023) at NOAA/
  NESDIS[^licrtm] have already published the offline version (train against
  a dumped K-matrix); the online version (train against CRTM's Jacobian
  computed inside the training loop) is only expressible with torch-ed
  physics.
- **Physics-constrained sea-ice emissivity operator.** The §6.6 Sub-track B
  deliverable gains an additional rigor: Kirchhoff's law as a loss term,
  monotonicity with temperature as an architectural constraint, all
  differentiable end-to-end.
- **Ocean DA via PINN-per-layer.** StrAss-PINN (Cavalcanti et al.
  arXiv:2503.19160, 2025) demonstrates the exact pattern applied to ocean
  reconstruction. A SOCA-native analog is a natural Year-2 project.

This §4.6 does not become a Year-1 deliverable on its own — it is the
technical justification for why §4.5 and §6.4 are worth doing in the first
place. If the OASIM bake-off picks torch as the JEDI AD standard, the
hybrid-operator pattern unlocks immediately. If it picks Enzyme, hybrid
operators are still *possible* but require additional Python/torch glue.
This trade-off is itself part of the §4.5 evaluation criteria.

### 4.7 Differentiable JEDI — the long-horizon vision

If Mode B and/or Enzyme succeed, the natural end state is a fully
differentiable JEDI — a `oops::Increment` whose operations are recorded on
an autograd tape, enabling:

- Learned model-error correction across fv3-jedi / mpas-jedi / soca.
- Online tuning of physics + ML parameters against 4D-Var cost.
- Coupled atmosphere-ocean-ice 4D-Var where the coupling dynamics are
  differentiable and, in part, learned.
- Drop-in compatibility with NeuralGCM-style hybrid forecast models.

This is too big for Year 1 as a product, but Year 1 should produce a
**design study and prototype of a torch-backed fv3-jedi Increment** so the
FY28 roadmap is informed.

---

## 5. Infrastructure dependencies

A few cross-cutting investments make both pillars tractable:

- **Framework choice: torch as primary, JAX as interop-only.** libtorch
  is already in-tree (TorchBalance, MLBalance); JAX has no first-class
  C++ API. In-JEDI code uses libtorch exclusively. Offline training may
  use either framework, exporting via ONNX or TorchScript. JAX-based
  partnerships (NeuralGCM) interoperate via dlpack + ONNX, with no JAX
  runtime inside JEDI proper. PyTorch dominates the AI-weather ecosystem
  (Aurora, AIFS, FourCastNet, FuXi, Pangu). Precedent: TorchClim[^torchclim]
  embeds libtorch in CESM physics; MOOSE does the same for scientific ML.
- **An AD-technology decision.** Today JEDI hand-codes TLM/adjoint in
  `*TLAD.cc/h` files throughout UFO/SOCA/FV3-JEDI — no Tapenade, no Enzyme,
  no autograd. The existing libtorch integrations use inference-only with
  pre-baked Jacobians; none calls `torch::autograd::grad`. §4.5 proposes a
  time-boxed bake-off of torch-autograd, Enzyme, and ML-emulation on OASIM
  to pick the JEDI AD standard going forward. This is the single highest-
  leverage infrastructure decision in the plan.
- **PyTorch as a first-class JEDI dependency** in spack-stack, with CI
  coverage. TorchBalance and MLBalance already require PyTorch 2.8–2.10;
  formalize this.
- **GPU availability in the JCSDA CI / development environment.** NVIDIA
  partnership unlocks hardware access; without it, torch integration is
  bottlenecked.
- **A JEDI-native data-conversion bridge to Anemoi format.** Anemoi is
  becoming the de-facto open-source training-data standard across European
  NMHS; JEDI should read and write it.
- **A `jedi-ai-models` or similar repo** for storing versioned, signed,
  citable learned-model checkpoints used in operational tests.
- **An AI Weather Model Evaluation Protocol** — an open, publishable extension
  of WeatherBench 2[^wb2] with observation-impact metrics.

---

## 6. Year 1 tactical plan (FY27)

Ten deliverables, grouped as: **infrastructure** (6.1, 6.2), **flagship
science** (6.3 FSOI-QC, 6.4 OASIM, 6.6 Ocean/coupled), **partnership and
community** (6.5 VarBC, 6.7 NVIDIA, 6.9 jedi-eval, 6.10 MPAS/CREDIT), and
**governance** (6.8). Success criterion: eight of ten completed, including
6.1 and at least three of the flagship-science/partnership items.

### 6.1 PyTorch-in-JEDI Standards & Infrastructure

- Charter a small working group across oops, saber, soca, ufo, crtm.
- Produce a **`claude/torch-in-jedi.md`** architecture doc codifying the
  existing patterns (TorchBalance, MLBalance, CRTM-ONNX).
- Ship an `oops::MLModel` abstraction used by at least two existing repos.
- Add PyTorch + ONNX Runtime to spack-stack officially; GPU CI in place.
- Document an `ai-models/` registry convention.

### 6.2 CRTM-ONNX integration completed and merged

- Merge `btj_ml-emulator-onnx-bridge` to develop.
- Ship end-to-end path: trained Python emulator → ONNX export → CRTM runtime
  → UFO `ObsRadianceCRTM` → JEDI test passing adjoint check.
- Publish a whitepaper with runtime + accuracy comparison to CRTM.

### 6.3 FSOI-trained real-time ML QC prototype (FSOI-QC) — flagship

The most strategically distinctive deliverable of Year 1. See §4.4 for full
motivation.

- Reactivate `JCSDA-internal/FSOI` or fold its pipeline into a new
  `ai-observation-impact` workstream under JEDI.
- Generate a labelled training set of ~10⁶ obs–FSOI pairs from a retrospective
  GDAS cycle (AMSU-A + ABI + conventional as an initial scope).
- Train a supervised classifier (likely a transformer or gradient-boosted
  tree baseline) predicting sign-of-FSOI from features available at
  assimilation time.
- Implement a UFO filter stage `MLImpactReject` that invokes the model and
  flags predicted-detrimental observations.
- Run an OSE against a control GDAS retro; report forecast-skill change and
  acceptance-rate statistics.
- Target a peer-reviewed paper (*MWR* or *JAMES*) — this would be JCSDA's
  first operational ML-QC publication and a direct successor to the 2019 AMS
  conference work that never progressed beyond abstract.

### 6.4 OASIM differentiability pilot — evaluate torch-autograd vs Enzyme vs ML emulation

An explicit, time-boxed technology bake-off using one well-bounded operator
that JEDI otherwise cannot use in variational DA.

Context: OASIM (ocean biogeochemistry radiative transfer) is present in the
bundle at `bundle/ufo/src/ufo/operators/oasim/` as an optional build. It has
**no TLM/adjoint** and therefore cannot participate in 4D-Var or any
gradient-based DA. Adding one by hand is costly; adding one by an automated
AD approach would establish a template for every other TLM-missing operator
in JEDI.

Three tracks, evaluated against the same forward physics:

- **Track 1 — Mode A (ML emulation).** Train a neural network (feedforward or
  U-Net) on OASIM outputs; expose trained model via TorchScript in a UFO
  operator. Derivatives via `torch::autograd::grad`. Prior art:
  BGC-UNet[^bgcunet], WOMBAT surrogate work.
- **Track 2 — Mode B (physics-in-torch).** Reimplement OASIM's forward
  kernels in libtorch tensor ops. No training. TLM/adjoint via
  `torch::autograd::grad`. Prior art: PhiFlow[^phiflow].
- **Track 3 — Enzyme on existing Fortran.** Apply Enzyme LLVM-level AD to
  the existing OASIM Fortran without rewriting it. Prior art: the
  Oceananigans / Enzyme.jl / DJ4Earth stack.

Deliverables:
- Adjoint correctness verified (taylor-test, dot-product test) for all three
  tracks.
- Runtime benchmark vs. raw Fortran forward.
- One SOCA 3D-Var experiment assimilating ocean-color observations (MODIS /
  VIIRS / PACE chlorophyll) through the differentiable OASIM.
- A decision memo recommending the JEDI-wide AD standard going forward.
- Target publication in *Geoscientific Model Development* or *JAMES*.

This is the single most consequential technology-direction decision in the
Year-1 plan. Regardless of winner, it finishes with JEDI's first
variational-DA capability for marine biogeochemistry.

### 6.5 Learned VarBC proof-of-concept in UFO

- Implement a UFO `BiasPredictor` plug that accepts a torch model.
- Train on O–B statistics from an existing GDAS cycled experiment.
- Demonstrate reduction in seasonal systematic bias vs. classical VarBC on at
  least one AMSU-A and one ABI channel set.
- Target publication in JAMES or QJRMS.

### 6.6 Ocean and coupled AI-DA flagship

The ocean/coupled flagship deliverable. Builds on active literature
(Gregory 2023/2025, ECMWF Newsletter 177, IceNet) with implementations
inside SOCA and the coupling repo. Two sub-tracks, either of which on its
own is a Year-1 success:

- **Sub-track A: Learned sea-ice model-error correction in SOCA.** Train a
  U-Net (following Gregory et al. 2023[^gregory2023]) on SOCA DA increments
  from a retrospective cycle to learn systematic model errors in sea-ice
  concentration / thickness / snow depth. Deploy as an online correction
  inside the SOCA model-interface layer. Target a verification against a
  control retro showing reduced forecast error out to 1–2 weeks.
- **Sub-track B: Learned sea-ice emissivity operator in UFO.** Adapting
  the ECMWF Newsletter 177 pattern[^ecmwf177] — jointly learn sea-ice
  state and the emissivity component of the microwave observation
  operator inside the DA cost function. Replaces the current hard-coded
  emissivity assumption and improves AMSR-family microwave radiance
  assimilation over ice.

Deliverable: one publication in *JAMES* or *The Cryosphere*; one SOCA
retro showing quantified improvement.

### 6.7 One flagship partnership demonstration

Choose NVIDIA as the Year-1 anchor (stated interest already on the table):

- Demonstrate `oops::hofx` running against FourCastNet / SFNO forecasts as
  the "model forecast," with actual observations and CRTM.
- Produces observation-space diagnostics of FourCastNet against real obs
  — a rare artifact today.
- Joint NVIDIA/JCSDA blog post + GTC-class presentation.

### 6.8 AI-DA Strategy Working Group

- Chartered for FY27 with quarterly deliverables.
- Produces the FY28 technical roadmap addressing (a) latent-space DA,
  (b) differentiable JEDI prototype, (c) learned model-error correction,
  (d) learned QC.
- Cross-connects to NOAA 10-Year DA Strategy milestones and Project EAGLE.

### 6.9 `jedi-eval` — observation-space verification for AI weather models

A standalone package (UFO-based) that ingests AI-forecast output (GraphCast,
AIFS, Aurora, Prithvi, CREDIT-trained, etc.) in a standardized format and
produces the verification artifacts the existing community benchmarks cannot:

- Per-instrument O−F / O−A statistics against real observations (not
  reanalysis-referenced RMSE).
- FSOI-style per-observation impact scores for AI forecasts (extending the
  FSOI-QC pipeline of §6.3 to AI models).
- New-instrument generalization metrics: how does each AI model perform
  against an instrument it was not trained on? A structural DOP weakness
  that JEDI's plug-in operator stack makes trivial to probe.
- Coupled ocean + sea-ice verification against in-situ OceanBench-style
  observations — a capability WeatherBench 2 does not offer.

Deliverable: one public release of `jedi-eval` with a first round of
quarterly evaluations for 3–4 public-weight AI weather models, and one
whitepaper co-authored with partners (NCAR, ECMWF, NVIDIA). This is the
artifact that operationalizes §3.4.

### 6.10 NCAR + JCSDA joint AI-DA pilot via MPAS-JEDI

NCAR has an AI-NWP training platform (**CREDIT**[^credit]) with no DA loop;
JCSDA has a DA framework with no native AI-NWP. MPAS-JEDI is the existing
bilateral collaboration. The obvious joint deliverable:

- Wrap a CREDIT-trained AI model (WXFormer or a FuXi-class configuration) as
  an `oops::Model` implementation consumable by mpas-jedi.
- Run one full EnKF or 4D-EnVar cycle in mpas-jedi against a CREDIT-trained
  AI forecast model, using real observations and actual MPAS-JEDI
  configuration.
- Produce the first open-source demonstration of an AI-NWP model cycled
  inside an operational-grade DA framework against real observations.

Named counterparts: David Gagne / MILES at NCAR (CREDIT authors); JCSDA
MPAS-JEDI team. Non-trivial but contained — the interface contract is
`oops::Model`, which is well-defined. Deliverable: joint *JAMES* paper and
a reference configuration shipped in the bundle under a `mpas-jedi-credit`
profile.

---

## 7. Three-to-five-year vision (FY28–FY31)

**FY28 — Learned components at scale.**

- At least one operational test cycle uses CRTM-ONNX in production.
- Learned VarBC replaces classical VarBC for at least one instrument family.
- **FSOI-QC v2** — extended from Year-1 AMSU-A/ABI scope to full
  conventional + satellite observation set; running as a parallel shadow
  filter in a NOAA pre-operational cycle; being evaluated for acceptance as
  part of the NOAA next-generation QC pipeline.
- **AD standard selected.** Year-1 OASIM bake-off has chosen the JEDI AD
  technology (torch-autograd, Enzyme, or continued hand-coding with ML
  emulators for new operators). Three additional TLM-missing UFO operators
  (wind speed, pathsum, surface-corrected) ported to the chosen stack.
- An AI-aware ensemble DA prototype (EnKF cycled against GraphCast or AIFS
  ensembles) is running in research mode.
- Prithvi-WxC or an analogous foundation model is fine-tuned as a H-operator
  encoder for a hard-to-model instrument.

**FY29 — Hybrid foundation-model × JEDI.**

- A **torch-differentiable fv3-jedi Increment** exists and is used in at least
  one 4D-Var experiment.
- The chosen AD substrate (torch-autograd or Enzyme) is applied at scale:
  all new UFO operators are added without hand-coded TLMs. Backlog
  burn-down for legacy hand-coded TLMs has begun.
- Learned model-error correction is running inside fv3-jedi and soca.
- JCSDA publishes the first **coupled AI-DA experiment**: AI atmospheric
  forecast model coupled with soca ocean DA via the JEDI coupling layer.

**FY30 — Operational AI-DA.**

- A learned-component JEDI configuration is adopted as a production NOAA
  analysis path in at least one domain (e.g., regional hurricane DA).
- Silurian / Google / ECMWF cite JEDI analyses as their training or
  verification substrate.
- JCSDA evaluations of public AI weather models become the de-facto community
  reference.

**FY31 — The integrated stack.**

- JEDI 10.x ships with a native ML-component abstraction.
- A single YAML configuration selects classical, learned-component, or
  fully-end-to-end DA paradigms.
- Coupled atm–ocean–ice AI-DA is operational in a partner agency.

---

## 8. Risks and open questions

### 8.1 Dependency risks

- **libtorch ABI drift.** PyTorch C++ ABIs change frequently; spack-stack
  integration has already produced friction. Mitigation: pin versions
  conservatively and keep an ONNX Runtime fallback (precedent:
  CRTM-ONNX branch).
- **Talent.** Current JCSDA and partner staff are strong in C++/Fortran DA
  but thin in ML. Mitigation belongs in the hiring memo, not this one.
- **Data.** Training-quality observation datasets do not exist in a
  JCSDA-hosted form. The `ai-models/` registry and observation-archive
  investments in §6.1 begin to address this.
- **Geopolitics and licensing.** Aurora, Prithvi, GraphCast, AIFS are
  openly licensed; Pangu and FuXi are Chinese-origin with usage
  restrictions for some partner agencies. Mitigation: document the
  licensing posture of every integrated model.
- **Speed.** ECMWF, NOAA, and industry are all moving quickly. At least
  one externally visible artifact (NVIDIA demo, CRTM-ONNX merge, or
  FSOI-QC paper) must ship by end of FY27 to establish credibility
  before the FY28 funding cycle.

### 8.2 The DOP question — "JEDI doesn't help here"

The serious challenge to this memo's thesis is **Direct Observation
Prediction (DOP)** — end-to-end obs-to-forecast ML that skips classical
DA entirely. GraphDOP (ECMWF), Aardvark (Cambridge/Microsoft/ECMWF),
and FuXi Weather (Fudan) are three independent implementations. Full
treatment in `paper_ai_dop.md`; the short answer:

**What DOP actually removes.** The variational minimizer, the explicit
analysis step, and explicit B/R covariance estimation. JEDI's inner DA
algorithm is genuinely not part of a DOP forecast pipeline.

**What DOP does not remove.** Observation ingestion and decoding
(BUFR/HDF5/NetCDF), real-time QC of grossly wrong observations, bias
correction of drifting satellites, observation operators for *new*
instruments, coupled atm–ocean–ice DA, analyses as a first-class
deliverable (reanalysis, downstream applications), and FSOI-style
impact diagnostics. Every one of these is a JCSDA core competency and
an active gap in the DOP literature.

**Three independent signals that DOP is not displacing DA.**

1. ECMWF DG Florence Rabier (NL 182): *"Current ML methods still
   require an optimal starting point for their forecasts, and this is
   provided by data assimilation."*[^rabier] ECMWF runs both paradigms
   in parallel.
2. The most aggressive ML-forecast lab — Fudan — built FuXi-DA[^fuxida]
   and FuXi-En4DVar[^fuxi4dvar] *after* FuXi Weather. The frontier is
   rebuilding DA in ML form, not skipping it.
3. Every frontier AI model (DOP or otherwise) trained on reanalysis.
   Reanalysis is a DA product. The DA past is load-bearing for the
   AI-forecast future.

**Where DOP is structurally weakest — regional / convection-scale.**
StormCast[^stormcast], HRRRCast[^hrrrcast], WoFSCast[^wofscast], and
all current regional AI efforts (including RRFS-JEDI and MPAS-JEDI)
take a DA-produced analysis as initial condition. Radar — the
defining convective observation — is ingested by no published DOP
system. See `paper_regional_ai.md`.

**Repositioning.** Treat JEDI as the neutral US observation platform
underneath both paradigms:

- IODA as the ingestion layer feeding classical *and* AI-DOP pipelines.
- New-instrument rapid onboarding as a JEDI differentiator (DOP
  requires retraining; UFO requires YAML).
- Coupled atm–ocean–ice DA as the unique offering (§6.6).
- FSOI-QC and real-time diagnostics (§6.3) as services DOP needs but
  cannot produce.
- Reanalysis-grade analyses as training fuel for the next AI
  generation — a natural JCSDA–NOAA–NASA pitch.

---

## 9. Scope limits

This memo is technical strategy only. It does not propose organizational
structure, hiring, costs, or FTEs — those belong in a separate memo.
Partnership targets are directional, not contractual. The posture toward
Anemoi, Modulus, and Earth-2 is interoperation, not displacement.

---

## 10. Request

The specific asks of the Director are:

1. **Endorse the two-pillar framing** (AI-for-observation-science, not AI-for-
   forecasting) as the public-facing JCSDA AI posture.
2. **Charter the AI-DA Strategy Working Group** for FY27 with a quarterly
   deliverable cadence.
3. **Approve the ten Year-1 deliverables in §6** as the FY27 technical
   milestones for the JCSDA AI workstream.
4. **Sanction exploratory partnership conversations** with NVIDIA, NASA/IBM
   Prithvi team, Silurian, DeepMind, the ECMWF AIFS/Anemoi team, and
   NSF NCAR (MILES + MMM for the MPAS-JEDI + CREDIT pilot, AI2ES for
   trustworthy-AI-DA methodology).
5. **Align Year-1 deliverables with NOAA's 10-Year DA Strategy and Project
   EAGLE** at the program-review level so JCSDA's AI investment is
   institutionally legible inside NOAA.

---

## References

Supporting notes: see `paper_foundation_weather_models.md`,
`paper_ml_data_assimilation.md`, `paper_differentiable_programming.md`,
`paper_ocean_coupled_ai.md`, `paper_pinn_and_piml.md`, `paper_ai_dop.md`,
`paper_ncar_ai.md`, `paper_ai_benchmarks.md`, `paper_regional_ai.md`,
`competitive_landscape.md`, and `existing_jedi_ai_work.md` in this directory.

[^pangu]: Bi, K. et al. "Accurate medium-range global weather forecasting with
3D neural networks." *Nature* **619**, 533–538 (2023).
[arXiv:2211.02556](https://arxiv.org/abs/2211.02556).

[^graphcast]: Lam, R. et al. "Learning skillful medium-range global weather
forecasting." *Science* **382**, 1060–1066 (2023). [DOI](https://www.science.org/doi/10.1126/science.adi2336).

[^gencast]: Price, I. et al. "Probabilistic weather forecasting with machine
learning." *Nature* **637**, 84–90 (2024).
[Nature](https://www.nature.com/articles/s41586-024-08252-9).
[arXiv:2312.15796](https://arxiv.org/abs/2312.15796).

[^aurora]: Bodnar, C. et al. "A foundation model for the Earth system."
*Nature* (May 2025). [arXiv:2405.13063](https://arxiv.org/abs/2405.13063).
[microsoft/aurora](https://github.com/microsoft/aurora).

[^aifs]: ECMWF, "ECMWF's AI forecasts become operational" (Feb 2025).
[ECMWF](https://www.ecmwf.int/en/about/media-centre/news/2025/ecmwfs-ai-forecasts-become-operational).

[^aifs-ens]: ECMWF, "ECMWF's ensemble AI forecasts become operational"
(Jul 2025). [ECMWF](https://www.ecmwf.int/en/about/media-centre/news/2025/ecmwfs-ensemble-ai-forecasts-become-operational).
AIFS 1.1.0 preprint: [arXiv:2509.18994](https://arxiv.org/abs/2509.18994).

[^neuralgcm]: Kochkov, D. et al. "Neural general circulation models for
weather and climate." *Nature* **632**, 1060–1066 (2024).
[arXiv:2311.07222](https://arxiv.org/abs/2311.07222).

[^prithvi]: Schmude, J. et al. "Prithvi WxC: Foundation Model for Weather and
Climate" (IBM + NASA, 2024). [arXiv:2409.13598](https://arxiv.org/abs/2409.13598) ·
[Hugging Face checkpoint](https://huggingface.co/ibm-nasa-geospatial/Prithvi-WxC-1.0-2300M).

[^eagle]: NOAA EPIC, "Project EAGLE to accelerate AI weather prediction."
[EPIC](https://epic.noaa.gov/noaa-project-eagle-to-accelerate-ai-weather-prediction-advances-for-the-united-states/).
NOAA 10-Year DA Strategy: [EPIC](https://epic.noaa.gov/10-year-strategy-for-data-assimilation/).

[^stegmann]: Stegmann, P. G. et al. "A deep learning approach to fast
radiative transfer." *JQSRT* (2022).
[ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0022407322000255) ·
[NOAA repo](https://repository.library.noaa.gov/view/noaa/64509/noaa_64509_DS1.pdf).
Probabilistic CRTM emulator follow-up:
[arXiv:2504.16192](https://arxiv.org/abs/2504.16192).

[^zhang]: Zhang, Y. et al. "Impacts of Offline Nonlinear Bias Correction
Schemes Using ML on the All-Sky Assimilation of Cloud-Affected Infrared
Radiances." *JAMES* (2024).
[DOI](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2024MS004281).

[^liang]: Liang, X. et al. "A Machine Learning Approach to the Observation
Operator for Satellite Radiance Data Assimilation." *JMSJ* **101**, 79–95
(2023).
[JMSJ](https://www.jstage.jst.go.jp/article/jmsj/101/1/101_2023-005/_html/).

[^fablet]: Fablet, R. et al. "Learning Variational Data Assimilation Models
and Solvers." *JAMES* (2021).
[DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2021MS002572).
4DVarNet-SSH: Beauchamp et al., *GMD* **16**, 2119 (2023).

[^farchi]: Farchi, A. et al. "Using machine learning to correct model error
in data assimilation and forecast applications." *QJRMS* **147** (2021).
[DOI](https://rmets.onlinelibrary.wiley.com/doi/10.1002/qj.4116).

[^geer]: Geer, A. "Data assimilation or machine learning?" *ECMWF Newsletter*
**167** (2021).
[ECMWF](https://www.ecmwf.int/en/newsletter/167/meteorology/data-assimilation-or-machine-learning).

[^wb2]: Rasp, S. et al. "WeatherBench 2: A Benchmark for the Next Generation
of Data-Driven Global Weather Models." *JAMES* (2024).
[DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2023MS004019) ·
[arXiv:2308.15560](https://arxiv.org/abs/2308.15560).

[^hotta]: Hotta, D., Kalnay, E., Ota, Y. "Proactive QC: A Fully Flow-Dependent
Quality Control Scheme Based on EFSO." *Monthly Weather Review* **145**,
3331–3354 (2017).
[DOI](https://journals.ametsoc.org/view/journals/mwre/145/8/mwr-d-16-0290.1.xml).
Follow-up: Chen, T.-C. & Kalnay, E., "Proactive Quality Control: Observing
System Experiments Using the NCEP Global Forecast System", *MWR* **148**,
3911–3931 (2020).
[DOI](https://journals.ametsoc.org/view/journals/mwre/148/9/mwrD200001.xml).

[^phiflow]: Holl, P. & Thuerey, N. "PhiFlow: Differentiable Simulations for
PyTorch, TensorFlow and Jax." ICML (2024).
[GitHub](https://github.com/tum-pbs/PhiFlow) ·
[ICML paper](https://proceedings.mlr.press/v235/holl24a.html).

[^mitgcmad]: Gaikwad, S. et al. "MITgcm-AD v2: Open source tangent linear
and adjoint modeling framework for the oceans and atmosphere enabled by the
Automatic Differentiation tool Tapenade." arXiv:2401.11952 (2024).
[arXiv](https://arxiv.org/abs/2401.11952).

[^bgcunet]: Neural emulator of marine biogeochemistry (BGC-UNet / Black Sea
application). Frontiers in Marine Science (2026).
[Frontiers](https://www.frontiersin.org/journals/marine-science/articles/10.3389/fmars.2026.1760162/full).
See also Hybrid ML DA for Marine Biogeochemistry:
[arXiv:2504.05218](https://arxiv.org/abs/2504.05218).

[^rabier]: Rabier, F. "Forecasts from observations" (editorial). *ECMWF
Newsletter* **182** (2024).
[ECMWF](https://www.ecmwf.int/en/newsletter/182/editorial/forecasts-observations).
Companion technical update: "An update on AI-DOP: skilful weather forecasts
produced directly from observations." *ECMWF Newsletter* **182**.
[ECMWF](https://www.ecmwf.int/en/newsletter/182/earth-system-science/update-ai-dop-skilful-weather-forecasts-produced-directly).

[^fuxida]: Xu et al. "FuXi-DA: a generalized deep learning data assimilation
framework for assimilating satellite observations." *npj Clim. Atmos. Sci.*
(2025).
[npj](https://www.nature.com/articles/s41612-025-01039-3).

[^fuxi4dvar]: Li et al. "FuXi-En4DVar: An Assimilation System Based on
Machine Learning Weather Forecasting Model Ensuring Physical Constraints."
*GRL* (2024).
[DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2024GL111136).

[^raissi]: Raissi, M., Perdikaris, P. & Karniadakis, G. E. "Physics-informed
neural networks: A deep learning framework for solving forward and inverse
problems involving nonlinear partial differential equations." *JCP* **378**,
686–707 (2019).
[ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0021999118307125).
Survey: Karniadakis et al., "Physics-informed machine learning", *Nat. Rev.
Phys.* **3**, 422–440 (2021).
[Nature](https://www.nature.com/articles/s42254-021-00314-5).

[^licrtm]: Li et al. "Physics-constraint deep learning based radiative
transfer emulator." *Optics Express* **31**(17), 28596 (2023). NOAA/NESDIS
work incorporating a Jacobian-accuracy loss term into a CRTM neural-network
emulator.
[Optics Express](https://opg.optica.org/abstract.cfm?uri=oe-31-17-28596) ·
[NOAA PDF](https://repository.library.noaa.gov/view/noaa/55900/noaa_55900_DS1.pdf).
Directly relevant: Mishra & Molinaro, "Physics Informed Neural Networks for
Simulating Radiative Transfer," *JQSRT* 270 (2021).
[arXiv:2009.13291](https://arxiv.org/abs/2009.13291).

[^gregory2023]: Gregory, W. et al. "Deep Learning of Systematic Sea Ice
Model Errors From Data Assimilation Increments." *JAMES* (2023).
[DOI](https://agupubs.onlinelibrary.wiley.com/doi/abs/10.1029/2023MS003757).
Follow-up: Gregory et al., "Advancing global sea ice prediction capabilities
using a fully coupled climate model with integrated machine learning",
*Science Advances* (2025).
[Science Advances](https://www.science.org/doi/10.1126/sciadv.ady8957).

[^ecmwf177]: ECMWF Newsletter 177 (2023). "Combining machine learning and
data assimilation to estimate sea ice concentration."
[ECMWF](https://www.ecmwf.int/en/newsletter/177/earth-system-science/combining-machine-learning-and-data-assimilation-estimate).
Jointly learns sea-ice state and sea-ice surface emissivity inside a DA
framework.

[^torchclim]: Zhang, C. et al. "TorchClim v1.0: a deep-learning plugin for
climate model physics." *GMD* **17**, 5459–5479 (2024).
[GMD](https://gmd.copernicus.org/articles/17/5459/2024/). Canonical precedent
for embedding libtorch inference into a large Fortran-based Earth-system
model (CESM). Companion precedent: Liu et al., "Enabling scientific machine
learning in MOOSE using Libtorch" (*SoftwareX*, 2024).

[^vandenberghe]: Vandenberghe, F., Bolmier, G., Auligné, T., Mahajan, R. B.,
Holdaway, D. "Predicting Forecast Sensitivity: Observation Impact with
Machine Learning." AMS 99th Annual Meeting (2019). JCSDA, Boulder, CO.
[Abstract](https://ams.confex.com/ams/2019Annual/webprogram/Paper354865.html).
Tested gradient boosting and neural networks to predict FSOI for AMSU-A /
NOAA-18; reported that non-linear methods improved prediction over linear
baselines. No peer-reviewed follow-up identified as of 2026. JCSDA-internal
FSOI pipeline: [JCSDA-internal/FSOI](https://github.com/JCSDA-internal/FSOI)
(last active 2022).

[^latent]: "Physically consistent global atmospheric data assimilation with
machine learning in latent space." *Science Advances* (2025).
[Science Advances](https://www.science.org/doi/10.1126/sciadv.aea4248) ·
[arXiv:2502.02884](https://arxiv.org/abs/2502.02884).

[^credit]: Schreck, J. S. et al. "Community Research Earth Digital Intelligence
Twin (CREDIT)." *npj Climate and Atmospheric Science* (2025).
[arXiv:2411.07814](https://arxiv.org/abs/2411.07814). NCAR/MILES PyTorch
AI-NWP training platform (WXFormer, FuXi implementations) on Derecho.

[^ai2es]: AI Institute for Research on Trustworthy AI in Weather, Climate,
and Coastal Oceanography (AI2ES). NSF AI Institute led by A. McGovern
(University of Oklahoma) with NCAR, NOAA, and university partners.
[ai2es.org](https://www.ai2es.org).


[^chaosbench]: Nathaniel, J. et al. "ChaosBench: A multi-channel,
physics-based benchmark for subseasonal-to-seasonal climate prediction."
*NeurIPS Datasets & Benchmarks* (2024).
[arXiv:2402.00712](https://arxiv.org/abs/2402.00712).

[^extremewx]: ExtremeWeatherBench (BrightBand / community).
[GitHub](https://github.com/brightbandtech/ExtremeWeatherBench). Benchmark
for AI skill on extreme events (heat waves, atmospheric rivers, tropical
cyclones).

[^oceanbench]: Février, M. et al. "OceanBench: A global ocean forecasting
benchmark." *NeurIPS Datasets & Benchmarks* (2025). Mercator Ocean
International. The only existing AI benchmark with a direct
model-to-observations (CLASS-4 in-situ) verification track.

[^stormcast]: Pathak, J. et al. "StormCast: Kilometer-scale convection-
allowing model emulation using generative diffusion modeling."
[arXiv:2408.10958](https://arxiv.org/abs/2408.10958) (2024). NVIDIA.

[^hrrrcast]: NOAA GSL. "HRRRCast: An AI emulator for the High-Resolution
Rapid Refresh." [arXiv:2507.05658](https://arxiv.org/abs/2507.05658)
(2025). V3 released March 2026 at 3-km resolution.

[^wofscast]: Flora, M. L. et al. "WoFSCast: A machine-learning emulator
of the Warn-on-Forecast System." *Geophysical Research Letters* (2025).
[DOI](https://doi.org/10.1029/2024GL112383). GraphCast architecture
adapted to storm-scale ensemble DA.

[^nnradar]: Liu, Y. et al. "A neural-network radar reflectivity
observation operator for variational data assimilation."
[arXiv:2512.18289](https://arxiv.org/abs/2512.18289) (2025).

[^radarqc]: Hu, J. et al. "Machine-learning quality control for airborne
Doppler radar observations." *Artificial Intelligence for the Earth
Systems* (2024).

[^corrdiff]: Mardani, M. et al. "Residual diffusion modeling for
km-scale atmospheric downscaling." *Nature Communications Earth &
Environment* (2025). [DOI](https://doi.org/10.1038/s43247-025-02042-5).
NVIDIA Earth-2 CorrDiff.

### Additional context

- **GraphDOP** (ECMWF, observation-only forecast research):
  [arXiv:2412.15687](https://arxiv.org/abs/2412.15687). DA-diagnostic follow-up:
  [arXiv:2510.27388](https://arxiv.org/abs/2510.27388).
- **Aardvark Weather** (end-to-end observation-to-forecast):
  Allen et al., *Nature* (Mar 2025).
  [arXiv:2404.00411](https://arxiv.org/abs/2404.00411) · [Nature](https://www.nature.com/articles/s41586-025-08897-0).
- **Score-based DA**: Rozet & Louppe, NeurIPS 2023.
  [arXiv:2306.10574](https://arxiv.org/abs/2306.10574).
- **Anemoi** ECMWF framework:
  [ecmwf/anemoi](https://github.com/ecmwf/anemoi).
- **NVIDIA SFNO / torch-harmonics / FourCastNet 3**:
  [SFNO blog](https://developer.nvidia.com/blog/modeling-earths-atmosphere-with-spherical-fourier-neural-operators/) ·
  [FCN3 blog](https://developer.nvidia.com/blog/fourcastnet-3-enables-fast-and-accurate-large-ensemble-weather-forecasting-with-scalable-geometric-ml/).
- **Silurian AI**: [silurian.ai](https://silurian.ai/) ·
  [GFT-C announcement](https://silurian.ai/blog/gft-cyclones).
- **Ensemble DA with AI forecast models**:
  [arXiv:2407.17781](https://arxiv.org/abs/2407.17781).
- **ClimaX**: Nguyen et al., ICML 2023.
  [arXiv:2301.10343](https://arxiv.org/abs/2301.10343).

---

*End of memo. Supporting research notes in this directory.*
