#!/usr/bin/env bash
# Build, test, and manage droste images.
#
# Usage:
#   scripts/build.sh                          # build and test droste-thread
#   scripts/build.sh thread build             # just build droste-thread
#   scripts/build.sh yarn                     # build and test droste-yarn
#   scripts/build.sh yarn test                # boot and smoke test droste-yarn
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

trap 'echo ""; echo "--- build.sh finished at $(date "+%Y-%m-%d %H:%M:%S") ---"' EXIT

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [IMAGE] [COMMAND] [OPTIONS]

Build and test droste images.

Images:
  thread     Container-ready base image (default)
  yarn       VM-capable image (builds on top of thread)
  fabric     HA/storage/cluster image (builds on top of yarn)
  tapestry   Testing/benchmarking/security image (builds on top of fabric)
  loom       Development/build toolchain image (builds on top of tapestry)
  jacquard   Proxmox VE testing environment (builds on top of loom)
  all        All tiers

Commands:
  prereqs    Check build host prerequisites
  build      Build the image(s) with Packer
  test       Boot existing image(s) and run smoke tests
  all        Prereqs + build + test (default)
  help       Show this help message

Options:
  --force          Overwrite existing images (required for 'all build')
  --ssh-key FILE   Path to SSH public key (default: auto-detect)
  --ssh-port PORT  Host port for SSH (default: 2222)

Examples:
  $(basename "$0")                          # build and test thread (default)
  $(basename "$0") thread build             # just build thread
  $(basename "$0") yarn                     # prereqs + build + test yarn
  $(basename "$0") all test                 # smoke test all tiers
  $(basename "$0") all build                # build all tiers
  $(basename "$0") yarn test --ssh-key ~/.ssh/id_ed25519.pub
EOF
}

# ── Prereqs ─────────────────────────────────────────────────────────
do_prereqs() {
    echo "Checking prerequisites..."
    echo ""
    "$SCRIPT_DIR/check-prereqs.sh"
}

# ── Build (thread) ───────────────────────────────────────────────────
do_build_thread() {
    echo "Building droste-thread image..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-thread"
    packer init .
    packer build -force droste-thread.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-thread/droste-thread.qcow2"
}

# ── Build (yarn) ─────────────────────────────────────────────────────
do_build_yarn() {
    local base_image="$PROJECT_DIR/output-droste-thread/droste-thread.qcow2"
    if [[ ! -f "$base_image" ]]; then
        echo "droste-thread.qcow2 not found, building thread first..."
        echo ""
        do_build_thread
        echo ""
    fi

    echo "Building droste-yarn image (on top of droste-thread)..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-yarn"
    packer init .
    packer build -force -var "base_image=$base_image" droste-yarn.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-yarn/droste-yarn.qcow2"
}

# ── Build (fabric) ──────────────────────────────────────────────────
do_build_fabric() {
    local base_image="$PROJECT_DIR/output-droste-yarn/droste-yarn.qcow2"
    if [[ ! -f "$base_image" ]]; then
        echo "droste-yarn.qcow2 not found, building yarn first..."
        echo ""
        do_build_yarn
        echo ""
    fi

    echo "Building droste-fabric image (on top of droste-yarn)..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-fabric"
    packer init .
    packer build -force -var "base_image=$base_image" droste-fabric.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-fabric/droste-fabric.qcow2"
}

# ── Build (tapestry) ───────────────────────────────────────────────
do_build_tapestry() {
    local base_image="$PROJECT_DIR/output-droste-fabric/droste-fabric.qcow2"
    if [[ ! -f "$base_image" ]]; then
        echo "droste-fabric.qcow2 not found, building fabric first..."
        echo ""
        do_build_fabric
        echo ""
    fi

    echo "Building droste-tapestry image (on top of droste-fabric)..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-tapestry"
    packer init .
    packer build -force -var "base_image=$base_image" droste-tapestry.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-tapestry/droste-tapestry.qcow2"
}

# ── Build (loom) ──────────────────────────────────────────────────
do_build_loom() {
    local base_image="$PROJECT_DIR/output-droste-tapestry/droste-tapestry.qcow2"
    if [[ ! -f "$base_image" ]]; then
        echo "droste-tapestry.qcow2 not found, building tapestry first..."
        echo ""
        do_build_tapestry
        echo ""
    fi

    echo "Building droste-loom image (on top of droste-tapestry)..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-loom"
    packer init .
    packer build -force -var "base_image=$base_image" droste-loom.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-loom/droste-loom.qcow2"
}

# ── Build (jacquard) ──────────────────────────────────────────────
do_build_jacquard() {
    local base_image="$PROJECT_DIR/output-droste-loom/droste-loom.qcow2"
    if [[ ! -f "$base_image" ]]; then
        echo "droste-loom.qcow2 not found, building loom first..."
        echo ""
        do_build_loom
        echo ""
    fi

    echo "Building droste-jacquard image (on top of droste-loom)..."
    echo ""

    cd "$PROJECT_DIR/packer/droste-jacquard"
    packer init .
    packer build -force -var "base_image=$base_image" droste-jacquard.pkr.hcl

    echo ""
    echo "Build complete."
    ls -lh "$PROJECT_DIR/output-droste-jacquard/droste-jacquard.qcow2"
    ls -lh "$PROJECT_DIR/output-droste-jacquard/droste-jacquard-diff.qcow2"
}

# ── Test ────────────────────────────────────────────────────────────
do_test() {
    local image_type="$1"
    shift

    local ssh_key=""
    local ssh_port=2222

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssh-key)  ssh_key="$2"; shift 2 ;;
            --ssh-port) ssh_port="$2"; shift 2 ;;
            *)          echo "Unknown test option: $1" >&2; exit 1 ;;
        esac
    done

    # Auto-detect SSH key if not provided
    if [[ -z "$ssh_key" ]]; then
        for candidate in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
            if [[ -f "$candidate" ]]; then
                ssh_key="$candidate"
                break
            fi
        done
        if [[ -z "$ssh_key" ]]; then
            echo "Error: no SSH public key found. Use --ssh-key FILE." >&2
            exit 1
        fi
        echo "Using SSH key: $ssh_key"
    fi

    # Select image path
    local image
    case "$image_type" in
        thread)   image="$PROJECT_DIR/output-droste-thread/droste-thread.qcow2" ;;
        yarn)     image="$PROJECT_DIR/output-droste-yarn/droste-yarn.qcow2" ;;
        fabric)   image="$PROJECT_DIR/output-droste-fabric/droste-fabric.qcow2" ;;
        tapestry) image="$PROJECT_DIR/output-droste-tapestry/droste-tapestry.qcow2" ;;
        loom)     image="$PROJECT_DIR/output-droste-loom/droste-loom.qcow2" ;;
        jacquard) image="$PROJECT_DIR/output-droste-jacquard/droste-jacquard.qcow2" ;;
    esac

    if [[ ! -f "$image" ]]; then
        echo "Error: image not found at $image" >&2
        echo "Run '$(basename "$0") $image_type build' first." >&2
        exit 1
    fi

    local private_key="${ssh_key%.pub}"
    if [[ ! -f "$private_key" ]]; then
        echo "Error: private key not found: $private_key" >&2
        exit 1
    fi

    echo "Booting image for smoke test..."
    echo ""

    # Kill any stale QEMU from a previous run
    local work_dir="${XDG_CACHE_HOME:-$HOME/.cache}/droste-boot"
    local pidfile="${work_dir}/droste.pid"
    if [[ -f "$pidfile" ]]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    fi
    rm -f "${work_dir}/droste-ephemeral.qcow2"

    # Boot in background
    "$SCRIPT_DIR/boot-droste.sh" \
        --ssh-key "$ssh_key" \
        --ssh-port "$ssh_port" \
        --image "$image" \
        --daemonize

    # Wait for SSH to become available
    echo "Waiting for SSH..."
    local retries=30
    while ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -o LogLevel=ERROR -o ConnectTimeout=2 \
              -p "$ssh_port" -i "$private_key" agent@localhost true &>/dev/null; do
        ((retries--))
        if [[ $retries -le 0 ]]; then
            echo "Error: SSH did not become available" >&2
            exit 1
        fi
        sleep 2
    done
    echo "SSH is up."
    echo ""

    # Run smoke tests for this tier
    "$SCRIPT_DIR/ssh-smoke-test.sh" \
        --port "$ssh_port" \
        --ssh-key "$private_key" \
        "$PROJECT_DIR/checks/${image_type}.checks"

    # Clean up — kill QEMU
    local pidfile="${XDG_CACHE_HOME:-$HOME/.cache}/droste-boot/droste.pid"
    if [[ -f "$pidfile" ]]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    fi

    echo ""
    echo "Test complete. VM stopped."
}

# ── Tier order ────────────────────────────────────────────────────────
ALL_TIERS=(thread yarn fabric tapestry loom jacquard)

# ── Parse image and command ──────────────────────────────────────────
IMAGE="thread"
COMMAND="all"
FORCE=false

if [[ $# -gt 0 ]]; then
    case "$1" in
        prereqs|build|test|help|-h|--help)
            COMMAND="$1"
            shift
            ;;
        thread|yarn|fabric|tapestry|loom|jacquard|all)
            IMAGE="$1"
            shift
            COMMAND="${1:-all}"
            if [[ $# -gt 0 ]]; then shift; fi
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
fi

# ── Parse global options ─────────────────────────────────────────────
REMAINING=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true; shift ;;
        *)       REMAINING+=("$1"); shift ;;
    esac
done
set -- ${REMAINING+"${REMAINING[@]}"}

# ── Guard: refuse to overwrite existing images without --force ────────
check_existing_images() {
    local found=()
    for tier in $(resolve_tiers); do
        local dir="$PROJECT_DIR/output-droste-${tier}"
        for img in "$dir"/*.qcow2; do
            [[ -f "$img" ]] && found+=("$img")
        done
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        echo "Error — Image(s) present:" >&2
        for img in "${found[@]}"; do
            echo "  $img" >&2
        done
        echo "" >&2
        echo "To overwrite existing images, run: $(basename "$0") $IMAGE $COMMAND --force" >&2
        exit 1
    fi
}

# ── Helpers for "all" image target ────────────────────────────────────
do_build_image() {
    case "$1" in
        thread)   do_build_thread ;;
        yarn)     do_build_yarn ;;
        fabric)   do_build_fabric ;;
        tapestry) do_build_tapestry ;;
        loom)     do_build_loom ;;
        jacquard) do_build_jacquard ;;
    esac
}

resolve_tiers() {
    if [[ "$IMAGE" == "all" ]]; then
        echo "${ALL_TIERS[@]}"
    else
        echo "$IMAGE"
    fi
}

# ── Main ────────────────────────────────────────────────────────────
case "$COMMAND" in
    all)
        do_prereqs
        if [[ "$IMAGE" == "all" && "$FORCE" == false ]]; then
            check_existing_images
        fi
        for tier in $(resolve_tiers); do
            echo ""
            do_build_image "$tier"
        done
        for tier in $(resolve_tiers); do
            echo ""
            do_test "$tier" "$@"
        done
        ;;
    prereqs)
        do_prereqs
        ;;
    build)
        if [[ "$IMAGE" == "all" && "$FORCE" == false ]]; then
            check_existing_images
        fi
        for tier in $(resolve_tiers); do
            do_build_image "$tier"
        done
        ;;
    test)
        for tier in $(resolve_tiers); do
            do_test "$tier" "$@"
        done
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage >&2
        exit 1
        ;;
esac
