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

Codifies `claude/pr-conventions.md` end-to-end and persists per-feature state for multi-day workflows.

> **Read first:** `claude/pr-conventions.md` is authoritative; this is the operational playbook.
>
> **Approval gate (always):** never call `gh pr create`, `gh api -X PATCH`, `gh pr ready`, `gh pr edit --add-label`/`--remove-label`, `gh issue create`, `rm`, MEMORY.md edits, or `git push` without showing the user what you're about to do and waiting for explicit confirmation.

## Parse arguments

| Form | Action |
|---|---|
| `<slug> <repo:branch> ...` (≥1 repo) | **NEW** — analyze, draft, save state |
| `<slug>` (state file exists) | **Resume** — reconcile + propose next steps |
| `<slug> --show` | Read-only reconcile + status table |
| `<slug> --ready <repo>` | Draft → ready (also adds review-stage label) |
| `<slug> --drop <repo> <full-pr-url>` | Remove stale `build-group=` line (+ label cascade) |
| `<slug> --label <repo> <add\|rm> <label>` | Manual single-label nudge |
| `--list` | List all `project_*_prs.md` state files |

### Slug resolution

Glob `project_*_prs.md`, read each frontmatter, build `{slug, feature} → file` map.

1. **Exact match** on `slug` or `feature` → use it. If matched via `feature`, print one note line: `(resolved feature 'implicit-vertical-diffusion' → slug 'implicit-vertical')`.
2. **Fuzzy fallback** if no exact: prefix-match either direction, case-insensitive. If exactly one candidate, propose it explicitly (e.g. `no exact match for 'sequential-enk' — closest is 'sequential-enkf'. Use that?`) and wait for "yes". Multiple → list and ask. **Never silently substitute.**
3. **No match** → fall through to branch auto-discovery (next subsection) only if no `<repo:branch>` args were provided; otherwise treat as a NEW invocation.

### Branch auto-discovery

Fallback when slug resolution finds no state file AND the user provided no `<repo:branch>` args. Try to discover candidate branches in `bundle/*/`:

```bash
suffix="${slug//-/_}"   # convert slug to typical branch-name form (hyphens → underscores)
for dir in bundle/*/; do
  repo=$(basename "$dir")
  for cand in "feature/$suffix" "feature/<slug>" "$suffix" "<slug>"; do
    if git -C "$dir" rev-parse --verify "$cand" >/dev/null 2>&1; then
      printf '%s:%s\n' "$repo" "$cand"
      break
    fi
  done
done
```

If ≥1 repo matches, propose the discovered list explicitly to the user (e.g., `auto-discovered: oops:feature/foo, ufo:feature/foo — proceed?`) and wait for confirmation. On approval, treat as if invoked with those `<repo:branch>` args (NEW workflow). Otherwise — or if zero matches — error out with usage and `--list` output. **Never silently proceed without confirmation.**

## Paths

```
STATE_DIR  = $CLAUDE_CONFIG_DIR/projects/$(pwd | tr / -)/memory
STATE_FILE = $STATE_DIR/project_<slug>_prs.md
MEMORY_INDEX = $STATE_DIR/MEMORY.md
```

`$CLAUDE_CONFIG_DIR` is `~/.claude-personal` or `~/.claude-work`; both `projects/<slug>/memory/` dirs symlink through `~/.claude-shared/`, so writes are visible from either profile.

## State file format

Frontmatter is authoritative; body is human-readable journal.

```yaml
---
name: project_<slug>_prs
description: In-flight PR coordination state for <feature> (<repo list>)
type: project
feature: <feature-name>
slug: <slug>            # hyphenated by convention
phase: NEW              # NEW | DRAFTED | OPEN | CLOSED
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
issue:                  # null if user opted out; absent in legacy state
  repo: oops            # most-upstream repo in the set (lowest merge_order)
  number: 1234
  url: https://github.com/JCSDA-internal/oops/issues/1234
  state: open           # open | closed
  closing_repo: fv3-jedi  # repo of last-merging PR; carries `Closes ...`
repos:
  - repo: oops
    branch: feature/x
    pr: null            # null until opened
    pr_state: null      # open | closed | merged
    ci_state: null      # pending | green | failing | unknown
    last_sha: <8-char>  # for force-push detection (prefix-match)
    merge_order: 1      # ties allowed (parallel)
    is_draft: false
    build_groups: []    # canonical https://github.com/JCSDA-internal/<repo>/pull/<n>
    labels: []          # current GH labels
---
```

Body sections: `## Drafted bodies` (per-repo title + body, used at DRAFTED→OPEN), `## Decision log` (dated reasoning notes), `## Reconciliation log` (drift events).

**Legacy / imported state files.** Missing `issue:`, per-repo `labels:`, or a stub `## Drafted bodies` ("PRs already open on GitHub; live bodies are the source of truth.") are not drift — treat as null/empty.

### Phase semantics

- `NEW` — transient; written as `DRAFTED` once user approves.
- `DRAFTED` — bodies approved, some/no PRs opened. `OPEN` once all `pr` populated.
- `OPEN` — all PRs opened. All sub-actions operate.
- `CLOSED` — manual transition; never auto-closes.

## Workflow

### NEW — first invocation

1. Verify each `<repo>` exists under `bundle/`.
2. `git -C bundle/<repo> fetch origin` per repo.
3. **Fan out: launch one `Explore` agent per `<repo:branch>` in parallel** (single message, multiple `Agent` tool calls). Use the prompt template in `agent-prompt.md` (Read it from this skill's base directory), substituting `<repo>` and `<branch>`.
4. Wait for all reports (~400 words each).
5. Synthesize — **think hard** about merge order per `claude/pr-conventions.md`:
   - PR nature (additive / breaking / mixed) from each agent.
   - Merge order: a PR is independently mergeable if its CI passes against current `develop` of others. Build-DAG informational, not authoritative.
   - **Minimal `build_groups`**: only PRs whose CI cannot pass without the matching change.
   - `is_draft`: true only for circular cross-repo deps.
   - Resolve `<TBD-<repo>-PR>` placeholders into a coherent plan.
   - Reviewer candidates: dedupe across repos into one ranked list (surfaced in step 7 as suggestions only).
   - **Opening labels per repo** (see ## Reference for full lifecycle):
     - `bug` if it fixes incorrect behavior in merged code.
     - `waiting for another PR` if `build_groups` non-empty.
     - `waiting for other repos` only if user flagged an external (model-side) dep.
     - `coordinate merge` / `ready for merge` are NOT opening labels (review-stage only).
6. **Tracking issue** — every PR set should reference one (zenhub uses these for story-point tracking).
   a. Search candidates across affected repos (1–3 keywords from slug/feature):
      ```bash
      for r in <repo1> <repo2> ...; do
        gh issue list -R "JCSDA-internal/$r" --state open --limit 50 \
          --search "<slug-keyword> OR <feature-keyword>" \
          --json number,title,assignees,url --jq '.[] | "\(.url) — \(.title) [@\(.assignees[].login // "unassigned")]"'
      done
      ```
   b. Three outcomes — ask user:
      - **Reuse existing:** user picks one.
      - **Open new:** in **most-upstream repo** (lowest `merge_order`; ties → user picks). Short title (≤60 chars), 2–3 sentence body, default assignee `travissluka`. Body template:
        ```
        <one-paragraph summary of the goal>

        Tracked across:
        - JCSDA-internal/<repo1> (PR forthcoming)
        - JCSDA-internal/<repo2> (PR forthcoming)

        Story points: TBD (set in zenhub).
        ```
      - **Opt out:** for trivial fixes. Set `issue: null`; `<ISSUE-REF>` becomes `n/a`; one-line rationale to decision log.
   c. (Skip if opted out.) Determine `closing_repo`: last-to-merge (highest `merge_order`; ties → user picks). Carries `Closes JCSDA-internal/<issue.repo>#<n>` (or bare `Closes #<n>` if same repo); all others `Refs JCSDA-internal/<issue.repo>#<n>`. Cross-repo close keywords work within the same org.
7. Show user, in one combined message:
   - Per-repo drafted title + body (with `<TBD-...>` and `<ISSUE-REF>` placeholders)
   - Cross-repo plan: merge-order table; build-group topology; draft/ready
   - Reviewer suggestions (NOT assigned)
   - Opening labels per repo
   - Tracking issue: existing #N OR proposed `gh issue create` invocation, plus `closing_repo`
8. On approval:
   a. If user chose **Open new**:
      ```bash
      gh issue create -R JCSDA-internal/<upstream> \
        --title "<short title>" \
        --body-file /tmp/jedi-prs-<slug>-issue.md \
        --assignee travissluka
      ```
      Then print `⚠️ Set story points in zenhub: <issue.url>` (skill cannot — no zenhub CLI). Don't gate on confirmation; just remind.
   b. Substitute `<ISSUE-REF>` placeholders:
      - `closing_repo`: `Closes JCSDA-internal/<issue.repo>#<n>` (or bare `Closes #<n>` if same repo).
      - All others: `Refs JCSDA-internal/<issue.repo>#<n>`.
      - Opt-out: `n/a`.
   c. Write state file as `phase: DRAFTED`; populate the `issue:` block (or `issue: null` if opted out); insert resolved bodies under `## Drafted bodies`; append `## Active Projects` line in `MEMORY.md`.

### DRAFTED — open PRs

1. Read state file. Verify `phase: DRAFTED`.
2. Pre-flight per repo with `pr: null`: `git -C bundle/<repo> ls-remote origin <branch>`. If branch missing on origin, ask before pushing.
3. Group repos by `merge_order`. Open lowest-numbered group first; within a group, parallel (one Bash block, multiple `gh pr create`).
4. For each PR:
   - Read drafted body from `## Drafted bodies` → `### <repo>`.
   - Substitute resolved URLs into `<TBD-X-PR>` placeholders. URL form: `https://github.com/JCSDA-internal/<repo>/pull/<n>`.
   - Show **final** body + opening labels. On approval:
     ```bash
     gh pr create -R JCSDA-internal/<repo> \
       --title "<title>" \
       --body-file /tmp/jedi-prs-<slug>-<repo>-body.md \
       --assignee travissluka \
       [--label "bug"] [--label "waiting for another PR"] \
       [--draft]
     ```
     One `--label "<name>"` per opening label. Quote multi-word names.
   - Capture PR number from output URL.
5. Update state: `pr`, `pr_state: open`, `ci_state: pending`, `is_draft`, `last_sha`, `labels` (those actually passed). Update `last_updated`.
6. After all groups open, set `phase: OPEN`. User can interrupt between groups.

### Resume — bare `<slug>`

1. Read state file. Read `phase`.
2. Reconcile against live `gh`. One Bash block:
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
   Derive `ci_state`: any FAILURE/CANCELLED/TIMED_OUT → `fail`; all SUCCESS (or SUCCESS+SKIPPED) → `green`; PENDING/QUEUED/IN_PROGRESS without fail → `pending`; empty rollup → `unknown`.
   For each repo with `pr: null`: `gh pr list -R JCSDA-internal/<repo> --search "head:<branch>" --json number,state,url`.
   If `issue` non-null: `gh issue view <issue.number> -R JCSDA-internal/<issue.repo> --json state,closedAt --jq '{state, closedAt}'`. Update `issue.state`.
3. **Force-push detection.** `git -C bundle/<repo> fetch origin <branch>`, then `rev-parse origin/<branch>`. Prefix-compare to `last_sha`: `case "$new" in $old*) match;; *) DRIFT;; esac` (string equality flags spurious drift on length differences).
4. Reconcile:
   - **Match** → proceed.
   - **Non-destructive drift** (CI changed, body edited externally, fast-forward commits): update frontmatter; append dated `## Reconciliation log` line. (Skipped if `--show`.)
   - **Destructive drift** (PR closed/deleted, force-push not descendant of `last_sha`, unexpected PR for `pr: null` branch, or tracking issue closed before `closing_repo` PR has merged): **stop**, show what changed, ask before mutating.
5. Print **tracking-issue header** then status table:
   - `Tracking issue: <issue.url> (<state>)`
   - `Tracking issue: (none — opted out)`
   - `Tracking issue: (none — legacy state file)`

   Status-table glyphs:

   | Glyph | meaning |
   |---|---|
   | 🟢 | open / CI green |
   | 🔴 | CI fail |
   | 🟡 | CI pending |
   | ⚪ | CI unknown |
   | 🟣 | merged |
   | ⚫ | closed |
   | 📝 | draft |

   Columns: `repo | branch | PR | state | ci | sha | order | draft | build_groups | labels`. Sort by `merge_order` ascending (then repo name). Render `build_groups` as `repo#PR`. Labels: comma-separated, as-stored (mixed case — `bug`, `INFRA`, `Epic`); `(none)` if empty.
6. **Label-drift reconciliation.** Compare live vs state `labels`:
   - Live ⊃ state: silently adopt (human-curated tags like `INFRA`, partner-org tags).
   - Live ⊂ state: log to `## Reconciliation log`; re-propose if lifecycle still calls for it.
   - Evaluate each managed label against ## Reference; stage transitions for step 7.
7. If `--show`: **stop. Do not write state.** Otherwise propose next steps (each is a user-approval item):
   - "All level-N CI green → open level-(N+1)?"
   - "Upstream PR `<repo>#<n>` merged → drop downstream `build-group=` lines (and `waiting for another PR` if last dep)?"
   - "Draft `<repo>#<n>` CI green → convert to ready?"
   - "Reviewers approved `<repo>#<n>` → add `coordinate merge` / `ready for merge`?"
   - "Failing CI on `<repo>#<n>` → investigate."
   - "Tracking issue closed but `closing_repo` PR not merged — confirm intentional?"

### `--ready <repo>`

Confirm with user. Propose appropriate review-stage label:
- `coordinate merge` if any sibling has `pr_state` ∈ {open, null}.
- `ready for merge` if all siblings are `merged` (or single-repo set).

Apply in one Bash block (so failure stops the cascade):

```bash
gh pr ready <n> -R JCSDA-internal/<repo> && \
gh pr edit <n> -R JCSDA-internal/<repo> --add-label "<chosen-label>"
```

Update state: `is_draft: false`; add label to `repos[i].labels`. Decision-log line.

### `--drop <repo> <full-pr-url>`

1. Canonicalize `<full-pr-url>` → `https://github.com/JCSDA-internal/<repo>/pull/<n>`.
2. `gh pr view <state-pr> -R JCSDA-internal/<repo> --json body --jq .body > /tmp/jedi-prs-<slug>-<repo>-body.md`
3. Delete the line `build-group=<full-pr-url>` from the file. If not found, surface to user.
4. Show diff. On approval:
   ```bash
   gh api -X PATCH "repos/JCSDA-internal/<repo>/pulls/<state-pr>" \
     -F body=@/tmp/jedi-prs-<slug>-<repo>-body.md --jq '.body' > /dev/null
   ```
   (`gh pr edit --body-file` fails on JCSDA-internal repos due to a classic-projects GraphQL deprecation — the REST PATCH path works.)
5. Suggest CI re-trigger: `git -C bundle/<repo> commit --allow-empty -m 'trigger CI' && git -C bundle/<repo> push`.
6. Update `repos[i].build_groups` (drop the URL). Decision-log line.
7. **Label cascade.** If `build_groups` now empty AND `waiting for another PR` is in `labels`: propose dropping it. If `reviewDecision == APPROVED`, also propose adding `coordinate merge` (siblings still in flight) or `ready for merge` (all siblings merged). Single `gh pr edit ... --add-label`/`--remove-label` call. Update `repos[i].labels`.

### `--label <repo> <add|rm> <label>`

Escape hatch for manual nudges (`do not merge`, `OBS`, etc.). Validate against managed lifecycle (## Reference) or known unmanaged labels (group tags, partner orgs, `enhancement`). Confirm with user.

```bash
gh pr edit <state-pr> -R JCSDA-internal/<repo> --add-label "<label>"     # for add
gh pr edit <state-pr> -R JCSDA-internal/<repo> --remove-label "<label>"  # for rm
```

Update `repos[i].labels`. Decision-log line. **Do not auto-cascade** other lifecycle labels — single change. Lifecycle reconciliation runs on next bare-resume.

### `--list`

```bash
ls "$CLAUDE_CONFIG_DIR/projects/$(pwd | tr / -)/memory"/project_*_prs.md 2>/dev/null
```

For each, read frontmatter `slug`, `feature`, `phase`, `last_updated`. Emit a small table.

### CLOSED — wrap up

User explicitly transitions to `phase: CLOSED`:

1. Confirm all `pr_state: merged` (or `closed` for any abandoned).
2. **Prefer updating an existing summary memory** over creating a new one:
   ```bash
   ls "$STATE_DIR"/project_<slug>_*.md "$STATE_DIR"/project_<slug-with-underscores>_*.md 2>/dev/null \
     | grep -v _prs.md
   ```
   Both hyphen and underscore variants (this skill uses hyphens; hand-written memories may use underscores). If one exists (`_summary.md`, `_branches.md`, `_reference.md`, etc.), update it with merged dates. Else create `project_<slug>_summary.md`.
3. Prompt user to delete the state file and the `## Active Projects` index entry. Both destructive — wait for explicit approval before `rm` and MEMORY.md edit.

## Reference

### Managed labels

Canonical org labels: `JCSDA-internal/github-admin:github_api/org_labels.py`. The skill manages the lifecycle of:

| Label | Apply when | Drop when |
|---|---|---|
| `bug` | At PR open if defect fix (not feature/refactor/warning cleanup) | Stays for life of PR |
| `waiting for another PR` | `build_groups` non-empty | `--drop` removes last entry |
| `waiting for other repos` | User flags external (model-side) dep | External dep lands |
| `coordinate merge` | Reviewed AND any sibling still in flight | All siblings merged or this PR merges |
| `ready for merge` | Reviewed AND all siblings merged (or single-repo set) | This PR merges |

A PR is in one of two label-states (mutually exclusive):
- **Blocked** — has any `waiting for *` (the two variants can coexist).
- **Mergeable** — exactly one of `coordinate merge` or `ready for merge`.

`bug` is independent. Labels are only proposed when they would *change* state.

Everything else (group tags `INFRA`/`OBS`, partner orgs, `do not merge`, `enhancement`, etc.) is human-curated; adopt into state silently if observed live.

### gh syntax

```bash
gh pr create ... --label "bug" --label "waiting for another PR"        # at open; one --label per name
gh pr edit <n> -R JCSDA-internal/<repo> --add-label "coordinate merge"
gh pr edit <n> -R JCSDA-internal/<repo> --remove-label "waiting for another PR"
gh pr view <n> -R JCSDA-internal/<repo> --json labels --jq '[.labels[].name]'
```

Quote labels with spaces. `--add-label`/`--remove-label` works on JCSDA-internal repos (unlike `--body-file`).

### URL canonicalization

All build-group URLs in state and bodies use `https://github.com/JCSDA-internal/<repo>/pull/<n>`. `--drop` matches by string equality, so non-canonical inputs would silently miss. If user passes `JCSDA-internal/oops#3275` or `.../pull/3275/files`, normalize first.
