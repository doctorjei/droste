#!/usr/bin/env bash
# Smoke test droste-jacquard additions over SSH.
#
# Verifies Phase 6 additions only (Proxmox VE environment).
# Phase 1-5 checks are in their respective smoke test scripts.
#
# Usage:
#   scripts/smoke-test-jacquard.sh
#   scripts/smoke-test-jacquard.sh --port 2222 --user agent --host localhost
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

Smoke test droste-jacquard additions over SSH.

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
echo "droste-jacquard smoke test"
echo "=========================="
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

# ── PVE kernel ─────────────────────────────────────────────────────
echo "Kernel:"
check "PVE kernel running"                "uname -r | grep pve"
check "Debian stock kernel removed"       "! dpkg -l linux-image-amd64 2>/dev/null | grep -q ^ii"
echo ""

# ── PVE CLI tools ──────────────────────────────────────────────────
echo "PVE CLI tools:"
check "pveversion available"              "command -v pveversion"
check "pvesh available"                   "command -v pvesh"
check "qm available"                      "test -x /usr/sbin/qm"
check "pct available"                     "test -x /usr/sbin/pct"
check "pvecm available"                   "command -v pvecm"
check "pvesm available"                   "test -x /usr/sbin/pvesm"
echo ""

# ── PVE daemons ────────────────────────────────────────────────────
echo "PVE daemons:"
check "pveproxy installed"                "test -x /usr/bin/pveproxy"
check "pvedaemon installed"               "test -x /usr/bin/pvedaemon"
echo ""

echo "ZFS:"
check "zpool available"                   "command -v zpool || test -x /usr/sbin/zpool"
check "zfs available"                     "command -v zfs || test -x /usr/sbin/zfs"
echo ""

# ── Cluster ────────────────────────────────────────────────────────
echo "Cluster:"
check "corosync available"                "test -x /usr/sbin/corosync"
check "ha-manager available"              "test -x /usr/sbin/ha-manager"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "=========================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
