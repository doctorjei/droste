#!/usr/bin/env bash
# Boot a droste image for smoke testing with QEMU.
#
# Creates an ephemeral QCOW2 overlay by default (changes discarded on exit).
# Use --persist for iterative testing with a persistent overlay.
# Use --share to mount a host directory inside the guest via virtiofs.
#
# Prerequisites: qemu-system-x86_64, cloud-localds (from cloud-image-utils).
#                virtiofsd (for --share only).
#
# Usage:
#   boot-droste.sh --ssh-key ~/.ssh/id_ed25519.pub
#   boot-droste.sh --ssh-key ~/.ssh/id.pub --persist --memory 4096
#   boot-droste.sh --ssh-key ~/.ssh/id.pub --share ~/projects
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
SHARE_DIR=""

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
  --share DIR      Share a host directory via virtiofs (mounted at /mnt/share)
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
        --share)     SHARE_DIR="$2"; shift 2 ;;
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

if [[ -n "$SHARE_DIR" ]]; then
    if [[ ! -d "$SHARE_DIR" ]]; then
        echo "Error: share directory not found: $SHARE_DIR" >&2
        exit 1
    fi
    if ! command -v virtiofsd &>/dev/null; then
        echo "Error: virtiofsd not found (required for --share)." >&2
        echo "  sudo apt install virtiofsd" >&2
        exit 1
    fi
    SHARE_DIR="$(realpath "$SHARE_DIR")"
fi

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

# ── Start virtiofsd (if --share) ──────────────────────────────────
VIRTIOFSD_PID=""
VIRTIOFSD_SOCK=""
if [[ -n "$SHARE_DIR" ]]; then
    VIRTIOFSD_SOCK="${WORK_DIR}/${HOSTNAME}-virtiofsd.sock"
    rm -f "$VIRTIOFSD_SOCK"

    virtiofsd --socket-path="$VIRTIOFSD_SOCK" \
              --shared-dir="$SHARE_DIR" \
              --sandbox=none &
    VIRTIOFSD_PID=$!

    # Wait for socket to appear
    retries=20
    while [[ ! -S "$VIRTIOFSD_SOCK" ]]; do
        if ! kill -0 "$VIRTIOFSD_PID" 2>/dev/null; then
            echo "Error: virtiofsd exited unexpectedly" >&2
            exit 1
        fi
        ((retries--))
        if [[ $retries -le 0 ]]; then
            echo "Error: virtiofsd socket did not appear" >&2
            kill "$VIRTIOFSD_PID" 2>/dev/null
            exit 1
        fi
        sleep 0.1
    done
fi

# ── Cleanup on exit ───────────────────────────────────────────────
cleanup() {
    if [[ -n "$VIRTIOFSD_PID" ]]; then
        kill "$VIRTIOFSD_PID" 2>/dev/null || true
        rm -f "$VIRTIOFSD_SOCK"
    fi
}
trap cleanup EXIT

# ── Build QEMU command ─────────────────────────────────────────────
QEMU_ARGS=(
    qemu-system-x86_64
    -cpu host
    -enable-kvm
    -smp "$CPUS"
    -drive "file=${OVERLAY},format=qcow2,if=virtio"
    -drive "file=${CIDATA_ISO},format=raw,if=virtio"
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
)

if [[ -n "$SHARE_DIR" ]]; then
    # virtiofs requires shared memory backend
    QEMU_ARGS+=(
        -m "$MEMORY"
        -object "memory-backend-memfd,id=mem,size=${MEMORY}M,share=on"
        -numa "node,memdev=mem"
        -chardev "socket,id=virtiofs0,path=${VIRTIOFSD_SOCK}"
        -device "vhost-user-fs-pci,chardev=virtiofs0,tag=share"
    )
else
    QEMU_ARGS+=(-m "$MEMORY")
fi

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
echo "  SSH:      ssh -p ${SSH_PORT} droste@localhost"
echo "  Persist:  $PERSIST"
if [[ -n "$SHARE_DIR" ]]; then
    echo "  Share:    $SHARE_DIR -> /mnt/share (virtiofs)"
    echo "  Mount:    sudo mount -t virtiofs share /mnt/share"
fi
echo ""

exec "${QEMU_ARGS[@]}"
