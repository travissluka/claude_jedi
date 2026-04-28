# Inventory of Existing AI/ML Work in JEDI Bundle

**Date:** April 16, 2026
**Report Scope:** Very thorough scan of /home/tsluka/work/jedi/bundle/ across all repos
**Covered Repos:** saber, soca, crtm, ufo, oops, pyiri-jedi, fv3-jedi, and others

---

## Executive Summary

JEDI has **two major, active PyTorch-based balance operator implementations** already in production/testing:

1. **TorchBalance (SABER)** — Generic variable balance operator driven by TorchScript models for atmosphere-ocean-ice coupling (active, experimental)
2. **MLBalance (SOCA)** — Ocean/ice-focused balance operator with native PyTorch neural network emulators (active, experimental)

Additionally, there is a **feature branch in CRTM** with ONNX Runtime integration for ML-emulator radiative transfer, representing a third major thrust.

**Key capability:** Both TorchBalance and MLBalance accept learned models to represent cross-variable balance relationships, with automatic differentiation support for adjoint operations. The infrastructure is modern (PyTorch 2.8–2.10, TorchScript, ONNX) and integrates seamlessly into SABER's covariance block-chain architecture.

**Biggest gaps:**
- No hybrid data assimilation (ensemble + learned model) infrastructure
- No uncertainty quantification (UQ) from neural network predictions
- Limited documentation of ML/AI capabilities in public-facing docs
- CRTM ONNX branch not yet merged to develop
- No cross-repo standardization for model I/O (each uses custom paths/formats)

**Existing standardization opportunities:**
- Both TorchBalance and MLBalance use YAML configuration for model loading
- Both compute Jacobians at inference time (no pre-computed matrices)
- Both support masking for spatial constraints (land/ice masks)
- PyTorch ecosystem is the de-facto standard; libtorch C++ API is consistent

---

## Detailed Findings by Repo

### **SABER** — System Agnostic Background Error Representation

**TorchBalance Block** (New, 2024–2025)

- **Location:** `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/`
- **Files:**
  - `TorchBalance.h` / `TorchBalance.cc` (~250 LOC)
  - `TorchBalanceEmulator.h` / `TorchBalanceEmulator.cc` (~150 LOC)
  - `create_test_emulator.py` (~300 LOC)
  - `CMakeLists.txt`
- **What it does:**
  Implements a SABER outer block that applies learned variable balance transforms via TorchScript models. Loads one or more `.ts` (TorchScript) models, each defining the Jacobian of one output variable w.r.t. multiple input variables. Supports masking (e.g., land masks) and multi-level Jacobians. Applies forward and adjoint operations via matrix-free multiplication.

- **Stage:** Experimental (active development)
- **Scope:** ~400 LOC C++, ~300 LOC Python
- **Key Features:**
  - Requires PyTorch 2.8–2.10 (libtorch C++ API)
  - Jacobian naming convention: `d{output}_div_d{input}` (hardcoded in C++)
  - Single-level Jacobian support (multi-level planned)
  - Configurable spatial masking per emulator
  - Optional Jacobian field export for debugging
  - Test suite: `test/testinput/dirac_torchbalance.yaml`
  - Tests: atmosphere–ocean–ice balance with 2 emulators (SST, air temp)

- **Configuration Example (YAML):**
  ```yaml
  saber outer blocks:
  - saber block name: TorchBalance
    save jacobians: false
    surface emulators:
    - name: sea_water_potential_temperature
      path: ./testdata/sst_emulator.ts
      jacobian wrt: [air_temperature, water_vapor_mixing_ratio_wrt_moist_air]
  ```

- **Documentation:**
  - `/home/tsluka/work/jedi/bundle/jedi-docs/docs/inside/jedi-components/saber/torchBalance.rst` (~193 lines, comprehensive)
  - Covers TorchScript model interface, YAML config, PyTorch installation, example K-matrix structure

- **Git Branches:** `feature/torchbalance`, `feature/torchbalance_cleaning`, `feature/torch_installation`

---

### **SOCA** — System for Ocean Coupled Assimilation

> **Status correction (April 2026):** MLBalance has been **superseded** by
> SABER's TorchBalance. On 22 Jan 2026, commit `52748226` ("mlbalance to
> torchbalance; fixed ctests") renamed the directory `src/saber/mlbalance/` →
> `src/saber/torchbalance/` in SABER. On 13 Mar 2026, commit `feeec2d6`
> ("Torch based Balance Operator #1174") introduced the generalized
> TorchBalance. Both MLBalance (SOCA) and TorchBalance (SABER) are authored
> by Benjamin Menetrier and Guillaume Vernieres, confirming an intentional
> in-house rewrite. MLBalance remains in-tree for backward compatibility but
> should be treated as **legacy / being retired**; TorchBalance is the
> canonical learned-balance path going forward.

#### 1. **MLBalance Block** (New, 2024) — *LEGACY*

- **Location:** `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/`
- **Files:**
  - `MLBalance.h` / `MLBalance.cc` (~250 LOC)
  - `MLBalanceParameters.h` (~33 LOC)
  - `MLJac.h` (~93 LOC)
  - `KEmul/BaseEmul.h` (~301 LOC)
  - `KEmul/IceNet.h` (~116 LOC)
  - `KEmul/IceEmul.h` (~280 LOC)
  - `CMakeLists.txt`
- **What it does:**
  Ocean-centric balance operator with native PyTorch neural network emulators. Defines balance relationships between potential temperature, salinity, SSH, ice thickness, ice concentration, etc. Supports training and inference of feedforward neural networks. Includes gradient aggregation across MPI ranks for distributed training. K-matrix has structure with multi-level Jacobians for temperature/salt and single-level for ice variables.

- **Stage:** Experimental (active development)
- **Scope:** ~1,200 LOC C++/header
- **Key Features:**
  - Native PyTorch (libtorch), not TorchScript
  - Includes full training loop: MSE loss, Adam optimizer, gradient aggregation
  - Supports model serialization (`torch::load`, `torch::save`)
  - Normalization/standardization of inputs
  - MPI-aware training (gradient averaging across ranks)
  - Hard-coded K-matrix structure (7 Jacobian fields: ds/dt, dssh/dt, dssh/ds, dc/dsst, dc/dsss, dc/dhi, dc/dhs)
  - Arctic/Antarctic region-specific models in config
  
- **Test Suite:**
  - `/home/tsluka/work/jedi/bundle/soca/test/testinput/dirac_mlbalance.yml`
  - `/home/tsluka/work/jedi/bundle/soca/test/testinput/train_mlbalance.yml`
  - Reference: `testref/dirac_mlbalance.test`
  - Test data: `Data/mlbalance/`

- **Configuration Example:**
  ```yaml
  saber outer blocks:
  - saber block name: MLBalance
    ML Balances:
      arctic:
        ffnn:
          inputSize: 7
          outputSize: 1
          hiddenSize: 2
          load model: data_generated/train_mlbalance/mlbalance.pt
  ```

- **Documentation:** None found in docs/ (internal only)

#### 2. **ModelOceanIceEmulator** (Existing, ~2025)

- **Location:** `/home/tsluka/work/jedi/bundle/soca/src/soca/Model/OceanIceEmulator/` and `LinearModel/OceanIceEmulator/`
- **Files:**
  - `ModelOceanIceEmulator.h` / `.cc` (~50 LOC)
  - `LinearModelOceanIceEmulator.h` / `.cc` (~50 LOC)
- **What it does:**
  Simple non-physical emulator model for ocean/ice. Only advances time; no actual dynamics. Used for testing DA operators without running full MOM6/CICE.

- **Stage:** Active (test infrastructure)
- **Scope:** ~100 LOC
- **Tests:** `hofx_4d_oceaniceemulator.yml`, `4dvar_oceaniceemulator.yml`, `forecast_oceaniceemulator.yml`, `linearmodel_oceaniceemulator.yml`

---

### **CRTM** — Community Radiative Transfer Model

#### ONNX Runtime ML Emulator Branch (Feature, not yet merged)

- **Branch:** `feature/btj_ml-emulator-onnx-bridge`
- **Recent commits:**
  - "Batch ONNX inference across all layers per profile"
  - "Integrate ONNX support into CRTMv3 library and lifecycle"
  - "Add C interface bridge and Fortran test for ONNX runtime"
  
- **What it does:**
  Adds C interface layer to load and run ONNX model files for radiative transfer calculations. Allows replacing CRTM's tau coefficient parameterization with learned models (neural networks exported to ONNX format). Fortran-callable C interface.

- **Stage:** Experimental (feature branch, not merged to develop)
- **Scope:** Unknown (need to check branch), but includes Fortran wrapper, C bridge
- **Key Files on Branch:**
  - `src/CRTM_ONNX_Interface.f90` (Fortran module with C binding)
  
- **Integration:** Intended to be optional (conditional compilation)

- **Note:** This is a **planned but not-yet-integrated capability**. No active tests on main develop branch.

---

### **PyIRI-JEDI** — Python Ionospheric Model Interface

- **Location:** `/home/tsluka/work/jedi/bundle/pyiri-jedi/`
- **What it does:**
  Interface between JEDI and PyIRI (a Python ionospheric model). Demonstrates Python model integration via OOPS/IODA, not ML-specific.

- **Stage:** Active
- **Scope:** Small Python/C++ interface
- **AI/ML Content:** None directly; however, it shows how to integrate external Python models into JEDI workflows.

---

### **OOPS** — Object-Oriented Prediction System (Core Framework)

#### HybridCovariance

- **Location:** `/home/tsluka/work/jedi/bundle/oops/src/oops/base/HybridCovariance.h`
- **What it does:**
  Framework for hybrid covariance combining parametric and ensemble (or other) components. Not ML-specific, but relevant for potential hybrid (ensemble + learned model) systems.

- **Stage:** Mature
- **AI/ML Note:** No learned models, but provides infrastructure for combining different covariance estimates.

---

### **UFO** — Unified Forward Operators

- **Operators Found:** `ObsRadianceCRTM`, `ObsAodCRTM`, `ObsRadianceCRTMTLAD`, `ObsAodCRTMTLAD`
- **What it does:**
  Standard radiative transfer observation operators using CRTM (not ML-based). Could eventually use CRTM ONNX models once that branch is merged.

- **Stage:** Active
- **AI/ML Content:** None yet; potential future integration with CRTM ONNX emulator.

---

### **FV3-JEDI** — FV3 Atmosphere Model Interface

#### Vertical Balance

- **Files:** Multiple test configs referencing `read vertical balance`, `compute vertical balance`, `write vertical balance`
  - `test/testinput/staticb_split_vbal_gfs.yaml`
  - `test/testinput/staticb_prep_DATE_geos.yaml`
  - Others

- **What it does:**
  Traditional vertical balance relationships (hydrostatic, geostrophic, etc.), not learned. Data-driven only in the sense that balance parameters may come from climatology.

- **Stage:** Active
- **AI/ML Content:** None (physics-based balance)

---

## Cross-Cutting Observations

### PyTorch Versions & Dependencies
- **TorchBalance:** Requires PyTorch 2.8–2.10 (libtorch, C++ API)
- **MLBalance:** Uses native PyTorch (libtorch, C++ API)
- Both require `find_package(Torch)` in CMake; conditional compilation if Torch not found
- Note: SOCA CMakeLists.txt has comment "ideally just do this: find_package(Torch QUIET)" but notes spack-stack needs a fix

### Model I/O Patterns
- **TorchScript models (.ts files):** TorchBalance loads via `torch::jit::load()`
- **PyTorch model weights (.pt files):** MLBalance loads via `torch::load()`
- **ONNX models (.onnx files):** Planned in CRTM (not yet active)
- **Configuration:** YAML-based for model paths and metadata

### Jacobian Computation
- **TorchBalance:** Calls `jac_physical(inputs, mask)` method on loaded TorchScript model
- **MLBalance:** Uses native PyTorch autodiff during training; inference applies learned Jacobians
- No pre-computed Jacobian matrices; all computed at inference time (memory-efficient but slower)

### Testing Infrastructure
- **TorchBalance:** Adjoint tests pass (torchbalance.ref), includes linear emulator test suite
- **MLBalance:** Dirac/adjoint tests, training workflow tests
- Both use SABER's QUENCH pseudo-model framework for isolated testing

### Documentation Status
- **TorchBalance:** Comprehensive RST documentation in jedi-docs
- **MLBalance:** No public documentation (internal only)
- **CRTM ONNX:** No documentation yet (feature branch)

---

## Gaps & Opportunities

### Critical Gaps
1. **Hybrid ensemble + learned model:** OOPS has `HybridCovariance` but no implementation combining ensemble spreads with NN predictions
2. **Uncertainty quantification:** No epistemic/aleatoric UQ from neural networks (e.g., ensembles of models, Bayesian approaches)
3. **Feature engineering / preprocessing:** No standardized pipeline for normalization, standardization, input feature selection
4. **Multi-output models:** Both TorchBalance and MLBalance assume single-output emulators (e.g., SST → T, not {T, Q})
5. **Physics-informed learning:** No PINN-style loss terms or soft constraints in training
6. **Learned operators as observation operators:** Only balance (background error) so far; no learned H operators

### Moderate Gaps
- No QC/QA metrics for when neural predictions become unreliable (e.g., extrapolation detection)
- No model versioning/registry for managing multiple versions of learned models in production
- No distributed training framework (MLBalance has MPI gradient averaging but no data parallelism strategy)
- Documentation not centralized (TorchBalance docs exist, MLBalance docs don't; CRTM ONNX is unmerged)

### Standardization Opportunities
- **Model I/O:** Define a standard path/naming convention for `.pt` and `.ts` files (currently ad-hoc)
- **YAML schema:** Create a JSON Schema for TorchBalance/MLBalance YAML to validate configs
- **Jacobian metadata:** Standardize how to store/query level information (currently hardcoded per block)
- **Training data:** No standard for input/output datasets for training balance operators
- **Testing:** Create a common adjoint test suite for all learned balance operators

---

## Files of Interest (Absolute Paths)

### TorchBalance
- `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/TorchBalance.h`
- `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/TorchBalance.cc`
- `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/TorchBalanceEmulator.h`
- `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/TorchBalanceEmulator.cc`
- `/home/tsluka/work/jedi/bundle/saber/src/saber/torchbalance/create_test_emulator.py`
- `/home/tsluka/work/jedi/bundle/saber/test/testinput/dirac_torchbalance.yaml`
- `/home/tsluka/work/jedi/bundle/jedi-docs/docs/inside/jedi-components/saber/torchBalance.rst`

### MLBalance
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/MLBalance.h`
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/MLBalance.cc`
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/MLJac.h`
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/KEmul/BaseEmul.h`
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/KEmul/IceNet.h`
- `/home/tsluka/work/jedi/bundle/soca/src/soca/MLBalance/KEmul/IceEmul.h`
- `/home/tsluka/work/jedi/bundle/soca/test/testinput/dirac_mlbalance.yml`
- `/home/tsluka/work/jedi/bundle/soca/test/testinput/train_mlbalance.yml`

### CRTM ONNX (Feature Branch)
- Branch: `origin/feature/btj_ml-emulator-onnx-bridge`

---

## Recommendations for AI Strategy

1. **Accelerate TorchBalance documentation & examples** — Make it more discoverable; add tutorials for creating custom balance operators
2. **Merge & document MLBalance** — Currently internal-only; document the ocean-ice-specific design
3. **Merge CRTM ONNX branch** — Brings ML emulator radiative transfer into the toolkit; adds ONNX interoperability
4. **Standardize model I/O & YAML schemas** — Create shared utilities for loading/validating learned models
5. **Add ensemble forecast + NN hybrid covariance** — Combine ensemble B with learned balance for improved flow-dependence
6. **Investigate physics-informed neural networks (PINNs)** — Could enforce conservation laws in balance operators
7. **Create a "learned operators registry"** — Central tracking of available trained models, versioning, performance metrics

---

**End of Report**
