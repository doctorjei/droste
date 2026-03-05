# Droste

Nested virtualization images for testing infrastructure operations — containers, VMs, DRBD, Pacemaker, iSCSI, LXC, Proxmox VE, and more. Built on Debian 13 (Trixie) as layered images across three formats: VM (QCOW2), LXC (rootfs tarballs), and OCI (Containerfiles).

## Image Formats

| Format | Base | Use case | Init | Kernel |
|--------|------|----------|------|--------|
| **VM** | genericcloud qcow2 | Full nested virt, hardware passthrough | systemd | Own kernel |
| **LXC** | genericcloud → seed | System containers, kernel module testing | systemd | Host kernel |
| **OCI** | debian:trixie-slim | Application containers, CI/CD | None | Host kernel |

## Tiers

Each tier builds on the previous one. Pick the smallest that has what you need.

### VM Tiers (textile metaphor)

| Tier | Based on | Focus | Size |
|------|----------|-------|------|
| **thread** | debian-13-genericcloud | Basic tools, containers, networking | 368 MB |
| **yarn** | thread | VM management, storage, nested virt | 559 MB |
| **fabric** | yarn | HA clustering, DRBD, iSCSI, Ceph | 1.1 GB |
| **tapestry** | fabric | Testing, benchmarking, security, observability | 1.3 GB |
| **loom** | tapestry | C/C++ development toolchain | 1.5 GB |
| **jacquard** | loom | Proxmox VE (PVE kernel, ZFS, corosync) | 2.2 GB |

### LXC Tiers (paper/publishing metaphor)

| Tier | Based on | Focus | Packages | Size |
|------|----------|-------|----------|------|
| **seed** | genericcloud (stripped) | Minimal system container base | 292 | 101 MB |
| **fiber** | seed | Basic tools, containers, networking | 440 | 251 MB |
| **sheet** | fiber | Storage, VM tooling, kernel-dependent tools | 491 | 337 MB |
| **page** | sheet | HA clustering, DRBD, iSCSI, Ceph | 635 | 403 MB |
| **tome** | page | Testing, security, observability | 764 | 628 MB |
| **gutenberg** | tome | C/C++ development toolchain | 839 | 790 MB |

### OCI Tiers (textile crafting metaphor)

| Tier | Based on | Focus |
|------|----------|-------|
| **hair** | debian:trixie-slim | Basic tools, containers, networking |
| **wool** | hair | Storage, VM tooling |
| **felt** | wool | HA clustering, Ceph |
| **amimono** | felt | Testing, security, observability |
| **embellisher** | amimono | C/C++ development toolchain |

LXC tiers include kernel-dependent packages (lvm2, DRBD, iSCSI, etc.) that work in system containers but not OCI application containers. No jacquard equivalent exists for LXC or OCI (hypervisor stack requires its own kernel).

Pick the smallest tier that has what you need. Most container and networking work only needs **thread** / **fiber** / **hair**. VM-in-VM testing needs **yarn**. Cluster or HA testing needs **fabric** / **page** / **felt**.

Each image includes a `droste` user (UID 1000) with passwordless sudo. SSH key
injection via cloud-init is required on first boot -- there is no login password.
See [BUILDING.md](BUILDING.md) for build instructions and SSH key setup.

## droste-thread: Basic Tools & Container Tools
*(based on debian-13-genericcloud)*

### Tools in addition to base image

**Applications**: ```atop, bc, dnstop, htop, iftop, iotop, smbclient, sqlite3, tmux```

**Filesystems**: ```acl, attr, cifs-utils, fatrace, inotify-tools, lsof, nfs-common, sshfs```

**General Utilities**: ```bsdextrautils, crudini, debootstrap, entr, expect, file, jo, jq, ltrace, make, moreutils, parallel, patch, psmisc, pv, pystrings (strings), rename, strace, sysstat, tree, unzip, xmlstarlet, xxd, zip```

**Networking**: ```conntrack, curl, dnsmasq, dnsutils, fping, git, inetutils-telnet, ipcalc, iproute2, ipset, iputils-arping, ipvsadm, netcat-openbsd, nftables, pipx, pyhttpd (httpd), rsync, socat, ssh-import-id, sshpass, tftpd-hpa, wget, whois, wireguard-tools```

**Virtualization**: ```fuse-overlayfs, lxc, lxcfs, podman, qemu-guest-agent, slirp4netns, systemd-container, uidmap```

**System Tools**: ```etckeeper, locales, molly-guard, watchdog```

## droste-yarn: VM Management & Storage
*(based on droste-thread)*

### Tools in addition to droste-thread

**Applications**: ```bmon, ncdu, nethogs, picocom```

**Networking**: ```bridge-utils, ethtool, hping3, nicstat```

**Storage**: ```btrfs-progs, cryptsetup, dosfstools, gdisk, lvm2, mdadm, mtools, nbd-client, nfs-kernel-server, ntfs-3g, parted, quota, squashfs-tools, thin-provisioning-tools```

**Virtualization**: ```cloud-image-utils, cpu-checker, libvirt-daemon-system, nbdkit, ovmf, qemu-system-x86, qemu-utils, swtpm, virtinst```

**General Utilities**: ```ansible, dmidecode, gettext-base, hdparm, lshw, pciutils, sysbench```

**System Tools**: ```linux-cpupower, irqbalance```

## droste-fabric: High Availability & Clustering
*(based on droste-yarn)*

### Tools in addition to droste-yarn

**High Availability**: ```fence-agents, keepalived, pacemaker, pacemaker-cli-utils, pcs, resource-agents, sbd```

**Cluster**: ```clustershell, dlm-controld```

**Storage**: ```ceph-common, drbd-utils, multipath-tools, open-iscsi, targetcli-fb```

**PXE**: ```pxelinux, syslinux-common```

**Networking**: ```ebtables```

**System Tools**: ```numactl```

## droste-tapestry: Testing, Security & Observability
*(based on droste-fabric)*

### Tools in addition to droste-fabric

**Applications**: ```lnav```

**Benchmarking**: ```apache2-utils, fio, iperf3, stress-ng```

**Networking**: ```arp-scan, bird2, haproxy, nmap, openvswitch-switch, tcpreplay```

**Security**: ```aide, apparmor-utils, auditd, lynis```

**Storage**: ```blktrace, sg3-utils, smartmontools, xorriso```

**Virtualization**: ```buildah, qemu-system-arm, skopeo```

**Observability**: ```prometheus-node-exporter```

**Clients**: ```postgresql-client, redis-tools```

**Hardware**: ```ipmitool```

## droste-loom: C/C++ Development Toolchain
*(based on droste-tapestry)*

### Tools in addition to droste-tapestry

**Compilers**: ```build-essential```

**Build Systems**: ```autoconf, automake, cmake, libtool, ninja-build, pkg-config```

**Debugging**: ```gdb, valgrind```

**General Utilities**: ```bear, ccache```

## droste-jacquard: Proxmox VE Environment
*(based on droste-loom)*

### Tools in addition to droste-loom

**Proxmox VE**: ```proxmox-ve, zfsutils-linux```
