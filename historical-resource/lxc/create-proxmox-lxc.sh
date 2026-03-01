#!/usr/bin/env bash
# Create a Proxmox LXC container for kanibako, then provision it with the
# existing Ansible playbook via pct exec (synchronous — no cloud-init needed).
#
# Prerequisites: Proxmox VE host with pct, pvesh, and pveam available.
#
# Usage:
#   create-proxmox-lxc.sh --ssh-key ~/.ssh/id_ed25519.pub --start
#   create-proxmox-lxc.sh --ssh-key ~/.ssh/id.pub --claude --start
set -euo pipefail

PLAYBOOK_REL="host-definitions/ansible/playbook.yml"

# ── Defaults ────────────────────────────────────────────────────────
CTID=""
CT_NAME="kanibako"
MEMORY=4096
SWAP=512
CORES=2
DISK_SIZE=32
STORAGE="local-lvm"
TEMPLATE_STORAGE="local"
BRIDGE="vmbr0"
IP_CONFIG="dhcp"
GW_CONFIG=""
SSH_KEY_FILE=""
INSTALL_CLAUDE="false"
KANIBAKO_REPO="https://github.com/doctorjei/kanibako.git"
KANIBAKO_BRANCH="main"
TEMPLATE=""
PRIVILEGED=false
APPARMOR_UNCONFINED=false
START_CT=false
MOUNT_POINTS=()

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create a Proxmox LXC container provisioned with kanibako via Ansible.

Options:
  --ctid ID          Container ID (default: auto-detect next available)
  --name NAME        Hostname (default: kanibako)
  --memory MB        Memory in MB (default: 4096)
  --swap MB          Swap in MB (default: 512)
  --cores N          CPU cores (default: 2)
  --disk-size GB     Root filesystem size in GB (default: 32)
  --storage STORE    Proxmox storage for rootfs (default: local-lvm)
  --template-storage STORE
                     Proxmox storage for templates (default: local)
  --bridge BRIDGE    Network bridge (default: vmbr0)
  --ip CIDR          Static IP, e.g. 192.168.0.50/24 (default: dhcp)
  --gw ADDRESS       Gateway for static IP
  --ssh-key FILE     Path to SSH public key file (required)
  --claude           Also install kanibako-plugin-claude
  --repo URL         Git repository URL (default: upstream GitHub)
  --branch REF       Git branch or tag (default: main)
  --template TPL     LXC template (default: auto-detect Ubuntu 24.04)
  --privileged       Create privileged container (default: unprivileged)
  --apparmor-unconfined
                     Set AppArmor profile to unconfined (for podman)
  --mp HOST:CT       Bind mount point, repeatable (e.g. /data:/mnt/data)
  --start            Start and provision after creation
  -h, --help         Show this help message
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ctid)    CTID="$2"; shift 2 ;;
        --name)    CT_NAME="$2"; shift 2 ;;
        --memory)  MEMORY="$2"; shift 2 ;;
        --swap)    SWAP="$2"; shift 2 ;;
        --cores)   CORES="$2"; shift 2 ;;
        --disk-size) DISK_SIZE="$2"; shift 2 ;;
        --storage) STORAGE="$2"; shift 2 ;;
        --template-storage) TEMPLATE_STORAGE="$2"; shift 2 ;;
        --bridge)  BRIDGE="$2"; shift 2 ;;
        --ip)      IP_CONFIG="$2"; shift 2 ;;
        --gw)      GW_CONFIG="$2"; shift 2 ;;
        --ssh-key) SSH_KEY_FILE="$2"; shift 2 ;;
        --claude)  INSTALL_CLAUDE="true"; shift ;;
        --repo)    KANIBAKO_REPO="$2"; shift 2 ;;
        --branch)  KANIBAKO_BRANCH="$2"; shift 2 ;;
        --template) TEMPLATE="$2"; shift 2 ;;
        --privileged) PRIVILEGED=true; shift ;;
        --apparmor-unconfined) APPARMOR_UNCONFINED=true; shift ;;
        --mp)      MOUNT_POINTS+=("$2"); shift 2 ;;
        --start)   START_CT=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Validate required arguments ─────────────────────────────────────
if [[ -z "$SSH_KEY_FILE" ]]; then
    echo "Error: --ssh-key is required" >&2
    usage >&2
    exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
    echo "Error: SSH key file not found: $SSH_KEY_FILE" >&2
    exit 1
fi

for cmd in pct pvesh pveam; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found — run this on a Proxmox VE host" >&2
        exit 1
    fi
done

# ── Auto-detect CTID ───────────────────────────────────────────────
if [[ -z "$CTID" ]]; then
    CTID=$(pvesh get /cluster/nextid)
    echo "Auto-detected CTID: $CTID"
fi

# ── Resolve LXC template ──────────────────────────────────────────
if [[ -z "$TEMPLATE" ]]; then
    echo "Updating template index..."
    pveam update >/dev/null 2>&1 || true

    TEMPLATE=$(pveam available --section system \
        | awk '/ubuntu-24.04/ { print $2 }' \
        | sort -V \
        | tail -n1)

    if [[ -z "$TEMPLATE" ]]; then
        echo "Error: could not find an Ubuntu 24.04 template" >&2
        echo "List available templates with: pveam available --section system" >&2
        exit 1
    fi
    echo "Selected template: $TEMPLATE"
fi

# Download template if not already cached
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
    echo "Downloading template ${TEMPLATE}..."
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
else
    echo "Template already cached: $TEMPLATE"
fi

TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

# ── Build pct create command ────────────────────────────────────────
PCT_ARGS=(
    "$CTID" "$TEMPLATE_PATH"
    --hostname "$CT_NAME"
    --memory "$MEMORY"
    --swap "$SWAP"
    --cores "$CORES"
    --rootfs "${STORAGE}:${DISK_SIZE}"
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}${GW_CONFIG:+,gw=${GW_CONFIG}}"
    --ostype ubuntu
    --features "nesting=1,fuse=1,keyctl=1"
    --ssh-public-keys "$SSH_KEY_FILE"
    --onboot 0
)

if $PRIVILEGED; then
    PCT_ARGS+=(--unprivileged 0)
else
    PCT_ARGS+=(--unprivileged 1)
fi

# Add bind mount points (mp0, mp1, ...)
for i in "${!MOUNT_POINTS[@]}"; do
    mp_spec="${MOUNT_POINTS[$i]}"
    host_path="${mp_spec%%:*}"
    ct_path="${mp_spec#*:}"
    PCT_ARGS+=("--mp${i}" "${host_path},mp=${ct_path}")
done

echo "Creating container ${CTID} (${CT_NAME})..."
pct create "${PCT_ARGS[@]}"

# ── Post-creation LXC config tweaks ────────────────────────────────
LXC_CONF="/etc/pve/lxc/${CTID}.conf"

if ! $PRIVILEGED; then
    # Allow /dev/fuse inside unprivileged container (for fuse-overlayfs)
    cat >> "$LXC_CONF" <<'EOF'
lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file 0 0
lxc.cgroup2.devices.allow: c 10:229 rwm
EOF
    echo "Added /dev/fuse passthrough to LXC config"
fi

if $APPARMOR_UNCONFINED; then
    echo "lxc.apparmor.profile: unconfined" >> "$LXC_CONF"
    echo "Set AppArmor profile to unconfined"
fi

echo "Container ${CTID} created."

# ── Start and provision ─────────────────────────────────────────────
if ! $START_CT; then
    echo ""
    echo "Container created but not started."
    echo "Start and provision manually:"
    echo "  pct start ${CTID}"
    echo "  # Then run the ansible provisioning steps"
    exit 0
fi

echo "Starting container ${CTID}..."
pct start "$CTID"

# Wait for network to come up
echo "Waiting for network..."
for attempt in $(seq 1 30); do
    if pct exec "$CTID" -- \
        sh -c 'ip -4 addr show dev eth0 | grep -q "inet "' 2>/dev/null; then
        break
    fi
    if [[ "$attempt" -eq 30 ]]; then
        echo "Error: container network did not come up within 60 seconds" >&2
        exit 1
    fi
    sleep 2
done
echo "Network is up."

# ── Install ansible + git inside the container ─────────────────────
echo "Installing ansible-core and git inside container..."
pct exec "$CTID" -- bash -c \
    'apt-get update -qq && apt-get install -y -qq ansible-core git'

# ── Run ansible-pull to provision ──────────────────────────────────
echo "Running ansible-pull to provision kanibako..."
pct exec "$CTID" -- bash -c "\
    ansible-pull \
        -U '${KANIBAKO_REPO}' \
        -C '${KANIBAKO_BRANCH}' \
        -e 'install_claude_plugin=${INSTALL_CLAUDE}' \
        '${PLAYBOOK_REL}'"

# ── Inject SSH key for agent user ──────────────────────────────────
echo "Injecting SSH key for agent user..."
pct exec "$CTID" -- mkdir -p /home/agent/.ssh
pct push "$CTID" "$SSH_KEY_FILE" /tmp/ssh_key_import
pct exec "$CTID" -- bash -c "\
    cat /tmp/ssh_key_import >> /home/agent/.ssh/authorized_keys && \
    rm -f /tmp/ssh_key_import && \
    chmod 700 /home/agent/.ssh && \
    chmod 600 /home/agent/.ssh/authorized_keys && \
    chown -R agent:agent /home/agent/.ssh"

# ── Verify rootless podman ──────────────────────────────────────────
echo "Verifying rootless podman..."
if pct exec "$CTID" -- \
    su - agent -c 'podman run --rm alpine echo "podman works"'; then
    echo "Rootless podman verification passed."
else
    echo "Warning: rootless podman verification failed." >&2
    echo "Possible causes:" >&2
    echo "  - No internet (alpine image can't be pulled)" >&2
    echo "  - AppArmor blocking (try --apparmor-unconfined)" >&2
    echo "  - Unprivileged restrictions (try --privileged)" >&2
fi

# ── Summary ─────────────────────────────────────────────────────────
CT_IP=$(pct exec "$CTID" -- \
    sh -c "ip -4 addr show dev eth0 \
        | grep -oP 'inet \K[0-9.]+'" 2>/dev/null || echo "<pending>")

echo ""
echo "Summary:"
echo "  CTID:    $CTID"
echo "  Name:    $CT_NAME"
echo "  Memory:  ${MEMORY} MB"
echo "  Swap:    ${SWAP} MB"
echo "  Cores:   $CORES"
echo "  Disk:    ${DISK_SIZE} GB"
echo "  SSH key: $SSH_KEY_FILE"
echo "  Claude:  $INSTALL_CLAUDE"
echo "  IP:      $CT_IP"
echo ""
echo "Connect:"
echo "  ssh agent@${CT_IP}"
echo "  pct enter ${CTID}"
