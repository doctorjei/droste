# Droste

Nested virtualization images for testing infrastructure operations — containers, VMs, DRBD, Pacemaker, iSCSI, LXC, Proxmox VE, and more. Built on Debian 13 (Trixie) as layered OCI images in three variants: process containers, system containers ([kento](https://pypi.org/project/kento/)), and VM-bootable ([tenkei](https://github.com/doctorjei/tenkei) kernel).

## Image Formats

| Variant | Base | Use case | Init | Kernel |
|---------|------|----------|------|--------|
| **App** (paper) | genericcloud → seed | Process containers, CI/CD | None | Host kernel |
| **System** (cloth) | App + init/systemd | System containers via [kento](https://pypi.org/project/kento/) | systemd | Host kernel |
| **VM** (wool) | System + [tenkei](https://github.com/doctorjei/tenkei) kernel | VMs via [kento](https://pypi.org/project/kento/) VM mode | systemd | Own kernel |

## Tiers

Each tier builds on the previous one. Three lines: paper (light), cloth (medium), wool (heavy).

### App Tiers — paper/publishing (process containers)

| Tier | Based on | Focus | Size |
|------|----------|-------|------|
| **seed** | genericcloud (stripped) | Minimal OCI base | 413 MB |
| **fiber** | seed | Basic tools, containers, networking | 1.02 GB |
| **sheet** | fiber | Storage, VM tooling | 1.63 GB |
| **page** | sheet | HA clustering, Ceph | 2.1 GB |
| **tome** | page | Testing, security, observability | 3.16 GB |
| **press** | tome | C/C++ development toolchain | 3.89 GB |
| **gutenberg** | press | Empty cap layer | 3.89 GB |

### System Tiers — cloth/weaving (bootable via [kento](https://pypi.org/project/kento/))

| Tier | Based on | Focus | Size |
|------|----------|-------|------|
| **lint** | seed | Bootable seed (systemd PID 1) | 553 MB |
| **thread** | fiber | + kernel-dependent tools | 1.16 GB |
| **yarn** | sheet | + lvm2, pciutils, nbd-client | 1.77 GB |
| **fabric** | page | + drbd, iscsi, multipath | 2.25 GB |
| **tapestry** | tome | + sg3-utils, smartmontools, qemu-arm | 3.44 GB |
| **loom** | press | Same kernel packages as tapestry | 4.17 GB |
| **jacquard** | gutenberg | Same kernel packages as tapestry | 4.17 GB |

### VM Tiers — wool (VM-bootable via kento VM mode)

| Tier | Based on | Focus |
|------|----------|-------|
| **root** | lint | VM-bootable seed |
| **hair** | thread | VM-bootable fiber |
| **wool** | yarn | VM-bootable sheet |
| **felt** | fabric | VM-bootable page |
| **amimono** | tapestry | VM-bootable tome |
| **stuffer** | loom | VM-bootable press |
| **stuffinator** | jacquard | VM-bootable gutenberg |

Each system tier adds init/systemd (21 packages) plus cumulative kernel-dependent packages. Each VM tier adds /boot/vmlinuz + initramfs, password, DHCP config, and VM-specific packages (qemu-guest-agent, watchdog, libvirt, nested virt, etc.) on top of its system sibling.

Pick the smallest tier that has what you need. Most container and networking work only needs **fiber** / **thread**. VM-in-VM testing needs **sheet**. Cluster or HA testing needs **page** / **fabric**.

Each image includes a `droste` user (UID 1000) with passwordless sudo.
App and system tiers have no login password (use `podman exec` or `lxc-attach`).
VM tiers have password `droste` for console/SSH login.

## Usage

```bash
# Process container (app tier)
podman run --rm -it localhost/droste-fiber bash

# System container via kento (system tier — boots systemd)
sudo kento container create localhost/droste-thread --name test --start
sudo lxc-attach -n test

# VM via kento VM mode (VM tier — full kernel)
sudo kento container create localhost/droste-root --vm --name vm1 --start
ssh -p 10022 droste@localhost   # password: droste
```

See [docs/usage.md](docs/usage.md) for detailed runtime documentation and
[BUILDING.md](BUILDING.md) for build instructions.

## droste-fiber: Basic Tools & Container Tools
*(based on droste-seed)*

### Tools in addition to seed

**Applications**: ```atop, bc, dnstop, htop, iftop, iotop, smbclient, sqlite3, tmux```

**Filesystems**: ```acl, attr, cifs-utils, fatrace, inotify-tools, lsof, nfs-common, sshfs```

**General Utilities**: ```bsdextrautils, crudini, debootstrap, entr, expect, file, jo, jq, ltrace, make, moreutils, parallel, patch, psmisc, pv, pystrings (strings), rename, strace, sysstat, tree, unzip, xmlstarlet, xxd, zip```

**Networking**: ```conntrack, curl, dnsmasq, dnsutils, fping, git, inetutils-telnet, ipcalc, iproute2, ipset, iputils-arping, ipvsadm, netcat-openbsd, nftables, pipx, pyhttpd (httpd), rsync, socat, ssh-import-id, sshpass, tftpd-hpa, wget, whois, wireguard-tools```

**Virtualization**: ```fuse-overlayfs, lxc, lxcfs, podman, qemu-guest-agent, slirp4netns, systemd-container, uidmap```

**System Tools**: ```etckeeper, locales, molly-guard, watchdog```

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

## droste-press: C/C++ Development Toolchain
*(based on droste-tome)*

### Tools in addition to droste-tome

**Compilers**: ```build-essential```

**Build Systems**: ```autoconf, automake, cmake, libtool, ninja-build, pkg-config```

**Debugging**: ```gdb, valgrind```

**General Utilities**: ```bear, ccache```

## droste-gutenberg: Proxmox VE Environment
*(based on droste-press)*

### Tools in addition to droste-press

**Proxmox VE**: ```proxmox-ve, zfsutils-linux```
