#!/usr/bin/env bash
# Smoke test for droste-full — runs inside the guest.
#
# Verifies Phase 2 additions only (VM tools, nested virt config).
# Phase 1 checks are in smoke-test-guest.sh.
#
# Usage:
#   sudo ./smoke-test-guest-full.sh
set -euo pipefail

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

echo "droste-full smoke test (guest)"
echo "==============================="
echo ""

# ── VM tools ──────────────────────────────────────────────────────────
echo "VM tools:"
check "qemu-system-x86_64 available"   "command -v qemu-system-x86_64"
check "qemu-img available"             "command -v qemu-img"
check "cloud-localds available"        "command -v cloud-localds"
check "ansible available"              "command -v ansible"
check "envsubst available"             "command -v envsubst"
check "swtpm available"                "command -v swtpm"
check "OVMF firmware exists"           "test -f /usr/share/OVMF/OVMF_CODE.fd"
check "gdisk available"                "command -v gdisk"
check "virsh available"                "command -v virsh"
check "virt-install available"         "command -v virt-install"
check "nbdkit available"               "command -v nbdkit"
check "lvm available"                  "command -v lvm"
check "mdadm available"                "command -v mdadm"
check "parted available"               "command -v parted"
check "mkfs.btrfs available"           "command -v mkfs.btrfs"
check "cryptsetup available"           "command -v cryptsetup"
check "quota available"                "command -v quota"
check "nbd-client available"           "test -x /usr/sbin/nbd-client"
check "exportfs available"             "test -x /usr/sbin/exportfs"
check "lspci available"                "command -v lspci"
check "picocom available"              "command -v picocom"
check "mount.ntfs available"           "test -x /usr/sbin/mount.ntfs-3g"
check "mkfs.fat available"             "command -v mkfs.fat"
check "mtools available"               "command -v mtools"
check "hdparm available"               "test -x /usr/sbin/hdparm"
check "dmidecode available"            "test -x /usr/sbin/dmidecode"
check "lshw available"                 "command -v lshw"
check "ncdu available"                 "command -v ncdu"
check "kvm-ok available"               "command -v kvm-ok"
check "nethogs available"              "command -v nethogs"
check "bmon available"                 "command -v bmon"
check "hping3 available"               "command -v hping3"
check "mksquashfs available"           "command -v mksquashfs"
check "irqbalance available"           "test -x /usr/sbin/irqbalance"
check "cpufreq-info available"         "command -v cpufreq-info"
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
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
