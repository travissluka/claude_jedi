# Cost Function Formulations

Mathematical formulations, configuration, and implementation of JEDI's variational cost functions. All in `oops/src/oops/assimilation/`.

## Overview

Every cost function minimizes `J(x) = Jb + Jo [+ Jc]`:
- **Jb** = background term (deviation from prior)
- **Jo** = observation term (fit to observations)
- **Jc** = optional constraint (e.g., digital filter initialization)

## 3D-Var

**YAML**: `cost type: 3D-Var`  
**File**: `CostFct3DVar.h`  
**TLM/ADM**: Not required

```
J = ½ (x - xb)ᵀ B⁻¹ (x - xb) + ½ (y - H(x))ᵀ R⁻¹ (y - H(x))
```

- **Control variable**: Single 3D state at analysis time (window midpoint)
- **Jb**: `CostJb3D` — one B matrix at one time
- **No model integration** — H(x) applied at analysis time only
- **Use when**: Single-time analysis, no model needed, fast

```yaml
cost function:
  cost type: 3D-Var
  time window:
    begin: 2023-01-01T00:00:00Z
    length: PT6H
  analysis variables: [ua, va, t, p]
  background:
    filename: background.nc
  background error:
    covariance model: SABER
```

## 3D-FGAT (First Guess at Appropriate Time)

**YAML**: `cost type: 3D-FGAT`  
**File**: `CostFctFGAT.h`  
**TLM/ADM**: Required

```
J = ½ (x - xb)ᵀ B⁻¹ (x - xb) + ½ Σₜ (yₜ - Hₜ(M(x,t)))ᵀ Rₜ⁻¹ (yₜ - Hₜ(M(x,t)))
```

- **Control variable**: 3D state at initial time (like 3D-Var)
- **Key difference from 3D-Var**: Background forecast to observation times, H(x) evaluated at correct time
- **Jb**: `CostJb3D` at initial time
- **Use when**: Obs distributed across time window, want correct temporal interpolation without full 4D-Var cost

## 4D-Var (Strong Constraint)

**YAML**: `cost type: 4D-Var`  
**File**: `CostFct4DVar.h`  
**TLM/ADM**: Required

```
J = ½ (x₀ - xb)ᵀ B⁻¹ (x₀ - xb) + ½ Σₜ (yₜ - Hₜ(M₀→ₜ(x₀)))ᵀ Rₜ⁻¹ (yₜ - Hₜ(M₀→ₜ(x₀)))
```

- **Control variable**: Initial condition x₀
- **Strong constraint**: State must lie on model trajectory M(x₀)
- **Jb**: `CostJb3D` at initial time
- **Inner loop**: TLM forward + ADM backward for gradient
- **Use when**: Standard 4D DA, model is trustworthy, need time-consistent analysis

```yaml
cost function:
  cost type: 4D-Var
  time window:
    begin: 2023-01-01T00:00:00Z
    end: 2023-01-01T06:00:00Z
  model:
    name: FV3
  linear model:
    name: FV3TLM
  background error:
    covariance model: SABER
```

## Weak Constraint 4D-Var

**YAML**: `cost type: 4D-Weak`  
**File**: `CostFctWeak.h`  
**TLM/ADM**: Required

```
J = ½ Σₖ (xₖ - xb,ₖ)ᵀ Bₖ⁻¹ (xₖ - xb,ₖ) + ½ Σₖ qₖᵀ Qₖ⁻¹ qₖ + ½ Σₜ (yₜ - Hₜ(x))ᵀ Rₜ⁻¹ (yₜ - Hₜ(x))
```

- **Control variable**: 4D — multiple states at sub-window boundaries + model error increments qₖ
- **Weak constraint**: Model error qₖ allows deviation from perfect model trajectory
- **Jb**: `CostJbJq` — background + model error at each sub-window
- **Sub-windows**: Window split into [t₀,t₁], [t₁,t₂], ..., each forecasted independently
- **Parallel sub-windows**: MPI `commTime` distributes sub-windows across ranks
- **Use when**: Model errors are significant, want better uncertainty estimates

```yaml
cost function:
  cost type: 4D-Weak
  time window:
    begin: 2023-01-01T00:00:00Z
    end: 2023-01-01T12:00:00Z
  subwindow: PT3H
  parallel subwindows: true
```

## 4D-Ens-Var (4D Ensemble Variational)

**YAML**: `cost type: 4D-Ens-Var`  
**File**: `CostFct4DEnsVar.h`  
**TLM/ADM**: Not required (no model in inner loop)

```
J = ½ (x - xb)ᵀ B⁻¹ (x - xb) + ½ Σₜ (yₜ - Hₜ(xₜ))ᵀ Rₜ⁻¹ (yₜ - Hₜ(xₜ))
```

- **Control variable**: 4D state at multiple snapshot times
- **B matrix**: 4D ensemble covariance (from ensemble forecasts, `CostJb4D`)
- **No model integration in cost function** — ensemble provides time dimension
- **Snapshot times**: t₀, t₀+Δt, t₀+2Δt, ...
- **Use when**: Ensemble available, want 4D covariance without TLM

```yaml
cost function:
  cost type: 4D-Ens-Var
  time window:
    begin: 2023-01-01T00:00:00Z
    end: 2023-01-01T12:00:00Z
  subwindow: PT3H
  background error:
    covariance model: ensemble
```

## Background Cost Terms (Jb)

| Class | Used By | Structure |
|-------|---------|-----------|
| `CostJb3D` | 3D-Var, 4D-Var, FGAT | Single B at one time |
| `CostJb4D` | 4D-Ens-Var | Multiple B at snapshot times |
| `CostJbJq` | Weak 4D-Var | B + model error Q at sub-windows |

Key operations: `linearize()` (create B via factory), `Bmult()` (y = B·x), `Bminv()` (y = B⁻¹·x), `randomize()`.

## Observation Cost Term (Jo)

`CostJo` (`CostJo.h`) manages all observation types:

1. `observers_->finalize()` — get H(x) and QC flags
2. Load obs: `yobs = Observations(obspaces, "ObsValue")`
3. Departures: `ydep = H(x) - y`
4. Gradient: `gradFG = R⁻¹ · ydep`
5. Cost: `Jo = ½ ydep · gradFG`

Rejected obs (QC flag > 0) automatically excluded via missing-value masking.

## Constraint Terms (Jc)

`CostJcDFI` — Digital Filter Initialization. Penalizes high-frequency oscillations in the analysis. Used with 4D-Var.

## Outer/Inner Loop Structure

The `Variational` application (`Variational.h`) runs:

```
For each outer iteration:
  1. Evaluate J at current first guess (NL model run)
  2. Linearize: set up B, TLM trajectory, obs operator linearization
  3. Run inner loop minimizer (PCG, DRPCG, etc.) to find increment δx
  4. Update: x ← x + δx
```

Inner loop uses TLM/ADM (for 4D methods) or direct B·δx (for 3D methods) to compute cost and gradient.

## Choosing a Cost Function

| Situation | Cost Function | Why |
|-----------|--------------|-----|
| Single-time analysis, no model | **3D-Var** | Simplest, fastest |
| Obs at different times, want correct timing | **3D-FGAT** | Evaluates H(x) at obs time |
| Full 4D DA with reliable model | **4D-Var** | Dynamically consistent analysis |
| Model errors significant | **Weak 4D-Var** | Estimates model error |
| Ensemble available, avoid TLM | **4D-Ens-Var** | No TLM needed, ensemble B |

## TLM/ADM Requirements

| Cost Function | Model TLM | Model ADM | Obs TL | Obs AD |
|---------------|-----------|-----------|--------|--------|
| 3D-Var | No | No | Yes | Yes |
| 3D-FGAT | Yes | Yes | Yes | Yes |
| 4D-Var | Yes | Yes | Yes | Yes |
| Weak 4D-Var | Yes | Yes | Yes | Yes |
| 4D-Ens-Var | No | No | Yes | Yes |
