#!/usr/bin/env bash
# LXC hook for OCI-backed droste containers.
#
# Reads pre-resolved OCI layer paths from droste-layers and composes
# an overlayfs rootfs on pre-start. Unmounts on post-stop.
#
# The layer paths are resolved at container creation time by
# droste-oci-lxc.sh (via podman/docker inspect) and written to
# /var/lib/lxc/<name>/droste-layers. This avoids calling podman
# from the hook, which fails in LXC's restricted mount namespace.
#
# Install to: /usr/local/lib/droste/droste-oci-hook.sh
#
# LXC config entries:
#   lxc.hook.version = 1
#   lxc.hook.pre-start = /usr/local/lib/droste/droste-oci-hook.sh
#   lxc.hook.post-stop = /usr/local/lib/droste/droste-oci-hook.sh
set -euo pipefail

# ── Hook dispatch ───────────────────────────────────────────────────
# Hook version 1: LXC_NAME, LXC_HOOK_TYPE set in environment
# Hook version 0: $1=name, $3=hook type
if [[ -n "${LXC_NAME:-}" ]]; then
    NAME="$LXC_NAME"
    HOOK_TYPE="${LXC_HOOK_TYPE:-}"
else
    NAME="${1:-}"
    HOOK_TYPE="${3:-}"
fi

if [[ -z "$NAME" ]]; then
    echo "Error: container name not provided" >&2
    exit 1
fi

LXC_DIR="/var/lib/lxc/${NAME}"
LAYERS_FILE="${LXC_DIR}/droste-layers"

if [[ ! -f "$LAYERS_FILE" ]]; then
    echo "Error: ${LAYERS_FILE} not found" >&2
    exit 1
fi

case "$HOOK_TYPE" in
    pre-start)
        lowerdir=$(cat "$LAYERS_FILE")
        if [[ -z "$lowerdir" ]]; then
            echo "Error: ${LAYERS_FILE} is empty" >&2
            exit 1
        fi

        mkdir -p "${LXC_DIR}/upper" "${LXC_DIR}/work" "${LXC_DIR}/rootfs"

        # Use mount(2) syscall directly via python3. The modern mount(8)
        # command uses fsconfig(2) which rejects colon-separated lowerdir
        # paths on kernel 6.x. The legacy mount(2) syscall handles them.
        mount_opts="lowerdir=${lowerdir},upperdir=${LXC_DIR}/upper,workdir=${LXC_DIR}/work"
        python3 -c "
import ctypes, ctypes.util, sys, os
libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
r = libc.mount(b'overlay', sys.argv[1].encode(), b'overlay', 0, sys.argv[2].encode())
if r != 0: print('overlay mount failed: ' + os.strerror(ctypes.get_errno()), file=sys.stderr); sys.exit(1)
" "${LXC_DIR}/rootfs" "$mount_opts"
        ;;

    post-stop)
        if mountpoint -q "${LXC_DIR}/rootfs" 2>/dev/null; then
            umount "${LXC_DIR}/rootfs" || true
        fi
        ;;

    *)
        echo "Error: unknown hook type: ${HOOK_TYPE}" >&2
        exit 1
        ;;
esac
