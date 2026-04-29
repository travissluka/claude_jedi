---
name: jedi-prs
description: >-
  Coordinate multi-repo PRs across JCSDA-internal repos. Handles change analysis,
  merge-order reasoning, build-group selection, body drafting, opening, label
  lifecycle (bug / waiting for another PR / coordinate merge / ready for merge),
  and the multi-day follow-up flow (draft→ready, drop stale build-groups). State
  is persisted in a memory file so a workflow that spans a CI cycle (hours) can
  be resumed across conversations.
  Use when: the user is preparing PRs for a feature that touches multiple bundle
  repos, or wants to resume / inspect / mutate an in-flight coordinated PR set.
argument-hint: "[<slug> [<repo:branch> ...] | <slug> [--show|--ready <repo>|--drop <repo> <url>|--label <repo> <add|rm> <label>] | --list]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Edit
  - Write
  - Agent
---

# Issue PRs — coordinated multi-repo PR workflow

Codifies the rules in `claude/pr-conventions.md` end-to-end so they are applied every time, and keeps a state file per in-flight feature so a multi-day workflow resumes cleanly.

> **Read first:** `claude/pr-conventions.md`. The rules there are authoritative; this file is the operational playbook.

## Parse arguments

`$ARGUMENTS` shapes:

| Form | Action |
|---|---|
| `<slug> <repo:branch> ...` (≥1 repo) | **NEW** phase: analyze branches, draft bodies, save state |
| `<slug>` (state file exists) | **Resume**: reconcile and propose next steps |
| `<slug> --show` | Read-only: reconcile + status table, then stop |
| `<slug> --ready <repo>` | Convert that repo's PR from draft → ready (also reconciles labels) |
| `<slug> --drop <repo> <full-pr-url>` | Remove a stale `build-group=` line (also reconciles labels) |
| `<slug> --label <repo> <add\|rm> <label>` | Add or remove a single label on that repo's PR (escape hatch for manual nudges) |
| `--list` | List all `project_*_prs.md` state files with phase |

If `<slug>` has no state file and no `<repo:branch>` args were provided, error out with usage.

### Slug resolution

The `<slug>` arg may match either:
1. The literal `slug:` field of a state file's frontmatter (preferred).
2. The `feature:` field, if no slug matches.

Resolution algorithm: glob `project_*_prs.md`, read each frontmatter, build a `{slug, feature} → file` map. If exactly one match, use it (and print a one-line note if it was matched via feature, e.g. `(resolved feature 'implicit-vertical-diffusion' → slug 'implicit-vertical')`). If multiple match, list them and ask. If none, error out.

## Paths

```
STATE_DIR  = $CLAUDE_CONFIG_DIR/projects/$(pwd | tr / -)/memory
STATE_FILE = $STATE_DIR/project_<slug>_prs.md
MEMORY_INDEX = $STATE_DIR/MEMORY.md
```

`$CLAUDE_CONFIG_DIR` is set to one of `~/.claude-personal` or `~/.claude-work`; both `projects/<slug>/memory/` dirs symlink through `~/.claude-shared/`, so writes are visible from either profile.

## State file format

```markdown
---
name: project_<slug>_prs
description: In-flight PR coordination state for <feature> (<repo list>)
type: project
feature: <feature-name>
slug: <slug>
phase: NEW  # NEW | DRAFTED | OPEN | CLOSED
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
repos:
  - repo: oops
    branch: feature/x
    pr: null              # PR number once opened
    pr_state: null        # open | closed | merged
    ci_state: null        # pending | green | failing
    last_sha: <short>     # 8-char origin SHA; force-push detection (compared via prefix-match)
    merge_order: 1        # ties allowed (same int = parallel)
    is_draft: false
    build_groups: []      # list of canonical https://github.com/JCSDA-internal/<repo>/pull/<n>
    labels: []            # current GH labels — managed by skill (bug, waiting for another PR, coordinate merge, ready for merge, ...)
---

# In-flight: <feature>

## Drafted bodies
### oops
**Title:** ...
**Body:**
```
<full body text>
```

(repeat per repo)

## Decision log
- YYYY-MM-DD: <reasoning notes>

## Reconciliation log
(populated only when state drifts from live gh on resume)
```

The frontmatter is authoritative. The body is human-readable journal + drafted PR bodies for the DRAFTED→OPEN transition.

### Phase semantics

- `NEW` — analysis runs, bodies drafted; transitions to `DRAFTED` on user approval. (NEW is transient; the state file is written with `phase: DRAFTED` once the user approves.)
- `DRAFTED` — bodies approved, no/some PRs opened. Transitions to `OPEN` when all `pr` fields populated.
- `OPEN` — all PRs opened. `--show`, `--ready`, `--drop`, `--label`, and bare-resume label reconciliation operate.
- `CLOSED` — manual transition. Skill writes a stable summary memory and prompts user to remove the inflight file + index entry.

## Workflow

### NEW — first invocation

1. Verify each `<repo>` directory exists under `bundle/`. If not, error out.
2. `git -C bundle/<repo> fetch origin` per repo (so `origin/<branch>` is current).
3. **Fan out: launch one Explore agent per `<repo:branch>` in parallel** (single message, multiple Agent tool calls). Use the per-repo prompt template below.
4. Wait for all reports. Each agent returns a structured short report (~400 words).
5. Synthesize across reports — **think hard** about merge order per `claude/pr-conventions.md`:
   - Identify each PR's nature (additive / breaking / mixed) from the agent's classification.
   - Determine merge order: a PR is mergeable independently if its CI passes against current `develop` of the others. Build-DAG is informational, not authoritative.
   - Pick **minimal** `build_groups`: only PRs whose CI cannot pass without the matching change.
   - Decide `is_draft`: only true if circular cross-repo deps require it.
   - Resolve `<TBD-<repo>-PR>` placeholders into a coherent plan (we don't have URLs yet, but we know the topology).
   - Dedupe reviewer candidates across repos; surface as a combined ranked list.
   - Propose **opening labels** per repo (see ## Labels for full lifecycle):
     - `bug` if the change clearly fixes incorrect behavior in merged code.
     - `waiting for another PR` for any repo whose `build_groups` is non-empty (i.e., depends on a sibling in this set).
     - `waiting for other repos` only if the user has flagged a model-side dependency outside this PR set; otherwise omit.
     - `coordinate merge` / `ready for merge` are NOT opening labels — they apply later, after review.
6. Show the user, in one combined message:
   - Per-repo: drafted title + body (with `<TBD-...>` placeholders still present)
   - Cross-repo plan: merge order table; build-group topology; draft-vs-ready
   - Reviewer candidates (with commit counts) — note: NOT assigned, just suggestions
   - Label proposal per repo (opening labels only)
7. On approval, **write the state file** with `phase: DRAFTED`; insert drafted bodies under `## Drafted bodies`; append an `## Active Projects` line to `MEMORY.md`.

#### Per-repo agent prompt template

Use `subagent_type: Explore`. Pass this prompt verbatim, substituting `<repo>` and `<branch>`:

```
Audit branch <branch> in /home/tsluka/work/jedi/bundle/<repo> to prepare a JCSDA-internal pull request.

Context: this is part of a coordinated multi-repo PR set for the JEDI bundle. The user follows the conventions documented in /home/tsluka/work/jedi/claude/pr-conventions.md (read this — section "Template" through "Reviewer assignment"). PR titles and bodies must follow that template.

Run these commands and read enough output to judge change semantics:
  git -C /home/tsluka/work/jedi/bundle/<repo> log --oneline origin/develop..origin/<branch>
  git -C /home/tsluka/work/jedi/bundle/<repo> log origin/develop..origin/<branch> --format=fuller
  git -C /home/tsluka/work/jedi/bundle/<repo> diff --stat origin/develop..origin/<branch>
  git -C /home/tsluka/work/jedi/bundle/<repo> diff origin/develop..origin/<branch>     # read enough to judge — this can be huge; sample purposefully
  git -C /home/tsluka/work/jedi/bundle/<repo> rev-parse origin/<branch>
  git -C /home/tsluka/work/jedi/bundle/<repo> log --format='%an' --since=2024-01-01 -- <changed-paths>   # for reviewer candidates

Report (under 400 words, structured):

1. **last_sha**: short SHA of origin/<branch>.

2. **Change classification**: additive (new API/files only) / breaking (rename/remove/signature change) / mixed. One sentence justification.

3. **Public API impact**: list of changed/added/removed types, functions, methods, YAML keys, or CMake targets that downstream repos in the bundle could compile/link against. If none, say "internal only — downstream unaffected at compile time."

4. **CI judgment**:
   - "Passes alone against current develop of others" — if this PR's CI would go green without any build-group annotations.
   - OR "Requires build-group from <repo>" — if the PR's bundle build depends on a sibling repo's matching change being available. Be specific about why (e.g., "saber tests call Diffusion::setParameters(VerticalMethod::Implicit, ...) which doesn't exist on oops develop").

5. **Drafted PR title and body** following the template at claude/pr-conventions.md (## Description / Issue(s) addressed / Dependencies / Impact / Manual Testing Instructions / Checklist). For sibling-PR references in the Dependencies section, use placeholders like `<TBD-oops-PR>` — the orchestrator will resolve them. Do not invent URLs.

6. **Reviewer candidates**: top 5 distinct authors from `git log --format='%an'` on the changed paths, with commit counts, ranked by recency-weighted activity. Note: this is a suggestion list — do NOT include the PR author themselves. Do NOT default to claude/maintainers.md (that is the admin/escalation list, not a review pool).

Do not run gh commands or interact with GitHub. Branches may not be pushed yet. Just analyze the local branch.
```

### DRAFTED — open PRs

1. Read state file. Verify `phase: DRAFTED`.
2. Pre-flight per repo with `pr: null`:
   - `git -C bundle/<repo> ls-remote origin <branch>` — if branch missing on origin, ask user before pushing. Push only with explicit approval.
3. Group repos by `merge_order`. Open lowest-numbered group first; within a group, open in parallel (one Bash block, multiple `gh pr create`).
4. For each PR:
   - Read drafted body from `## Drafted bodies` → `### <repo>` section.
   - Substitute resolved URLs into `<TBD-X-PR>` placeholders using PR numbers from earlier opened batches. (URL form: `https://github.com/JCSDA-internal/<repo>/pull/<n>`.)
   - Show **final** body + opening labels to user. On approval:
     ```bash
     gh pr create -R JCSDA-internal/<repo> \
       --title "<title>" \
       --body-file /tmp/jedi-prs-<slug>-<repo>-body.md \
       --assignee travissluka \
       [--label "bug"] [--label "waiting for another PR"] \
       [--draft]
     ```
     Repeat `--label "<name>"` per opening label. Quote multi-word names. See ## Labels.
   - Capture PR number from the output URL.
5. Update state: set `pr`, `pr_state: open`, `is_draft`, `last_sha`, `labels` (the labels actually passed to `gh pr create`). Update `last_updated`.
6. After all PRs in all groups open, set `phase: OPEN`.

User can interrupt between merge-order groups and resume later.

### Resume — bare `<slug>`

1. Read state file. Read `phase`.
2. Reconcile against live `gh`. Run all per-PR queries in **one Bash block** (multiple commands separated by `;`) so they execute in parallel-ish and share output:
   ```bash
   for entry in oops:3275 saber:1234 jedi-docs:1028; do
     r=${entry%:*}; n=${entry#*:}
     printf '==%s#%s==\n' "$r" "$n"
     gh pr view "$n" -R "JCSDA-internal/$r" \
       --json state,mergedAt,headRefOid,isDraft,statusCheckRollup,reviewDecision,labels \
       --jq '{state, isDraft, headRefOid: .headRefOid[0:8], mergedAt, reviewDecision,
              labels: [.labels[].name],
              ci_states: [.statusCheckRollup[] | .conclusion // .state]
                         | group_by(.) | map({(.[0]): length}) | add}'
   done
   ```
   Derive `ci_state` from the rollup map: any FAILURE/CANCELLED/TIMED_OUT → `fail`; all SUCCESS (or SUCCESS+SKIPPED) → `green`; any PENDING/QUEUED/IN_PROGRESS without a fail → `pending`; empty rollup → `unknown`.
   For each repo with `pr: null` in state: `gh pr list -R JCSDA-internal/<repo> --search "head:<branch>" --json number,state,url`.
3. **Force-push detection.** After `git -C bundle/<repo> fetch origin <branch>`, run `git -C bundle/<repo> rev-parse origin/<branch>` and compare to `last_sha` via **prefix match** — state stores ≥7-char SHAs, the comparison is `case "$new_sha" in $old_sha*) match;; *) DRIFT;; esac`. Direct string equality flags spurious drift when SHA lengths differ.
4. Reconcile:
   - **Match** → proceed.
   - **Non-destructive drift** (CI status changed, body edited externally, new commits past the same fast-forward line): update frontmatter; append a dated line to `## Reconciliation log`. (Skipped if `--show`.)
   - **Destructive drift** (PR closed/deleted, branch force-pushed onto a commit that is NOT a descendant of `last_sha`, or `gh pr list` returned an unexpected PR for a `pr: null` branch): **stop**, show what changed, ask user before mutating state.
5. Print status table using emoji for `pr_state`, `ci`, and `draft`:

   | Glyph | `pr_state` | `ci_state` | `is_draft` |
   |---|---|---|---|
   | 🟢 | open | green | — |
   | 🔴 | — | fail | — |
   | 🟡 | — | pending | — |
   | ⚪ | — | unknown | — |
   | 🟣 | merged | — | — |
   | ⚫ | closed | — | — |
   | 📝 | — | — | true (draft) |
   | (blank) | — | — | false (ready) |

   Example row format (markdown table; one row per repo):

   ```
   | repo      | branch                              | PR    | state | ci | sha       | order | draft | build_groups | labels                          |
   |-----------|-------------------------------------|-------|-------|----|-----------|-------|-------|--------------|---------------------------------|
   | oops      | feature/implicit-vertical-diffusion | #3275 | 🟢    | 🟢 | 01d90719  | 1     |       | (none)       | ready for merge                 |
   | jedi-docs | feature/implicit-vertical-diffusion | #1028 | 🟢    | 🟢 | 77104ced  | 1     |       | (none)       | coordinate merge                |
   | saber     | feature/implicit-vertical-diffusion | #1234 | 🟢    | 🔴 | aa320319  | 2     |       | oops#3275    | bug, waiting for another PR     |
   ```

   Sort rows by `merge_order` ascending (then by repo name within a level). Render `build_groups` as `repo#PR` shorthand for compactness; full URLs only in state. Labels: comma-separated, lowercase as-stored on GitHub; show `(none)` if empty.
6. **Label-drift reconciliation.** Compare each repo's live `labels` to state `labels`:
   - Live ⊃ state: someone added a label outside the skill — adopt it into state silently (no decision-log entry needed for human-curated labels like `INFRA`, `OBS`, partner-org tags).
   - Live ⊂ state: a managed label was removed externally — log to `## Reconciliation log` and re-propose if the lifecycle (## Labels) still calls for it.
   - Then evaluate each managed label against the lifecycle (## Labels) and stage transitions to propose in step 7.
7. If `--show`: **stop here. Do not write to the state file.** Otherwise propose actionable next steps. Label transitions are explicit user-approval items, not silent updates:
   - "All level-N CI green → ready to open level-(N+1)?"
   - "Upstream PR `<repo>#<n>` merged → drop downstream `build-group=` lines that point at it (and `waiting for another PR` if last dep)?"
   - "Draft `<repo>#<n>` CI is green → convert to ready?"
   - "Reviewers approved `<repo>#<n>` → add `coordinate merge` (siblings still in flight) / `ready for merge` (this is the last in the order)?"
   - "Failing CI on `<repo>#<n>` → investigate before next step."

### `--ready <repo>`

1. Confirm with user. Also propose, in the same prompt, the appropriate review-stage label per ## Labels:
   - `coordinate merge` if any sibling PR in the set has `pr_state` ∈ {open, null} (still in flight).
   - `ready for merge` if all siblings are `merged` (or this is a single-repo set).
   Both are draft-incompatible — the label transition is paired with the draft→ready flip.
2. Run in a single Bash block so failure of one stops the rest:
   ```bash
   gh pr ready <n> -R JCSDA-internal/<repo> && \
   gh pr edit <n> -R JCSDA-internal/<repo> --add-label "<chosen-label>"
   ```
3. Update state: `is_draft: false`; add the chosen label to `repos[i].labels`. Append decision log line.

### `--drop <repo> <full-pr-url>`

1. Canonicalize `<full-pr-url>` to `https://github.com/JCSDA-internal/<repo>/pull/<n>`.
2. `gh pr view <state-pr> -R JCSDA-internal/<repo> --json body --jq .body > /tmp/jedi-prs-<slug>-<repo>-body.md`
3. In the file, delete the line `build-group=<full-pr-url>` entirely. If the line is not found, surface to user.
4. Show diff to user.
5. On approval:
   ```bash
   gh api -X PATCH "repos/JCSDA-internal/<repo>/pulls/<state-pr>" \
     -F body=@/tmp/jedi-prs-<slug>-<repo>-body.md --jq '.body' > /dev/null
   ```
   (`gh pr edit --body-file` fails on JCSDA-internal repos due to a classic-projects GraphQL deprecation; the REST PATCH path works.)
6. Suggest: "Push an empty commit to retrigger CI: `git -C bundle/<repo> commit --allow-empty -m 'trigger CI' && git -C bundle/<repo> push`."
7. Update state `repos[i].build_groups` (drop the URL). Append decision log line.
8. **Label cascade.** If `repos[i].build_groups` is now empty AND `waiting for another PR` is in `repos[i].labels`:
   - Propose dropping the label. On approval:
     ```bash
     gh pr edit <state-pr> -R JCSDA-internal/<repo> --remove-label "waiting for another PR"
     ```
   - If the PR is already past review (e.g., `reviewDecision == APPROVED`), also propose adding `coordinate merge` (still has live siblings) or `ready for merge` (all siblings already merged) per ## Labels. Same `gh pr edit ... --add-label` call.
   - Update `repos[i].labels` to match.

### `--label <repo> <add|rm> <label>`

Escape hatch for manual label nudges (e.g., adding `do not merge` after a regression report, or applying a partner-org tag like `OBS`).

1. Validate `<label>` is one of the org-wide labels in the table at ## Labels (managed lifecycle labels) or is a known unmanaged label (group tags `INFRA`/`OBS`/etc., partner orgs, `do not merge`, `enhancement`, etc.). If unknown, list candidates and ask.
2. Confirm with user.
3. Apply:
   ```bash
   gh pr edit <state-pr> -R JCSDA-internal/<repo> --add-label "<label>"     # for add
   gh pr edit <state-pr> -R JCSDA-internal/<repo> --remove-label "<label>"  # for rm
   ```
4. Update `repos[i].labels`. Append decision log line. **Do not** auto-cascade other lifecycle labels — user explicitly invoked a single change. Lifecycle reconciliation happens on the next bare-resume.

### `--list`

```bash
ls "$CLAUDE_CONFIG_DIR/projects/$(pwd | tr / -)/memory"/project_*_prs.md 2>/dev/null
```

For each, read frontmatter `slug`, `feature`, `phase`, `last_updated`. Emit a small table.

## Approval gates (always)

- Every PR body before `gh pr create`.
- Every body edit before `gh api -X PATCH`.
- Every `--ready` before `gh pr ready`.
- Every label add/remove before `gh pr edit --add-label`/`--remove-label` (lifecycle proposals during resume, cascades during `--drop`/`--ready`, and `--label` invocations).
- Branch pushes (no `git push` without explicit permission, per memory).

## Labels

Canonical org labels live in `JCSDA-internal/github-admin:github_api/org_labels.py`. The skill manages a small subset; everything else (group tags `INFRA`/`OBS`/etc., partner-org tags, `enhancement`, `do not merge`, `help wanted`, etc.) is left to the human and only adopted into state if observed live.

### Managed lifecycle labels

| Label | Meaning | Apply when | Drop when |
|---|---|---|---|
| `bug` | Fixes incorrect behavior in merged code | At PR open if the change is a defect fix (not new feature, not refactor, not warning cleanup) | Stays for the life of the PR |
| `waiting for another PR` | Blocked on a sibling PR in this set | At PR open if `repos[i].build_groups` is non-empty; on `--drop` if a new dep is recorded | `--drop` removes the last entry from `build_groups` |
| `waiting for other repos` | Blocked on a model-side change outside this PR set | User explicitly flags an external dep when proposing the set; or an upstream merges that breaks a model interface | The external dep lands |
| `coordinate merge` | Reviewed and ready, but a sibling in this set still needs to land | Reviews approved AND any sibling has `pr_state` ∈ {open, null} | All siblings reach `pr_state: merged`; or this PR itself merges |
| `ready for merge` | Reviewed, ready, no coordination needed | Reviews approved AND all siblings already merged (or single-repo set) | This PR merges (label disappears with the PR) |

### Lifecycle interactions

- `waiting for another PR` and `waiting for other repos` are mutually compatible — a PR can be blocked on both kinds of dep simultaneously.
- `coordinate merge` and `ready for merge` are mutually exclusive; a transition adds one and removes the other.
- The `waiting for *` labels and the `*ready for merge*` labels are mutually exclusive — never apply both at the same time. If reviews land while a build-group is still open, leave only `waiting for another PR` until the dep clears.
- Labels are only proposed when they would *change* state — silent if everything matches the lifecycle table.

### gh syntax cheatsheet

```bash
gh pr create ... --label "bug" --label "waiting for another PR"        # at open; one --label per name
gh pr edit <n> -R JCSDA-internal/<repo> --add-label "coordinate merge"
gh pr edit <n> -R JCSDA-internal/<repo> --remove-label "waiting for another PR"
gh pr view <n> -R JCSDA-internal/<repo> --json labels --jq '[.labels[].name]'
```

Quote labels with spaces. `gh pr edit --add-label`/`--remove-label` works on JCSDA-internal repos (unlike `--body-file`, which has a known issue documented under `--drop`).

## URL canonicalization

All build-group URLs in state and bodies are normalized to:
```
https://github.com/JCSDA-internal/<repo>/pull/<n>
```
Strikethrough matching depends on string equality. If a user passes `JCSDA-internal/oops#3275` or `https://github.com/JCSDA-internal/oops/pull/3275/files`, normalize first.

## Closing out

When all PRs are merged, the user explicitly transitions to `phase: CLOSED`:
1. Confirm all `pr_state: merged` (or `closed` for any abandoned).
2. Write a stable project memory under `<memory-dir>/project_<slug>_summary.md` capturing what shipped (PRs, merge dates, key API additions). This is a normal `type: project` memory, not a state file.
3. Prompt user to delete the `project_<slug>_prs.md` state file and the `## Active Projects` index entry.

The skill never auto-closes.
