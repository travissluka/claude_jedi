# Distillations: Physics-Informed ML — What It Is, and When Torch Operators Help

Target audience: internal notes feeding the JCSDA AI strategy memo.
Purpose: clarify the question *"does rewriting observation operators in
torch pay off for physics-informed neural network work?"* — because the
answer depends on which flavor of PIML you mean.

---

## Four distinct techniques all get called "physics-informed"

It's worth separating them because they have different requirements on the
surrounding operator stack.

### 1. Classical PINN (Raissi, Perdikaris, Karniadakis 2019)

- **What it is.** A neural network `u_θ(x, t)` is trained to *be* the
  solution to a PDE. Loss has two parts: data loss (match measurements) +
  physics loss (PDE residual `r = ∂u_θ/∂t − N[u_θ]` evaluated via autograd
  on the NN's own outputs).
- **Reference:** Raissi, Perdikaris & Karniadakis, *JCP* **378** (2019).
  [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0021999118307125).
- **Does it need physics-in-torch?** *No.* The PDE operator is usually
  algebraic in derivatives of `u_θ` that autograd already provides. The
  "physics" is in the loss function formula, not in a torch-ed operator.
- **JEDI relevance.** Useful for *reconstructing state fields from sparse
  observations* (e.g., ocean interior flow from altimetry — see StrAss-PINN
  below). Less useful as a replacement for a forward observation operator,
  because classical PINNs are trained per-problem and don't generalize
  across scenes.

### 2. Physics-informed training of a learned operator

- **What it is.** Train an NN surrogate `H_θ(x) ≈ H_physics(x)` with a loss
  that combines (a) forward-output match + (b) physical constraints
  (conservation, monotonicity, nonnegativity, bounds).
- **Reference:** Karniadakis et al., *Nat. Rev. Phys.* **3** (2021)
  "Physics-informed machine learning" —
  [Nature](https://www.nature.com/articles/s42254-021-00314-5).
- **Does it need physics-in-torch?** *Sometimes.* If constraints are
  expressible as functions of NN outputs (e.g., nonnegative flux, Kirchhoff's
  law), no. If constraints require evaluating the physics operator inside
  the loss (e.g., Jacobian matching against the hand-coded K-matrix), then
  yes — physics must be differentiable in the training graph.
- **JEDI relevance.** This is the flavor that most naturally improves UFO
  emulators. A physics-constrained learned ocean bio-optics operator, for
  instance, would be strictly better than a plain MSE-trained one because
  it would refuse to produce negative radiances.

### 3. Jacobian-matching / K-matrix–preserving emulation

- **What it is.** Train the NN emulator so that *both* `NN(x) ≈ H(x)` *and*
  `∂NN/∂x ≈ ∂H/∂x`. Adds a Jacobian-accuracy loss term. Particularly
  important when the emulator must go into variational DA, because 3D-Var /
  4D-Var cost gradients depend on `∂H/∂x`.
- **Reference (directly relevant to JCSDA).** Li et al. (2023)
  "Physics-constraint deep learning based radiative transfer emulator" —
  NOAA/NESDIS work, *Optics Express* **31**(17), 28596.
  [OSA Publishing](https://opg.optica.org/abstract.cfm?uri=oe-31-17-28596) ·
  [NOAA repo PDF](https://repository.library.noaa.gov/view/noaa/55900/noaa_55900_DS1.pdf).
  This is the NOAA-authored CRTM emulator with *Jacobian-accuracy loss*.
  They computed CRTM's reference Jacobian (offline, from CRTM's K-matrix)
  and trained NN to match both output and Jacobian.
- **Does it need physics-in-torch?** *Partly.* The NOAA approach uses
  CRTM's K-matrix *dumped to disk* as a training target — no torch required
  on the physics side. But if CRTM (or OASIM, or any forward) were in
  torch, the Jacobian-matching loss could be computed *online* during
  training instead of dumped offline, dramatically simplifying pipelines.
- **JEDI relevance.** *Very high.* This is the bridge between §4.1
  TorchBalance work and §6.2 CRTM-ONNX work in the strategy memo — a
  Jacobian-accuracy-trained learned emulator is the honest answer for
  "use NN in a variational system without breaking adjoint tests."

### 4. Hybrid physics-ML operators (physics + NN in one autograd graph)

- **What it is.** A single callable whose internal computation mixes
  hand-written physics and learned components. Example:
  `H_hybrid(x) = H_fast_core(x) + NN_residual(x)` where the fast core is
  the cheap physics we trust and the NN models what the core gets wrong.
  The whole thing is one autograd tape.
- **Reference:** PhiFlow (Holl & Thuerey, ICML 2024) exemplifies this;
  NeuralGCM is the GCM-scale instance; "A Framework for Hybrid Physics-AI
  Coupled Ocean Models" (arXiv:2510.22676, 2025) is the ocean-DA instance.
- **Does it need physics-in-torch?** *Yes — this is the decisive case.*
  If the physics is not in torch, you can't compose it with the NN in a
  single backward pass. This is the unique capability torch-for-operators
  unlocks, and neither Tapenade nor Enzyme provides it equally cleanly.
- **JEDI relevance.** The highest-value pattern for the next decade. This
  is where "learned VarBC is not a separate module, but a learned residual
  on a torch-ed CRTM" becomes expressible in a single cost-function graph.

### Honorable mention: Neural Operators (DeepONet, FNO, PINO)

- **What they are.** Learn the mapping from one *function* (e.g., an
  initial condition) to another *function* (e.g., a solution field).
  DeepONet uses branch/trunk architecture (Lu, Jin, Pang, Zhang & Karniadakis,
  *Nat. Mach. Intell.* **3** (2021), arXiv:1910.03193). FNO uses Fourier
  layers. PINO adds PDE-residual loss on top of FNO.
  - [DeepONet GitHub](https://github.com/lululxvi/deeponet)
- **JEDI relevance.** Lower near-term. A DA system does not typically need
  operator-to-operator learning at the problem's global scale. Most useful
  as a replacement for a model's dynamical core (NeuralGCM-adjacent), which
  is the deep long-term agenda, not Year 1.

---

## The key table: when does physics-in-torch actually pay off?

| PIML flavor | Physics-in-torch helps? | Value for JEDI | Notes |
|-------------|-------------------------|----------------|-------|
| Classical PINN (state reconstruction) | No | Low | Solution lives in the NN; loss is algebraic |
| Physics-constrained emulator training | Sometimes | Medium | Only if constraints involve physics calls |
| **Jacobian-matching emulation** | **Online: yes; offline: no** | **High** | Online Jacobian loss simplifies training |
| **Hybrid physics + NN operators** | **Yes, decisively** | **Very high** | Only feasible if physics is in the autograd graph |
| Neural operators (DeepONet/FNO) | No | Low near-term | Orthogonal technology |

So the honest answer to the user's question *"is this where having
observation operators in torch is useful?"* is:

- **For classical PINN work** — not particularly.
- **For physics-constrained emulation** — helpful but not essential.
- **For Jacobian-matching emulation done online** — yes, a real productivity
  win; matches the direct prior art of NOAA-internal CRTM emulation.
- **For hybrid physics + learned operators** — indispensable; this is the
  decisive strategic reason to write observation operators in torch.

---

## Concrete JEDI opportunities that become expressible

Once forward operators live in torch (Mode B from §4.6 of the strategy memo),
these patterns become one-line code changes instead of multi-person
rewrites:

1. **Hybrid CRTM operator for cloudy/all-sky cases:** forward core in torch,
   NN residual for cloud-affected channels, single autograd graph. Trains
   end-to-end against brightness-temperature observations.
2. **Learned bias correction co-trained with the operator:** VarBC's linear
   predictor model becomes an NN inside the same graph as the forward
   operator, with physics-consistency loss terms.
3. **Online Jacobian-matched OASIM emulator:** the §6.4 OASIM pilot gains a
   natural follow-on where an emulator is trained with *both* output and
   Jacobian losses in a single training loop — no K-matrix dump step.
4. **Physics-informed sea-ice emissivity operator:** the ECMWF Newsletter 177
   pattern, with Kirchhoff's law enforced via a loss term and monotonicity
   with temperature enforced via architecture, both inside an autograd-
   compatible UFO filter stage.
5. **4D-Var through a torch operator chain:** the forward operator, the
   learned correction, and the classical minimizer all share one
   differentiable pathway; the 4D-Var cost gradient is literally the torch
   autograd gradient of a single Python-callable-or-C++-invocable function.

---

## Prior art directly relevant to JCSDA

- **Li et al. (2023)** — CRTM physics-constrained emulator (NOAA/NESDIS).
  Near-identical to what an internal JCSDA effort would produce.
  [Optics Express](https://opg.optica.org/abstract.cfm?uri=oe-31-17-28596).
- **Mishra & Molinaro (2021, 2022)** — "Physics Informed Neural Networks for
  Simulating Radiative Transfer", *JQSRT* arXiv:2009.13291. Full PINN
  formulation for RT.
- **Zhu et al. (2024)** — "Physics-informed neural networks for modeling
  atmospheric radiative transfer", *JQSRT* 309 (2024) 109253.
  [JQSRT](https://www.sciencedirect.com/science/article/abs/pii/S0022407324003601).
- **Rosenthal et al. (2021)** — "A Neural Network–Based Observation Operator
  for Coupled Ocean–Acoustic Variational Data Assimilation", *MWR* **149**.
  [MWR](https://journals.ametsoc.org/view/journals/mwre/149/6/MWR-D-20-0320.1.xml).
  Uses analytic differentiation of NN observation operator inside 4D-Var.
- **Frerix et al. (2021)** — "Variational Data Assimilation with a Learned
  Inverse Observation Operator."
  [arXiv:2102.11192](https://arxiv.org/pdf/2102.11192).
- **Wang et al. (2024)** — "A Four-Dimensional Variational Constrained
  Neural Network-Based Data Assimilation Method", *JAMES* 16.
  [DOI](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2023MS003687).
- **Φ-DVAE** — Glyn-Davies et al. (2024) "Physics-informed dynamical
  variational autoencoders for unstructured data assimilation", *JCP*.
  [JCP](https://www.sciencedirect.com/science/article/pii/S0021999124005412).
- **Dabrowski et al. (BPINN-Wildfire)** — Bayesian PINN for spatio-temporal
  wildfire DA. [GitHub](https://github.com/jjdabr/BPINN-Wildfire).
- **StrAss-PINN** — "Deep learning in the abyss: a stratified PINN for data
  assimilation", arXiv:2503.19160 (2025). PINN per ocean layer.

---

## Cross-cutting observations

1. **PINN terminology is slippery.** "Physics-informed" means at least
   four different things; the memo and conversations should specify
   which.
2. **The single most useful flavor for JEDI is hybrid physics + NN in one
   graph**, and it is the one that unambiguously requires torch-ed
   operators.
3. **Jacobian-matching emulation is already published by NOAA/NESDIS on
   CRTM** — a nearby JCSDA effort on the CRTM-ONNX path can
   operationalize this without reinventing the research.
4. **Ocean DA has a surprisingly mature PINN literature** (Φ-DVAE,
   StrAss-PINN, BPINN-Wildfire) that fits naturally with the
   ocean-and-coupled flagship in §6.6 of the strategy memo.
