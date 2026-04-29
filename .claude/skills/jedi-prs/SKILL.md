---
name: jedi-prs
description: >-
  Coordinate multi-repo PRs across JCSDA-internal repos. Handles change analysis,
  merge-order reasoning, build-group selection, tracking-issue check/creation,
  body drafting, opening, label lifecycle (bug / waiting for another PR /
  coordinate merge / ready for merge), and the multi-day follow-up flow
  (draft→ready, drop stale build-groups). State is persisted in a memory file
  so a workflow that spans a CI cycle (hours) can be resumed across conversations.
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

Resolution algorithm: glob `project_*_prs.md`, read each frontmatter, build a `{slug, feature} → file` map.

1. **Exact match** on `slug` or `feature` → use it (print a one-line note if matched via feature, e.g. `(resolved feature 'implicit-vertical-diffusion' → slug 'implicit-vertical')`).
2. **Fuzzy fallback** if no exact match: prefix-match either direction (`slug.startswith(input) or input.startswith(slug)`), case-insensitive. If exactly one candidate, propose it explicitly (e.g. `no exact match for 'sequential-enk' — closest is 'sequential-enkf'. Use that?`) and wait for user confirmation. If multiple, list them and ask. **Never silently substitute** — typo correction always needs an explicit "yes".
3. **No match** → error out with usage and the output of `--list`.

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
issue:                  # tracking issue (one per PR set); null only if user explicitly opted out
  repo: oops            # where the issue lives — preferred: the most-upstream repo in the set (lowest merge_order)
  number: 1234
  url: https://github.com/JCSDA-internal/oops/issues/1234
  state: open           # open | closed
  closing_repo: fv3-jedi  # repo of the LAST-merging PR — its body carries `Closes ...`; all other PRs use `Refs ...`
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

**Legacy / imported state files.** State files predating later schema additions may be missing the top-level `issue:` block, the per-repo `labels:` field, or the `## Drafted bodies` section (e.g., when imported from PRs that were already open on GitHub). Treat any missing optional field as null/empty rather than as drift; do not flag it for reconciliation. The Resume workflow's label-drift step will silently adopt live labels into a previously-empty `labels:`. The `## Drafted bodies` section may legitimately be a placeholder ("PRs already open on GitHub; live bodies are the source of truth.") for imported sets — don't treat that as missing data.

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
6. **Tracking issue.** Every PR set should reference at least one open GitHub issue (zenhub uses these for tracking and story-point assignment). See ## Tracking issue for the full lifecycle.
   a. Search for candidate issues across the affected repos:
      ```bash
      for r in <repo1> <repo2> ...; do
        gh issue list -R "JCSDA-internal/$r" --state open --limit 50 \
          --search "<slug-keyword> OR <feature-keyword>" \
          --json number,title,assignees,url --jq '.[] | "\(.url) — \(.title) [@\(.assignees[].login // "unassigned")]"'
      done
      ```
      Use 1–3 keywords from the slug/feature for `--search`. If no hits, also propose a broader fallback search (e.g., search by changed-file area).
   b. Surface candidates to user. Three outcomes — ask which:
      - **Reuse existing:** user picks one.
      - **Open new:** propose creating one in the **most-upstream repo** in the set (lowest `merge_order`; ties → user picks). Draft a short title (≤60 chars) and a 2–3 sentence body using the template at ## Tracking issue. Default assignee is `travissluka`.
      - **Opt out:** for trivial changes (typo fix, doc cherry-pick, etc.) the user may decline. Set `issue: null`; skip step (c); PR bodies render `## Issue(s) addressed` as `n/a`.
   c. Determine `closing_repo`: the repo whose PR is **last to merge** (highest `merge_order`; ties → user picks). Its body will carry the `Closes ...` line; all others use `Refs ...`.
7. Show the user, in one combined message:
   - Per-repo: drafted title + body (with `<TBD-...>` and `<ISSUE-REF>` placeholders still present)
   - Cross-repo plan: merge order table; build-group topology; draft-vs-ready
   - Reviewer candidates (with commit counts) — note: NOT assigned, just suggestions
   - Label proposal per repo (opening labels only)
   - Tracking issue: existing #N OR proposed `gh issue create` invocation (with title + body + assignee), and the `closing_repo` choice
8. On approval:
   a. If user chose **Open new** in 6b: open the issue, capture the number, then print: `⚠️ Set story points in zenhub: <issue.url>` (the skill cannot set them — no zenhub CLI installed). Don't gate on confirmation; just remind.
      ```bash
      gh issue create -R JCSDA-internal/<upstream> \
        --title "<short title>" \
        --body-file /tmp/jedi-prs-<slug>-issue.md \
        --assignee travissluka
      ```
   b. Substitute `<ISSUE-REF>` placeholders in each drafted body:
      - If `issue: null` (opted out): replace `<ISSUE-REF>` with `n/a`.
      - Otherwise:
        - `closing_repo`'s body: `Closes JCSDA-internal/<issue.repo>#<issue.number>` (or bare `Closes #<n>` if `closing_repo == issue.repo`).
        - All other repos: `Refs JCSDA-internal/<issue.repo>#<issue.number>`.
   c. **Write the state file** with `phase: DRAFTED`; populate `issue:` block (or set `issue: null`); insert resolved drafted bodies under `## Drafted bodies`; append an `## Active Projects` line to `MEMORY.md`.

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

5. **Drafted PR title and body** following the template at claude/pr-conventions.md (## Description / Issue(s) addressed / Dependencies / Impact / Manual Testing Instructions / Checklist). For sibling-PR references in the Dependencies section, use placeholders like `<TBD-oops-PR>` — the orchestrator will resolve them. For the `## Issue(s) addressed` section, write the literal placeholder `<ISSUE-REF>` on its own line — the orchestrator will substitute either `Closes JCSDA-internal/<repo>#<n>` (last-to-merge PR) or `Refs JCSDA-internal/<repo>#<n>` (all others). Do not invent issue numbers or URLs.

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
5. Update state: set `pr`, `pr_state: open`, `ci_state: pending`, `is_draft`, `last_sha`, `labels` (the labels actually passed to `gh pr create`). Update `last_updated`.
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
   If `issue` is non-null, also query: `gh issue view <issue.number> -R JCSDA-internal/<issue.repo> --json state,closedAt --jq '{state, closedAt}'`. Update `issue.state` from the result.
3. **Force-push detection.** After `git -C bundle/<repo> fetch origin <branch>`, run `git -C bundle/<repo> rev-parse origin/<branch>` and compare to `last_sha` via **prefix match** — state stores ≥7-char SHAs, the comparison is `case "$new_sha" in $old_sha*) match;; *) DRIFT;; esac`. Direct string equality flags spurious drift when SHA lengths differ.
4. Reconcile:
   - **Match** → proceed.
   - **Non-destructive drift** (CI status changed, body edited externally, new commits past the same fast-forward line): update frontmatter; append a dated line to `## Reconciliation log`. (Skipped if `--show`.)
   - **Destructive drift** (PR closed/deleted, branch force-pushed onto a commit that is NOT a descendant of `last_sha`, `gh pr list` returned an unexpected PR for a `pr: null` branch, or tracking issue closed before the `closing_repo` PR has merged): **stop**, show what changed, ask user before mutating state.
5. Print a one-line **tracking issue** header — three cases:
   - Issue tracked: `Tracking issue: <issue.url> (<state>)`
   - User opted out: `Tracking issue: (none — opted out)`
   - State file predates the issue field: `Tracking issue: (none — legacy state file)`

   Then a status table using emoji for `pr_state`, `ci`, and `draft`:

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

   Sort rows by `merge_order` ascending (then by repo name within a level). Render `build_groups` as `repo#PR` shorthand for compactness; full URLs only in state. Labels: comma-separated, displayed as-stored on GitHub (org labels mix case — `bug`, `INFRA`, `Epic`); show `(none)` if empty.
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
   - "Tracking issue closed but `closing_repo` PR not merged — confirm intentional?"

### `--ready <repo>`

1. Confirm with user. Also propose, in the same prompt, the appropriate review-stage label per ## Labels:
   - `coordinate merge` if any sibling PR in the set has `pr_state` ∈ {open, null} (still in flight).
   - `ready for merge` if all siblings are `merged` (or this is a single-repo set).
   Both review-stage labels imply the PR is review-ready, so they should only be applied at the moment of the draft→ready flip — pair the label add with the flip in the same Bash block.
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

### CLOSED — wrap up

When all PRs are merged, the user explicitly transitions to `phase: CLOSED`:

1. Confirm all `pr_state: merged` (or `closed` for any abandoned).
2. Stable summary memory — **prefer updating an existing one over creating a new one**:
   ```bash
   ls "$STATE_DIR"/project_<slug>_*.md "$STATE_DIR"/project_<slug-with-underscores>_*.md 2>/dev/null \
     | grep -v _prs.md
   ```
   Search both hyphen and underscore variants of the slug (slugs in this skill are hyphenated by convention — `sequential-enkf` — but earlier hand-written memories may use underscores — `project_sequential_enkf_branches.md`). If a summary-style memory already exists (`_summary.md`, `_branches.md`, `_reference.md`, etc.), update it with merged dates, working-branch resets, and any final PR info. Only create `project_<slug>_summary.md` if no existing summary covers the feature.
3. Prompt user to delete the `project_<slug>_prs.md` state file and the `## Active Projects` index entry. Both are destructive — **wait for explicit user approval** before `rm` and before the MEMORY.md edit.

The skill never auto-closes.

## Approval gates (always)

- Every PR body before `gh pr create`.
- Every body edit before `gh api -X PATCH`.
- Every `--ready` before `gh pr ready`.
- Every label add/remove before `gh pr edit --add-label`/`--remove-label` (lifecycle proposals during resume, cascades during `--drop`/`--ready`, and `--label` invocations).
- Every issue creation (`gh issue create`) and the `closing_repo` choice.
- Branch pushes (no `git push` without explicit permission, per memory).

## Tracking issue

Every PR set should reference at least one open GitHub issue so zenhub can track it (story points, sprint planning). The skill enforces this gate at NEW; the user can opt out per set, but the default is to require an issue.

### Placement

- **Existing issue:** any open issue the user picks. Skill records `{repo, number, url, state}` plus `closing_repo`.
- **New issue:** opened in the **most-upstream repo** in the set (the one with the lowest `merge_order`). Rationale: keeps the canonical tracker near the upstream change; downstream PRs reference cross-repo via the standard `JCSDA-internal/<repo>#<n>` form (which respects `feedback_cross_repo_pr_refs.md`).

### Closing PR

The `closing_repo` is the repo whose PR is **last to merge** (highest `merge_order`). That PR's body carries `Closes ...` (which auto-closes the issue when it merges); all other PRs use `Refs ...`.

- Same-repo close: `Closes #<n>` (when `closing_repo == issue.repo`).
- Cross-repo close: `Closes JCSDA-internal/<issue.repo>#<n>`. GitHub honors cross-repo close keywords within the same org when the actor has triage perms — works for JCSDA-internal.
- All non-closing PRs: `Refs JCSDA-internal/<issue.repo>#<n>` — links the PR to the issue without closing it.

If `merge_order` ties pick more than one candidate for `closing_repo`, ask the user.

### Issue body template

Short and stub-like — the user fills in detail later, and the linked PRs carry the substantive write-up. Two or three sentences max.

```
<one-paragraph summary of the goal>

Tracked across:
- JCSDA-internal/<repo1> (PR forthcoming)
- JCSDA-internal/<repo2> (PR forthcoming)

Story points: TBD (set in zenhub).
```

### Story points

The skill **cannot** set zenhub story points (no zenhub CLI installed; would need a zenhub PAT and a custom GraphQL call). After `gh issue create` succeeds, the skill prints:

> ⚠️ Set story points in zenhub: <issue.url>

…and prompts the user to confirm before proceeding. Don't gate on user confirmation that points are set — just remind.

### Opting out

The opt-out path (chosen at NEW step 6b) sets `issue: null` in state, renders `## Issue(s) addressed` as `n/a` in every PR body, and writes a one-line rationale to the decision log.

### Resume reconciliation

Wired into the Resume workflow above: step 2 queries `gh issue view` alongside the PR queries; step 4 surfaces external issue-closure (before the `closing_repo` PR has merged) as destructive drift.

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

A PR is in one of two label-states:

- **Blocked** — has zero or more `waiting for *` labels (the two `waiting for *` variants can coexist).
- **Mergeable** — has exactly one of `coordinate merge` or `ready for merge`.

The two states are mutually exclusive: never apply a `waiting for *` label and a `coordinate merge`/`ready for merge` label to the same PR at the same time. If reviews land while a build-group is still open, the PR stays Blocked — leave the `waiting for *` label in place; do not add `coordinate merge` until the dep clears.

`bug` is independent of the blocked/mergeable axis and may coexist with any label.

Labels are only proposed when they would *change* state — silent if everything matches the lifecycle table.

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
`--drop` matches `build-group=<url>` lines by string equality, so non-canonical inputs would silently miss. If a user passes `JCSDA-internal/oops#3275` or `https://github.com/JCSDA-internal/oops/pull/3275/files`, normalize first.

