# Using Droste Images

Droste OCI images run in three modes: process containers, system containers,
and VMs. All three use the same OCI image store — no conversion or duplication.

## Quick Start

```bash
# Process container — run tools directly
podman run --rm -it localhost/droste-fiber bash

# System container — boots systemd, persistent
sudo kento container create localhost/droste-thread --name test --start
sudo lxc-attach -n test

# VM — full kernel, SSH access
sudo kento container create localhost/droste-root --vm --name vm1 --start
ssh -p 10022 droste@localhost   # password: droste
```

## Three Runtime Modes

| Mode | Image line | Runtime | Init | Access |
|------|-----------|---------|------|--------|
| **Process container** | App (paper) | podman | None | `podman exec` / `podman run` |
| **System container** | System (cloth) | [kento](https://pypi.org/project/kento/) | systemd | `lxc-attach` or SSH |
| **VM** | VM (wool) | [kento](https://pypi.org/project/kento/) --vm | systemd | SSH or serial console |

**App tiers** (seed, fiber, sheet, page, tome, press, gutenberg) are standard
OCI images. No init system, no services — run a command and exit.

**System tiers** (lint, thread, yarn, fabric, tapestry, loom, jacquard) add
init/systemd and kernel-dependent packages. They boot as LXC system containers
with systemd as PID 1. Persistent across restarts. Tiers from **thread** onward
also include LXC management tooling (lxc, systemd-container) and have `kento`
pre-installed, enabling nested LXC/VM operations from within a booted tier.
**lint** (the minimal system base) does not — use it for pure LXC boot testing
without nested-container needs.

**VM tiers** (root, hair, wool, felt, amimono, stuffer, stuffinator) add a
[gemet](https://github.com/doctorjei/gemet) kernel and initramfs, VM-specific
packages (qemu-guest-agent, watchdog, libvirt, nested virtualization tools, etc.),
and boot config on top of each system tier. Kento boots them via QEMU + virtiofs
— the OCI layers become the VM's root filesystem without extraction or disk images.

## How It Works

An OCI image is a stack of filesystem layers (tarballs) plus metadata. Podman
stores these layers unpacked on disk. Normally, `podman run` unions those layers
into a temporary rootfs via overlayfs, runs a single process, and tears it down.
That's fine for process containers, but it's not a machine — there's no init
system, no services, no persistent state.

Kento and gemet extend this to system containers and VMs without copying or
converting the image data.

### OCI → LXC system container (kento)

LXC system containers are full Linux environments that boot an init system
(systemd) as PID 1, just like a real machine. They share the host kernel but
have their own process tree, network, and filesystem.

The problem: LXC has its own rootfs model — it expects a directory tree, not
OCI layers. Kento bridges this gap:

1. **Layer resolution.** Kento queries podman's GraphDriver API to get the
   absolute paths of each unpacked OCI layer on the host filesystem. No data
   is copied — kento reads podman's store directly.

2. **Overlayfs mount.** At container start, a kento-generated LXC hook script
   mounts an overlayfs with:
   - **lowerdir**: the OCI layers (read-only, stacked in order)
   - **upperdir**: a per-container writable directory
   - **merged**: the LXC rootfs mountpoint

   This is the same mechanism podman uses internally, but kento mounts it
   for LXC instead. The OCI layers become the container's root filesystem.

3. **Boot.** LXC starts `/sbin/init` (systemd) inside the overlayfs as PID 1.
   Systemd brings up services, networking, and SSH — exactly like a real
   machine boot, but using the host kernel.

4. **Cleanup.** On stop, the hook unmounts the overlayfs. The OCI layers are
   untouched. The writable upper layer preserves any changes made inside the
   container (installed packages, config edits, log files). `kento container scrub`
   clears this upper layer to restore the container to its pristine image state.

**Why system tiers work but app tiers don't:** App tiers (seed, fiber, etc.)
have init/systemd stripped out — there's no `/sbin/init` to boot. System
tiers (lint, thread, etc.) add back the 21 packages that were excluded from
the OCI seed (systemd, dbus, udev, polkitd, cloud-init, kmod, etc.) plus
`CMD ["/sbin/init"]`. This is the only difference — same tools, same users,
same config, but with an init system that can boot.

System tiers also add kernel-dependent packages that don't work in process
containers (e.g., ipvsadm, cifs-utils, lvm2, drbd-utils). These packages
need kernel modules that are accessible via LXC's shared kernel but not
available in OCI's isolated namespace. From **thread** onward, cloth tiers
also include `lxc` and `systemd-container` management tooling plus the
`kento` CLI (installed via `pipx install --global`, available at
`/usr/local/bin/kento`). This lets a booted cloth or wool tier spawn its
own nested LXC containers or VMs.

### OCI → VM (kento + gemet)

VM tiers go further: they boot inside a real virtual machine with their own
kernel. The OCI image becomes the VM's root filesystem — no disk images, no
qcow2, no conversion.

1. **Kernel extraction.** Kento reads `/boot/vmlinuz` and `/boot/initramfs.img`
   from inside the OCI image. These are the
   [gemet](https://github.com/doctorjei/gemet) kernel and initramfs, copied
   into every VM tier's Containerfile from gemet's `boot` OCI image
   via a multi-stage `COPY --from=gemet-boot`.

2. **virtiofsd.** Kento launches virtiofsd, which shares the OCI layers
   (mounted as overlayfs, same as LXC mode) to the guest VM via the virtio
   filesystem protocol. The host exposes the container's root filesystem
   as a FUSE share.

3. **QEMU boot.** Kento starts QEMU with:
   - `-kernel` and `-initrd` pointing to the extracted gemet files
   - A virtiofs device tagged `rootfs` connecting to the virtiofsd socket
   - User-mode networking with SSH port forwarding

4. **Initramfs pivot.** The gemet initramfs is a minimal script (~6 lines)
   that mounts the virtiofs share tagged `rootfs` and calls `switch_root`
   into it. From the VM's perspective, the OCI layers **are** the root
   filesystem — it boots into `/sbin/init` (systemd) exactly as if it were
   installed on a local disk.

5. **VM boot fixes.** Raw OCI images would fail to boot as VMs for two
   reasons. Each VM tier's Containerfile addresses them:
   - **Password**: the droste user has no password in app/system tiers
     (locked account). VMs need console/SSH login, so VM tiers set
     `droste:droste` via chpasswd.
   - **DHCP**: no network config exists by default. VM tiers create a
     systemd-networkd config for DHCP on physical ethernet interfaces
     (`[Match] Name=en* eth*`) and enable the service. A separate
     higher-priority drop-in marks `Kind=veth` interfaces other than
     `eth0` `Unmanaged=yes` (`[Match] Name=!eth0`), so networkd leaves LXC
     veth pairs on their bridge while still managing the guest's own primary
     NIC.

   (fstab is already empty in the canopy base — no fstab clearing needed.)

**Why VM tiers exist separately:** System tiers could theoretically boot as
VMs if you added kernel files. VM tiers formalize this by including the gemet
kernel, setting a password, configuring DHCP, and installing VM-specific
packages that only make sense with a hypervisor — qemu-guest-agent (hypervisor
integration), watchdog (hardware watchdog), qemu-system-x86/libvirt/swtpm/ovmf
(nested virtualization), nfs-kernel-server, irqbalance, linux-cpupower, and
cpu-checker. Higher VM tiers also add fence-agents (full, vs fence-agents-common
in app tiers) and numactl. Kernel module configs for nested KVM, nbd, and drbd
are included. All baked into the image so `kento --vm` works without any manual
setup.

### Zero duplication

All three modes read from the same podman layer store. A droste-thread image
is stored once as a stack of OCI layers. Running it as a process container
(podman), a system container (kento LXC), or a VM (kento --vm via its VM
sibling droste-hair) all reference the same layer data. The only per-instance
storage is the overlayfs upper layer for writes, which starts empty and can
be cleared with `kento container scrub`.

## Running Process Containers

Process containers use podman directly. No special tools needed.

```bash
# Interactive shell
podman run --rm -it localhost/droste-fiber bash

# One-shot command
podman run --rm localhost/droste-sheet ansible --version

# With networking
podman run --rm --network=host localhost/droste-fiber curl http://example.com

# Mount host directory
podman run --rm -v /path/on/host:/mnt:Z localhost/droste-fiber ls /mnt
```

App tiers have no init system — `podman run` executes the command directly.
When the command exits, the container is removed (`--rm`).

## Running System Containers

System containers require [kento](https://pypi.org/project/kento/) (`pip install kento`).
Kento is also pre-installed in all thread+ cloth tiers and all hair+ VM tiers,
so you can run `kento` from within a booted container or VM without installing
it there.

### Create and start

```bash
sudo kento container create localhost/droste-thread --name my-test --start
```

Kento reads podman's layer store directly — no image data is copied. The
container boots systemd as PID 1.

### Attach

```bash
sudo lxc-attach -n my-test
```

This gives a root shell inside the running container. SSH is also available
— openssh-server is installed at lint (cloth L0), so every cloth and wool
tier ships sshd.

### Lifecycle

```bash
sudo kento container list                  # show all containers
sudo kento container stop my-test          # stop
sudo kento container start my-test         # start again
sudo kento container scrub my-test         # clear writable layer (fresh state)
sudo kento container rm my-test            # remove container
```

`scrub` clears all changes made inside the container without re-downloading
or re-extracting any image data. The OCI layers are read-only and shared.

### Create options

| Flag | Default | Purpose |
|------|---------|---------|
| `--name` | auto | Container name |
| `--start` | false | Start after creation |
| `--bridge` | None | Network bridge |
| `--nesting` | true | Allow nested containers |

On Proxmox hosts, kento auto-detects PVE and uses `pct` instead of `lxc-*`
commands. Use `--vmid` to set the Proxmox container ID.

## Running VMs

VM mode requires [kento](https://pypi.org/project/kento/) and
[gemet](https://github.com/doctorjei/gemet) kernel files baked into the
image (already included in all VM tiers).

### Create and start

```bash
sudo kento container create localhost/droste-root --vm --name vm1 --start
```

Kento launches QEMU with the gemet kernel, using virtiofs to mount the
OCI layers as the VM's root filesystem. No disk images are created.

### SSH access

```bash
ssh -p 10022 droste@localhost
```

Kento assigns SSH ports starting at 10022. Check the assigned port with:

```bash
sudo kento container list
```

### Serial console

If SSH isn't available, connect to the QEMU serial console via the socket
in the VM's state directory.

### VM create options

All system container options apply, plus:

| Flag | Default | Purpose |
|------|---------|---------|
| `--vm` | — | Enable VM mode (required) |
| `--port` | auto (10022+) | SSH port mapping (host:guest) |

## Tier Selection Guide

Pick the smallest tier that has what you need:

| Use case | App tier | System tier | VM tier |
|----------|----------|-------------|---------|
| Basic containers, networking, CI | fiber | thread | hair |
| Storage, libvirt, QEMU | sheet | yarn | wool |
| HA clustering, Ceph, DRBD | page | fabric | felt |
| Testing, security, monitoring (incl. pytest) | tome | tapestry | amimono |
| C/C++ + kernel/initramfs build | press | loom | stuffer |
| Proxmox VE (pct/qm/pmxcfs) | — | — | stuffinator |

**Wool L2+ tiers** (wool, felt, amimono, stuffer, stuffinator) include
`qemu-system-x86` + `virtiofsd` and place the `droste` user in the `kvm`
group, so a booted droste VM can host nested VMs (e.g., `kento create --vm`
from inside). **wool L0/L1** (root, hair) stay minimal — they boot as VMs
themselves but can't host nested VMs.

**seed / lint / root** are minimal base images with no additional tools.
Use them for custom builds or as starting points for your own Containerfiles.

## Credentials & Access

| Tier line | User | Password | Sudo | Login methods |
|-----------|------|----------|------|---------------|
| **App** (paper) | droste | *(none)* | passwordless | `podman exec`, `podman run` |
| **System** (cloth) | droste | *(none)* | passwordless | `lxc-attach`, SSH (key-based) |
| **VM** (wool) | droste | `droste` | via sudo group | SSH (password or key), serial console |

The `droste` user in **wool L2+ tiers** is also a member of the `kvm`
group, so it can use `/dev/kvm` directly for nested KVM workloads.

App and system tiers have no login password set — use `podman exec` or
`lxc-attach` for interactive access. SSH works on system tiers if you
inject a key (e.g., `ssh-copy-id` via `lxc-attach`).

VM tiers have password `droste` set for console and SSH login.

## Networking

**System containers** get an IP via the bridge specified at creation time
(requires `--bridge`, no default). Check the IP inside the container:

```bash
sudo lxc-attach -n my-test -- ip addr show
```

**VMs** use DHCP via systemd-networkd on physical ethernet interfaces
(`[Match] Name=en* eth*`; veth interfaces other than `eth0` are left
unmanaged). Kento sets
up user-mode networking with port forwarding for SSH.

**Proxmox** hosts use `vmbr0` by default (auto-detected by kento).

## First-Boot Configuration (cloud-init)

All system and VM tiers ship with `cloud-init`, `cloud-guest-utils`, and
`cloud-utils` installed. App tiers do not (no init system to run cloud-init).

The default datasource list is restricted to the ones that make sense for
droste's runtime environments:

```yaml
# /etc/cloud/cloud.cfg.d/99-droste.cfg
datasource_list: [NoCloud, ConfigDrive, None]
```

- **NoCloud** — file/ISO/label-based. Used by kento (auto-detected from
  composed images and routed through a NoCloud seed), `cloud-localds`, and
  hand-built ISOs.
- **ConfigDrive** — Proxmox and OpenStack.
- **None** — fallback; boot succeeds without first-boot config.

This skips ~17 cloud-specific datasources (AWS, Azure, GCE, etc.) that
droste isn't aimed at, which speeds up first boot. To override per
deployment, write your own drop-in to `/etc/cloud/cloud.cfg.d/` that
lex-sorts after `99-droste.cfg`.

## Storage & Cleanup

**OCI images** live in podman's store. Kento reads layers directly — no
duplication. List images:

```bash
podman images | grep droste
```

**System containers** store writable layers and config in:
- LXC: `/var/lib/lxc/<name>/`
- PVE: `/etc/pve/nodes/<node>/lxc/<vmid>.conf`
- Writable data: `~/.local/share/kento/<name>/` (of the invoking user)

**VMs** store state in `/var/lib/kento/vm/<name>/`.

**Cleanup:**

```bash
# Remove a container (stops it first if running)
sudo kento container rm my-test

# Remove OCI images
podman rmi localhost/droste-fiber

# Remove all droste images
podman images | grep droste | awk '{print $1}' | xargs podman rmi
```
