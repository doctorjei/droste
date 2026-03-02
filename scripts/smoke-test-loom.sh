#!/usr/bin/env bash
# Smoke test droste-loom additions over SSH.
#
# Verifies Phase 5 additions only (C/C++ development toolchain).
# Phase 1-4 checks are in their respective smoke test scripts.
#
# Usage:
#   scripts/smoke-test-loom.sh
#   scripts/smoke-test-loom.sh --port 2222 --user agent --host localhost
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────
HOST="localhost"
PORT=2222
USER="agent"
SSH_KEY=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Smoke test droste-loom additions over SSH.

Options:
  --host HOST      Guest hostname or IP (default: localhost)
  --port PORT      SSH port (default: 2222)
  --user USER      SSH user (default: agent)
  --ssh-key FILE   Path to SSH private key (default: ssh default)
  -h, --help       Show this help message
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    HOST="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --user)    USER="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Build SSH command ───────────────────────────────────────────────
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSH_OPTS+=(-p "$PORT")
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_run() {
    ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$@"
}

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if ssh_run "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

# ── Connectivity ────────────────────────────────────────────────────
echo "droste-loom smoke test"
echo "======================"
echo ""
echo "Target: ${USER}@${HOST}:${PORT}"
echo ""

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

# ── Compilers ───────────────────────────────────────────────────────
echo "Compilers:"
check "gcc available"                   "command -v gcc"
check "g++ available"                   "command -v g++"
check "make available"                  "command -v make"
echo ""

# ── Build systems ───────────────────────────────────────────────────
echo "Build systems:"
check "cmake available"                 "command -v cmake"
check "autoconf available"              "command -v autoconf"
check "automake available"              "command -v automake"
check "pkg-config available"            "command -v pkg-config"
check "ninja available"                 "command -v ninja"
echo ""

# ── Debugging ───────────────────────────────────────────────────────
echo "Debugging:"
check "gdb available"                   "command -v gdb"
check "valgrind available"              "command -v valgrind"
echo ""

# ── Utilities ───────────────────────────────────────────────────────
echo "Utilities:"
check "ccache available"                "command -v ccache"
check "bear available"                  "command -v bear"
check "libtoolize available"             "command -v libtoolize"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "======================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
