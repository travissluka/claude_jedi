# jedi-docs (JEDI Documentation Repository)

> Last updated against commit `91e03357` (2026-04-16). Run `cd bundle/jedi-docs && git log --oneline 91e03357..HEAD` to see what changed since.

> **WARNING**: The developers do NOT consistently keep jedi-docs up to date with the code. If there is a discrepancy between what jedi-docs says and what the code does, **trust the code**. Use jedi-docs for conceptual understanding and workflow guidance, but always verify specifics against the actual source.

## Overview

Official Sphinx/RST documentation for the JEDI project. Hosted on ReadTheDocs. Source at `bundle/jedi-docs/`. Contains user guides, developer docs, tutorials, data conventions, and per-component reference material.

## Build

```bash
# Build HTML docs locally (requires sphinx, myst_parser, sphinxcontrib-bibtex)
cd bundle/jedi-docs/docs
make html
# Output in _build/html/

# JEDI-EDU (separate manual)
cd bundle/jedi-docs/jedi-edu
make html
```

Hosted version: ReadTheDocs (configured via `.readthedocs.yml`, Python 3.11, Sphinx builder).

## Structure

```
jedi-docs/
├── docs/                          # Main documentation (Sphinx)
│   ├── index.rst                 # Master TOC
│   ├── conf.py                   # Sphinx config
│   ├── overview/                 # What is JEDI, governance, methodology
│   ├── working-practices/         # Git flow, code review, PR process, testing standards
│   ├── learning/                  # Links to tutorials (release-specific)
│   ├── using/                     # User guide
│   │   ├── building_and_running/  # Build steps, YAML config format/content
│   │   ├── jedi_environment/      # Spack-stack, modules, containers, cloud (AWS)
│   │   └── running_skylab/        # Skylab bundle, HPC guide
│   ├── inside/                    # Developer docs (~287 files)
│   │   ├── jedi-components/       # Per-component docs (oops, saber, ioda, ufo, vader, fv3-jedi, mpas-jedi, soca, config, skylab)
│   │   ├── conventions/           # IODA data conventions (Markdown) — variable naming, units, groups, dimensions
│   │   ├── practices/             # Git flow, issues, PRs, ECMWF forks, OpenMP guidelines
│   │   ├── testing/               # Unit testing framework, adding tests
│   │   └── developer_tools/       # ecbuild/CMake, debuggers, gcov, GPTL profiling, Sphinx, Git LFS, Homebrew
│   ├── FAQ/                       # Build troubleshooting (segfaults, CMake, compilers)
│   └── ref/                       # BibTeX references
├── jedi-edu/                      # Educational manual (separate Sphinx project)
│   ├── variational/              # 3D-Var tutorials with L95
│   ├── ensemble/                 # Ensemble DA methods
│   └── hybrid/                   # Hybrid DA methods
└── howto/                         # Practical how-to guides
    ├── cylc/                      # Cylc workflow manager setup
    ├── macos/                     # macOS dev environment
    └── profiling/                 # Valgrind, Intel VTune, etc.
```

## What jedi-docs Covers That Our .claude/ Docs Don't

These sections contain unique content not derivable from source code alone:

### IODA Data Conventions (`docs/inside/conventions/`)
Formal specification of observation data formats: variable naming standards, units, group structure (ObsValue, ObsError, MetaData, etc.), dimension semantics, enumerated constants. Inspired by CF Conventions. **This is the authoritative reference for IODA data layout** (though may lag behind code changes).

### Build & Environment Guides (`docs/using/`)
Step-by-step build instructions, spack-stack version compatibility table (which spack-stack version goes with which JEDI release), Python venv setup, HPC module loading, container usage (Docker/Singularity/Vagrant), AWS cloud deployment. Practical onboarding material.

### Git Flow & Working Practices (`docs/inside/practices/`, `docs/working-practices/`)
JEDI's required branching model: `main` (releases only), `develop` (permanent dev branch), `feature/*`, `bugfix/*`, `hotfix/*`, `release/*` branches. PR process, code review expectations, issue management. **This is the authoritative guide for contributing to JEDI repos.**

### YAML Configuration Reference (`docs/inside/jedi-components/configuration/`)
Detailed explanation of YAML config file format, hierarchy, key-value syntax, and how eckit parses configs. Includes annotated examples from real test inputs.

### Testing Infrastructure (`docs/inside/testing/`)
How to run ctest, how JEDI tests are organized, and detailed instructions for adding new tests to any JEDI repo. Goes beyond our `.claude/` docs which focus on test commands.

### Developer Tools (`docs/inside/developer_tools/`)
Guides for: ecbuild/CMake usage, debugging (gdb, TotalView, DDT), code coverage (gcov), profiling (GPTL), Git LFS, Sphinx documentation, oops environment variables.

### JEDI-EDU Tutorials (`jedi-edu/`)
Educational material for learning DA concepts using JEDI: variational methods (3D-Var with L95 model), ensemble methods, hybrid approaches. Aimed at students and new users.

### Per-Component Narrative Docs

The jedi-docs component sections (`docs/inside/jedi-components/`) provide **narrative explanations** that complement our `.claude/` API-oriented docs:

- **SABER**: BUMP workflows, calibration recipes, explicit diffusion tutorial, QUENCH usage guide, Met Office blocks (UKMO), ML balance (torchBalance), testing patterns
- **UFO**: QC filter user guide (with YAML examples for each filter), adding new operators, variable transforms guide, bias correction (VarBC), marine UFO, obs error configuration
- **OOPS**: Algorithmic details (cost functions, minimization theory), application descriptions, toy model usage
- **FV3-JEDI**: Data handling, visualization, testing procedures
- **MPAS-JEDI**: Static B matrix setup, diagnostics

## How to Use jedi-docs Effectively

1. **Conceptual understanding**: Read jedi-docs for the "why" and high-level design. Read `.claude/` docs for the "what" (concrete classes, methods, factory names).
2. **Onboarding tasks**: jedi-docs build guide and working practices are the starting point for new contributors.
3. **YAML configuration**: jedi-docs has the most complete examples; cross-reference with actual test YAML files in each repo.
4. **Filter/operator usage**: The UFO QC filter docs in jedi-docs show YAML config patterns for each filter type — useful when writing new test configs.
5. **Always verify against code**: If jedi-docs says a parameter is named X but the code uses Y, trust the code.
