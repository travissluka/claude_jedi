---
name: update-repos
description: >-
  Sync JEDI bundle repos (git fetch/pull/merge develop), analyze what changed
  since .claude docs were last updated, propose targeted doc updates with user
  review, and produce a cross-repo summary highlighting impact on active projects.
  Use when: "update repos", "sync bundle", "what changed", "pull latest",
  "update docs", or any variation.
argument-hint: "[repo...] [--no-pull] [--no-docs] [--docs-only]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Edit
  - Agent
---

# Update Repos

Sync JEDI bundle repositories, analyze recent changes, update architecture docs, and summarize impact.

Two helper scripts in `scripts/` collapse dozens of per-repo git calls into two batched invocations. Use them — do NOT loop over repos with individual Bash tool calls.

## Parse Arguments

Parse `$ARGUMENTS` for:
- **Positional args**: Specific repo names (e.g., `oops ufo saber`). If none given, operate on ALL repos.
- **`--no-pull`**: Skip git fetch/pull/merge (Phase 1). Just analyze and update docs.
- **`--no-docs`**: Skip doc update proposals (Phase 3). Just sync and report.
- **`--docs-only`**: Skip git sync. Analyze changes and update `claude/*.md` files only. Implies `--no-pull`.

## Configuration

All paths are resolved relative to the project root (where `.claude/` and `bundle/` live). The Claude Code session's CWD is the project root, so relative paths work as-is.

```
SCRIPTS=.claude/skills/update-repos/scripts
bundle dir:  bundle/
docs dir:    claude/
```

The scripts auto-detect the project root from their own location. Override with `PROJECT_ROOT`, `BUNDLE_ROOT`, or `DOCS_ROOT` env vars if needed.

### Repo categories

**Documented repos** (have `claude/<repo>.md`, analyzed in Phase 2):
`oops ioda ufo saber vader fv3-jedi mpas-jedi pyiri-jedi soca coupling jedi-docs`

**Undocumented source repos** (sync only, report activity):
_(none currently — every source repo in the bundle has a `claude/<repo>.md`)_

**External repos** (sync only, do NOT analyze for doc updates):
`gsw crtm mpas fv3-jedi-lm`

**Paired data repos** (sync alongside their code repo, never analyzed for doc updates):
- `ioda` → `ioda-data`
- `ufo` → `ufo-data`
- `fv3-jedi` → `fv3-jedi-data`
- `mpas-jedi` → `mpas-jedi-data`

When the code repo's `develop` is being pulled/merged in Phase 1, its paired data repo must be synced too — reference outputs are versioned with the code that produced them, and updating one without the other causes phantom test failures. If a code repo is *not* in this run's scope, leave its data repo alone.

**Other data repos** (SKIP entirely — not tied to a single code repo):
`jedi-model-data test-data-release`

**Special doc**: `cross-repo-interactions.md` — update only when multiple repos have cross-cutting API changes.

### Doc header format

Each `claude/<repo>.md` has on line 3:
```
> Last updated against commit `<hash>` (<date>). Run `cd bundle/<repo> && git log --oneline <hash>..HEAD` to see what changed since.
```

`cross-repo-interactions.md` uses a date instead of per-repo hashes.

---

## Phase 1: Git Sync

**Skip if `--no-pull` or `--docs-only` is set.**

Call the sync script **once** with the full list of source repos plus any paired data repos for code repos in scope:

```
.claude/skills/update-repos/scripts/sync.sh oops ioda ioda-data ufo ufo-data saber vader fv3-jedi fv3-jedi-data mpas-jedi mpas-jedi-data pyiri-jedi jedi-docs soca coupling gsw crtm mpas fv3-jedi-lm
```

Filter the repo list to user-specified repos if any were passed. Whenever a code repo with a paired data repo (`ioda`, `ufo`, `fv3-jedi`, `mpas-jedi`) survives the filter, append its paired data repo to the sync list. If the user explicitly excludes a code repo, drop its data repo too — never sync a data repo on its own.

The script emits TSV: `repo  branch  dirty  action  result  details`. Parse it into the sync-results table.

**What the script handles for you** (do NOT call these directly):
- `.git` presence check → `skipped / no .git directory`
- Dirty working tree → `skipped / dirty working tree` (leaves tree untouched)
- Detached HEAD → `skipped / detached HEAD`
- Fetch failure → `failed / fetch error (network?)`
- `develop` branch: `git pull --ff-only origin develop`; diverged → `failed / diverged (ff-only refused)`
- Feature branch: `git merge origin/develop --no-edit`; conflict → auto-`merge --abort` and report `conflict / aborted`

**Safety rules** (already enforced by the script): never `reset --hard`, never `stash`, never leave a repo in a conflicted state, never force-push.

If a repo reports a conflict or dirty state, report it to the user in the Phase 4 summary action items — do not try to resolve it automatically.

---

## Phase 2: Analyze Changes

**Always compare against `origin/develop`, never `HEAD`.** The docs describe what's on develop; a repo may be checked out on a feature branch whose HEAD carries unmerged feature-only work that must NOT influence doc updates. `analyze.sh` enforces this for you (via `COMPARE_REF`, default `origin/develop`) — do NOT recreate the diffs with `git log stored..HEAD` in the main thread. When you spawn deep-dive agents in Phase 3a, their prompts must also use `stored..origin/develop` (or the emitted `compare=` hash), never `stored..HEAD`.

If you spot commits with messages like "Merge develop into feature/..." or a large diff that seems wildly out of proportion to recent activity, that's the tell: you're probably looking at feature-branch work. Re-check with `git -C bundle/<repo> branch --show-current` and rerun the comparison against `origin/develop`.

Call the analyze script **once** with the list of documented repos:

```
.claude/skills/update-repos/scripts/analyze.sh oops ioda ufo saber vader fv3-jedi mpas-jedi pyiri-jedi soca coupling jedi-docs
```

(Filter to user-specified repos if any were passed.)

The script emits a block per repo:
```
==REPO <name> stored=<stored> compare=<origin/develop> head=<HEAD> commits=<n> class=<label> STATUS=<s>==
--LOG--
<git log --oneline stored..origin/develop>
--STAT--
<git diff --stat stored..origin/develop>
```

The `head=` field reflects the branch HEAD for context only — it is **not** used to compute the diff. All doc updates, hash bumps, and deep-dive diffs should reference `compare=` (origin/develop).

### STATUS values

- `no-changes` — stored hash == origin/develop. Skip, no doc work needed.
- `changed` — there are new commits on develop. Read the LOG and STAT.
- `hash-not-found` — stored hash not in repo (amended/force-pushed history). Report and ask user.
- `compare-ref-missing` — `origin/develop` not found (fetch didn't happen, or the repo uses a different default branch). Report; do not guess.
- `no-doc` / `parse-error` / `repo-error` — report as action item.

### class values (auto-classification from changed file list)

Use these to decide whether to deep-dive or just bump the hash:

| class | meaning | default action |
|-------|---------|----------------|
| `test-only` | only files under `test/` | bump hash only |
| `build-only` | only `CMakeLists.txt`/`*.cmake` | bump hash only |
| `docs-only` | only `*.md`/`*.rst`/`*.txt` | bump hash only |
| `fortran-only` | only `*.F90`/`*.f90` | bump hash unless commit messages suggest new functionality (not compiler-compat) |
| `code` | touches `*.h`/`*.hpp`/`*.cc`/`*.cpp` or mixed | **deep-dive required** — read the actual diff |

**Do not guess for `class=code`.** You must look at the actual changes (see Phase 3a) before deciding whether the doc needs content updates.

### Categorize significance (for `class=code`)

From most to least significant:
- **API changes**: public class interfaces, changed function signatures, renamed/removed classes
- **New classes/files**: entirely new source files
- **Config changes**: new YAML keys, changed parameter names, new factory-registered types
- **Internal refactor**: implementation changes with no public API impact
- **Minor**: formatting, typos

A repo has **significant changes** if it has anything in the first 3 categories.

### Undocumented source repos

If any source repo is in the "undocumented" list above, grab recent activity with a single call if relevant:

```
git -C bundle/<repo> log --oneline -5
```

Only bother if the Phase 1 table showed new commits for that repo. (Currently every source repo has a doc, so this section is a no-op — it stays in case the bundle adds a new repo before its doc is written.)

### CLAUDE.md check

Check whether changes affect the main `CLAUDE.md`:
- Build dependency order changes (new repos, changed deps in `bundle/CMakeLists.txt`)
- New repos added to or removed from the bundle
- Structural changes to project layout

Only dig in if Phase 1 reported new commits in repos whose `CMakeLists.txt` or bundle-level config changed.

### Build-dependency DAG check

`claude/build-and-test.md` (`## Build dependency DAG`) records each repo's direct JEDI deps from top-level `find_package(... REQUIRED)` plus subdir `target_link_libraries(...)` for `coupling`. If any repo in this run has a class=code change that touches `CMakeLists.txt` or any `**/CMakeLists.txt` under it, re-derive the DAG via:

```bash
for r in oops vader saber ioda ufo fv3-jedi-lm fv3-jedi soca mpas-jedi pyiri-jedi coupling; do
  echo "=== $r ==="
  grep -E 'find_package\([[:space:]]*(oops|vader|saber|ioda|ufo|crtm|gsw|fv3jedilm|fv3-jedi|soca|MPAS|fv3jedi)[[:space:]]' bundle/$r/CMakeLists.txt
done
```

For `coupling`, also `grep target_link_libraries bundle/coupling/test_mom6fv3/src/CMakeLists.txt`. If the result diverges from the table in `build-and-test.md`, propose an update as part of Phase 3.

---

## Phase 3: Update Docs

**Skip if `--no-docs` is set.**
**Skip repos with `STATUS=no-changes` or non-`code` class unless commits suggest new functionality.**

### 3a. Deep-dive only `class=code` repos

For each repo where content updates might be needed:
- Read the header file(s) touched: `git -C bundle/<repo> diff <stored>..origin/develop -- <path/to/file.h>`
- Compare against the current `claude/<repo>.md` description
- For new classes, read the new header to extract the public interface
- For config changes, find example YAML configs

**Always diff against `origin/develop`, never `HEAD`** — see the Phase 2 warning. Use the `compare=` hash from the analyze-script block as the canonical endpoint.

**Parallelize with agents when 2+ repos need deep-dives.** Single prompt template (note the explicit `origin/develop` endpoint):

> Read the diff between `<stored-hash>` and `origin/develop` in `bundle/<repo>` (do NOT use HEAD — the repo may be on a feature branch and unmerged work must be ignored). Focus on headers and any new files. Compare against the current `claude/<repo>.md`. Return a bulleted list of proposed edits (section + specific change + why) under 150 words. If nothing substantive changed, return "no content updates needed."

For 0–1 repos with code changes, do it directly in the main thread — agent overhead isn't worth it.

### 3b. Draft updates

For each repo, draft specific targeted edits:
- New sections to add
- Existing sections to modify
- Outdated information to correct
- Updated commit hash + today's date for the header line

Also draft any `CLAUDE.md` edits if relevant.

### 3c. Present for review

**BEFORE making any edits**, present ALL proposed changes:

```
### Proposed Doc Updates

**oops.md** (12 new commits since 792d377a, class=code):
- Add new `SequentialEnsembleSolver` class to "Ensemble Solvers" section
- Update solver count from 6 to 7
- Bump hash: `792d377a` → `abc12345` (<today>)

**ufo.md** (3 new commits since 5fd433e2, class=code):
- Add `computeLocalization(Point3, Point3)` overload to obs localization section
- Bump hash: `5fd433e2` → `def67890` (<today>)

**Hash-only bumps** (no content changes):
- ioda.md: `aaa..bbb` (class=test-only)
- saber.md: `ccc..ddd` (class=build-only)

**No changes needed**: vader.md, fv3-jedi.md
**No new commits**: jedi-docs.md, pyiri-jedi.md, mpas-jedi.md

**CLAUDE.md**: No changes needed

Proceed with these updates?
```

Wait for user confirmation.

### 3d. Apply updates

Use the **Edit** tool for targeted changes. Do NOT rewrite entire files. For each file:
1. Update the commit hash and date on line 3
2. Apply the specific section edits as proposed and approved

### 3e. cross-repo-interactions.md

If changes span multiple repos and affect cross-repo interfaces (e.g., a new `oops` abstract interface that model repos must implement), propose updates to `cross-repo-interactions.md` as well. Update its date line.

---

## Phase 4: Summary Report

```
## JEDI Bundle Update Summary (<today's date>)

### Git Sync Results
| Repo | Branch | Status |
| ... | ... | ... |

### Changes Since Last Doc Update
| Repo | Commits | Class | Significance | Key Changes | Doc Updated? |
| oops | 12 | code | API changes | SequentialEnsembleSolver | Yes |
| ioda | 1 | test-only | minor | test rename | Hash only |
| saber | 0 | — | — | (no changes) | — |

### Impact on Active Projects
Cross-reference with `claude/active-projects.md`:
- For each active project, list which repos changed and how
- Highlight anything that could cause regressions or require adaptation
- Note if feature branches absorbed new develop commits via merge

### Repos Without .claude Docs
_(omit section if every source repo is documented; otherwise list undocumented repos with new-commit summaries)_

### Action Items
- [ ] Resolve merge conflict in <repo> (if any from Phase 1)
- [ ] Review <repo> changes for <project> impact
- [ ] Consider adding claude/<repo>.md (if significant undocumented changes)
```

---

## Error Handling

Most error cases are handled by the scripts themselves; the main thread's job is to parse the structured output and report in Phase 4.

- **Network failures** (fetch): sync.sh reports `failed / fetch error`; continue
- **Merge conflicts**: sync.sh auto-aborts and reports `conflict / aborted`; add to action items
- **Dirty working tree**: sync.sh reports and skips; add to action items
- **Detached HEAD**: sync.sh reports and skips; still run analyze.sh (it reads HEAD regardless)
- **Stored hash missing from history** (`STATUS=hash-not-found`): amended/force-pushed. Ask the user rather than guessing a replacement.
- **Unparseable doc header** (`STATUS=parse-error`): report, skip analysis
- **No changes anywhere**: report "All repos up to date, no doc updates needed" and exit

## Safety Rules

- NEVER leave a repo in a conflicted state (scripts handle this via `merge --abort`)
- NEVER force-push, stash, `reset --hard`, or clean
- NEVER create merge commits on `develop` (scripts use `pull --ff-only`)
- Always get user approval before writing doc content changes
- Hash-only bumps can be applied as part of a bundled approval — do not ask separately for each

## Do NOT

- Loop over repos with individual Bash tool calls — use `sync.sh` and `analyze.sh`
- Run `git fetch`, `git status`, or `git log` per repo from the main thread when the scripts can batch it
- Deep-dive into diffs for `class=test-only`, `build-only`, `docs-only`
- Spawn agents when there are 0–1 `class=code` repos to review
