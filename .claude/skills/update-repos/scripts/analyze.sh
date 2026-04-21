#!/bin/bash
# Analyze changes per repo since the hash stored in claude/<repo>.md line 3.
# Usage: analyze.sh repo1 repo2 ...
# Emits a ==REPO== block per repo with stored/head/commits/class/STATUS flags,
# followed by --LOG-- and --STAT-- sections when STATUS=changed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$PROJECT_ROOT/bundle}"
DOCS_ROOT="${DOCS_ROOT:-$PROJECT_ROOT/claude}"

# Classify a newline-separated file list (on stdin) into one of:
#   test-only   : only test/ files
#   build-only  : only CMakeLists.txt / *.cmake
#   docs-only   : only *.md / *.rst / *.txt
#   fortran-only: only *.F90 / *.f90 (likely compiler compat)
#   code        : any C/C++ source or header, or mixed
classify() {
  local files has_cpp=0 has_fortran=0 has_test=0 has_build=0 has_docs=0 has_other=0
  files=$(cat)
  [[ -z "$files" ]] && { printf "empty"; return; }

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      test/*|*/test/*) has_test=1 ;;
      *CMakeLists.txt|*.cmake) has_build=1 ;;
      *.md|*.rst|*.txt) has_docs=1 ;;
      *.h|*.hpp|*.cc|*.cpp|*.c) has_cpp=1 ;;
      *.F90|*.f90|*.F|*.f) has_fortran=1 ;;
      *) has_other=1 ;;
    esac
  done <<< "$files"

  if (( has_cpp == 0 && has_fortran == 0 && has_other == 0 )); then
    if (( has_test == 1 && has_build == 0 && has_docs == 0 )); then
      printf "test-only"; return
    fi
    if (( has_build == 1 && has_test == 0 && has_docs == 0 )); then
      printf "build-only"; return
    fi
    if (( has_docs == 1 && has_test == 0 && has_build == 0 )); then
      printf "docs-only"; return
    fi
    printf "meta-only"; return
  fi

  if (( has_cpp == 0 && has_fortran == 1 && has_other == 0 )); then
    printf "fortran-only"; return
  fi

  printf "code"
}

for repo in "$@"; do
  doc="$DOCS_ROOT/$repo.md"
  dir="$BUNDLE_ROOT/$repo"

  if [[ ! -f "$doc" ]]; then
    printf "==REPO %s STATUS=no-doc==\n\n" "$repo"
    continue
  fi

  stored=$(sed -n '3p' "$doc" | grep -oE '`[0-9a-f]{7,}`' | head -1 | tr -d '`')
  if [[ -z "$stored" ]]; then
    printf "==REPO %s STATUS=parse-error==\n\n" "$repo"
    continue
  fi

  head_hash=$(git -C "$dir" rev-parse --short=8 HEAD 2>/dev/null)
  if [[ -z "$head_hash" ]]; then
    printf "==REPO %s STATUS=repo-error==\n\n" "$repo"
    continue
  fi

  if ! git -C "$dir" rev-parse --verify "${stored}^{commit}" >/dev/null 2>&1; then
    printf "==REPO %s stored=%s head=%s STATUS=hash-not-found==\n\n" \
      "$repo" "$stored" "$head_hash"
    continue
  fi

  stored_full=$(git -C "$dir" rev-parse --short=8 "$stored" 2>/dev/null)

  if [[ "$stored_full" == "$head_hash" ]]; then
    printf "==REPO %s stored=%s head=%s STATUS=no-changes==\n\n" \
      "$repo" "$stored_full" "$head_hash"
    continue
  fi

  commits=$(git -C "$dir" log --oneline "${stored}..HEAD" 2>/dev/null)
  count=$(printf '%s' "$commits" | grep -c .)
  files=$(git -C "$dir" diff --name-only "${stored}..HEAD" 2>/dev/null)
  stat=$(git -C "$dir" diff --stat "${stored}..HEAD" 2>/dev/null)
  class=$(printf '%s\n' "$files" | classify)

  printf "==REPO %s stored=%s head=%s commits=%s class=%s STATUS=changed==\n" \
    "$repo" "$stored_full" "$head_hash" "$count" "$class"
  printf -- "--LOG--\n%s\n" "$commits"
  printf -- "--STAT--\n%s\n\n" "$stat"
done
