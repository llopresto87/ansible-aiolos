#!/usr/bin/env bash

set -euo pipefail

include_remotes="false"
base_branch=""
output_file=""

usage() {
  cat <<'USAGE'
Usage: scripts/compare_branch_status.sh [options]

Options:
  --base <branch>          Base branch (default: current branch)
  --include-remotes        Include origin/* branches in analysis
  --output <path>          Write markdown report to path
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      base_branch="${2:-}"
      shift 2
      ;;
    --include-remotes)
      include_remotes="true"
      shift
      ;;
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This script must run inside a git repository." >&2
  exit 1
fi

if [[ -z "$base_branch" ]]; then
  base_branch="$(git rev-parse --abbrev-ref HEAD)"
fi

if ! git rev-parse --verify "$base_branch" >/dev/null 2>&1; then
  echo "Base branch '$base_branch' was not found." >&2
  exit 1
fi

tmp_report="$(mktemp)"
trap 'rm -f "$tmp_report"' EXIT

{
  echo "# Branch Status Report"
  echo
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Base branch: $base_branch"
  echo
  echo "## Branch Matrix"
  echo
  echo "| Branch | Scope | Merge Base | Behind | Ahead | Changed Files |"
  echo "|---|---|---|---:|---:|---:|"

  while IFS= read -r branch; do
    [[ "$branch" == "$base_branch" ]] && continue

    if git merge-base "$base_branch" "$branch" >/dev/null 2>&1; then
      merge_base="yes"
      read -r behind ahead < <(git rev-list --left-right --count "$base_branch...$branch")
      changed_files="$(git diff --name-only "$base_branch...$branch" | wc -l | tr -d ' ')"
    else
      merge_base="no"
      behind="-"
      ahead="-"
      changed_files="$(git diff --name-only "$base_branch..$branch" | wc -l | tr -d ' ')"
    fi

    echo "| $branch | local | $merge_base | $behind | $ahead | $changed_files |"
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)

  if [[ "$include_remotes" == "true" ]]; then
    while IFS= read -r remote_branch; do
      [[ "$remote_branch" == "origin" ]] && continue
      short_name="${remote_branch#origin/}"
      [[ "$short_name" == "$base_branch" ]] && continue
      [[ "$short_name" == "HEAD" ]] && continue

      if git merge-base "$base_branch" "refs/remotes/$remote_branch" >/dev/null 2>&1; then
        merge_base="yes"
        read -r behind ahead < <(git rev-list --left-right --count "$base_branch...refs/remotes/$remote_branch")
        changed_files="$(git diff --name-only "$base_branch...refs/remotes/$remote_branch" | wc -l | tr -d ' ')"
      else
        merge_base="no"
        behind="-"
        ahead="-"
        changed_files="$(git diff --name-only "$base_branch..refs/remotes/$remote_branch" | wc -l | tr -d ' ')"
      fi

      echo "| $remote_branch | remote | $merge_base | $behind | $ahead | $changed_files |"
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)
  fi

  echo
  echo "## Category Summary"
  echo

  summarize_branch() {
    local ref="$1"
    local label="$2"
    local diff_expr

    if git merge-base "$base_branch" "$ref" >/dev/null 2>&1; then
      diff_expr="$base_branch...$ref"
    else
      diff_expr="$base_branch..$ref"
    fi

    local total inventory roles scripts playbooks docs
    total="$(git diff --name-only "$diff_expr" | wc -l | tr -d ' ')"
    inventory="$(git diff --name-only "$diff_expr" | grep -E '^(01_proxmox|02_lxc|02_vm|03_applications)/' | wc -l | tr -d ' ' || true)"
    roles="$(git diff --name-only "$diff_expr" | grep -E '^roles/' | wc -l | tr -d ' ' || true)"
    scripts="$(git diff --name-only "$diff_expr" | grep -E '(^scripts/|\.sh$)' | wc -l | tr -d ' ' || true)"
    playbooks="$(git diff --name-only "$diff_expr" | grep -E '^playbooks/' | wc -l | tr -d ' ' || true)"
    docs="$(git diff --name-only "$diff_expr" | grep -E '\.md$' | wc -l | tr -d ' ' || true)"

    echo "### $label"
    echo
    echo "- total: $total"
    echo "- inventory: $inventory"
    echo "- roles: $roles"
    echo "- scripts: $scripts"
    echo "- playbooks: $playbooks"
    echo "- docs: $docs"
    echo
  }

  while IFS= read -r branch; do
    [[ "$branch" == "$base_branch" ]] && continue
    summarize_branch "$branch" "$branch (local)"
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)

  if [[ "$include_remotes" == "true" ]]; then
    while IFS= read -r remote_branch; do
      [[ "$remote_branch" == "origin" ]] && continue
      short_name="${remote_branch#origin/}"
      [[ "$short_name" == "$base_branch" ]] && continue
      [[ "$short_name" == "HEAD" ]] && continue
      summarize_branch "refs/remotes/$remote_branch" "$remote_branch (remote)"
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)
  fi
} > "$tmp_report"

if [[ -n "$output_file" ]]; then
  mkdir -p "$(dirname "$output_file")"
  cp "$tmp_report" "$output_file"
  echo "Report written to $output_file"
else
  cat "$tmp_report"
fi
