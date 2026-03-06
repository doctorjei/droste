# Droste

Nested virtualization images for testing infrastructure operations — containers, VMs, DRBD, Pacemaker, iSCSI, LXC, Proxmox VE, and more. Built on Debian 13 (Trixie) as layered images across three formats: VM (QCOW2), OCI (Containerfiles), and LXC-bootable OCI.

## Image Formats

| Format | Base | Use case | Init | Kernel |
|--------|------|----------|------|--------|
| **OCI** | genericcloud → seed | Process containers, CI/CD | None | Host kernel |
| **System OCI** | OCI + init/systemd | System containers via [kento](https://pypi.org/project/kento/) | systemd | Host kernel |
| **VM OCI** | System OCI + kernel | VM boot via [kento](https://pypi.org/project/kento/) VM mode | systemd | Own kernel |

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

Each system tier adds init/systemd (21 packages) plus cumulative kernel-dependent packages. Each VM tier adds /boot/vmlinuz + initramfs, password, and DHCP config on top of its system sibling.

Pick the smallest tier that has what you need. Most container and networking work only needs **fiber** / **thread**. VM-in-VM testing needs **sheet**. Cluster or HA testing needs **page** / **fabric**.

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
