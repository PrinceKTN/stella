#!/data/data/com.termux/files/usr/bin/bash

set -u

ROOT="$HOME/stella"
FORGE="$ROOT/core/skills/project-forge"
STATE="$ROOT/state/project-forge"
LOG="$ROOT/logs/project-forge/project-forge.log"

mkdir -p "$STATE" "$(dirname "$LOG")"

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    printf '[%s] %s\n' "$(timestamp)" "$*" >> "$LOG"
}

usage() {
    cat <<'HELP'
STELLA PROJECT FORGE v0.1

Usage:
  project-forge status
  project-forge inspect [directory]
  project-forge test [directory]
  project-forge diff [directory]
  project-forge stage [directory]
  project-forge commit [directory] "message"
  project-forge push [directory]
  project-forge help

Workflow:
  DISCOVER → PLAN → IMPLEMENT → TEST → REVIEW
  → STAGE → COMMIT → PUSH → VERIFY → DOCUMENT

Safety:
  stage, commit and push are approval-gated.
  destructive Git operations are blocked.
HELP
}

require_repo() {
    local dir="${1:-.}"

    if ! git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "ERROR: Not a Git repository: $dir"
        return 1
    fi

    git -C "$dir" rev-parse --show-toplevel
}

status_cmd() {
    local dir="${1:-.}"

    if ! require_repo "$dir" >/dev/null; then
        return 1
    fi

    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                 PROJECT FORGE STATUS                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo

    echo "Project root:"
    git -C "$dir" rev-parse --show-toplevel

    echo
    echo "Branch:"
    git -C "$dir" branch --show-current

    echo
    echo "Repository:"
    git -C "$dir" status --short --branch

    echo
    echo "Recent commits:"
    git -C "$dir" log -5 --oneline 2>/dev/null || true

    echo
    echo "Remote:"
    git -C "$dir" remote -v 2>/dev/null || true

    log "status dir=$dir"
}

inspect_cmd() {
    local dir="${1:-.}"

    require_repo "$dir" >/dev/null || return 1

    echo
    echo "PROJECT INSPECTION"
    echo "────────────────────────────────────────"

    echo
    echo "Root:"
    git -C "$dir" rev-parse --show-toplevel

    echo
    echo "Branch:"
    git -C "$dir" branch --show-current

    echo
    echo "Changed files:"
    git -C "$dir" status --short

    echo
    echo "Tracked files:"
    git -C "$dir" ls-files | wc -l

    echo
    echo "Untracked files:"
    git -C "$dir" ls-files --others --exclude-standard | wc -l

    log "inspect dir=$dir"
}

test_cmd() {
    local dir="${1:-.}"

    require_repo "$dir" >/dev/null || return 1

    echo
    echo "PROJECT TEST DISCOVERY"
    echo "────────────────────────────────────────"

    local found=0

    if [ -f "$dir/stella-test.sh" ]; then
        echo "FOUND: stella-test.sh"
        found=1
    fi

    if [ -d "$dir/tests" ]; then
        echo "FOUND: tests/"
        find "$dir/tests" -maxdepth 2 -type f | sort
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        echo "No standard Stella test entry point detected."
        echo "Project Forge will not pretend the project passed."
    fi

    log "test-discovery dir=$dir found=$found"
}

diff_cmd() {
    local dir="${1:-.}"

    require_repo "$dir" >/dev/null || return 1

    echo
    echo "PROJECT DIFF"
    echo "────────────────────────────────────────"

    git -C "$dir" diff --stat
    echo
    git -C "$dir" diff -- .
    log "diff dir=$dir"
}

approval() {
    local action="$1"

    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    APPROVAL REQUIRED                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    echo "Requested action: $action"
    echo
    printf "Approve this action? [y/N]: "
    read -r answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            echo "Action cancelled."
            log "approval-denied action=$action"
            return 1
            ;;
    esac
}

stage_cmd() {
    local dir="${1:-.}"

    require_repo "$dir" >/dev/null || return 1

    approval "git add / stage project changes" || return 1

    git -C "$dir" add --all

    echo
    echo "STAGING COMPLETE"
    git -C "$dir" status --short

    log "stage dir=$dir"
}

commit_cmd() {
    local dir="${1:-.}"
    local message="${2:-}"

    require_repo "$dir" >/dev/null || return 1

    if [ -z "$message" ]; then
        echo "ERROR: Commit message required."
        return 1
    fi

    approval "git commit" || return 1

    git -C "$dir" diff --cached --quiet 2>/dev/null

    if [ "$?" -eq 0 ]; then
        echo "ERROR: Nothing staged for commit."
        return 1
    fi

    git -C "$dir" commit -m "$message"

    echo
    echo "COMMIT CREATED"
    git -C "$dir" log -1 --oneline

    log "commit dir=$dir message=$message"
}

push_cmd() {
    local dir="${1:-.}"

    require_repo "$dir" >/dev/null || return 1

    approval "git push to configured remote" || return 1

    git -C "$dir" push

    echo
    echo "PUSH COMPLETE"

    log "push dir=$dir"
}

case "${1:-help}" in
    status)
        status_cmd "${2:-.}"
        ;;
    inspect)
        inspect_cmd "${2:-.}"
        ;;
    test)
        test_cmd "${2:-.}"
        ;;
    diff)
        diff_cmd "${2:-.}"
        ;;
    stage)
        stage_cmd "${2:-.}"
        ;;
    commit)
        commit_cmd "${2:-.}" "${3:-}"
        ;;
    push)
        push_cmd "${2:-.}"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        echo
        usage
        exit 1
        ;;
esac
