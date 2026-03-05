#!/usr/bin/env bash
# Manage OCI-backed droste LXC containers.
#
# Uses OCI images (podman/docker) as the read-only base for LXC system
# containers via overlayfs. The OCI store IS the layer store — no
# extraction or duplication of image data.
#
# Usage:
#   droste-oci-lxc.sh create test-hair droste-hair:latest
#   droste-oci-lxc.sh create test-hair droste-hair:latest --start
#   droste-oci-lxc.sh destroy test-hair
#   droste-oci-lxc.sh list
#   droste-oci-lxc.sh reset test-hair
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="/usr/local/lib/droste/droste-oci-hook.sh"
LXC_BASE="/var/lib/lxc"

# ── Container engine detection ──────────────────────────────────────
detect_container_cmd() {
    if command -v podman &>/dev/null; then
        echo podman
    elif command -v docker &>/dev/null; then
        echo docker
    else
        echo "Error: neither podman nor docker found" >&2
        exit 1
    fi
}

# ── Check image exists ──────────────────────────────────────────────
image_exists() {
    local engine="$1" image="$2"
    case "$engine" in
        podman) podman image exists "$image" 2>/dev/null ;;
        docker) docker image inspect "$image" >/dev/null 2>&1 ;;
    esac
}

# ── Resolve OCI layer paths ─────────────────────────────────────────
# Returns colon-separated lowerdir string (topmost layer first).
get_lowerdir() {
    local engine="$1" image="$2"
    local upper lower

    case "$engine" in
        podman)
            upper=$(podman image inspect "$image" --format '{{.GraphDriver.Data.UpperDir}}')
            lower=$(podman image inspect "$image" --format '{{.GraphDriver.Data.LowerDir}}')
            ;;
        docker)
            upper=$(docker image inspect --format '{{index .GraphDriver.Data "UpperDir"}}' "$image")
            lower=$(docker image inspect --format '{{index .GraphDriver.Data "LowerDir"}}' "$image")
            ;;
    esac

    if [[ -n "$lower" ]]; then
        echo "${upper}:${lower}"
    else
        echo "$upper"
    fi
}

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Manage OCI-backed droste LXC containers.

Commands:
  create <name> <image> [opts]   Create LXC container from OCI image
  destroy <name>                 Remove container and writable layer
  list                           List droste OCI-backed containers
  reset <name>                   Clear writable layer (revert to OCI state)

Create options:
  -b, --bridge NAME    Network bridge (default: lxcbr0)
  -m, --memory MB      Memory limit (default: no limit)
  -c, --cores N        CPU limit (default: no limit)
  -n, --nesting        Enable nesting (default: on)
      --no-nesting     Disable nesting
      --start          Start container after creation

Examples:
  $(basename "$0") create test-hair droste-hair:latest
  $(basename "$0") create test-hair droste-hair:latest --start -b br0
  $(basename "$0") destroy test-hair
  $(basename "$0") list
  $(basename "$0") reset test-hair
EOF
}

# ── Require root ────────────────────────────────────────────────────
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Error: must run as root" >&2
        exit 1
    fi
}

# ── Generate LXC config ────────────────────────────────────────────
generate_config() {
    local name="$1" bridge="$2" memory="$3" cores="$4" nesting="$5"
    local lxc_dir="${LXC_BASE}/${name}"

    cat <<EOF
lxc.uts.name = ${name}
lxc.rootfs.path = dir:${lxc_dir}/rootfs

lxc.hook.version = 1
lxc.hook.pre-start = ${HOOK_SCRIPT}
lxc.hook.post-stop = ${HOOK_SCRIPT}

lxc.net.0.type = veth
lxc.net.0.link = ${bridge}
lxc.net.0.flags = up

lxc.init.cmd = /sbin/init
lxc.mount.auto = proc:rw sys:rw cgroup:rw
lxc.apparmor.profile = unconfined
lxc.tty.max = 4
lxc.pty.max = 1024
EOF

    if [[ "$memory" != "0" ]]; then
        echo "lxc.cgroup2.memory.max = ${memory}M"
    fi

    if [[ "$cores" != "0" ]]; then
        echo "lxc.cgroup2.cpuset.cpus = 0-$((cores - 1))"
    fi

    if [[ "$nesting" == "true" ]]; then
        echo "lxc.include = /usr/share/lxc/config/nesting.conf"
    fi
}

# ── Create ──────────────────────────────────────────────────────────
do_create() {
    if [[ $# -lt 2 ]]; then
        echo "Error: create requires <name> and <image>" >&2
        usage >&2
        exit 1
    fi

    local name="$1" image="$2"
    shift 2

    local bridge="lxcbr0"
    local memory="0"
    local cores="0"
    local nesting="true"
    local start=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--bridge)      bridge="$2"; shift 2 ;;
            -m|--memory)      memory="$2"; shift 2 ;;
            -c|--cores)       cores="$2"; shift 2 ;;
            -n|--nesting)     nesting="true"; shift ;;
            --no-nesting)     nesting="false"; shift ;;
            --start)          start=true; shift ;;
            -*)               echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
            *)                echo "Error: unexpected argument: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    require_root

    local lxc_dir="${LXC_BASE}/${name}"
    if [[ -d "$lxc_dir" ]]; then
        echo "Error: container already exists: ${name}" >&2
        exit 1
    fi

    # Verify hook script is installed
    if [[ ! -x "$HOOK_SCRIPT" ]]; then
        echo "Error: hook script not found: ${HOOK_SCRIPT}" >&2
        echo "Install it with:" >&2
        echo "  sudo mkdir -p $(dirname "$HOOK_SCRIPT")" >&2
        echo "  sudo install -m 755 ${SCRIPT_DIR}/droste-oci-hook.sh ${HOOK_SCRIPT}" >&2
        exit 1
    fi

    # Verify OCI image exists
    local engine
    engine=$(detect_container_cmd)
    if ! image_exists "$engine" "$image"; then
        echo "Error: OCI image not found: ${image}" >&2
        echo "Pull it first: ${engine} pull <registry>/${image}" >&2
        exit 1
    fi

    # Create directory structure
    mkdir -p "${lxc_dir}"/{rootfs,upper,work}

    # Write image reference
    echo "$image" > "${lxc_dir}/droste-image"

    # Resolve and write layer paths (so the hook doesn't need podman)
    local lowerdir
    lowerdir=$(get_lowerdir "$engine" "$image")
    if [[ -z "$lowerdir" ]]; then
        echo "Error: failed to resolve layer paths for ${image}" >&2
        rm -rf "$lxc_dir"
        exit 1
    fi
    echo "$lowerdir" > "${lxc_dir}/droste-layers"

    # Generate config
    generate_config "$name" "$bridge" "$memory" "$cores" "$nesting" \
        > "${lxc_dir}/config"

    echo ""
    echo "Container created: ${name}"
    echo "  Image:   ${image}"
    echo "  Engine:  ${engine}"
    echo "  Bridge:  ${bridge}"
    if [[ "$memory" != "0" ]]; then
        echo "  Memory:  ${memory} MB"
    fi
    if [[ "$cores" != "0" ]]; then
        echo "  Cores:   ${cores}"
    fi
    echo "  Nesting: ${nesting}"
    echo "  Config:  ${lxc_dir}/config"

    if $start; then
        echo ""
        echo "Starting container..."
        lxc-start -n "$name"
        echo "  Status: running"
    else
        echo "  Status: stopped (use 'lxc-start -n ${name}' to boot)"
    fi
}

# ── Destroy ─────────────────────────────────────────────────────────
do_destroy() {
    if [[ $# -lt 1 ]]; then
        echo "Error: destroy requires <name>" >&2
        usage >&2
        exit 1
    fi

    local name="$1"
    local lxc_dir="${LXC_BASE}/${name}"

    require_root

    if [[ ! -d "$lxc_dir" ]]; then
        echo "Error: container not found: ${name}" >&2
        exit 1
    fi

    if [[ ! -f "${lxc_dir}/droste-image" ]]; then
        echo "Error: ${name} is not an OCI-backed droste container" >&2
        exit 1
    fi

    # Stop if running
    if lxc-info -n "$name" -s 2>/dev/null | grep -q RUNNING; then
        echo "Stopping container..."
        lxc-stop -n "$name"
    fi

    # Unmount rootfs if mounted
    if mountpoint -q "${lxc_dir}/rootfs" 2>/dev/null; then
        umount "${lxc_dir}/rootfs" || true
    fi

    # Release OCI image mount
    local image engine
    image=$(cat "${lxc_dir}/droste-image")
    engine=$(detect_container_cmd)
    if [[ "$engine" == "podman" ]]; then
        podman image unmount "$image" >/dev/null 2>&1 || true
    fi

    # Remove container directory
    rm -rf "$lxc_dir"

    echo "Container destroyed: ${name}"
}

# ── List ────────────────────────────────────────────────────────────
do_list() {
    local found=false

    printf "%-20s %-30s %-10s %s\n" "NAME" "IMAGE" "STATUS" "UPPER SIZE"
    printf "%-20s %-30s %-10s %s\n" "----" "-----" "------" "----------"

    for image_file in "${LXC_BASE}"/*/droste-image; do
        [[ -f "$image_file" ]] || continue
        found=true

        local lxc_dir name image status upper_size
        lxc_dir=$(dirname "$image_file")
        name=$(basename "$lxc_dir")
        image=$(cat "$image_file")

        if lxc-info -n "$name" -s 2>/dev/null | grep -q RUNNING; then
            status="running"
        else
            status="stopped"
        fi

        if [[ -d "${lxc_dir}/upper" ]]; then
            upper_size=$(du -sh "${lxc_dir}/upper" 2>/dev/null | cut -f1)
        else
            upper_size="0"
        fi

        printf "%-20s %-30s %-10s %s\n" "$name" "$image" "$status" "$upper_size"
    done

    if ! $found; then
        echo "(no OCI-backed droste containers found)"
    fi
}

# ── Reset ───────────────────────────────────────────────────────────
do_reset() {
    if [[ $# -lt 1 ]]; then
        echo "Error: reset requires <name>" >&2
        usage >&2
        exit 1
    fi

    local name="$1"
    local lxc_dir="${LXC_BASE}/${name}"

    require_root

    if [[ ! -d "$lxc_dir" ]]; then
        echo "Error: container not found: ${name}" >&2
        exit 1
    fi

    if [[ ! -f "${lxc_dir}/droste-image" ]]; then
        echo "Error: ${name} is not an OCI-backed droste container" >&2
        exit 1
    fi

    # Refuse if running
    if lxc-info -n "$name" -s 2>/dev/null | grep -q RUNNING; then
        echo "Error: container is running. Stop it first: lxc-stop -n ${name}" >&2
        exit 1
    fi

    # Unmount rootfs if mounted
    if mountpoint -q "${lxc_dir}/rootfs" 2>/dev/null; then
        umount "${lxc_dir}/rootfs" || true
    fi

    # Clear writable layer
    rm -rf "${lxc_dir:?}/upper" "${lxc_dir:?}/work"
    mkdir -p "${lxc_dir}/upper" "${lxc_dir}/work"

    echo "Container reset: ${name}"
    echo "  Writable layer cleared. Next start will use clean OCI state."
}

# ── Command dispatch ────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    create)   do_create "$@" ;;
    destroy)  do_destroy "$@" ;;
    list)     do_list ;;
    reset)    do_reset "$@" ;;
    -h|--help|help)  usage ;;
    *)
        echo "Error: unknown command: ${COMMAND}" >&2
        usage >&2
        exit 1
        ;;
esac
