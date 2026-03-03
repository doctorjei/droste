#!/usr/bin/env bash
# Check that build host prerequisites are installed for droste image building.
#
# Usage:
#   scripts/check-prereqs.sh
set -euo pipefail

MISSING=()
OK=()
NOTES=()

# ── Check commands ──────────────────────────────────────────────────
check_cmd() {
    local cmd="$1"
    local install="$2"
    local purpose="$3"
    local note="${4:-}"

    if command -v "$cmd" &>/dev/null; then
        OK+=("$cmd ($purpose)")
    else
        MISSING+=("$cmd  —  $install  ($purpose)")
        if [[ -n "$note" ]]; then
            NOTES+=("$cmd: $note")
        fi
    fi
}

check_cmd packer \
    "see install note below" \
    "image builds" \
    "Not in Debian repos. Install from HashiCorp:
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
      echo \"deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | sudo tee /etc/apt/sources.list.d/hashicorp.list
      sudo apt update && sudo apt install packer"

check_cmd ansible-playbook \
    "apt install ansible" \
    "Packer provisioner"

check_cmd qemu-system-x86_64 \
    "apt install qemu-system-x86" \
    "Packer QEMU builder, boot script"

check_cmd qemu-img \
    "apt install qemu-utils" \
    "overlay creation, image compression"

check_cmd cloud-localds \
    "apt install cloud-image-utils" \
    "boot script cloud-init ISO"

check_cmd envsubst \
    "apt install gettext-base" \
    "boot script template substitution"

# ── Check /dev/kvm ──────────────────────────────────────────────────
if [[ -c /dev/kvm ]]; then
    OK+=("/dev/kvm (hardware acceleration)")
else
    MISSING+=("/dev/kvm  —  see note below  (builds will be very slow without it)")
    NOTES+=("/dev/kvm: Requires CPU virtualization support (VT-x/AMD-V) enabled in BIOS.
      If running inside a VM, enable nested virtualization on the host:
        Intel: echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf
        AMD:   echo 'options kvm_amd nested=1'   | sudo tee /etc/modprobe.d/kvm.conf")
fi

# ── Report ──────────────────────────────────────────────────────────
echo "droste build host prerequisites"
echo "================================"
echo ""

if [[ ${#OK[@]} -gt 0 ]]; then
    echo "Found:"
    for item in "${OK[@]}"; do
        echo "  + $item"
    done
    echo ""
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Missing:"
    for item in "${MISSING[@]}"; do
        echo "  - $item"
    done
    echo ""

    if [[ ${#NOTES[@]} -gt 0 ]]; then
        echo "Install notes:"
        for note in "${NOTES[@]}"; do
            echo "  $note"
            echo ""
        done
    fi

    # Show one-liner for the simple apt packages
    APT_PKGS=()
    for cmd in ansible qemu-system-x86 qemu-utils cloud-image-utils gettext-base; do
        if ! dpkg -s "$cmd" &>/dev/null 2>&1; then
            APT_PKGS+=("$cmd")
        fi
    done
    if [[ ${#APT_PKGS[@]} -gt 0 ]]; then
        echo "Quick install (apt packages only):"
        echo "  sudo apt install ${APT_PKGS[*]}"
        echo ""
    fi

    exit 1
else
    echo "All prerequisites met."
fi
