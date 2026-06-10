# Droste

Nested virtualization images for testing infrastructure operations — containers, VMs, DRBD, Pacemaker, iSCSI, LXC, Proxmox VE, and more. Built on Debian 13 (Trixie) as layered OCI images in three variants: process containers, system containers ([kento](https://pypi.org/project/kento/)), and VM-bootable ([gemet](https://github.com/doctorjei/gemet) kernel).

## Image Formats

| Variant | Base | Use case | Init | Kernel |
|---------|------|----------|------|--------|
| **App** (paper) | [canopy](https://github.com/doctorjei/gemet) → seed | Process containers, CI/CD | None | Host kernel |
| **System** (cloth) | App + init/systemd | System containers via [kento](https://pypi.org/project/kento/) | systemd | Host kernel |
| **VM** (wool) | System + [gemet](https://github.com/doctorjei/gemet) kernel | VMs via [kento](https://pypi.org/project/kento/) VM mode | systemd | Own kernel |

## Tiers

Each tier builds on the previous one. Three lines: paper (light), cloth (medium), wool (heavy).

### App Tiers — paper/publishing (process containers)

| Tier | Based on | Focus | Pull size¹ |
|------|----------|-------|------------|
| **seed** | canopy (gemet) | Minimal OCI base | 196 MB |
| **fiber** | seed | Basic tools, containers, networking | 568 MB |
| **sheet** | fiber | Storage, VM tooling | 731 MB |
| **page** | sheet | HA clustering, Ceph | 937 MB |
| **tome** | page | Testing, security, observability | 1.38 GB |
| **press** | tome | C/C++ development toolchain | 1.89 GB |
| **gutenberg** | press | Empty cap layer | 1.89 GB |

### System Tiers — cloth/weaving (bootable via [kento](https://pypi.org/project/kento/))

| Tier | Based on | Focus | Pull size¹ |
|------|----------|-------|------------|
| **lint** | seed | Bootable seed (systemd PID 1) | 269 MB |
| **thread** | fiber | + kernel-dependent tools | 647 MB |
| **yarn** | sheet | + lvm2, pciutils, nbd-client | 804 MB |
| **fabric** | page | + drbd, iscsi, multipath | 1018 MB |
| **tapestry** | tome | + sg3-utils, smartmontools, qemu-arm | 1.49 GB |
| **loom** | press | Same kernel packages as tapestry | 2.01 GB |
| **jacquard** | gutenberg | Same kernel packages as tapestry | 2.01 GB |

### VM Tiers — wool (VM-bootable via kento VM mode)

| Tier | Based on | Focus | Pull size¹ |
|------|----------|-------|------------|
| **root** | lint | VM-bootable lint | 317 MB |
| **hair** | thread | VM-bootable thread | 696 MB |
| **wool** | yarn | VM-bootable yarn | 959 MB |
| **felt** | fabric | VM-bootable fabric | 1.47 GB |
| **amimono** | tapestry | VM-bootable tapestry | 1.94 GB |
| **stuffer** | loom | VM-bootable loom | 2.44 GB |
| **stuffinator** | jacquard | VM-bootable jacquard | 2.77 GB |

¹ Compressed download size from GHCR (`ghcr.io/doctorjei/droste-<tier>:1.2.0-rc1`,
linux/amd64), measured 2026-06-10. Unpacked on-disk size in podman's store is
larger. See [Getting the images](docs/usage.md#getting-the-images).

Each system tier adds init/systemd (21 packages) plus cumulative kernel-dependent packages. Cloth tiers from **thread** onward also include LXC + systemd-container management tools and have `kento` pre-installed (via pipx), making them capable of nested LXC/VM operations from within a booted tier. Each VM tier adds /boot/vmlinuz + initramfs, password, DHCP config, and VM-specific packages (qemu-guest-agent, watchdog, libvirt, nested virt, etc.) on top of its system sibling. Wool L2+ tiers (wool, felt, amimono, stuffer, stuffinator) also add `qemu-system-x86` + `virtiofsd` and place the `droste` user in the `kvm` group, so they can host nested VMs (e.g., `kento create --vm` from inside a booted droste VM).

**stuffinator** additionally restores a minimal Proxmox VE — `qemu-server pve-container pve-cluster`, giving `pct`, `qm`, and pmxcfs (`/etc/pve`) — so it can serve as kento's `pve-lxc`/`pve-vm` E2E host. No `proxmox-ve` metapackage, no `pve-manager` web stack, no ZFS, and no proxmox kernel: it keeps the gemet kernel it COPYs. The PVE package install is kernel-independent, but `pve-vm`/`qm` runtime requires gemet's KVM-host kernel.

All system and VM tiers ship with `cloud-init` for declarative first-boot configuration, with a default datasource list of `[NoCloud, ConfigDrive, None]` (override via `/etc/cloud/cloud.cfg.d/`). See [docs/usage.md](docs/usage.md#first-boot-configuration-cloud-init).

Pick the smallest tier that has what you need. Most container and networking work only needs **fiber** (process) or **thread** (system with LXC + kento tooling). VM-in-VM testing needs **sheet** / **yarn**. Cluster or HA testing needs **page** / **fabric**.

Each image includes a `droste` user (UID 1000) with passwordless sudo.
App and system tiers have no login password (use `podman exec` or `lxc-attach`).
VM tiers have password `droste` for console/SSH login.

## Usage

Pre-built images are published to GHCR for every tier — pull one, or build
locally (see [BUILDING.md](BUILDING.md)). The examples below use `localhost/`
(local builds); substitute `ghcr.io/doctorjei/droste-<tier>:<tag>` to use the
published images.

```bash
# Pull a prebuilt image from GHCR (all 21 tiers published)
podman pull ghcr.io/doctorjei/droste-thread:latest

# Process container (app tier)
podman run --rm -it localhost/droste-fiber bash

# System container via kento (system tier — boots systemd)
sudo kento container create localhost/droste-thread --name test --start
sudo lxc-attach -n test

# VM via kento VM mode (VM tier — full kernel)
sudo kento container create localhost/droste-root --vm --name vm1 --start
ssh -p 10022 droste@localhost   # password: droste
```

See [docs/usage.md](docs/usage.md) for detailed runtime documentation (including
[Getting the images](docs/usage.md#getting-the-images)) and
[BUILDING.md](BUILDING.md) for build instructions.

## droste-fiber: Basic Tools & Container Tools
*(based on droste-seed)*

### Tools in addition to seed

**Applications**: ```atop, bc, dnstop, htop, iftop, iotop, smbclient, sqlite3, tmux```

**Filesystems**: ```acl, attr, inotify-tools, lsof, smbnetfs, sshfs```

**General Utilities**: ```crudini, debootstrap, entr, expect, jo, jq, ltrace, make, moreutils, parallel, patch, pv, pystrings (strings), rename, strace, sysstat, tree, unzip, xmlstarlet, xxd, zip```

**Networking**: ```conntrack, dnsmasq, dnsutils, fping, gh, git, inetutils-telnet, ipcalc, ipset, iptables, iputils-arping, nftables, pyhttpd (httpd), rsync, sshpass, tftpd-hpa, whois, wireguard-tools```

**Python**: ```pipx, python3-pip, python3-venv, uv```

**Virtualization**: ```fuse-overlayfs, podman, passt, uidmap```

**System Tools**: ```etckeeper```

## droste-sheet: VM Management & Storage
*(based on droste-fiber)*

### Tools in addition to droste-fiber

**Applications**: ```bmon, ncdu, nethogs, picocom```

**Networking**: ```bridge-utils, ethtool, hping3, nicstat```

**Storage**: ```btrfs-progs, cryptsetup, dosfstools, gdisk, lvm2, mdadm, mtools, nbd-client, nfs-kernel-server, ntfs-3g, parted, quota, squashfs-tools, thin-provisioning-tools```

**Virtualization**: ```cloud-image-utils, cpu-checker, libvirt-daemon-system, nbdkit, ovmf, qemu-system-x86, qemu-utils, swtpm, virtinst```

**General Utilities**: ```ansible, dmidecode, gettext-base, hdparm, lshw, pciutils, sysbench```

**System Tools**: ```linux-cpupower, irqbalance```

## droste-page: High Availability & Clustering
*(based on droste-sheet)*

### Tools in addition to droste-sheet

**High Availability**: ```fence-agents, keepalived, pacemaker, pacemaker-cli-utils, pcs, resource-agents, sbd```

**Cluster**: ```clustershell, dlm-controld```

**Storage**: ```ceph-common, drbd-utils, multipath-tools, open-iscsi, targetcli-fb```

**PXE**: ```pxelinux, syslinux-common```

**Networking**: ```ebtables```

**System Tools**: ```numactl```

## droste-tome: Testing, Security & Observability
*(based on droste-page)*

### Tools in addition to droste-page

**Applications**: ```lnav```

**Benchmarking**: ```apache2-utils, fio, iperf3, stress-ng```

**Networking**: ```arp-scan, bird2, haproxy, nmap, openvswitch-switch, tcpreplay```

**Security**: ```aide, apparmor-utils, auditd, lynis```

**Storage**: ```blktrace, sg3-utils, smartmontools, xorriso```

**Virtualization**: ```buildah, qemu-system-arm, skopeo```

**Observability**: ```prometheus-node-exporter```

**Clients**: ```postgresql-client, redis-tools```

**Hardware**: ```ipmitool```

**Testing**: ```python3-pytest```

## droste-press: C/C++ Development Toolchain
*(based on droste-tome)*

### Tools in addition to droste-tome

**Compilers**: ```build-essential```

**Build Systems**: ```autoconf, automake, cmake, libtool, ninja-build, pkg-config```

**Debugging**: ```gdb, valgrind```

**General Utilities**: ```bear, ccache```

**Kernel/initramfs Build**: ```bison, busybox-static, cpio, flex, libelf-dev, libncurses-dev, libssl-dev```

**Shell Linting**: ```shellcheck```

## droste-gutenberg: Placeholder
*(based on droste-press)*

This is an empty cap layer. No additional packages are installed — it
exists as a user-extensible top of the press (paper L6) line for adding
project-specific tooling without modifying lower tiers.

## droste-thread: System Container Baseline
*(based on droste-fiber + lint-equivalent systemd reinstall)*

Thread is the first cloth L1+ tier. It adds kernel-dependent packages
that only work with a real init system, LXC/systemd-container management
tooling, and the `kento` lifecycle tool.

### Tools in addition to droste-fiber (inherited) and lint (systemd reinstall)

**Container management**: ```apparmor, lxc, lxcfs, systemd-container```

(`apparmor` is installed explicitly here — `lxc` only Recommends it, and
builds use `--no-install-recommends`; the parser is required for LXC's
generated profile to load on an AppArmor-active kernel. yarn and fabric add
it too; upper cloth tiers get it via `apparmor-utils`.)

**Kernel-dependent**: ```cifs-utils, fatrace, ipvsadm, molly-guard, nfs-common```

**Lifecycle tool**: ```kento``` (installed via `pipx install --global` —
available at `/usr/local/bin/kento`)

Inherited by all downstream cloth tiers (yarn, fabric, tapestry, loom,
jacquard) and all VM L1+ tiers (hair, wool, felt, amimono, stuffer,
stuffinator) via the tier inheritance chain. **lint** (cloth L0) and
**root** (wool L0) stay minimal and do not include these.
