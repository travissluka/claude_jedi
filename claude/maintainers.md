# Repo Maintainers

> Snapshot taken 2026-07-22 from `JCSDA-internal/github-admin` repo, file `tf/configuration.tf`.
>
> **Covers:** maintainer/admin GitHub handles per bundle repo. Use this to know who to ping when a PR sits without review or who can force-merge / override branch protection.

## Source of truth

The canonical list lives in terraform config that drives the org's repo settings:

```
gh api repos/JCSDA-internal/github-admin/contents/tf/configuration.tf | \
  python3 -c "import json,sys,base64; print(base64.b64decode(json.load(sys.stdin)['content']).decode())"
```

In that file, **`maintainers`** is the list of GitHub handles with maintainer-level permission on the repo (can approve PRs, can merge, can manage settings under `repository_profile`). **`admin_users`** is reserved for special cases (the comment says "DO NOT USE THIS" for normal repos) and appears mainly on UKMO-hosted repos. **`write_teams`** grants commit access to whole GitHub teams (not individuals).

**Org owners are not in this file.** GitHub org-owner role sits above the per-repo terraform grants, so org owners hold admin (force-merge, override branch protection) on *every* JCSDA-internal repo regardless of its `maintainers` list. **ytremolet (Yannick Tremolet)** is an org owner, so he can merge any bundle repo even where he is not listed as a maintainer (e.g. ioda, ufo). Treat this list as the repo-scoped grants only; for a hard override, an org owner is always an option.

To re-snapshot this doc: re-run `/update-repos` (the skill refreshes from terraform when it runs).

## Bundle repos (terraform-managed)

Sorted in build-dependency order.

| Bundle dir | Repo (`tf` key) | Maintainers | Write teams |
|---|---|---|---|
| `gsw` | `GSW-Fortran` | travissluka | ufo |
| `oops` | `oops` | ytremolet, fmahebert | (jedi via JEDI profile) |
| `vader` | `vader` | svahl991, fmahebert, MarekWlasak | ukmo, fv3-development |
| `saber` | `saber` | fmahebert, ncrossette | ukmo, fv3-development |
| `ioda` | `ioda` | srherbener, fmahebert | (jedi via JEDI profile) |
| `ufo` | `ufo` | BenjaminTJohnson, BenjaminRuston, fmahebert, srherbener, fcvdb, huishao-r, mikecooke77 | ufo |
| `fv3-jedi-lm` | `fv3-jedi-linearmodel` | fmahebert, danholdaway, rtodling, cmgas | (jedi via JEDI profile) |
| `fv3-jedi` | `fv3-jedi` | fmahebert, danholdaway, rtodling, cmgas | (jedi via JEDI profile) |
| `soca` | `soca` | shlyaeva, Dooruk | soca |
| `mpas` | `MPAS-Model` | liujake, byoung-joo, svahl991 | (jedi via JEDI profile) |
| `mpas-jedi` | `mpas-jedi` | jim-p-w, byoung-joo, ibanos90, junmeiban, svahl991, fmahebert, BenjaminRuston | (jedi via JEDI profile) |
| `coupling` | `coupling` | fmahebert, travissluka | (jedi via JEDI profile) |
| `pyiri-jedi` | `pyiri-jedi` | climbfuji, fmahebert, huishao-r, BenjaminRuston, ncrossette | navy, jedi |
| `jedi-docs` | `jedi-docs` | ashley314, cmgas, ncrossette | jedi |
| `crtm` | (not in terraform config) | — | — |

The bundle itself (`jedi-bundle`) is maintained by **fmahebert, eap, ytremolet** with write access via `fv3-development`, `soca`, `obs-core`, `jcsda-core` teams.

## Data repos (not in build, but referenced by tests)

| Repo | Maintainers |
|---|---|
| `ioda-data` | srherbener, fmahebert |
| `ufo-data` | BenjaminTJohnson, BenjaminRuston, fmahebert, srherbener, fcvdb, huishao-r, mikecooke77 |
| `fv3-jedi-data` | fmahebert, danholdaway, rtodling, cmgas |
| `mpas-jedi-data` | jim-p-w, byoung-joo, ibanos90, junmeiban, svahl991, fmahebert, BenjaminRuston |
| `jedi-model-data` | svahl991, fmahebert, danholdaway, MarekWlasak, ncrossette |
| `soca-data` | shlyaeva, Dooruk, danholdaway |

## Repository profiles

Most JEDI repos use `repository_profile = "JEDI"`, which auto-grants the `jedi` team write access and requires 2 reviews. Repos with `repository_profile = "NO_PROFILE"` (e.g., `pyiri-jedi`, all UKMO repos) configure write teams explicitly.

## CRTM

`crtm` (and other CRTM-* repos) appear only as commented entries in `tf/imports.tf` — they are *not* under JCSDA terraform management. Per the org's "CRTM-core" team description ("Core team members with highest level of access"), governance lives elsewhere; check the CRTM repo's GitHub settings or contact JCSDA staff directly if a CRTM-side change is needed.

## Org-wide maintainer activity (most-frequent appearances)

These handles show up across many bundle repos and are good first-stop pings for cross-cutting issues:

- **fmahebert** — oops, ioda, ufo, saber, vader, fv3-jedi, fv3-jedi-lm, mpas-jedi, coupling, pyiri-jedi (10 repos)
- **srherbener** — ioda, ufo (and most data repos)
- **BenjaminRuston** — ufo, mpas-jedi, pyiri-jedi
- **danholdaway** — fv3-jedi, fv3-jedi-lm
- **ytremolet** — oops (and jedi-bundle)
- **ncrossette** — saber, pyiri-jedi, jedi-docs
- **cmgas** — fv3-jedi, fv3-jedi-lm, jedi-docs

For PRs stuck without review, escalate to one of these handles or to the relevant write team (e.g., `@JCSDA-internal/jedi-core` for cross-cutting infra, `@JCSDA-internal/ufo` for obs work).
