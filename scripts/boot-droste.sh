#!/usr/bin/env bash
# Boot a droste image for smoke testing with QEMU.
#
# Creates an ephemeral QCOW2 overlay by default (changes discarded on exit).
# Use --persist for iterative testing with a persistent overlay.
#
# Prerequisites: qemu-system-x86_64, cloud-localds (from cloud-image-utils).
#
# Usage:
#   boot-droste.sh --ssh-key ~/.ssh/id_ed25519.pub
#   boot-droste.sh --ssh-key ~/.ssh/id.pub --persist --memory 4096
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT_TEMPLATE="${SCRIPT_DIR}/../cloud-init/user-data.yml"
DEFAULT_IMAGE="${SCRIPT_DIR}/../output-droste-thread/droste-thread.qcow2"

# ── Defaults ────────────────────────────────────────────────────────
IMAGE=""
MEMORY=2048
CPUS=2
SSH_PORT=2222
SSH_KEY_FILE=""
HOSTNAME="droste"
PERSIST=false
DAEMONIZE=false

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Boot a droste image with QEMU for smoke testing.

By default, changes are ephemeral (discarded on exit).
Use --persist to keep changes across reboots.

Prerequisites:
  - qemu-system-x86_64
  - cloud-localds (from cloud-image-utils package)

Options:
  --image FILE     Path to base QCOW2 image (default: output-droste-thread/droste-thread.qcow2)
  --memory MB      Memory in MB (default: 2048)
  --cpus N         CPU count (default: 2)
  --ssh-port PORT  Host port for SSH forwarding (default: 2222)
  --ssh-key FILE   Path to SSH public key file (required)
  --hostname NAME  Guest hostname (default: droste)
  --persist        Use persistent overlay (changes survive reboot)
  --daemonize      Run QEMU in background
  -h, --help       Show this help message
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)     IMAGE="$2"; shift 2 ;;
        --memory)    MEMORY="$2"; shift 2 ;;
        --cpus)      CPUS="$2"; shift 2 ;;
        --ssh-port)  SSH_PORT="$2"; shift 2 ;;
        --ssh-key)   SSH_KEY_FILE="$2"; shift 2 ;;
        --hostname)  HOSTNAME="$2"; shift 2 ;;
        --persist)   PERSIST=true; shift ;;
        --daemonize) DAEMONIZE=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -z "$SSH_KEY_FILE" ]]; then
    echo "Error: --ssh-key is required" >&2
    usage >&2
    exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
    echo "Error: SSH key file not found: $SSH_KEY_FILE" >&2
    exit 1
fi

IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
if [[ ! -f "$IMAGE" ]]; then
    echo "Error: Base image not found: $IMAGE" >&2
    echo "Run 'cd packer && packer init . && packer build droste-thread.pkr.hcl' first." >&2
    exit 1
fi

# ── Check prerequisites ────────────────────────────────────────────
for cmd in qemu-system-x86_64 cloud-localds; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found." >&2
        echo "  sudo apt install qemu-system-x86 cloud-image-utils" >&2
        exit 1
    fi
done

# ── Work directory ──────────────────────────────────────────────────
WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/droste-boot"
mkdir -p "$WORK_DIR"

# ── Create overlay disk ────────────────────────────────────────────
if $PERSIST; then
    OVERLAY="${WORK_DIR}/${HOSTNAME}-persist.qcow2"
    if [[ ! -f "$OVERLAY" ]]; then
        echo "Creating persistent overlay: $OVERLAY"
        qemu-img create -f qcow2 -b "$(realpath "$IMAGE")" -F qcow2 "$OVERLAY"
    else
        echo "Using existing persistent overlay: $OVERLAY"
    fi
else
    OVERLAY="${WORK_DIR}/${HOSTNAME}-ephemeral.qcow2"
    echo "Creating ephemeral overlay (changes discarded on exit)"
    qemu-img create -f qcow2 -b "$(realpath "$IMAGE")" -F qcow2 "$OVERLAY"
fi

# ── Generate cloud-init ISO ────────────────────────────────────────
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_FILE")
export SSH_PUBLIC_KEY DROSTE_HOSTNAME="$HOSTNAME"

USERDATA="${WORK_DIR}/${HOSTNAME}-user-data.yml"
envsubst < "$CLOUD_INIT_TEMPLATE" > "$USERDATA"

CIDATA_ISO="${WORK_DIR}/${HOSTNAME}-cidata.iso"
cloud-localds "$CIDATA_ISO" "$USERDATA"

# ── Build QEMU command ─────────────────────────────────────────────
QEMU_ARGS=(
    qemu-system-x86_64
    -cpu host
    -enable-kvm
    -m "$MEMORY"
    -smp "$CPUS"
    -drive "file=${OVERLAY},format=qcow2,if=virtio"
    -drive "file=${CIDATA_ISO},format=raw,if=virtio"
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
)

if $DAEMONIZE; then
    QEMU_ARGS+=(-display none -daemonize -pidfile "${WORK_DIR}/${HOSTNAME}.pid")
else
    QEMU_ARGS+=(-nographic)
fi

# ── Launch ──────────────────────────────────────────────────────────
echo ""
echo "Booting droste image..."
echo "  Image:    $IMAGE"
echo "  Overlay:  $OVERLAY"
echo "  Memory:   ${MEMORY} MB"
echo "  CPUs:     $CPUS"
echo "  SSH:      ssh -p ${SSH_PORT} agent@localhost"
echo "  Persist:  $PERSIST"
echo ""

exec "${QEMU_ARGS[@]}"
