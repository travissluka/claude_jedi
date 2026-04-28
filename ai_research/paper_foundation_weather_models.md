# Distillations: Foundation-Scale Weather & Earth-System Models

Target audience: internal notes feeding the JCSDA AI strategy memo.
Coverage: the models that matter most for deciding where JCSDA should (and should
not) try to play on the "big, top-down" end of the spectrum.

---

## GraphCast (Google DeepMind, 2022/2023)

- **Reference:** Lam et al., *Science* 382, 1060–1066 (2023). arXiv:2212.12794.
  [Science](https://www.science.org/doi/10.1126/science.adi2336) ·
  [DeepMind blog](https://deepmind.google/blog/graphcast-ai-model-for-faster-and-more-accurate-global-weather-forecasting/) ·
  [GitHub (google-deepmind/graphcast)](https://github.com/google-deepmind/graphcast)
- **Architecture:** Graph neural network on an icosahedral multi-mesh over the
  sphere. Autoregressive 6 h step. Inputs: two analysis snapshots.
- **Training data:** ERA5 reanalysis, 39 yrs, 0.25°.
- **Output:** 10 days of deterministic forecasts, hundreds of variables, 0.25°.
- **Performance:** Outperformed ECMWF HRES on ~90% of 1380 verification targets.
  Runs a 10-day forecast in <1 minute on a single TPU v4.
- **Significance for JCSDA:**
  - First credible "the analysis is the input" model at operational skill.
  - **Critically dependent on a conventional analysis (ERA5 / GDAS)** for both
    training and initialization. JEDI-produced analyses are in its supply chain.
  - Weights are open and checkpoints are runnable — NOAA's Project EAGLE retrained
    GraphCast on GDAS as the basis of Global-EAGLE-Solo / Ensemble.

## GenCast (Google DeepMind, 2024)

- **Reference:** Price et al., *Nature* 637, 84–90 (2024). arXiv:2312.15796.
  [Nature](https://www.nature.com/articles/s41586-024-08252-9) ·
  [DeepMind blog](https://deepmind.google/blog/gencast-predicts-weather-and-the-risks-of-extreme-conditions-with-sota-accuracy/)
- **Architecture:** Diffusion model with GNN/sparse-transformer processor;
  generative per-step denoising produces stochastic trajectories.
- **Ensemble:** 50+ members per forecast; 15-day lead times, 0.25°.
- **Performance:** Beats ECMWF ENS on 97.2% of targets overall, 99.8% beyond 36 h
  lead. 8 min per 15-day member on TPU v5.
- **Significance for JCSDA:**
  - Generative AI moves from deterministic forecasting into probabilistic
    forecasting — directly competing with the EnKF/ensemble-mean paradigm.
  - But it still requires an initial analysis (still a DA problem).
  - Suggests a future where **ensemble DA produces the initial conditions and a
    diffusion model produces the forecast ensemble** — JEDI's native territory is
    the first half of that sentence.

## Pangu-Weather (Huawei, 2022/2023)

- **Reference:** Bi et al., *Nature* 619, 533–538 (2023). arXiv:2211.02556.
  [arXiv](https://arxiv.org/abs/2211.02556) ·
  [Nature announcement](https://www.huawei.com/en/news/2023/7/pangu-ai-model-nature-publish)
- **Architecture:** 3D Earth-Specific Transformer (3DEST); hierarchical
  time-step models (1 h, 3 h, 6 h, 24 h) to limit compounding error.
- **Training data:** ERA5, 0.25°, 43 yrs.
- **Performance:** First AI model to beat ECMWF HRES on deterministic targets at
  1 h to 7 day lead times; 10,000× faster inference.
- **Significance for JCSDA:** Establishes the transformer-on-gridded-ERA5 recipe
  that Aurora, Prithvi-WxC, and AIFS all later build on. Shows that architecture
  choice (3D vs 2D, Earth-specific positional encoding) matters.

## FourCastNet / SFNO / FourCastNet 3 (NVIDIA)

- **References:** Pathak et al. 2022 (arXiv:2202.11214); Bonev et al. 2023
  (Spherical Fourier Neural Operators, arXiv:2306.03838); FourCastNet 3 (2024/25).
  [SFNO blog](https://developer.nvidia.com/blog/modeling-earths-atmosphere-with-spherical-fourier-neural-operators/) ·
  [FCN3 blog](https://developer.nvidia.com/blog/fourcastnet-3-enables-fast-and-accurate-large-ensemble-weather-forecasting-with-scalable-geometric-ml/) ·
  [torch-harmonics](https://github.com/NVIDIA/torch-harmonics)
- **Architecture:** FCN1 used Adaptive Fourier Neural Operators on ViT backbone;
  FCN2 (SFNO) replaced Cartesian FFT with **differentiable spherical harmonic
  transforms** to respect sphere geometry and enable stable long rollouts
  (year-long on a single A6000). FCN3 scales to large ensembles.
- **Significance for JCSDA:**
  - NVIDIA's entire ML-weather stack is PyTorch-native and **open-source under
    permissive licenses** (torch-harmonics, Modulus, PhysicsNeMo).
  - Perfect interop substrate for JEDI's existing torch-based SABER/SOCA work.
  - NVIDIA has publicly stated partnership interest — they are the most
    technically-aligned "big" partner for JCSDA's bottom-up pillar.

## AIFS / AIFS-ENS / Anemoi (ECMWF, 2024–2026)

- **References:**
  - [AIFS 1.1.0 preprint](https://arxiv.org/abs/2509.18994) (2025, arXiv:2509.18994)
  - [AIFS-ENS operational](https://www.ecmwf.int/en/about/media-centre/news/2025/ecmwfs-ensemble-ai-forecasts-become-operational) (1 July 2025)
  - [Anemoi framework](https://github.com/ecmwf/anemoi) ·
    [ECMWF blog](https://www.ecmwf.int/en/about/media-centre/news/2024/anemoi-new-framework-weather-forecasting-based-machine-learning)
- **Status:** AIFS Single (deterministic) operational since 25 Feb 2025; AIFS-ENS
  (51-member ensemble) operational since 1 Jul 2025. Reports ~10× faster than
  IFS, ~1000× less energy. 20% improvement on surface temperature.
- **Framework:** Anemoi is a **Python/PyTorch open-source framework** for the full
  ML weather pipeline — `anemoi-datasets`, `anemoi-graphs`, `anemoi-models`,
  `anemoi-training`, `anemoi-inference`. Joint effort across ECMWF + 10 European
  NMHS. Permissive license.
- **Significance for JCSDA:**
  - Europe is operational with AI-NWP; the US is not.
  - Anemoi is the emerging **de-facto open-source backbone** for ML weather
    models. NOAA EPIC's Project EAGLE plans to use Anemoi going forward.
  - JCSDA should treat Anemoi the way it treats ATLAS or eckit: not a competitor,
    but a framework to **interoperate with** and contribute to.

## NeuralGCM (Google Research + ECMWF, 2024)

- **Reference:** Kochkov et al., *Nature* 632, 1060–1066 (2024). arXiv:2311.07222.
  [Nature](https://www.nature.com/articles/s41586-024-07744-y) ·
  [Google research](https://research.google/blog/fast-accurate-climate-modeling-with-neuralgcm/)
- **Architecture:** **Hybrid differentiable GCM** — spectral dycore rewritten in
  JAX + ML subgrid parameterizations. End-to-end differentiable, tuned online
  across many time steps.
- **Performance:** Deterministic and ensemble weather skill on par with best
  ML and physics-based methods; stable 40-yr climate integrations.
- **Significance for JCSDA:**
  - The "hybrid physics + ML, fully differentiable" paradigm — potentially the
    most important single direction for JEDI's long-term vision.
  - A differentiable model obviates the TLM/adjoint investment JCSDA has made
    across fv3-jedi, mpas-jedi, and soca — and enables 4D-Var on a GCM that
    trains itself. This is an existential question for the next 5 years.

## Aurora (Microsoft Research, 2024 / *Nature* 2025)

- **Reference:** Bodnar et al., *Nature* (May 2025). arXiv:2405.13063.
  [Nature](https://www.nature.com/articles/s41586-025-09005-y) ·
  [GitHub (microsoft/aurora)](https://github.com/microsoft/aurora)
- **Architecture:** 1.3B-parameter 3D Swin Transformer with 3D Perceiver
  encoder/decoder. Trained on >1M hours of weather + climate data, fine-tuned to
  multiple downstream tasks.
- **Capabilities:** Air quality, ocean waves, tropical cyclone tracks,
  high-resolution weather. ~5000× speedup over IFS. Beats GraphCast on 94% of
  targets.
- **Significance for JCSDA:**
  - First true **Earth-system foundation model** (atmos + waves + chemistry).
  - Spawned Silurian AI (ex-Aurora team). Aurora is the intellectual ancestor of
    the private-sector weather-foundation-model ecosystem.
  - Demonstrates **pretrain-then-fine-tune** as a viable paradigm for small-data
    problems (air quality, chemistry) — potentially useful for specialized UFO
    operators on instruments with limited training data.

## Prithvi-WxC (IBM + NASA, 2024)

- **Reference:** Schmude et al. (2024) arXiv:2409.13598.
  [Hugging Face](https://huggingface.co/ibm-nasa-geospatial/Prithvi-WxC-1.0-2300M) ·
  [NASA Earthdata](https://www.earthdata.nasa.gov/news/blog/prithvi-weather-climate-advancing-our-understanding-atmosphere)
- **Architecture:** 2.3B-parameter transformer, masked-reconstruction pretraining.
- **Training data:** NASA **MERRA-2 reanalysis**, 160 variables.
- **Fine-tuned tasks announced:** Gravity-wave parameterization, hurricane track
  & intensity, downscaling, climate projection.
- **Significance for JCSDA:**
  - Fully open weights on Hugging Face — rare among frontier weather models.
  - MERRA-2-trained (NASA DA product), not GDAS/ERA5 — makes it a **natural
    target for a JCSDA-hosted fine-tune on GDAS-family analyses**.
  - Demonstrates foundation-model-style pretrain/fine-tune for
    parameterization replacement, a pattern JCSDA could adopt for observation
    operators.

## ClimaX (Microsoft Research, 2023)

- **Reference:** Nguyen et al., ICML 2023. arXiv:2301.10343.
  [arXiv](https://arxiv.org/abs/2301.10343)
- **Architecture:** ViT with variable tokenization + variable aggregation —
  trained on CMIP6, fine-tunable to arbitrary variable sets.
- **Significance for JCSDA:** Intellectual precursor to Aurora. The
  "variable-tokenization" idea matters for JEDI because it mirrors the
  `oops::Variables` abstraction — an analogous ML architecture that adapts to
  whatever variable set a given model repo exposes would fit JEDI idiomatically.

## FuXi Weather (Fudan, 2024/2025)

- **Reference:** *Nature Communications* (2025).
  [Nature Comms](https://www.nature.com/articles/s41467-025-62024-1)
- **Architecture:** End-to-end learned **data-to-forecast** system that cycles
  its own analysis and forecast.
- **Significance for JCSDA:** An existence proof that the whole assimilation +
  forecast pipeline can be learned; but its analysis is not interpretable in
  observation-error / observation-operator terms, which is where JCSDA's
  expertise lives.

---

## Cross-cutting observations

1. **Everyone trains on reanalysis.** GraphCast, Pangu, GenCast, Aurora, AIFS,
   NeuralGCM, Prithvi-WxC — all trained on ERA5 or MERRA-2. **A reanalysis is a
   DA product.** The AI forecast era is built on the DA era, and will remain so
   until an observation-to-forecast path (GraphDOP / Aardvark) matures.
2. **PyTorch (with JAX a strong second) dominates.** Fortran is absent. JEDI's
   C++/Fortran/Python stack is the odd one out — but JEDI's torch integrations
   (TorchBalance, MLBalance, CRTM ONNX) show the bridge is viable.
3. **Differentiability is becoming a first-class requirement.** NeuralGCM, SFNO,
   Aardvark, Aurora fine-tuning all depend on end-to-end gradients. JEDI's
   classical TLM/adjoint infrastructure is not directly compatible with torch
   autograd — this is the single biggest technical gap to close.
4. **The center of gravity for "forecasting" is moving to industry and to
   Europe.** JCSDA cannot and should not try to out-forecast DeepMind or ECMWF.
   The strategy must be defined by what DA + observation science uniquely offers
   the ML forecast ecosystem.
