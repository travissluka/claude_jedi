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

## Parse Arguments

Parse `$ARGUMENTS` for:
- **Positional args**: Specific repo names (e.g., `oops ufo saber`). If none given, operate on ALL repos.
- **`--no-pull`**: Skip git fetch/pull/merge (Phase 1). Just analyze and update docs.
- **`--no-docs`**: Skip doc update proposals (Phase 3). Just sync and report.
- **`--docs-only`**: Skip git sync. Analyze changes and update `claude/*.md` files only. Implies `--no-pull`.

## Configuration

```
BUNDLE_ROOT=/home/tsluka/work/jedi/bundle
DOCS_ROOT=/home/tsluka/work/jedi/claude
PROJECT_ROOT=/home/tsluka/work/jedi
```

### Repo categories

**Documented repos** (have `claude/<repo>.md`):
oops, ioda, ufo, saber, vader, fv3-jedi, mpas-jedi, pyiri-jedi, jedi-docs

**Special doc**: `cross-repo-interactions.md` — not tied to a single repo, update only when multiple repos have cross-cutting API changes.

**Data repos** (SKIP entirely — large, rarely relevant):
ioda-data, ufo-data, fv3-jedi-data, mpas-jedi-data, jedi-model-data, test-data-release

**External repos** (sync but do NOT analyze for doc updates):
gsw, crtm, mpas, fv3-jedi-lm

**Undocumented repos** (check for activity, report only):
soca, coupling, and anything else in bundle/ not listed above

### Doc header format

Each `claude/<repo>.md` file has this on line 3:
```
> Last updated against commit `<hash>` (<date>). Run `cd bundle/<repo> && git log --oneline <hash>..HEAD` to see what changed since.
```

The `cross-repo-interactions.md` file uses a date instead of per-repo commit hashes.

---

## Phase 1: Git Sync

**Skip if `--no-pull` or `--docs-only` is set.**

For each repo in bundle/ (excluding data repos), filtering to user-specified repos if any:

### Pre-flight checks (per repo)

1. Verify `.git` directory exists. Skip non-repo entries (CMakeLists.txt, LICENSE, etc.).
2. Check for uncommitted changes: `git -C <path> status --porcelain`
   - If dirty: **report** the dirty files but do NOT stash or clean. Skip sync for this repo but still analyze it in Phase 2.
3. Detect current branch: `git -C <path> rev-parse --abbrev-ref HEAD`
   - If `HEAD` (detached): **report** and skip sync.

### Sync logic

4. `git -C <path> fetch origin`
   - On network failure: report error, continue to next repo.
5. **On `develop` branch**: `git -C <path> pull --ff-only origin develop`
   - If ff-only fails (diverged history): report and skip. Do NOT force-merge.
6. **On a feature branch**: `git -C <path> merge origin/develop --no-edit`
   - If merge conflicts: immediately run `git -C <path> merge --abort`, report the conflicting files, continue to next repo.
   - **NEVER leave a repo in a conflicted state.**

### Sync output

Collect results into a table and display:

```
| Repo | Branch | Action | Result |
|------|--------|--------|--------|
| oops | feature/sequential_enkf | merge origin/develop | OK (3 new commits) |
| ioda | develop | pull --ff-only | OK (up to date) |
| saber | develop | pull --ff-only | OK (7 new commits) |
| fv3-jedi | HEAD (detached) | skipped | detached HEAD |
```

---

## Phase 2: Analyze Changes

For each documented repo (filtered by user args if specified):

1. Read the first 3 lines of `claude/<repo>.md` to extract the stored commit hash (the 8-char hex inside backticks after "commit").
2. Get current HEAD: `git -C bundle/<repo> rev-parse --short=8 HEAD`
3. If stored hash == current HEAD prefix: report "no changes", move on.
4. Run: `git -C bundle/<repo> log --oneline <stored-hash>..HEAD`
5. Run: `git -C bundle/<repo> diff --stat <stored-hash>..HEAD`

### Categorize changes by significance

From most to least significant:
- **API changes**: New/modified public class interfaces, changed function signatures, renamed/removed classes
- **New classes/files**: Entirely new source files added
- **Config changes**: New YAML keys, changed parameter names, new factory-registered types
- **Test changes**: New or modified tests (may indicate new features being tested)
- **Build changes**: CMakeLists.txt, ecbuild config changes
- **Documentation only**: README, comments, inline docs
- **Minor**: Formatting, typos, internal refactoring with no API impact

A repo has **significant changes** if it has anything in the first 4 categories.

### Undocumented repos

For repos not in the "data" or "external" categories that also lack a `claude/*.md` file, run `git -C bundle/<repo> log --oneline -5` to capture recent activity. Note these in the summary.

### CLAUDE.md check

Also check whether changes affect the main `CLAUDE.md`:
- Build dependency order changes (new repos, changed deps)
- New repos added to or removed from the bundle
- Test count changes (if easy to determine)
- Any structural changes to the project layout

---

## Phase 3: Update Docs

**Skip if `--no-docs` is set.**
**Skip repos with no significant changes.**

### 3a. Understand the changes

For each repo with significant changes, read the relevant source files to understand what changed:
- New or modified files listed in the diffstat
- For new classes: read the header file to understand the public interface
- For API changes: compare the current doc description with the new code
- For config changes: find example YAML configs

Use `git -C bundle/<repo> diff <stored-hash>..HEAD -- <file>` for specific files when needed.

Use Agent subagents to parallelize analysis across repos when multiple repos have significant changes.

### 3b. Draft updates

For each repo, draft the specific targeted edits:
- New sections to add
- Existing sections to modify
- Outdated information to remove or correct
- The updated commit hash and date for the header line

Also draft any CLAUDE.md edits if relevant.

### 3c. Present for review

**BEFORE making any edits**, present ALL proposed changes to the user in this format:

```
### Proposed Doc Updates

**oops.md** (12 new commits since 792d377a):
- Add new `SequentialEnsembleSolver` class to "Ensemble Solvers" section
- Update solver count from 6 to 7
- Update commit hash to `abc12345` (2026-03-31)

**ufo.md** (3 new commits since 5fd433e2):
- Add `computeLocalization(Point3, Point3)` overload to obs localization section
- Update commit hash to `def67890` (2026-03-31)

**CLAUDE.md**:
- No changes needed

**No changes needed**: saber.md, vader.md, fv3-jedi.md
**No changes detected**: jedi-docs.md, pyiri-jedi.md

Proceed with these updates?
```

Wait for user confirmation. If the user wants to modify the proposals, adjust accordingly.

### 3d. Apply updates

Use the **Edit** tool for targeted changes. Do NOT rewrite entire files. For each file:
1. Update the commit hash and date on the header line (line 3)
2. Apply the specific section edits as proposed and approved

### 3e. cross-repo-interactions.md

If changes span multiple repos and affect cross-repo interfaces (e.g., new oops abstract interface that model repos must implement), propose updates to `cross-repo-interactions.md` as well. Update its date line.

---

## Phase 4: Summary Report

Present a final summary:

```
## JEDI Bundle Update Summary (<today's date>)

### Git Sync Results
| Repo | Branch | Status |
|------|--------|--------|
| ... | ... | ... |

### Changes Since Last Doc Update
| Repo | Commits | Significance | Key Changes | Doc Updated? |
|------|---------|-------------|-------------|--------------|
| oops | 12 | API changes | SequentialEnsembleSolver, EAKF | Yes |
| ufo | 3 | Config | Point3 obs localization | Yes |
| saber | 0 | — | (no changes) | — |

### Impact on Active Projects

Cross-reference with `claude/active-projects.md`:
- For each active project, list which repos changed and how
- Highlight anything that could cause regressions or require adaptation
- Note if feature branches were updated with new develop commits

### Repos Without .claude Docs
- soca: X commits (brief summary)
- coupling: X commits (brief summary)

### Action Items
- [ ] Resolve merge conflict in <repo> (if any)
- [ ] Review <repo> changes for <project> impact
- [ ] Consider adding claude/<repo>.md (if significant undocumented changes)
```

---

## Error Handling

- **Network failures** (git fetch): Log error, mark repo as "fetch failed", continue.
- **Merge conflicts**: `git merge --abort` immediately, report conflicting files, continue.
- **Dirty working tree**: Report dirty files, skip sync for that repo, still analyze in Phase 2.
- **Detached HEAD**: Report, skip sync, still analyze.
- **Missing repo directory**: Report and continue.
- **Unparseable doc header**: Report the parsing issue, skip that repo's analysis.
- **No changes anywhere**: Report "All repos up to date, no doc updates needed" and exit.

## Safety Rules

- NEVER leave a repo in a conflicted state
- NEVER force-push, stash, reset --hard, or clean
- NEVER create merge commits on the develop branch (use --ff-only)
- Always report per-repo errors but continue the overall operation
- Always get user approval before writing doc changes
