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
