#!/bin/bash
# Preflight + sync for JEDI bundle repos.
# Usage: sync.sh [--no-pull] repo1 repo2 ...
# Emits one TSV header line, then one row per repo. Continues on per-repo errors.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$PROJECT_ROOT/bundle}"

NO_PULL=0
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --no-pull) NO_PULL=1 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

printf "repo\tbranch\tdirty\taction\tresult\tdetails\n"

for repo in "$@"; do
  dir="$BUNDLE_ROOT/$repo"

  if [[ ! -d "$dir/.git" ]]; then
    printf "%s\t-\t-\t-\tskipped\tno .git directory\n" "$repo"
    continue
  fi

  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$branch" == "HEAD" ]]; then
    printf "%s\tdetached\t%s\t-\tskipped\tdetached HEAD\n" "$repo" "$dirty"
    continue
  fi

  if [[ "$dirty" -gt 0 ]]; then
    printf "%s\t%s\t%s\t-\tskipped\tdirty working tree\n" "$repo" "$branch" "$dirty"
    continue
  fi

  if [[ $NO_PULL -eq 1 ]]; then
    printf "%s\t%s\t0\tnone\tok\t--no-pull\n" "$repo" "$branch"
    continue
  fi

  if ! git -C "$dir" fetch origin >/dev/null 2>&1; then
    printf "%s\t%s\t0\tfetch\tfailed\tfetch error (network?)\n" "$repo" "$branch"
    continue
  fi

  before=$(git -C "$dir" rev-parse --short=8 HEAD 2>/dev/null)

  if [[ "$branch" == "develop" ]]; then
    if git -C "$dir" pull --ff-only origin develop >/dev/null 2>&1; then
      after=$(git -C "$dir" rev-parse --short=8 HEAD 2>/dev/null)
      if [[ "$before" == "$after" ]]; then
        printf "%s\t%s\t0\tpull\tok\tup-to-date\n" "$repo" "$branch"
      else
        count=$(git -C "$dir" rev-list --count "${before}..${after}" 2>/dev/null)
        printf "%s\t%s\t0\tpull\tok\t%s new commits (%s..%s)\n" \
          "$repo" "$branch" "$count" "$before" "$after"
      fi
    else
      printf "%s\t%s\t0\tpull\tfailed\tdiverged (ff-only refused)\n" "$repo" "$branch"
    fi
  else
    if git -C "$dir" merge origin/develop --no-edit >/dev/null 2>&1; then
      after=$(git -C "$dir" rev-parse --short=8 HEAD 2>/dev/null)
      if [[ "$before" == "$after" ]]; then
        printf "%s\t%s\t0\tmerge\tok\tup-to-date\n" "$repo" "$branch"
      else
        count=$(git -C "$dir" rev-list --count "${before}..${after}" 2>/dev/null)
        printf "%s\t%s\t0\tmerge\tok\t%s new commits from develop\n" \
          "$repo" "$branch" "$count"
      fi
    else
      git -C "$dir" merge --abort >/dev/null 2>&1
      printf "%s\t%s\t0\tmerge\tconflict\taborted\n" "$repo" "$branch"
    fi
  fi
done
