# SABER Block Chain Mechanics

How SABER decomposes the background error covariance B into chains of outer blocks and a central block.

## The B Matrix Decomposition

SABER factorizes B as a chain of operators:

```
B = Outer_N · ... · Outer_1 · Central · Outer_1ᵀ · ... · Outer_Nᵀ
```

- **Outer blocks** — transforms between variable/grid spaces (applied symmetrically)
- **Central block** — self-adjoint core covariance operator

## Block Types

### Outer Blocks (`SaberOuterBlockBase`)

Transform from "outer" (model) space to "inner" (covariance) space:

```cpp
virtual void multiply(FieldSet3D &) const = 0;        // Forward transform
virtual void multiplyAD(FieldSet3D &) const = 0;       // Adjoint (reverse) transform
virtual void leftInverseMultiply(FieldSet3D &) const;   // Inverse (calibration)
```

Examples: interpolation, variable transforms (VADER), standard deviation scaling, localization.

### Central Blocks (`SaberCentralBlockBase`)

Self-adjoint core covariance:

```cpp
virtual void multiply(FieldSet3D &) const = 0;      // Apply B_central
virtual void randomize(FieldSet3D &) const = 0;      // Sample from N(0, B)
virtual void multiplySqrt(cv, FieldSet3D &) const;   // Square-root: U·cv
virtual void multiplySqrtAD(FieldSet3D &, cv) const;  // Adjoint: Uᵀ·field
```

Examples: BUMP_NICAS, spectral covariance, diffusion, ID (identity).

## The Multiply Chain

### Parametric Block Chain (`SaberParametricBlockChain`)

```
INPUT: fset (outer space)

1. ADJOINT of outer blocks (outer → inner):
   For i = 0 to N-1 (forward through stored list):
     outerBlock[i].multiplyAD(fset)

2. CENTRAL block multiply:
   centralBlock.multiply(fset)

3. FORWARD through outer blocks (inner → outer):
   For i = N-1 down to 0 (reverse through stored list):
     outerBlock[i].multiply(fset)

OUTPUT: fset (outer space, multiplied by B)
```

**Why this ordering?** Outer blocks are stored innermost-to-outermost. The adjoint pass goes forward (0→N-1) to transform from outer to inner space. The forward pass goes backward (N-1→0) to transform back.

### Ensemble Block Chain (`SaberEnsembleBlockChain`)

```
INPUT: fset (outer space)

1. Outer blocks adjoint (outer → inner)

2. Ensemble covariance:
   result = 0
   For each member ie:
     If localization:
       tmp = fset ⊙ ensemble[ie]          # Schur product
       locBlockChain.multiply(tmp)          # Apply localization
       tmp = tmp ⊙ ensemble[ie]            # Second Schur
     Else:
       weight = dot_product(fset, ensemble[ie])
       tmp = ensemble[ie] * weight
     result += tmp
   result /= (ens_size - 1)

3. Outer blocks forward (inner → outer)

OUTPUT: fset (multiplied by ensemble B)
```

### Hybrid Block Chain (`SaberHybridBlockChain`)

Weighted sum of components (parametric and/or ensemble):

```
INPUT: fset (outer space)

1. Outer blocks adjoint (shared across components)

2. For each component j:
   tmp = fset * √(weight_j)          # Apply sqrt weight
   component_j.multiply(tmp)          # Apply component B
   tmp *= √(weight_j)                # Apply sqrt weight again
   result += tmp                      # Accumulate

3. Outer blocks forward (shared)

OUTPUT: fset (multiplied by weighted-sum B)
```

Weights are applied as √w before and after to maintain self-adjointness:
**B_hybrid = Σⱼ √wⱼ · Bⱼ · √wⱼ**

Optional: `run in parallel: true` splits MPI ranks across components.

## leftInverseMultiply vs multiply

| Method | Direction | Use Case |
|--------|-----------|----------|
| `multiply` | Forward (inner → outer) | Normal B application |
| `multiplyAD` | Adjoint (outer → inner) | Normal B application |
| `leftInverseMultiply` | Inverse (outer → inner) | Calibration: transform ensemble to inner space |
| `rightInverseMultiply` | Right inverse (inner → outer) | Ensemble transform |

## Square-Root Form

For control-vector-based minimization, B = U·Uᵀ:

- `multiplySqrt(cv, fset)` — apply U: control vector → field
- `multiplySqrtAD(fset, cv)` — apply Uᵀ: field → control vector

Control vector size:
- **Parametric**: determined by central block (e.g., diffusion length scales)
- **Ensemble without localization**: one scalar per member
- **Ensemble with localization**: `ens_size × loc_ctlVecSize()`

## YAML Configuration

### Parametric

```yaml
background error:
  covariance model: SABER
  saber outer blocks:
    - saber block name: StdDev
      # ... parameters
    - saber block name: VADER
      # ... parameters
  saber central block:
    saber block name: BUMP_NICAS
    # ... parameters
```

Outer blocks applied in YAML order (first listed = outermost).

### Ensemble

```yaml
background error:
  covariance model: SABER
  saber outer blocks:
    - saber block name: StdDev
  ensemble:
    members from template:
      template:
        filename: ens/member_%{member}%.nc
      pattern: "%{member}%"
      nmembers: 20
  localization:
    saber central block:
      saber block name: BUMP_NICAS
```

### Hybrid

```yaml
background error:
  covariance model: SABER
  saber outer blocks:
    - saber block name: VADER
  components:
    - weight:
        value: 0.6
      covariance:
        covariance model: SABER
        saber central block:
          saber block name: BUMP_NICAS
    - weight:
        value: 0.4
      covariance:
        covariance model: SABER
        ensemble:
          # ... ensemble config
```

## Block Chain Types (Factory)

| YAML `covariance model` | Class | Description |
|--------------------------|-------|-------------|
| `SABER` (default) | `SaberParametricBlockChain` | Outer blocks + parametric central |
| (with `ensemble:` key) | `SaberEnsembleBlockChain` | Ensemble-based covariance |
| (with `components:` key) | `SaberHybridBlockChain` | Weighted sum of sub-chains |

## Calibration

Two modes for computing block statistics from ensemble:

**Direct**: All members loaded at once, passed to `directCalibration(ensemble)`.

**Iterative** (`iterative ensemble loading: true`): Members streamed one-at-a-time:
1. `iterativeCalibrationInit()`
2. For each member: `iterativeCalibrationUpdate(member)`
3. `iterativeCalibrationFinal()`

Reduces memory for large ensembles.

## Built-in Validation Tests

Configure in YAML under the block chain:

```yaml
adjoint test: true          # Verify <y, Ax> = <Aᵀy, x>
adjoint tolerance: 1.0e-10
square-root test: true      # Verify UUᵀ = B
square-root tolerance: 1.0e-10
inverse test: true           # Verify B⁻¹B = I
```

## Integration with oops

`ErrorCovariance<MODEL>` (`saber/src/saber/oops/ErrorCovariance.h`) wraps the block chain:

- Registered as `"SABER"` in the covariance factory
- `multiply()` → `blockChain_->multiply()`
- `randomize()` → `blockChain_->randomize()`
- `inverseMultiply()` → iterative GMRESR solver (no direct inverse)

## Key Files

| File | Purpose |
|------|---------|
| `saber/blocks/SaberBlockChainBase.h` | Abstract chain interface |
| `saber/blocks/SaberParametricBlockChain.h/.cc` | Parametric implementation |
| `saber/blocks/SaberEnsembleBlockChain.h/.cc` | Ensemble implementation |
| `saber/blocks/SaberHybridBlockChain.h` | Hybrid implementation |
| `saber/blocks/SaberOuterBlockChain.h` | Chain of outer block applicators |
| `saber/blocks/SaberOuterBlockBase.h` | Outer block interface + factory |
| `saber/blocks/SaberCentralBlockBase.h` | Central block interface + factory |
| `saber/oops/ErrorCovariance.h` | Integration with oops covariance system |
| `saber/oops/instantiateCovarFactory.h` | Factory registration chaining |
