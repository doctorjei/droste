#!/usr/bin/env bash
# Build LXC overlay tarballs for droste tiers.
#
# Each tier produces an overlay-only tarball (just the delta from previous
# tiers). At runtime, stack layers with overlayfs to compose any tier level.
# Seed is the full base; every tier above is overlay-only.
#
# Usage:
#   lxc/build-rootfs.sh fiber   # Build fiber overlay on seed
#   lxc/build-rootfs.sh all     # Build all tiers sequentially
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/output"
QUIET=false

# Tier chain: each tier lists its prerequisites (bottom to top)
declare -A TIER_LAYERS
TIER_LAYERS[fiber]="seed"
TIER_LAYERS[sheet]="seed fiber"
TIER_LAYERS[page]="seed fiber sheet"
TIER_LAYERS[tome]="seed fiber sheet page"
TIER_LAYERS[press]="seed fiber sheet page tome"
TIER_LAYERS[gutenberg]="seed fiber sheet page tome press"

ALL_TIERS=(fiber sheet page tome press gutenberg)

usage() {
    cat <<EOF
Usage: $(basename "$0") TIER [OPTIONS]

Build LXC overlay tarballs for droste tiers.

Each tier produces an overlay-only tarball containing just the changes
from the previous tier. Stack layers with overlayfs at runtime.

Tiers:
  fiber      Thread equivalent (tools, containers, networking)
  sheet      Yarn equivalent (VM/storage tooling)
  page       Fabric equivalent (HA, clustering, Ceph)
  tome       Tapestry equivalent (testing, security, observability)
  press      Loom equivalent (C/C++ dev toolchain)
  gutenberg  Empty cap layer on press
  all        Build all tiers sequentially

Options:
  --quiet    Suppress provision script output (show only on failure)

Requires droste-seed.tar.xz in output/ (built by build-seed.sh).
Each tier requires all previous tier overlay tarballs in output/.

Output:
  output/droste-TIER.tar.xz   Overlay tarball (delta only)
EOF
}

# ── Common overlay build function ────────────────────────────────────
# Usage: do_overlay_build TIER_NAME PROVISION_SCRIPT [PRE_PROVISION_HOOK]
#
# Extracts all prerequisite layers, mounts overlayfs, runs provision
# in chroot, tars only the upper dir (delta).
do_overlay_build() {
    local tier="$1"
    local provision_script="$2"
    local pre_provision_hook="${3:-}"
    local layers="${TIER_LAYERS[$tier]}"

    # Verify all prerequisite layers exist
    for layer in $layers; do
        local tarball
        if [[ "$layer" == "seed" ]]; then
            tarball="$OUTPUT_DIR/droste-seed.tar.xz"
        else
            tarball="$OUTPUT_DIR/droste-${layer}.tar.xz"
        fi
        if [[ ! -f "$tarball" ]]; then
            echo "Error: $layer tarball not found at $tarball" >&2
            echo "Build prerequisite tiers first." >&2
            exit 1
        fi
    done

    if [[ $EUID -ne 0 ]]; then
        echo "Error: $tier build requires root (for overlayfs, chroot, bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-${tier}.XXXXXX")

    cleanup_overlay() {
        # Unmount in reverse order
        mountpoint -q "$work_dir/merged/dev/pts" 2>/dev/null && umount "$work_dir/merged/dev/pts" || true
        mountpoint -q "$work_dir/merged/dev"     2>/dev/null && umount "$work_dir/merged/dev"     || true
        mountpoint -q "$work_dir/merged/proc"    2>/dev/null && umount "$work_dir/merged/proc"    || true
        mountpoint -q "$work_dir/merged/sys"     2>/dev/null && umount "$work_dir/merged/sys"     || true
        mountpoint -q "$work_dir/merged"         2>/dev/null && umount "$work_dir/merged"         || true
        rm -rf "$work_dir"
    }
    trap cleanup_overlay EXIT

    # Create directory structure
    mkdir -p "$work_dir"/{layers,upper,work,merged}

    # Extract each layer into its own directory
    for layer in $layers; do
        local tarball layer_dir="$work_dir/layers/$layer"
        mkdir -p "$layer_dir"
        if [[ "$layer" == "seed" ]]; then
            tarball="$OUTPUT_DIR/droste-seed.tar.xz"
            echo "Extracting seed (base layer)..."
        else
            tarball="$OUTPUT_DIR/droste-${layer}.tar.xz"
            echo "Extracting $layer overlay..."
        fi
        tar -xf "$tarball" -C "$layer_dir"
    done

    # Build lowerdir string (topmost layer first)
    local lowerdir=""
    local layers_array=($layers)
    for (( i=${#layers_array[@]}-1; i>=0; i-- )); do
        if [[ -n "$lowerdir" ]]; then
            lowerdir="$lowerdir:"
        fi
        lowerdir="$lowerdir$work_dir/layers/${layers_array[$i]}"
    done

    echo "Mounting overlayfs (${#layers_array[@]} lower layers)..."
    mount -t overlay overlay \
        -o "lowerdir=$lowerdir,upperdir=$work_dir/upper,workdir=$work_dir/work" \
        "$work_dir/merged"

    # Bind mounts for chroot
    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/merged/dev"
    mount --bind /proc "$work_dir/merged/proc"
    mount --bind /sys "$work_dir/merged/sys"
    mount -t devpts devpts "$work_dir/merged/dev/pts"

    # DNS resolution inside chroot
    rm -f "$work_dir/merged/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/merged/etc/resolv.conf"

    # Run optional pre-provision hook (e.g., copy files into chroot)
    if [[ -n "$pre_provision_hook" ]]; then
        eval "$pre_provision_hook"
    fi

    # Write and run provision script
    cat > "$work_dir/merged/tmp/provision.sh" <<PROVISION_EOF
$provision_script
PROVISION_EOF
    chmod +x "$work_dir/merged/tmp/provision.sh"

    echo "Running provision script in chroot..."
    if [[ "$QUIET" == true ]]; then
        local logfile="/tmp/droste-provision-${tier}.log"
        if ! chroot "$work_dir/merged" /tmp/provision.sh > "$logfile" 2>&1; then
            echo ""
            echo "Provision failed. Full output:"
            cat "$logfile"
            rm -f "$logfile"
            exit 1
        fi
        rm -f "$logfile"
    else
        chroot "$work_dir/merged" /tmp/provision.sh
    fi

    # Unmount bind mounts and overlay
    echo "Cleaning up mounts..."
    umount "$work_dir/merged/dev/pts"
    umount "$work_dir/merged/dev"
    umount "$work_dir/merged/proc"
    umount "$work_dir/merged/sys"
    umount "$work_dir/merged"

    # Tar only the upper dir (the delta)
    echo "Creating overlay tarball (delta only)..."
    mkdir -p "$OUTPUT_DIR"
    tar -cJf "$OUTPUT_DIR/droste-${tier}.tar.xz" -C "$work_dir/upper" .

    local size
    size=$(du -h "$OUTPUT_DIR/droste-${tier}.tar.xz" | cut -f1)
    echo ""
    echo "Output: $OUTPUT_DIR/droste-${tier}.tar.xz ($size)"

    # Clean up
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Fiber ────────────────────────────────────────────────────────────
do_build_fiber() {
    local pre_hook="
        cp '$PROJECT_DIR/ansible/files/pystrings' \"\$work_dir/merged/tmp/pystrings\"
        cp '$PROJECT_DIR/ansible/files/pyhttpd' \"\$work_dir/merged/tmp/pyhttpd\"
    "

    do_overlay_build fiber '#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Strip documentation ──────────────────────────────────────────
cat > /etc/dpkg/dpkg.cfg.d/01-nodoc <<'"'"'DPKG_CONF'"'"'
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/info/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/locale.alias
path-include /usr/share/locale/en*
path-include /usr/share/locale/zh*
path-include /usr/share/locale/hi*
path-include /usr/share/locale/es*
path-include /usr/share/locale/ar*
path-include /usr/share/locale/fr*
path-include /usr/share/locale/bn*
path-include /usr/share/locale/pt*
path-include /usr/share/locale/id*
path-include /usr/share/locale/ur*
path-include /usr/share/locale/de*
path-include /usr/share/locale/ja*
path-include /usr/share/locale/ko*
DPKG_CONF

rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name "en*" ! -name "zh*" ! -name "hi*" ! -name "es*" \
    ! -name "ar*" ! -name "fr*" ! -name "bn*" ! -name "pt*" \
    ! -name "id*" ! -name "ur*" ! -name "de*" ! -name "ja*" \
    ! -name "ko*" -exec rm -rf {} + 2>/dev/null || true

# ── Locales (before main install to avoid locale warnings) ────
apt-get update
apt-get install -y --no-install-recommends locales
cat >> /etc/locale.gen <<'"'"'LOCALE_LIST'"'"'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
zh_TW.UTF-8 UTF-8
hi_IN.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
ar_SA.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
bn_IN.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
pt_PT.UTF-8 UTF-8
id_ID.UTF-8 UTF-8
ur_PK.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
ja_JP.UTF-8 UTF-8
ko_KR.UTF-8 UTF-8
LOCALE_LIST
locale-gen

# ── Install packages ────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    lxc podman fuse-overlayfs slirp4netns uidmap systemd-container \
    iproute2 dnsmasq nftables ipcalc ipvsadm \
    sudo openssh-server \
    curl jq rsync tmux smbclient git wget make file \
    netcat-openbsd dnsutils tree unzip zip pipx htop patch bc \
    inetutils-telnet ssh-import-id molly-guard debootstrap sshpass xmlstarlet \
    lsof strace sysstat iotop iftop psmisc expect moreutils \
    rename entr jo whois sqlite3 atop etckeeper tftpd-hpa \
    cifs-utils nfs-common sshfs \
    acl attr \
    wireguard-tools \
    conntrack ipset \
    socat fping iputils-arping \
    parallel \
    dnstop fatrace inotify-tools \
    crudini \
    lxcfs \
    ltrace \
    pv \
    bsdextrautils xxd

# ── Python micro-tools ──────────────────────────────────────────
install -m 755 /tmp/pystrings /usr/local/bin/pystrings
install -m 755 /tmp/pyhttpd /usr/local/bin/pyhttpd
update-alternatives --install /usr/bin/strings strings /usr/local/bin/pystrings 10
update-alternatives --install /usr/bin/httpd httpd /usr/local/bin/pyhttpd 10
rm -f /tmp/pystrings /tmp/pyhttpd

# ── Droste user ─────────────────────────────────────────────────
existing_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -n "$existing_user" ] && [ "$existing_user" != "droste" ]; then
    userdel -r "$existing_user"
fi
existing_group=$(getent group 1000 | cut -d: -f1 || true)
if [ -n "$existing_group" ] && [ "$existing_group" != "droste" ]; then
    groupdel "$existing_group"
fi
groupadd -g 1000 droste 2>/dev/null || true
useradd -u 1000 -g droste -m -s /bin/bash droste 2>/dev/null || true
echo "droste:droste" | chpasswd
printf "droste ALL=(ALL) NOPASSWD:ALL\n" > /etc/sudoers.d/droste
chmod 0440 /etc/sudoers.d/droste

# ── Rootless Podman ──────────────────────────────────────────────
printf "droste:100000:65536\n" >> /etc/subuid
printf "droste:100000:65536\n" >> /etc/subgid
mkdir -p /home/droste/.config/containers
cat > /home/droste/.config/containers/storage.conf <<'"'"'STORAGE_CONF'"'"'
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
STORAGE_CONF
chown -R droste:droste /home/droste/.config

# ── SSH hardening ────────────────────────────────────────────────
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
systemctl enable ssh 2>/dev/null || true

# ── IP forwarding ────────────────────────────────────────────────
cat > /etc/sysctl.d/99-droste.conf <<'"'"'SYSCTL_CONF'"'"'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL_CONF

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
' "$pre_hook"
}

# ── Sheet ────────────────────────────────────────────────────────────
do_build_sheet() {
    do_overlay_build sheet '#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep "^ii" | wc -l)"

apt-get update
apt-get install -y --no-install-recommends \
    ansible gettext-base \
    squashfs-tools cloud-image-utils qemu-utils \
    dosfstools mtools ntfs-3g \
    gdisk parted btrfs-progs \
    cryptsetup mdadm \
    ncdu \
    hping3 bmon nethogs nicstat ethtool \
    lshw sysbench picocom \
    lvm2 thin-provisioning-tools nbd-client quota \
    pciutils hdparm dmidecode bridge-utils

echo "Packages after: $(dpkg -l | grep "^ii" | wc -l)"

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
'
}

# ── Page ─────────────────────────────────────────────────────────────
do_build_page() {
    do_overlay_build page '#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep "^ii" | wc -l)"

apt-get update

apt-get install -y --no-install-recommends \
    clustershell \
    pcs pacemaker pacemaker-cli-utils resource-agents \
    keepalived ebtables fence-agents-common \
    pxelinux syslinux-common \
    drbd-utils sbd dlm-controld \
    open-iscsi targetcli-fb multipath-tools

apt-get install -y --no-install-recommends ceph-common

echo "Packages after: $(dpkg -l | grep "^ii" | wc -l)"

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
'
}

# ── Tome ─────────────────────────────────────────────────────────────
do_build_tome() {
    do_overlay_build tome '#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep "^ii" | wc -l)"

apt-get update

apt-get install -y --no-install-recommends \
    openvswitch-switch nmap bird2 \
    haproxy apache2-utils \
    fio stress-ng iperf3 \
    buildah skopeo \
    prometheus-node-exporter lnav \
    postgresql-client redis-tools \
    lynis aide \
    arp-scan tcpreplay auditd \
    blktrace xorriso ipmitool \
    sg3-utils smartmontools apparmor-utils

apt-get install -y --no-install-recommends tshark
apt-get install -y --no-install-recommends qemu-system-arm

echo "Packages after: $(dpkg -l | grep "^ii" | wc -l)"

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
'
}

# ── Press ────────────────────────────────────────────────────────────
do_build_press() {
    do_overlay_build press '#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep "^ii" | wc -l)"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config \
    autoconf automake libtool \
    gdb valgrind \
    ccache ninja-build bear

echo "Packages after: $(dpkg -l | grep "^ii" | wc -l)"

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
'
}

# ── Gutenberg ────────────────────────────────────────────────────────
do_build_gutenberg() {
    # Empty cap layer — just create an empty overlay tarball
    for layer in ${TIER_LAYERS[gutenberg]}; do
        local tarball
        if [[ "$layer" == "seed" ]]; then
            tarball="$OUTPUT_DIR/droste-seed.tar.xz"
        else
            tarball="$OUTPUT_DIR/droste-${layer}.tar.xz"
        fi
        if [[ ! -f "$tarball" ]]; then
            echo "Error: $layer tarball not found at $tarball" >&2
            echo "Build prerequisite tiers first." >&2
            exit 1
        fi
    done

    echo "Creating gutenberg (empty cap layer)..."
    mkdir -p "$OUTPUT_DIR"

    # Create a tarball with just a marker file
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/droste-gutenberg.XXXXXX")
    mkdir -p "$tmp_dir/etc"
    echo "droste-gutenberg" > "$tmp_dir/etc/droste-tier"
    tar -cJf "$OUTPUT_DIR/droste-gutenberg.tar.xz" -C "$tmp_dir" .
    rm -rf "$tmp_dir"

    echo ""
    echo "Output: $OUTPUT_DIR/droste-gutenberg.tar.xz (empty cap)"
    ls -lh "$OUTPUT_DIR/droste-gutenberg.tar.xz"
}

# ── Parse options ────────────────────────────────────────────────────
TIER="${1:-}"
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet) QUIET=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Main ─────────────────────────────────────────────────────────────
case "$TIER" in
    fiber)     do_build_fiber ;;
    sheet)     do_build_sheet ;;
    page)      do_build_page ;;
    tome)      do_build_tome ;;
    press)     do_build_press ;;
    gutenberg) do_build_gutenberg ;;
    all)
        for tier in "${ALL_TIERS[@]}"; do
            echo ""
            echo "════════════════════════════════════════════════"
            echo "  Building droste-${tier}"
            echo "════════════════════════════════════════════════"
            echo ""
            "do_build_${tier}"
        done
        echo ""
        echo "All tiers built. Overlay tarballs in $OUTPUT_DIR/"
        ls -lh "$OUTPUT_DIR"/droste-*.tar.*
        ;;
    -h|--help) usage ;;
    *)
        if [[ -z "${1:-}" ]]; then
            usage
        else
            echo "Unknown tier: $1" >&2
            usage >&2
            exit 1
        fi
        ;;
esac
