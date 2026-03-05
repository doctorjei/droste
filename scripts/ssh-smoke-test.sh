#!/usr/bin/env bash
# Run smoke tests against a running droste instance over SSH.
#
# Reads a check definition file and executes each check remotely.
# Prints verbose output with section headers, pass/fail per check,
# and a summary.
#
# Usage:
#   scripts/ssh-smoke-test.sh --port 2222 --ssh-key KEY checks/thread.checks
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────
HOST="localhost"
PORT=2222
USER="droste"
SSH_KEY=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] CHECKFILE

Run smoke tests from a check definition file over SSH.

Options:
  --host HOST      Guest hostname or IP (default: localhost)
  --port PORT      SSH port (default: 2222)
  --user USER      SSH user (default: droste)
  --ssh-key FILE   Path to SSH private key (default: ssh default)
  -h, --help       Show this help message

Check file format (tab-separated):
  # Section header
  description<TAB>command
  description<TAB>command<TAB>ssh-only
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
CHECKFILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    HOST="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --user)    USER="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)         CHECKFILE="$1"; shift ;;
    esac
done

if [[ -z "$CHECKFILE" ]]; then
    echo "Error: no check file specified" >&2
    usage >&2
    exit 1
fi

if [[ ! -f "$CHECKFILE" ]]; then
    echo "Error: check file not found: $CHECKFILE" >&2
    exit 1
fi

# ── Build SSH command ───────────────────────────────────────────────
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSH_OPTS+=(-p "$PORT")
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_run() {
    ssh -n "${SSH_OPTS[@]}" "${USER}@${HOST}" "$@"
}

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

# ── Derive tier name from filename ──────────────────────────────────
TIER=$(basename "$CHECKFILE" .checks)

echo "droste-${TIER} smoke test"
echo "======================"
echo ""
echo "Target: ${USER}@${HOST}:${PORT}"
echo ""

# ── Connectivity check ──────────────────────────────────────────────
echo "Connectivity:"
if ! ssh_run true; then
    echo "  - FAIL: cannot connect to ${USER}@${HOST}:${PORT}"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
fi
echo "  + SSH connection"
PASS=1
echo ""

# ── Run @quiet inherited check files (failures only) ──────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while IFS= read -r line; do
    [[ "$line" =~ ^@quiet\  ]] || continue
    qfile="${line#@quiet }"
    qfile="$PROJECT_DIR/checks/$qfile"
    [[ -f "$qfile" ]] || { echo "Warning: quiet file not found: $qfile" >&2; continue; }
    while IFS= read -r qline; do
        [[ -z "$qline" ]] && continue
        [[ "$qline" =~ ^# ]] && continue
        [[ "$qline" =~ ^@ ]] && continue
        IFS=$'\t' read -r desc cmd flag <<< "$qline"
        if ssh_run "$cmd" &>/dev/null; then
            PASS=$((PASS + 1))
        else
            echo "  - FAIL (${qfile##*/}): $desc"
            ERRORS+=("(${qfile##*/}) $desc")
            FAIL=$((FAIL + 1))
        fi
    done < <(sed '/@stop/,$d' "$qfile")
done < "$CHECKFILE"

# ── Run checks from file (verbose, skip directives) ───────────────
while IFS= read -r line; do
    # Skip empty lines and directives
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^@ ]] && continue

    # Section headers
    if [[ "$line" =~ ^#\  ]]; then
        echo "${line#\# }:"
        continue
    fi

    # Parse: description<TAB>command [<TAB>ssh-only]
    IFS=$'\t' read -r desc cmd flag <<< "$line"

    if ssh_run "$cmd" &>/dev/null; then
        echo "  + $desc"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $desc"
        ERRORS+=("$desc")
        FAIL=$((FAIL + 1))
    fi
done < "$CHECKFILE"

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
