# JEDI PR Conventions

> Cheat-sheet for writing JCSDA-internal pull request descriptions correctly.
>
> **Covers:** PR authoring workflow (review before opening, self-assignment, reviewer-after-CI), PR template structure, Dependencies section content (depends-on / depended-by / build-groups), determining merge order from code-change content (not just the build-DAG), disabling stale build-groups as upstreams merge, `build-group=` and `run-ci-on-draft=` annotation syntax, draft-mode workflow (CI deferral pattern + circular cross-repo cycles), CI re-trigger via empty commit, prose-reference syntax for cross-repo PRs, labels.

Canonical jedi-docs source: `bundle/jedi-docs/docs/working-practices/testing.rst` — section "Testing Development across Multiple Repositories". This file is a distilled local copy of the rules + a record of the project's preferred PR-authoring conventions.

## Authoring workflow

When preparing a PR for the author's review, follow this sequence:

0. **Gather context before drafting.** Don't write a PR body from memory; the project's house style and the live template are the source of truth.
   - Re-read this file's "Template" and "Dependencies section" sections — section ordering and checklist text must match the JCSDA template literally (don't invent custom checklist items, don't add "Reviewer candidates" / "Performance results" headings as top-level sections — that content goes inside `## Description`).
   - Fetch the live template in case it has changed:
     ```bash
     gh api 'repos/JCSDA-internal/.github/contents/PULL_REQUEST_TEMPLATE.md' \
       | python3 -c "import json,sys,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content']).decode())"
     ```
   - Scan 2–3 recently merged PRs in the target repo for tone and section length:
     ```bash
     gh pr list --repo JCSDA-internal/<repo> --state merged --limit 5 --json number,title,url
     gh pr view <number> --repo JCSDA-internal/<repo>
     ```
   - Check feedback memory for PR-related entries (`feedback_pr_*`, `feedback_cross_repo_pr_refs`, `feedback_pr_strikethrough_stale_buildgroup`, `feedback_pr_authoring_workflow`, `feedback_pr_issue_bullet_style`, `feedback_pr_build_group_syntax`).

1. **Draft the full PR text** (title + body following the template structure below) and surface it in chat for review *before* calling `gh pr create`. Do not open the PR until the user has approved the wording.
2. Along with the body, propose:
   - **Reviewers** — pull candidates from `git -C bundle/<repo> log --format='%an' --since=<recent> -- <changed-paths> | sort | uniq -c | sort -rn`. Surface the top contributors to the affected files, with commit counts. `claude/maintainers.md` is the **admin/escalation** list, not a review pool — most reviewers are topical contributors who aren't on it. Use a maintainer name only when they are independently topically relevant. Filter out the PR author. Do NOT assign reviewers yet; assignment waits until CI is green.
   - **Labels** — propose a label only when one clearly applies. `bug` is the only actively-curated label; everything else is optional. If unsure, leave label suggestion empty.
3. Once approved, open the PR with `gh pr create`, including:
   - `--assignee <user>` — the PR is always self-assigned to the author
   - The agreed body and title
   - Draft mode (`--draft`) when the change set has unavoidable circular cross-repo deps, **or** when a PR's CI would fail until a companion PR exists with a known URL (Draft = no CI fires; useful for parking a "second" PR while the "first" one's CI drives the bundle build — see "Draft as a CI deferral" below). Otherwise open as Ready.
4. **Do not request reviewers at PR-open time.** Wait for CI to go green; revisit the reviewer list with the user after that.
5. Empty-commit retrigger if needed (see "Re-triggering CI" below); flag any failing checks back to the user before assigning reviewers.

## Before opening a PR

Determine **merge order and minimal cross-repo dependencies** *before* issuing PRs. **Think carefully** — the order is not mechanical; the build-DAG (`claude/build-and-test.md` #build-dependency-dag) is *informational*, not the authoritative answer.

The DAG tells you which repo's *develop branch* depends on which at compile time. PR merge order depends on what each PR's *changes* do: a PR is mergeable independently if its CI can pass against all of its dependencies' current `develop`. So for each PR ask:

1. **Does this PR's CI pass without any `build-group=`?** If yes, it can merge first regardless of its repo's position in the DAG.
2. **If not, which other PR(s) must merge first to make CI pass?** Those are real ordering constraints, and only those need `build-group=` annotations.
3. **What is each change's nature?** Pure additions (new API, new file) on an upstream are usually backward-compatible — downstream can keep using old API → upstream PR is independently mergeable. Removals/renames/signature changes on an upstream break downstream → upstream PR cannot merge until downstream PR catches up, and the upstream PR will need `build-group=<downstream PR>` for *its own bundle build* to pass.

A common surprise: an "upstream" PR sometimes has to wait for a "downstream" PR. If `oops` is renaming or removing an API that `ufo` uses, `ufo`'s PR (which fixes the usage) can pass CI on its own (ufo's tests work with oops on develop, which still has the old API), but `oops`'s PR cannot — its bundle build fails because ufo on develop still uses the renamed/removed API. So `oops` PR carries `build-group=<ufo PR>` and `ufo` PR has none. Despite oops being "upstream" in the DAG, **ufo merges first**.

Output of this analysis should always be:
- A merge-order list (which PR first, second, …).
- Which PRs need `build-group=` lines (and pointing at which other PRs).
- Which PRs can be opened Ready vs. need Draft.

If there is a true **circular dependency** (rare — usually a sign the change set should be reorganized), the workflow is:

1. Open every PR involved in the cycle as **Draft**
2. Add the `build-group=` annotations on each pointing at the other PRs in the cycle
3. Once green CI is confirmed via the linked group, convert from Draft to Ready for review

## Template (from `JCSDA-internal/.github/PULL_REQUEST_TEMPLATE.md`)

```
## Description
## Issue(s) addressed
## Dependencies
## Impact
## Manual Testing Instructions (optional)
## Checklist
```

Keep all section headings even when a section is empty (put `n/a` under the heading). Order matches the template — don't reshuffle.

## Dependencies section — preferred structure

The template only asks for "PRs this PR depends on," but the project convention is to list dependencies in **three explicit groups** so reviewers and the merger can see the full coordination picture without reading three other PRs. Use bullet lists for the two prose groups; put `build-group=` lines as bare lines (not bullets) below.

```markdown
## Dependencies

This PR depends on:
- https://github.com/JCSDA-internal/oops/pull/3275

PRs that depend on this PR (must merge after this one):
- https://github.com/JCSDA-internal/jedi-docs/pull/1028

build-group=https://github.com/JCSDA-internal/oops/pull/3275
```

Notes:
- Use **full GitHub URLs**, not `JCSDA-internal/<repo>#<n>` shorthand or bare `#<n>` (bare `#<n>` would autolink to the current repo and break).
- Plain bullet `- <url>` for the two prose lists — GitHub renders these with PR status icons; `- [ ]` checkbox form is not needed.
- **Keep `build-group=` lines minimal.** Only include another PR if this PR's bundle build would otherwise fail. Listing every related PR in `build-group=` wastes CI capacity and makes failures harder to diagnose. The "depends on" / "depended by" prose lists are the place to record the *full* relationship; `build-group=` is the place to record only what CI actually needs to compile-and-test together.
- If this PR has no cross-repo dependencies at all, still write the `## Dependencies` heading and put `n/a` underneath.

## Annotation syntax (read by CI)

JEDI's CI parser scans the PR description for **bare** `key=value` lines starting at column 0. Any prefix at all (a markdown bullet, blockquote, indentation, code-fence, or surrounding backticks) prevents the line from matching and the annotation has no effect.

| Annotation | Purpose |
|---|---|
| `build-group=<full PR URL>` | Pull a matching PR from another bundle repo into this PR's CI bundle. One line per dependency. |
| `run-ci-on-draft=true` | Run CI checks even while the PR is in Draft status (default: skipped on drafts). Documented in jedi-docs `working-practices/testing.rst`; not yet used in practice in this project — verify behavior the first time you rely on it. |

### Correct

```
build-group=https://github.com/JCSDA-internal/oops/pull/3275
build-group=https://github.com/JCSDA-internal/saber/pull/1234
```

### Wrong (silently ignored — no error, just no effect)

Anything other than a bare line beginning with `build-group=` at column 0 will be ignored. The most common mistake is putting it inside a markdown bullet (`- build-group=...`) — confirmed broken on `JCSDA-internal/saber#1234` (implicit-vertical-diffusion, 2026-04-28).

### Recommended placement

Put `build-group=` lines inside the `## Dependencies` section, separated from the prose bullets by a blank line, as shown in the example above. The parser doesn't care where in the body they are, but keeping them with the related prose dependency lists makes the body easy to scan.

## Draft as a CI deferral

**CI does not fire on Draft PRs by default.** This is useful beyond circular deps: when one PR's CI would fail until a companion PR exists with a known URL (e.g., a testref refresh that depends on an upstream behavior change), open the dependent PR as Draft *first*, get its URL, then open the upstream PR as Ready with `build-group=<draft PR url>`. The upstream's CI fires immediately and pulls in the draft's branch via the resolver. Only flip the dependent PR out of Draft *after* the upstream is green — exiting Draft fires CI on the dependent PR.

Worked example for a 2-PR upstream/downstream pair where the downstream is a testref refresh (e.g., oops EAKF bug fix + soca testref companion):

1. Create downstream PR (e.g., soca) **as Draft**. Body has `build-group=<upstream PR url placeholder>`. No CI runs.
2. Create upstream PR (e.g., oops) **as Ready** with `build-group=<downstream PR url>` (URL now known from step 1). Upstream CI runs immediately, pulling the Draft downstream branch via the resolver.
3. Edit downstream PR body to fill in the real upstream URL. Still Draft, still no CI.
4. Wait for upstream CI to be green.
5. Flip downstream out of Draft. Exiting Draft fires its CI; bundle includes the upstream branch via build-group → both green.
6. Merge upstream first, downstream second. Remove stale `build-group=` lines as repos merge into develop (see "Merge sequence" below).

The opt-in alternative `run-ci-on-draft=true` (see annotation table) makes CI run on Drafts; not used in this project — the deferral is the feature.

## Merge sequence — `build-group=` is dynamic

`build-group=` annotations are **not static**. As each PR in a coordinated set merges, the remaining PRs no longer need their `build-group=` lines pointing at it (the matching changes are now on `develop` and get pulled into CI bundles automatically). **Disabling stale annotations is mandatory** — leaving a `build-group=` line referencing an already-merged PR breaks CI on the referencing PR (the resolver fails to fetch a merged-and-deleted branch). Disable, retrigger CI to confirm green, then merge.

### Disabling a `build-group=` line

Delete the line entirely. Do not use `~~build-group=...~~` (strikethrough) — the `~~` prefix has caused test failures in some CI configurations.

### Worked example: a two-repo coordinated change (oops + ufo)

State at PR-open time:
- `ufo` PR — no `build-group=`. Its CI passes because its changes work against current `oops` on develop.
- `oops` PR — `build-group=https://github.com/JCSDA-internal/ufo/pull/<n>`. Its bundle build needs the matching ufo changes (otherwise ufo on develop can't compile against the new oops).

Merge sequence:

1. **Confirm `ufo` PR CI is green** → merge `ufo` first (it's independently mergeable).
2. After `ufo` merges, the matching changes are on `ufo` develop. The `oops` PR no longer needs to *pull in* the ufo PR — develop already has it. Leaving the now-stale `build-group=` line active would break the next CI run on `oops`.
3. Edit `oops` PR body: delete the `build-group=https://github.com/JCSDA-internal/ufo/pull/<n>` line.
4. Empty-commit push to retrigger CI on the `oops` PR (annotations are read at CI-launch time).
5. Once green, merge `oops`.

This pattern (open all PRs simultaneously with build-groups, then disable them as upstream PRs merge) is common for any cross-repo feature that needs lockstep API changes. The same flow applies regardless of how many repos are involved — disable one annotation at a time, in merge order.

## Re-triggering CI

Push an empty commit:

```bash
git commit --allow-empty -m 'trigger CI' && git push
```

This is also how you pick up changes to `build-group=` annotations after editing the PR body — the annotations are read at CI-launch time, not on every PR-body edit.

## Cross-repo PR references in prose

When *prose-referencing* a PR in another repo (e.g., in the Description or Impact section, or in commit messages), use the full `JCSDA-internal/<repo>#<n>` form, not bare `#<n>` — bare `#<n>` autolinks to the *current* repo and produces a broken link.

Example: in a saber PR Description, write `see JCSDA-internal/oops#3275 for details`, not `see #3275 for details`.

## Labels

Only `bug` is actively curated — apply it when the PR fixes incorrect behavior in merged code (not when it adds new functionality, and not for warning cleanup or refactors). Other repo labels exist but are not required; leave them off unless the author asks for one.

## Reviewer assignment

- Assignee: the PR author (self-assignment is the convention; see Authoring workflow above).
- Reviewers: chosen from recent contributors to the changed files (`git log --format='%an' -- <paths>`); maintainers from `claude/maintainers.md` only when independently topically relevant. Assigned only **after CI is green** — earlier requests waste reviewer attention if the build then breaks.

## Other PR-body conventions

- **Don't hard-wrap markdown prose** — one paragraph = one line. PR rendering handles the wrap; manual newlines break inline links and code spans.
- The Issue(s) addressed section uses `Resolves #<n>` — this auto-closes the issue on merge. `Refs #<n>` for related-but-not-resolving issues.
- The Checklist boxes are self-attestation; tick them when the assertion is true.
