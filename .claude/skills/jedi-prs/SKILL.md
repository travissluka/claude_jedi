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
argument-hint: "[<slug> [<repo:branch> ...] | <slug> [--show|status|--ready <repo>|--drop <repo> <url>|--label <repo> <add|rm> <label>|--close] | --list]"
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
| (no args) | **Status** — read-only across all active state files |
| `<slug> --show` (or `<slug> status`) | **Status** — read-only for one slug |
| `<slug> <repo:branch> ...` (≥1 repo) | **NEW** — analyze, draft, save state |
| `<slug> --import <repo>:<pr#> ...` (≥1 PR) | **Import** — track already-open PRs (skip NEW/DRAFTED → straight to OPEN) |
| `<slug>` (state file exists) | **Resume** — Status + write back drift + propose next steps |
| `<slug> --ready <repo>` | Draft → ready (also adds review-stage label) |
| `<slug> --drop <repo> <full-pr-url>` | Remove stale `build-group=` line (+ label cascade) |
| `<slug> --label <repo> <add\|rm> <label>` | Manual single-label nudge |
| `<slug> --close` | Transition phase → CLOSED + clean up state file + MEMORY.md (single combined approval) |
| `--list` | List all `project_*_prs.md` state files (filenames + frontmatter, no live `gh` calls) |

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
  repo: fv3-jedi        # closing repo (highest merge_order) = same as closing_repo
  number: 1234
  url: https://github.com/JCSDA-internal/fv3-jedi/issues/1234
  state: open           # open | closed
  closing_repo: fv3-jedi  # repo of last-merging PR; carries `Closes ...` (== issue.repo)
repos:
  - repo: oops
    branch: feature/x
    pr: null            # null until opened
    pr_state: null      # open | closed | merged
    ci_state: null      # pending | green | failing | unknown
    last_sha: <8-char>  # for force-push detection (prefix-match)
    merge_order: 1      # ties allowed (parallel)
    is_draft: false     # default; only `true` for highly-experimental single-PR work or circular cross-repo deps
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

## Issue-closure rule (load-bearing)

Exactly **one** PR in a coordinated set uses `Resolves` to auto-close the tracking issue; **every other PR** carries a bare bullet reference (no keyword). The `## Issue(s) addressed` section is always a markdown bullet list — the canonical template's plain-line example is overridden by the user's preference for bullets (renders better next to the bulleted Dependencies lists).

- The closer is the **last-to-merge** PR (the unique repo at the highest `merge_order`). If multiple repos tie for highest `merge_order`, the user picks one and the rest fall back to bare-bullet refs.
- Closer body: `- Resolves JCSDA-internal/<issue.repo>#<n>` — or `- Resolves #<n>` when the closer's repo equals `issue.repo`.
- All other PRs: `- JCSDA-internal/<issue.repo>#<n>` — or `- #<n>` when the PR's repo equals `issue.repo`. **No `Refs` keyword.** Bare bullet ref creates the GitHub backlink without auto-closing.
- If the user opted out of a tracking issue: `<ISSUE-REF>` becomes the literal `n/a` for every PR (still under the heading); no bullet refs, no keyword.

GitHub's auto-close keyword (`Resolves`/`Closes`/`Fixes`) works inside markdown bullets — what GitHub looks for is the keyword + ref pattern, not the surrounding markup. Cross-repo `Resolves JCSDA-internal/<repo>#<n>` works within the same org but auto-close is less reliable than same-repo; flag manual close as a fallback in the decision log.

The state file's `issue.closing_repo` is the source of truth for who closes. If merge-order changes after PRs are open (e.g., user revises plan), update `closing_repo` and re-edit body lines via `gh api -X PATCH` (same path as `--drop`) so exactly one PR still uses `Resolves`.

## Workflow

### NEW — first invocation

1. Verify each `<repo>` exists under `bundle/`.
2. `git -C bundle/<repo> fetch origin` per repo.
3. **Fan out: launch one `Explore` agent per `<repo:branch>` in parallel** (single message, multiple `Agent` tool calls). Use the prompt template in `agent-prompt.md` (Read it from this skill's base directory), substituting `<repo>` and `<branch>`.
4. Wait for all reports (~400 words each).
5. Synthesize — **think hard** about merge order per `claude/pr-conventions.md`:
   - PR nature (additive / breaking / mixed) from each agent.
   - Merge order: a PR is independently mergeable if its CI passes against current `develop` of others. Build-DAG informational, not authoritative.
   - **Minimal `build_groups`**: only PRs whose CI cannot pass without the matching change. Note that the bundle CI runs sibling repos' tests too, not just the repo's own — so if PR-X depends on PR-Y, AND PR-Y depends on PR-Z, then PR-X's `build_groups` should usually include both PR-Y and PR-Z (transitive). Don't rely on the bundle resolver to follow chains.
   - `is_draft`: **default `false`** — open PRs as Ready when the user has reviewed the change with you (the common case). Use `--draft` only when the change is a single PR of highly experimental code that Claude produced largely autonomously (the user wants a buffer to inspect before CI), or when there is an unavoidable circular cross-repo dependency. When in doubt, ask the user.
   - Resolve `<TBD-<repo>-PR>` placeholders into a coherent plan.
   - Reviewer candidates: dedupe across repos into one ranked list (surfaced in step 7 as suggestions only).
   - **Opening labels per repo** (see ## Reference for full lifecycle):
     - `bug` if it fixes incorrect behavior in merged code.
     - `waiting for another PR` if `build_groups` non-empty.
     - `waiting for other repos` only if user flagged an external (model-side) dep.
     - `coordinate merge` / `ready for merge` are NOT opening labels (review-stage only).
   - **Merge-order validation**: if any `build_groups` are non-empty, devise a minimal set of branch-combination tests to confirm the assumed order. For each dependency edge (A must merge before B): describe (a) building/testing B against A's current `develop` (should fail — confirms the dep exists) and (b) building/testing B against A's feature branch (should pass — confirms the fix). Switch the dependency repo to develop in the existing tree, rebuild the dependent + downstream, run the targeted ctest, then restore. **Each branch checkout requires its own explicit per-action approval** even if the user has approved the overall test plan — the `feedback_no_branch_switch.md` rule supersedes implicit consent. Note that the user's environment has `VALIDATE_PARAMETERS=1`, so YAML strict-validation failures are a common failure signature for missing dependencies. If all PRs are independently mergeable (no `build_groups`) — skip and note "independently mergeable, no order testing needed." Include a concise testing plan in step 7.
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
      - **Open new:** in the **closing repo** — the unique repo at the highest `merge_order`, same one that gets `closing_repo` and carries `Resolves` in its PR body (ties → user picks). Same-repo `Resolves #<n>` reliably auto-closes; cross-repo `Resolves JCSDA-internal/<repo>#<n>` is supported within the same org but auto-close is less reliable, so flag manual close as a fallback in the decision log. Short title (≤60 chars), 2–3 sentence body, default assignee `travissluka`. Body template:
        ```
        <one-paragraph summary of the goal>

        Tracked across:
        - JCSDA-internal/<repo1> (PR forthcoming)
        - JCSDA-internal/<repo2> (PR forthcoming)

        Story points: TBD (set in zenhub).
        ```
      - **Opt out:** for trivial fixes. Set `issue: null`; `<ISSUE-REF>` becomes `n/a`; one-line rationale to decision log.
   c. (Skip if opted out.) Determine `closing_repo` per the **Issue-closure rule** above: the unique repo at the highest `merge_order`; ties → user picks one. Cross-repo `Resolves JCSDA-internal/<repo>#<n>` works within the same org.
7. Show user, in one combined message:
   - Per-repo drafted title + body (with `<TBD-...>` and `<ISSUE-REF>` placeholders) — bodies must follow the canonical PR template (## Description / ## Issue(s) addressed / ## Dependencies / ## Impact / ## Manual Testing Instructions (optional) / ## Checklist) with the canonical Checklist verbatim:
     ```
     - [x] I have performed a self-review of my own code
     - [x] I have made corresponding changes to the documentation
     - [x] I have run the unit tests before creating the PR
     ```
     (Tick all three by default; the user can untick if not applicable.) Issue refs use bullet style per the **Issue-closure rule**.
   - Cross-repo plan: merge-order table; build-group topology; whether each PR opens Ready (default) or Draft (only if highly-experimental single PR or circular dep)
   - Merge-order test plan (or "independently mergeable, no testing needed")
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
   b. Substitute `<ISSUE-REF>` placeholders per the **Issue-closure rule** above. Verify exactly one PR uses `- Resolves ...` and every other PR uses a bare bullet ref (or all `n/a` if opted out).
   c. Write state file as `phase: DRAFTED`; populate the `issue:` block (or `issue: null` if opted out); insert resolved bodies under `## Drafted bodies`; append `## Active Projects` line in `MEMORY.md`.

### DRAFTED — open PRs

1. Read state file. Verify `phase: DRAFTED`.
2. Pre-flight per repo with `pr: null`: `git -C bundle/<repo> ls-remote origin <branch>`. If branch missing on origin, ask before pushing.
3. Group repos by `merge_order`. Open lowest-numbered group first; within a group, parallel (one Bash block, multiple `gh pr create`).
4. For each PR:
   - Read drafted body from `## Drafted bodies` → `### <repo>`.
   - Substitute resolved URLs into `<TBD-X-PR>` placeholders for any sibling that's already open. URL form: `https://github.com/JCSDA-internal/<repo>/pull/<n>`. Sibling references that are not yet open (e.g., the depended-by list of an upstream PR) stay as `<TBD-X-PR>` placeholders for now and get patched in step 7.
   - Show **final** body + opening labels + draft flag. On approval:
     ```bash
     ( cd bundle/<repo> && gh pr create \
         --title "<title>" \
         --body-file /tmp/jedi-prs-<slug>-<repo>-body.md \
         --assignee travissluka \
         --base develop --head <branch> \
         [--label "bug"] [--label "waiting for another PR"] \
         [--draft] )
     ```
     `cd` into the repo so `gh` resolves the upstream automatically; running from the bundle parent fails with "Head sha can't be blank" because `gh` defaults to your fork's `main`. One `--label "<name>"` per opening label; quote multi-word names. `--draft` only when `is_draft: true` for that repo (default omitted).
   - Capture PR number from output URL.
   - **Empty-commit retrigger** if needed: when a PR opens with `build-group=` lines and CI doesn't pick them up on first run (e.g., draft→ready transition didn't fire CI, or the parser timed out), follow with:
     ```bash
     git -C bundle/<repo> commit --allow-empty -m 'trigger CI' && git -C bundle/<repo> push
     ```
     Otherwise skip — opening a non-draft PR triggers CI automatically.
5. Update state: `pr`, `pr_state: open`, `ci_state: pending` (non-draft) or `unknown` (draft), `is_draft` (per repo, as opened), `last_sha`, `labels` (those actually passed). Update `last_updated`.
6. After all groups open, set `phase: OPEN`. User can interrupt between groups.
7. **Post-open placeholder substitution.** Walk every PR opened in earlier groups and check its body for surviving `<TBD-X-PR>` placeholders (depended-by lists in upstream PRs reference downstream PRs that didn't exist when the upstream opened). For each, fetch the live body, substitute, and PATCH:
   ```bash
   gh pr view <pr> -R JCSDA-internal/<repo> --json body --jq .body > /tmp/jedi-prs-<slug>-<repo>-body.md
   sed -i 's|<TBD-<sibling>-PR>|https://github.com/JCSDA-internal/<sibling>/pull/<n>|g' /tmp/jedi-prs-<slug>-<repo>-body.md
   gh api -X PATCH "repos/JCSDA-internal/<repo>/pulls/<pr>" -F body=@/tmp/jedi-prs-<slug>-<repo>-body.md --jq .url
   ```
   Single combined approval gate covers all the PATCHes for this set.

### `--import <repo>:<pr#> ...`

For tracking PRs that were already opened outside this skill (e.g. you ran `gh pr create` directly, then decided to track the lifecycle). Skips the NEW/DRAFTED phases and writes a state file in `phase: OPEN` populated from live data.

1. Reject if a state file with this slug already exists; suggest plain `<slug>` resume instead.
2. For each `<repo>:<pr#>`: verify with `gh pr view <pr#> -R JCSDA-internal/<repo> --json state,headRefName,headRefOid,isDraft,labels,statusCheckRollup,reviewDecision`. Reject if `state != "OPEN"` (importing closed/merged PRs is out of scope).
3. Show user the discovered PRs and propose merge-order assignments + initial `build_groups` (default `merge_order: 1`, `build_groups: []` — user can refine). Single-PR imports skip merge-order discussion.
4. Tracking issue: same three-outcome flow as **NEW** step 6 (search candidates / open new in closing repo / opt out). For trivial single-PR imports, suggest **opt out** as the default.
5. Compute `closing_repo` per the **Issue-closure rule** (skip if opted out). Note: if PRs already have a `Closes`/`Refs` line in their bodies that disagrees with the chosen `closing_repo`, surface the discrepancy and ask before proceeding (live body edits via `gh api -X PATCH`).
6. On approval, write the state file directly with `phase: OPEN`. Per repo: populate `pr`, `pr_state: open`, `ci_state` (derived per the rules above), `last_sha` (from `headRefOid`), `is_draft` (from live), `labels` (from live), `branch` (from `headRefName`).
7. Append `## Active Projects` line in `MEMORY.md` (approval-gated).
8. Decision-log entry: `<date> — Imported existing PRs <list>; bypassed NEW/DRAFTED phases.`

### Status — `(no args)` or `<slug> --show` (alias: `<slug> status`)

Read-only. No writes, no `## Reconciliation log` appends, no migrations. Pure dashboard.

**Scope:** no args → all `OPEN`/`DRAFTED` state files (skip `CLOSED`). `--show <slug>` (or `<slug> status`) → just that slug.

1. Read each state file in scope.
2. Reconcile against live `gh`. One combined Bash block across all PRs in scope:
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
   Derive `ci_state` (first match wins):
   1. Any FAILURE/CANCELLED/TIMED_OUT → `fail`.
   2. Any PENDING/QUEUED/IN_PROGRESS, OR any blank/null state alongside non-FAILURE entries → `pending`. (Required-but-not-yet-reported checks render as blank `""`; treat as not-yet-complete.)
   3. All entries SUCCESS (optionally with SKIPPED, NEUTRAL) → `green`.
   4. Empty rollup → `unknown`.

   For each repo with `pr: null`: `gh pr list -R JCSDA-internal/<repo> --search "head:<branch>" --json number,state,url`. If `issue` non-null: `gh issue view <issue.number> -R JCSDA-internal/<issue.repo> --json state,closedAt`.
3. **Force-push check** (informational; surface in hints, don't write): `git -C bundle/<repo> fetch origin <branch>`, then `rev-parse origin/<branch>`. Prefix-compare to `last_sha`: `case "$new" in $old*) match;; *) drift;; esac`.
4. Render one block per slug:
   ```
   ## <slug> (<feature>) — phase: <phase>, last_updated: <date>
   Tracking issue: <issue.url> (<state>)   |   (none — opted out)   |   (none — legacy state file)
   <status table>
   Hints: <semicolon-joined applicable hints, or "—">
   ```

   Status-table glyphs:

   | Glyph | meaning |
   |---|---|
   | 🟢 | CI green |
   | 🔴 | CI fail |
   | 🟡 | CI pending |
   | ⚪ | CI unknown |
   | 🟣 | merged (post-merge only) |
   | ⚫ | closed (post-close only) |
   | 📝 | draft |

   Columns: `repo | branch | PR | ci | sha | order | draft | build_groups | labels`. Sort by `merge_order` (then repo). `draft`: `📝` or `—`. `build_groups`: render as `repo#PR`. Labels: comma-separated as-stored; `(none)` if empty. (No `state` column — destructive drift is surfaced via Hints instead of being a glyph.) For `phase: CLOSED` rendering, substitute `ci` with 🟣/⚫.

   Hints — compute each row that applies; emit as a single semicolon-joined line:

   | Condition | Hint |
   |---|---|
   | `is_draft && ci=green && review=REVIEW_REQUIRED` | `<repo>#<n> draft+green → ready to convert` |
   | `!is_draft && ci=green && review=APPROVED && no review-stage label` | `<repo>#<n> approved+green → label upgrade` |
   | `ci=fail` | `<repo>#<n> CI failing` |
   | `!is_draft && ci=green && review=REVIEW_REQUIRED` | `<repo>#<n> waiting for review` |
   | upstream build-group PR is `merged` but still listed | `<repo>#<n> can drop build-group <up>#<n>` |
   | force-push detected (sha prefix-mismatch) | `<repo>#<n> force-push since last reconcile` |
   | state file missing `issue:` OR any repo missing `labels:` | `legacy state — run \`/jedi-prs <slug>\` to migrate` |

5. **Footer** — only when scope > 1 slug (i.e., bare invocation):
   ```
   <N> active set(s); <M> merged-but-not-cleaned-up; <K> failing CI; <L> waiting for review; <D> still draft
   ```
   - `merged-but-not-cleaned-up` = PRs with `pr_state == merged` in still-active state files.
   - `failing CI` = PRs with `ci_state == fail`.
   - `waiting for review` = PRs with `!is_draft && ci_state == green && reviewDecision == REVIEW_REQUIRED`.
   - `still draft` = PRs with `is_draft == true`.

Empty case (bare, no active state files): `No active PR sets. Use \`/jedi-prs <slug> <repo:branch> ...\` to start one.`

### Resume — bare `<slug>`

Run the **Status** logic above (steps 1–4) for this slug, then mutate:

1. **Write back non-destructive drift — auto-apply, no prompt.** CI changed (incl. `pr_state` open→merged, ci_state pending→green), body edited externally, fast-forward commits → update frontmatter and append a dated `## Reconciliation log` line. Surface what was written in the dashboard; do not gate on approval. (Approval gates exist for *outgoing* GitHub mutations, not for syncing local state to observed reality.)
2. **Stop on destructive drift**: PR closed/deleted (without merge), force-push not descendant of `last_sha`, unexpected PR for `pr: null` branch, tracking issue closed before `closing_repo` PR has merged. Show what changed; wait for direction before mutating.
3. **Legacy-state migration** — if state file lacks `issue:` field, OR any `repos[i]` lacks `labels:`:
   - `issue:`: search candidate tracking issues across affected repos (same `gh issue list` query as **NEW** step 6a); three outcomes (reuse / opt out / opt out with note). Write `issue:` block (or `null`).
   - `labels:`: capture from the `gh pr view ... labels` already fetched in step 2; write back into each `repos[i].labels`.
   One-shot — never re-prompt for the same file.
4. **Label-drift reconciliation**: live ⊃ state → silently adopt; live ⊂ state → log to `## Reconciliation log` and re-propose if lifecycle calls for it.
5. **Propose next steps** (each item is its own approval gate):
   - "All `pr_state == merged` → run `/jedi-prs <slug> --close` to wrap up?" (highest priority — overrides the bullets below when it applies)
   - "All level-N CI green → open level-(N+1)?"
   - "Upstream PR `<repo>#<n>` merged → drop downstream `build-group=` lines?"
   - "Draft `<repo>#<n>` is open — `/jedi-prs <slug> --ready <repo>` to convert + trigger CI."
   - "Non-draft `<repo>#<n>` CI green + APPROVED → add `coordinate merge` / `ready for merge`?"
   - "Failing CI on `<repo>#<n>` → investigate."
   - "Tracking issue closed but `closing_repo` PR not merged — confirm intentional?"

### `--ready <repo>`

Confirm with user. This converts the draft to non-draft AND triggers CI immediately — do not proceed without explicit approval.

Apply in one Bash block (so failure stops the cascade):

```bash
gh pr ready <n> -R JCSDA-internal/<repo> && \
git -C bundle/<repo> commit --allow-empty -m 'trigger CI' && \
git -C bundle/<repo> push
```

Update state: `is_draft: false`, `ci_state: pending`. Decision-log line.

Review-stage labels (`coordinate merge` / `ready for merge`) are **not** added here — they are proposed on the next resume once CI is green and reviewers have approved.

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

For each, read frontmatter `slug`, `feature`, `phase`, `last_updated`. Emit a small table. Filename + frontmatter only — no live `gh` calls. Use the bare-invocation Dashboard for live status.

### `--close` — transition to CLOSED + clean up

Idempotent wrap-up. Run when all PRs are merged (or the user is abandoning the set). **Single combined approval gate** — do not split into per-action prompts.

1. **Reconcile fresh** (same `gh pr view` query as Status step 2). Verify each `repos[i].pr_state` is `merged` or `closed`. If any PR is still `open`, refuse: print which PRs are still open and stop.
2. **Auto-apply any pending drift** (per Resume step 1) so the state file reflects merge timestamps before deletion.
3. **Look for an existing summary memory** to update vs. creating a new one:
   ```bash
   ls "$STATE_DIR"/project_<slug>_*.md "$STATE_DIR"/project_<slug-with-underscores>_*.md 2>/dev/null \
     | grep -v _prs.md
   ```
   Both hyphen and underscore variants (this skill uses hyphens; hand-written memories may use underscores).
4. **Decide cleanup plan** — pick the first matching case:
   - **Existing summary memory found** → propose updating it with merged-PR dates + new merged-into-develop summary line.
   - **Degenerate single-repo case** — exactly one repo, `issue: null`, opening labels just `bug` or empty, no existing summary → **skip the summary entirely**. PR body + git log are sufficient context; a one-line memory adds noise.
   - **Otherwise** (multi-repo set, or single repo with tracking issue, or anything non-trivial) → propose creating `project_<slug>_summary.md` with: feature description, list of merged PRs with dates, what the issue tracked, any follow-ups left.
5. **Show one combined plan** to the user covering all of:
   - phase flip to `CLOSED` (in-memory only, since the state file is about to be deleted)
   - summary memory action: "update `<existing-file>`" / "create `project_<slug>_summary.md`" / "skip — degenerate case"
   - `rm <state-file>`
   - remove the `## Active Projects` line from `MEMORY.md`
   Render as a 4-line preview (or 3-line if summary skipped). **One yes/no.**
6. On approval, apply all changes in the order shown. Print one-line confirmation.

## Reference: managed labels

Canonical org labels: `JCSDA-internal/github-admin:github_api/org_labels.py`. The skill manages the lifecycle of:

| Label | Apply when | Drop when |
|---|---|---|
| `bug` | At PR open if defect fix (not feature/refactor/warning cleanup) | Stays for life of PR |
| `waiting for another PR` | `build_groups` non-empty | `--drop` removes last entry |
| `waiting for other repos` | User flags external (model-side) dep | External dep lands |
| `coordinate merge` | Reviewed AND any sibling still in flight | All siblings merged or this PR merges |
| `ready for merge` | Reviewed AND all siblings merged (or single-repo set) | This PR merges |

A PR is in one of two mutually exclusive label-states: **Blocked** — any `waiting for *`; **Mergeable** — exactly one of `coordinate merge` or `ready for merge`. `bug` is independent. Labels are only proposed when they would *change* state. Everything else (group tags, partner orgs, `do not merge`, `enhancement`) is human-curated; adopt into state silently if observed live.
