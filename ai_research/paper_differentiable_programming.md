# Distillations: Differentiable Programming & Autograd Substrates

Target audience: internal notes feeding the JCSDA AI strategy memo.
Coverage: "torch as an autograd substrate for JEDI" — i.e., using libtorch
C++ not to run neural networks, but to get tangent-linear and adjoint
operators *for free* by reimplementing physics-based operators in torch
tensors. Plus the direct competition — Tapenade, Enzyme, JAX.

This is conceptually distinct from the foundation-model and ML-surrogate
literature and needs its own vocabulary.

---

## The two modes, clearly separated

### Mode A — ML emulation

Train a neural network to approximate an existing forward operator H(x).
After training, the NN provides fast forward evaluation and (via autograd)
an analytic Jacobian. Cost: training data, loss design, accuracy bounds.
Representative prior art:

- **CRTM emulators** — Stegmann et al. (2022), *JQSRT* — deep NN surrogate for
  CRTM.
  [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0022407322000255)
- **BGC-UNet / Black Sea neural emulator** — Frontiers in Marine Science
  (2026). Neural surrogate for coupled ocean-biogeochemical model.
  [Frontiers](https://www.frontiersin.org/journals/marine-science/articles/10.3389/fmars.2026.1760162/full)
- **Surface chlorophyll neural emulator for Earth System Model**
  (2024/25, Progress in Oceanography).
  [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S146350032400177X)
- **Coastal ocean circulation model AI surrogate** — arXiv:2410.14952 (2024).
- **WOMBAT ML surrogate** — Pearson et al. (2024) — Australian WOMBAT ocean
  biogeochemistry calibrated with ML surrogate.
- **Hybrid ML DA for marine biogeochemistry** — arXiv:2504.05218 (2025).

### Mode B — Direct physics-in-torch for autograd

Reimplement an existing operator as a torch C++ function using tensor ops.
No neural network, no training. You get TLM + adjoint from
`torch::autograd::grad()` at negligible extra coding cost. Cost: one-time
engineering rewrite, possible perf hit vs. hand-optimized Fortran.

- **PhiFlow** (Holl, Thuerey) — differentiable PDE framework, ICML 2024;
  PyTorch/TensorFlow/JAX backends; GPU-capable fluid dynamics whose gradients
  compose with ML losses.
  [PhiFlow GitHub](https://github.com/tum-pbs/PhiFlow) ·
  [ICML paper](https://proceedings.mlr.press/v235/holl24a.html)
- **DiffTaichi** (Hu et al., ICLR 2020) — differentiable physics language for
  graphics + science; produces adjoint-mode gradients for written-from-scratch
  physics simulators.
- **torch-md / mdgrad** — PyTorch-differentiable molecular dynamics.
- **lcp-physics** — differentiable rigid-body physics engine in PyTorch.
- **torch-sla** (arXiv:2601.13994, 2026) — differentiable sparse linear
  algebra with adjoint solvers and sparse tensor parallelism for PyTorch.
  Directly relevant to DA cost-function minimization.
- **DiffSharp** — autodiff library with libtorch backend; example of using
  libtorch's tensor ops as a pure AD substrate.

Mode B is the one that eliminates hand-coded TLM. Mode A is the one that
eliminates hand-coded *everything* at the cost of accuracy.

---

## AD technology comparison

JEDI currently maintains TLM + adjoint by hand for virtually every operator
that has them. The question is: what automated AD technology would most
reduce that burden while preserving correctness and performance?

| Technology | Works on | Intrusion | Maturity | GPU | Composes with NNs |
|------------|----------|-----------|----------|-----|-------------------|
| **Hand-coded TLM/ADM** | any language | none (but high maintenance) | JEDI baseline | N/A | No |
| **Tapenade** (source-to-source AD) | Fortran, C | Low (preprocessor) | Very mature | No | No |
| **OpenAD** | Fortran, C | Low | Mature; less active | No | No |
| **Enzyme** (LLVM-IR level) | C, C++, Fortran, Julia, Rust, Swift | Minimal (compiler plugin) | Active, rapid growth | Yes (CUDA, HIP) | Partial (Julia side) |
| **libtorch autograd** (tensor-level) | C++ (+ Python); Fortran via ISO_C_BINDING wrapper | High (rewrite operator in torch tensors) | Mature | Yes, first-class | **Yes — same graph** |
| **JAX** (trace-compile AD) | Python, with XLA compilation | Highest (rewrite in Python/JAX) | Very mature | Yes | Yes |

### Key contrasts

- **Tapenade** is the current gold standard in Earth-system-adjacent work.
  **MITgcm-AD v2** is built on Tapenade and handles 10+ tutorial experiments
  including sea-ice and biogeochemistry.
  [MITgcm-AD v2 arXiv:2401.11952](https://arxiv.org/abs/2401.11952).
  Downside: Fortran-only, no GPU, no ML interop.

- **Enzyme** — LLVM-plugin AD. Paper: "Instead of Rewriting Foreign Code for
  Machine Learning" (Moses & Churavy, NeurIPS 2020).
  [Enzyme site](https://enzyme.mit.edu/). Differentiates existing compiled
  code with minimal annotation. The **Oceananigans.jl + Enzyme.jl** stack (via
  the DJ4Earth project) is the current reference architecture for
  differentiable ocean modeling. Enzyme works on Fortran too, which is
  critical for JEDI's fv3-jedi and mpas-jedi Fortran codebases.

- **libtorch autograd** — the tensor-level AD built into PyTorch, available
  as a C++ API via libtorch. Already linked into JEDI through TorchBalance
  and MLBalance (though those use TorchScript inference, not autograd).
  Highest intrusion — requires rewriting — but the only option that **puts
  physics and learned components in the same computational graph**.

- **JAX** — best-in-class for pure-Python differentiable science
  (NeuralGCM[^neuralgcm] is the headline example). Not a natural fit for a
  C++/Fortran codebase without a rewrite. Rule out for core JEDI but
  relevant if JCSDA ever hosts a Python-first companion stack.

---

## Literature precedents in Earth-system / atmosphere / ocean

- **NeuralGCM** (Kochkov et al., *Nature* 2024) — JAX-based GCM with
  differentiable dycore + ML subgrid. Proves Mode A + Mode B at GCM scale.
  [Nature](https://www.nature.com/articles/s41586-024-07744-y).
- **MITgcm-AD v2** (2024) — full-Tapenade AD of a production ocean model
  including biogeochemistry packages. The closest Mode-B-adjacent precedent
  for a JEDI-style codebase. [arXiv:2401.11952](https://arxiv.org/abs/2401.11952).
- **DJ4Earth / Oceananigans.jl + Enzyme.jl** — Moses et al. (2025),
  "Differentiable, and performance-portable Earth System Modeling via program
  transformations." Julia + Enzyme as the reference differentiable-Earth
  stack.
- **Differentiable Programming for Earth System Modeling** — Gelbrecht et al.
  (2023), *GMD*/EGUsphere preprint.
  [EGUsphere](https://egusphere.copernicus.org/preprints/2022/egusphere-2022-875/egusphere-2022-875-manuscript-version4.pdf).
  Review of differentiable programming for climate/Earth-system.
- **Hybrid machine learning data assimilation for marine biogeochemistry**
  (2025, arXiv:2504.05218) — treats ocean BGC DA specifically with ML.
- **Optimal control of PDEs in PyTorch** (arXiv:2408.12404, 2024) — uses
  torch autograd + NN surrogates to solve PDE-constrained optimization.

---

## OASIM as a concrete JEDI pilot target

OASIM (Ocean-Atmosphere Spectral Irradiance Model) is the canonical
"no-TLM-exists" operator in JEDI. From the codebase scan:

- **Location:** `bundle/ufo/src/ufo/operators/oasim/`
- **Status:** Optional build (`BUILD_OASIM=OFF` by default in bundle
  CMakeLists.txt); C++ wrapper around Fortran module around external OASIM
  library.
- **TLM/adjoint:** None. No `ObsRadianceOASIMTLAD.*` files exist.
- **Nonlinearity:** Radiative transfer through absorbing and scattering
  seawater constituents — strongly nonlinear in chlorophyll, CDOM, detritus,
  and minerals.
- **Why it matters:** Without TLM, this operator cannot be used in 4D-Var or
  any gradient-based DA. That locks it out of the entire variational toolbox
  soca supports.

**Mode-B pilot proposal:** Reimplement OASIM's forward operator in libtorch
C++ (or keep the Fortran physics and wrap it in a torch `autograd::Function`
via a differentiable surrogate for the nonlinear kernels). Run forward
through `torch::autograd::grad` to obtain analytic TLM/adjoint. Validate
adjoint via taylor-test against the forward operator. Deploy in a soca 3D-Var
over an ocean-color assimilation experiment.

Success criteria:
- Numerical adjoint test passes (dot-product consistency <1e-10).
- Forward runtime within 2–3× of the raw Fortran forward.
- One assimilation experiment demonstrating ocean-color observations (MODIS /
  VIIRS / PACE) impacting chlorophyll and carbon-state analysis.

If the pilot works, OASIM becomes the template for other "no-TLM" operators
in UFO — wind-speed, surface-corrected, pathsum, and several vertical-
interpolation variants are all candidates.

**Enzyme-on-Fortran pilot proposal (parallel track):** Apply Enzyme to the
existing OASIM Fortran module without rewriting it in torch. Compare both
technologies side-by-side on the same operator. Decision at end of pilot:
which AD technology wins as the JEDI standard for future operators?

---

## Where this fits in JEDI's existing torch landscape

**Important observation from the codebase:** Both TorchBalance (SABER) and
the retired MLBalance (SOCA) use libtorch for **inference only**. They load
TorchScript modules that expose Jacobians as *pre-computed methods* (e.g.
`module.get_method("jac_physical")`), meaning the derivative structure is
baked in at export time in Python. No `torch::autograd::grad` call exists in
the JEDI tree today.

That means the proposed "Mode B for autograd" is **a genuinely new capability
for JEDI**, not an extension of existing torch use. It would unlock:

1. TLM/adjoint for currently-TLM-less operators (OASIM, some windspeed
   variants, pathsum, etc.).
2. Composability: mix hand-written physics (in torch) with learned NNs (also
   in torch) in a single autograd graph — enabling, e.g., a hybrid operator
   where the physics is exact where we trust it and learned where we don't.
3. GPU acceleration via device placement, with no separate GPU port.
4. A forcing function for the PyTorch-in-JEDI standards (§6.1 in the main
   memo) — concrete requirements for autograd support push the `oops::MLModel`
   abstraction to be richer than inference-only.

---

## Honest risks

1. **Performance.** libtorch tensor ops carry dispatch overhead. For operators
   with small per-call workloads (tight O(10⁴) loops), Fortran will be
   faster. For larger per-call workloads (CRTM-like, BGC-like), torch is
   competitive and GPU is a free win.
2. **Rewrites are expensive.** The OASIM pilot should be the proof; full-repo
   migration is not justified unless the pilot is unambiguously successful.
3. **Enzyme might be a better answer for JEDI's Fortran-heavy fv3-jedi /
   mpas-jedi.** Run it in parallel before declaring torch the standard.
4. **Dependency growth.** libtorch is already in-tree for balance work. Making
   it load-bearing for more things increases blast radius of PyTorch version
   changes. spack-stack pin management gets more important.
5. **Library ABI.** C++ ABI incompatibility between GCC versions and libtorch
   builds has bitten this team before. CI must catch.

---

## Cross-cutting observations

1. The current JEDI use of libtorch is inference + pre-baked Jacobians — not
   live autograd. Adopting live autograd is a clear capability upgrade with a
   published precedent base (PhiFlow, NeuralGCM, mdgrad, lcp-physics, etc.).
2. Mode A (ML emulation) and Mode B (physics-in-torch for free AD) are
   different technologies, answer different questions, and should be tracked
   separately in the JCSDA strategy.
3. Enzyme is the rising star of Fortran/C++ AD and must be part of any JCSDA
   AD evaluation — not doing so risks locking into torch when Enzyme would be
   a lower-intrusion fit for much of the existing Fortran codebase.
4. The composability story (torch physics + torch NN in one graph) is the
   decisive argument for torch over Enzyme in cases where hybrid operators
   are the goal.

[^neuralgcm]: Kochkov, D. et al. "Neural general circulation models for
weather and climate." *Nature* **632**, 1060–1066 (2024).
