# jedi-docs

> Last updated against commit `61e5724c` (2026-04-29). Run `cd bundle/jedi-docs && git log --oneline 61e5724c..HEAD` to see what changed since.
>
> **Covers:** IODA data conventions (variable naming, units, groups), spack-stack/JEDI version compatibility, JEDI git flow (main/develop/feature/bugfix/hotfix/release), YAML config reference, JEDI-EDU tutorials, build troubleshooting FAQ.

External Sphinx/RST docs at `bundle/jedi-docs/`, hosted on ReadTheDocs. **Trust the code, not jedi-docs** — developers don't keep it consistently up to date. Use it only for content that isn't in source code.

## What's worth reading here (and nowhere else)

| Topic | Path |
|-------|------|
| **IODA data conventions** — authoritative variable naming, units, group structure (ObsValue/ObsError/MetaData), dimensions | `docs/inside/conventions/` |
| **Spack-stack version ↔ JEDI release compatibility table** | `docs/using/jedi_environment/` |
| **Git flow & PR process** — main/develop/feature/bugfix/hotfix/release branch model | `docs/working-practices/`, `docs/inside/practices/` |
| **YAML config reference** with annotated examples | `docs/inside/jedi-components/configuration/` |
| **JEDI-EDU tutorials** — DA concepts using L95 (3D-Var, ensemble, hybrid) | `jedi-edu/` |
| **Build troubleshooting FAQ** | `docs/FAQ/` |

For code-level questions (classes, factories, methods, file layouts), prefer the per-repo docs in `claude/` over jedi-docs.

## Building locally

```bash
make -C bundle/jedi-docs/docs html        # main docs
make -C bundle/jedi-docs/jedi-edu html    # educational manual
```
