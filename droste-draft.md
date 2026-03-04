# Droste — Nested Virtualization VM Image for Infrastructure Testing

*Named after the [Droste effect](https://en.wikipedia.org/wiki/Droste_effect):
a VM that can run VMs that can run containers that can run containers.*

## Problem

Testing infrastructure operations (DRBD upgrades, Pacemaker failover, iSCSI
reconfiguration, LXC creation scripts) on production systems is risky.
Mistakes that seem harmless — bringing down a network interface, running
`create-md --force` — can cost hours of resync time or cause cascading
failures. There's no safe way to rehearse these operations at full fidelity
before running them live.

## Solution

Droste is a minimal, headless VM image that contains every virtualization
primitive needed to simulate a multi-node Proxmox cluster inside a single
VM. Boot it, spin up nested VMs or containers representing your cluster
nodes, and test destructive operations with 1 GB virtual disks instead of
2 TB production drives.

## Design Principles

1. **Full fidelity** — same PVE kernel, same tools (`pct`, `qm`, `pvesh`),
   same DRBD/iSCSI/Pacemaker stack as production. Tests that pass in droste
   should work in production.
2. **Minimal footprint** — no web UI, no desktop, no unnecessary firmware.
   Small enough to distribute and boot quickly.
3. **Recursive by nature** — droste can test the playbooks that build droste.
4. **Disposable** — snapshot before testing, roll back after. Every test
   starts clean.

## Image Architecture

Two-layer build using QCOW2 backing files:

```
droste-base.qcow2          (~800 MB compressed)
  Debian 12 minimal + stock kernel + podman + lxc + qemu

droste-pve.qcow2            (~300-400 MB compressed, overlay on base)
  + PVE kernel + pct/qm/pvesh + DRBD + iSCSI + Pacemaker
```

The PVE layer is a thin QCOW2 overlay backed by the base image. Users who
only need container nesting can use the base; users testing Proxmox-specific
workflows use the PVE image (which requires both files).

**Why two layers?**
- Base is independently useful and cacheable
- QCOW2 backing files give native snapshot/rollback
- Only the PVE delta rebuilds when PVE packages update
- Distributable as: base (~400 MB compressed) + PVE overlay (~200 MB compressed)

## Component Inventory

### droste-base

| Component | Installed size | Notes |
|---|---|---|
| Debian 12 minimal (debootstrap) | ~300 MB | No manpages, no docs |
| Stock kernel + KVM modules | ~150 MB | Nested virt capable |
| QEMU (`qemu-system-x86_64`) | ~200-300 MB | For nested VMs |
| LXC userspace tools (`lxc-*`) | ~20-50 MB | No LXD daemon |
| Podman + fuse-overlayfs + slirp4netns | ~100-150 MB | Rootless OCI containers |
| uidmap, SSH, sudo, basics | ~50 MB | Minimal userland |
| **Total** | **~800 MB - 1 GB** | |

### droste-pve (additions on top of base)

| Component | Installed size | Removable? |
|---|---|---|
| PVE kernel (DRBD, ZFS modules) | ~200 MB | No — replaces stock kernel |
| pve-cluster / pmxcfs + corosync | ~50 MB | No — pct/qm need /etc/pve/ |
| pve-common (perl libraries) | ~30 MB | No — everything depends on it |
| pve-access-control | ~10 MB | No |
| pve-storage | ~20 MB | No |
| Perl dependency chain | ~100-150 MB | No — comes with core |
| qemu-server + pve-qemu-kvm | ~400 MB | Only if skipping VMs |
| pve-container + lxc-pve | ~50-100 MB | Only if skipping LXC |
| DRBD utils + drbd-dkms | ~30 MB | Optional |
| targetcli-fb + open-iscsi | ~20 MB | Optional |
| Pacemaker + pcs + resource-agents | ~50 MB | Optional |
| btrfs-progs | ~5 MB | Optional |
| **pve-manager (web UI)** | **~200-300 MB** | **YES — excluded** |
| **pve-ha-manager** | **~20 MB** | **YES — excluded** |
| **Total (PVE additions)** | **~700-800 MB** | |
| **Grand total (base + PVE)** | **~1.8-2 GB** | ~600-700 MB compressed |

## Build Process

### Ansible Playbooks

- `droste-base.yml` — Provisions the base layer:
  - Minimal Debian hardening (no root password, SSH key only)
  - Install podman, fuse-overlayfs, slirp4netns, uidmap
  - Install lxc tools, qemu-system-x86_64
  - Configure nested KVM (`/etc/modprobe.d/kvm.conf`)
  - Create `droste` user (UID 1000) with passwordless sudo
  - Strip docs, manpages, firmware blobs

- `droste-pve.yml` — Adds the PVE layer:
  - Configure PVE apt repo (no-subscription, DEB822 format)
  - Install PVE kernel, `pve-container`, `qemu-server`
  - Install DRBD utils + drbd-dkms (LINBIT repo)
  - Install targetcli-fb, open-iscsi
  - Install pacemaker, pcs, resource-agents
  - Install btrfs-progs
  - Skip pve-manager, pve-ha-manager
  - Configure pmxcfs for single-node operation

### Build Pipeline

```
Debian 12 cloud image (generic, ~250 MB)
    |
    v
ansible-playbook droste-base.yml
    |
    v
droste-base.qcow2 (exported, compressed)
    |
    v
ansible-playbook droste-pve.yml
    |
    v
droste-pve.qcow2 (exported as overlay, compressed)
```

Orchestrated by Packer, a shell script, or Makefile. The playbooks are also
runnable standalone against any existing Debian VM or bare metal.

## Testing Scenarios

Ranked by production pain avoided (based on real incidents from the Flamingo
Cluster build):

### Tier 1 — High-value (hours of production rework avoided)

1. **DRBD metadata upgrade (v08 → v09)**: The `create-md --force` mistake
   cost 17+ hours of full resync on 1.87 TB. With 1 GB droste virtual disks,
   this test takes seconds. Validate: `drbdadm down` → load new module →
   `drbdadm up` (in-place conversion, no `create-md`).

2. **Full Pacemaker failover cycle**: Standby primary → resources migrate →
   VIP moves → iSCSI reconnects → containers continue on initiator node.
   End-to-end, no production risk.

3. **DRBD split-brain + recovery**: Deliberately cause split-brain, verify
   handlers fire (`after-sb-0pri`, `after-sb-1pri`, `after-sb-2pri`), test
   manual `discard-my-data` recovery.

4. **DRBD multi-path resilience**: Test behavior when one path's interface
   goes down. Known issue: connect fails entirely if any configured path
   address can't be bound. Validate fixes before deploying.

5. **DRBD resync interruption**: Verify that disconnect/reconnect during
   resync preserves the bitmap and doesn't restart from zero.

### Tier 2 — Medium-value (prevents misconfig and debugging time)

6. **iSCSI device stability**: Verify `/dev/disk/by-path/` identifiers
   remain stable across reboots and failovers.

7. **Corosync multi-link**: Verify `ringN_addr` naming (not `linkN_addr`),
   test link failure with one ring down.

8. **LXC on iSCSI-backed storage**: Create unprivileged container with
   custom idmap, bind mounts. Verify stale-mount behavior after iSCSI
   interruption.

9. **Post-iSCSI-outage btrfs recovery**: Confirm btrfs goes read-only after
   write errors. Verify that `remount,rw` does NOT work and full
   `umount` + `mount` is required.

10. **Nested podman in LXC**: Test `nesting=1,fuse=1,keyctl=1`, `/dev/fuse`
    passthrough, rootless podman inside unprivileged container.

### Tier 3 — Setup validation

11. **PVE repo configuration**: DEB822 `.sources` format (leading spaces =
    silent failure), no-subscription repo, LINBIT repo with dearmored key.

12. **Pacemaker setup**: `pcs host auth` requires `/etc/hosts`, promotable
    DRBD clone needs `clone-max=2`, old targetcli config must be cleared.

13. **Corosync config location**: Must edit `/etc/pve/corosync.conf`
    (pmxcfs), not `/etc/corosync/corosync.conf`.

## Network Topology

Minimum two virtual networks inside droste to simulate production:

```
┌─────────────────────────────────────────────────┐
│  droste VM                                      │
│                                                 │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐       │
│  │ green   │   │  white  │   │   red   │       │
│  │ (nested │   │ (nested │   │ (nested │       │
│  │  VM/CT) │   │  VM/CT) │   │  VM/CT) │       │
│  └──┬──┬───┘   └──┬──┬───┘   └──┬──────┘       │
│     │  │          │  │          │               │
│  ───┼──┼──────────┼──┼──────────┼── vnet-mgmt  │
│     │  │          │  │               (all nodes)│
│     │  │          │  │                          │
│  ───┼──┴──────────┼──┘              vnet-direct │
│     │             │           (green↔white only) │
│     │             │                             │
│  ┌──┴─────────────┴──┐                          │
│  │   1 GB   1 GB     │                          │
│  │  (DRBD data disks)│                          │
│  └────────────────────┘                          │
└─────────────────────────────────────────────────┘
```

- **vnet-mgmt** (192.168.0.0/24): All nodes. Corosync ring 0, iSCSI, SSH.
- **vnet-direct** (10.0.0.0/30): Green ↔ white only. DRBD replication,
  Corosync ring 1.
- Optional 3rd network for WiFi simulation.

## Node Roles

| Role | Production | Droste equivalent | Resources |
|---|---|---|---|
| green | DRBD primary, iSCSI target | Nested VM or CT, 1 GB data disk | 1-2 GB RAM, 1-2 cores |
| white | DRBD secondary, iSCSI target | Nested VM or CT, 1 GB data disk | 1-2 GB RAM, 1-2 cores |
| red | iSCSI initiator, Samba, LXC host | Nested VM or CT, no data disk | 1 GB RAM, 1 core |

Total droste VM footprint: ~4-6 GB RAM, 4-6 cores for a 3-node simulation.

## Configuration Templates

Key config files that should be templatized for droste test clusters:

- `/etc/drbd.d/storage.res` — DRBD resource (both v8 and v9 syntax variants)
- `/etc/drbd.d/global_common.conf` — DRBD globals + split-brain handlers
- Corosync config (`/etc/pve/corosync.conf`) — multi-link, nodelist
- `/etc/iscsi/initiatorname.iscsi` — iSCSI initiator IQN
- targetcli saved config — backstores, targets, LUNs, ACLs
- `/etc/hosts` — node hostnames (required for `pcs host auth`)
- `/etc/network/interfaces` — multi-homed interfaces per node
- Pacemaker resource definitions — DRBD clone, VIP, iSCSI target/LUN group

## Relationship to Kanibako

Droste is a **separate project** with its own repository. Kanibako is the
first consumer — specifically, the kanibako LXC deployment script
(`create-proxmox-lxc.sh`) can be tested inside a droste VM without needing
a production Proxmox host.

Kanibako patterns reused in droste:
- Ansible playbook provisioning model
- CLI script conventions (flags, arg parsing, summary output)
- Cloud-init for initial VM bootstrap

Kanibako can list droste as an optional development dependency for testing
the Proxmox deployment paths.

## Distribution Formats

- **QCOW2** — primary format (Proxmox, libvirt, plain QEMU)
- **Proxmox template** — `.tar.zst` for direct `pveam` import (if feasible)
- **OVA** — for VirtualBox/VMware users
- **Raw** — convertible from QCOW2 via `qemu-img convert`

## Open Questions

1. **Agent autonomy**: The original framing included letting AI agents trigger
   tests without supervision. This implies an API or gateway layer on top of
   droste for submitting test jobs and collecting results. Design TBD.

2. **CI integration**: Can droste run in GitHub Actions (nested KVM)? GitHub
   runners support `/dev/kvm` on `ubuntu-latest`. This would allow testing
   Proxmox scripts in CI.

3. **Cluster-in-a-box script**: Beyond the raw image, should droste ship a
   script that boots 3 nested VMs, configures DRBD/Pacemaker/iSCSI between
   them, and produces a ready-to-test mini-cluster? (Likely yes, as a
   follow-up.)

4. **State management**: How to manage pre-built cluster snapshots (e.g.,
   "cluster at Phase 2, DRBD synced, Pacemaker running") so tests can start
   from a known state without rebuilding.

5. **Proxmox template feasibility**: Can a headless PVE install (no
   `pve-manager`) function correctly for `pct`/`qm` operations, or does the
   API daemon need to be running? Needs testing.

## Prior Art / Related Projects

- **Packer** — VM image builder (could orchestrate droste builds)
- **Vagrant** — multi-VM environments (heavier, VirtualBox-centric)
- **Firecracker** — microVMs for sandboxing (lighter but no nested PVE)
- **Kata Containers** — VM-isolated containers (different purpose)
- **LINBIT/virter** — LINBIT's own tool for spinning up DRBD test VMs
- **Proxmox nested virtualization** — documented but not packaged as a
  reusable image

## Lessons Learned (Flamingo Cluster)

Real incidents that droste testing would have prevented or mitigated:

| Incident | Cost | Droste test time |
|---|---|---|
| `create-md --force` destroyed DRBD bitmap | 17+ hours full resync of 1.87 TB | Seconds (1 GB disk) |
| Bringing down interface during DRBD resync | Resync progress lost, hours to recover | Seconds |
| `linkN_addr` in corosync config silently ignored | Hours debugging why 2nd ring didn't work | Minutes |
| iSCSI device name changed after reboot | Broken fstab, manual recovery | Minutes |
| btrfs `remount,rw` doesn't work after I/O errors | Data inaccessible until full umount/mount | Minutes |
| DRBD multi-path: all paths fail if one can't bind | Complete replication loss on single NIC failure | Minutes |
