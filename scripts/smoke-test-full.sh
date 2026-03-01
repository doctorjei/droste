#!/usr/bin/env bash
# Smoke test droste-full additions over SSH.
#
# Verifies Phase 2 additions only (VM tools, nested virt config).
# Phase 1 checks are in smoke-test.sh.
#
# Usage:
#   scripts/smoke-test-full.sh
#   scripts/smoke-test-full.sh --port 2222 --user agent --host localhost
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

Smoke test droste-full additions over SSH.

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
echo "droste-full smoke test"
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

# ── VM tools ──────────────────────────────────────────────────────────
echo "VM tools:"
check "qemu-system-x86_64 available"   "qemu-system-x86_64 --version"
check "qemu-img available"             "qemu-img --version"
check "cloud-localds available"        "cloud-localds --help"
check "ansible available"              "ansible --version"
check "envsubst available"             "envsubst --version"
check "swtpm available"                "swtpm --version"
check "OVMF firmware exists"           "test -f /usr/share/OVMF/OVMF_CODE.fd"
check "gdisk available"                "test -x /usr/sbin/gdisk"
check "virsh available"                "virsh --version"
check "virt-install available"         "virt-install --version"
check "nbdkit available"               "nbdkit --version"
check "lvm available"                  "sudo lvm version"
check "mdadm available"                "sudo mdadm --version"
check "parted available"               "sudo parted --version"
check "mkfs.btrfs available"           "test -x /usr/sbin/mkfs.btrfs"
check "cryptsetup available"           "test -x /usr/sbin/cryptsetup"
check "quota available"                "command -v quota"
check "nbd-client available"           "test -x /usr/sbin/nbd-client"
check "exportfs available"             "test -x /usr/sbin/exportfs"
check "lspci available"                "lspci --version"
check "picocom available"              "picocom --help"
check "mount.ntfs available"           "test -x /usr/sbin/mount.ntfs-3g"
check "mkfs.fat available"             "test -x /usr/sbin/mkfs.fat"
check "mtools available"               "command -v mtools"
check "hdparm available"               "test -x /usr/sbin/hdparm"
check "dmidecode available"            "test -x /usr/sbin/dmidecode"
check "lshw available"                 "sudo lshw -version"
check "ncdu available"                 "ncdu -v"
check "kvm-ok available"               "test -x /usr/sbin/kvm-ok"
check "nethogs available"              "test -x /usr/sbin/nethogs"
check "bmon available"                 "command -v bmon"
check "hping3 available"               "test -x /usr/sbin/hping3"
check "mksquashfs available"           "command -v mksquashfs"
check "irqbalance available"           "test -x /usr/sbin/irqbalance"
check "cpufreq-info available"         "command -v cpufreq-info"
check "ethtool available"              "test -x /usr/sbin/ethtool"
check "nicstat available"              "command -v nicstat"
check "brctl available"                "test -x /usr/sbin/brctl"
check "thin_check available"           "test -x /usr/sbin/thin_check"
check "sysbench available"             "sysbench --version"
echo ""

# ── Nested virtualization config ──────────────────────────────────────
echo "Nested virt config:"
check "kvm-nested.conf exists"         "test -f /etc/modprobe.d/kvm-nested.conf"
check "kvm_intel nested=1"             "grep -q 'options kvm_intel nested=1' /etc/modprobe.d/kvm-nested.conf"
check "kvm_amd nested=1"               "grep -q 'options kvm_amd nested=1' /etc/modprobe.d/kvm-nested.conf"
echo ""

# ── Module autoload ───────────────────────────────────────────────────
echo "Module autoload:"
check "droste.conf exists"             "test -f /etc/modules-load.d/droste.conf"
check "nbd module configured"          "grep -q 'nbd' /etc/modules-load.d/droste.conf"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
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
