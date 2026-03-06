# Building

Droste images are built with two pipelines: **VM** (Packer + Ansible) and
**OCI** (Podman Containerfiles). Both are driven by the `drostify` script.

```bash
scripts/drostify [COMMAND] [IMAGE] [OPTIONS]
```

Bare tier names are auto-detected — `drostify build fiber` routes to OCI,
`drostify build thread` routes to VM. Use explicit prefixes (`vm`, `oci`)
when you want to be specific.

## VM Builds

Requires KVM and Packer. Each tier auto-builds its prerequisites if missing.

```bash
drostify build thread              # build thread
drostify build yarn                # build yarn (auto-builds thread if missing)
drostify build all                 # build all VM tiers
drostify build all --force         # rebuild all VM tiers (overwrite existing)
drostify build yarn --force-cascade  # rebuild yarn + fabric + tapestry + loom + jacquard
drostify vm build thread           # explicit VM prefix
```

### VM Testing

```bash
drostify test thread               # boot + smoke test thread
drostify test all                  # smoke test all VM tiers
drostify vm test yarn              # explicit VM prefix
```

## OCI Builds

Requires Podman. The seed base image must be built first (separately).

### Building seed

The seed is built by a standalone script that extracts the genericcloud
qcow2 image, strips kernel/boot/init packages, creates the droste user,
and imports the result into Podman. Requires root and nbd kernel module.

```bash
sudo containers/droste-seed/build-seed.sh
```

### Building tiers

Once seed exists, all other OCI tiers build via Containerfiles:

```bash
drostify oci build fiber           # build fiber (process container)
drostify oci build fiber-lxc       # build fiber-lxc (kento-bootable)
drostify oci build sheet           # builds fiber first if missing
drostify oci build app-all         # all process containers (non-lxc)
drostify oci build sys-all         # all system containers (-lxc variants)
drostify oci build vm-all          # all VM-bootable containers (-vm variants)
drostify oci build all             # all OCI tiers (app + sys + vm)
drostify oci build sheet --force-cascade  # rebuild sheet + all downstream
```

### OCI Testing

```bash
drostify oci test fiber            # test fiber
drostify oci test all              # test all OCI tiers
```

### VM-bootable OCI images (-vm)

The `-vm` tier line adds kernel files (`/boot/vmlinuz` and `/boot/initramfs.img`)
on top of each `-lxc` image, enabling boot via kento VM mode (QEMU + virtiofs).

```bash
drostify oci build seed-vm         # build VM-bootable seed
drostify oci build vm-all          # build all -vm tiers
```

### Pushing seed to GHCR

CI workflows pull the seed image from GHCR. Push it after building:

```bash
scripts/push-seed-to-ghcr.sh
```

## Build-All

Build everything (OCI + VM) in one command:

```bash
drostify build-all                 # build all OCI + VM images
drostify build-all --force         # rebuild everything
```

## Options

| Flag | Effect |
|------|--------|
| `--force` | Rebuild named tier(s) even if images already exist |
| `--force-cascade` | Rebuild named tier(s) and all downstream dependents |
| `--verbose` | Show full build output (builds are quiet by default) |
| `--ssh-key FILE` | SSH public key for VM boot/test (default: auto-detect) |
| `--ssh-port PORT` | Host SSH port for VM boot/test (default: 2222) |

Default behavior (no flags) skips tiers whose images already exist.

## Credentials

### VM images

VM images ship with a `droste` user (UID 1000) and passwordless sudo. The
password is currently `droste` but will be locked in a future rebuild. SSH
key injection via cloud-init is the intended auth method — see the SSH Key
Injection section below.

### OCI images

OCI images have a `droste` user (UID 1000) with passwordless sudo. No
login password is set.

## SSH Key Injection

VM images require an SSH public key via cloud-init on first boot. The
`boot-droste.sh` script handles this:

```bash
scripts/boot-droste.sh --ssh-key ~/.ssh/id_ed25519.pub
```

Without an SSH key, the VM will boot but you will have no way to log in.
The `--ssh-key` flag is required.

For deployments outside `boot-droste.sh` (libvirt, Proxmox, OpenStack),
pass a cloud-init user-data that includes `ssh_authorized_keys` for the
`droste` user. See `cloud-init/user-data.yml` for the template.

### boot-droste.sh options

| Flag | Default | Effect |
|------|---------|--------|
| `--image FILE` | output-droste-thread/droste-thread.qcow2 | Base QCOW2 image |
| `--memory MB` | 2048 | Memory allocation |
| `--cpus N` | 2 | CPU count |
| `--ssh-port PORT` | 2222 | Host SSH forwarding port |
| `--ssh-key FILE` | (required) | SSH public key |
| `--hostname NAME` | droste | Guest hostname |
| `--share DIR` | — | Mount host directory via virtiofs at /mnt/share |
| `--persist` | — | Persistent overlay (changes survive reboot) |
| `--daemonize` | — | Run QEMU in background |

### Build-time vs runtime authentication

During Packer builds, the inline cloud-init in each `.pkr.hcl` creates a
temporary password so Packer can SSH in for provisioning. The ansible
playbook then locks the password and disables SSH password auth before
the image is finalized. The password in the Packer configs is build-only
and never present in shipped images.

## Testing

### VM smoke tests

SSH smoke tests run after boot, verifying the current tier's packages:

```bash
scripts/ssh-smoke-test.sh --port 2222 --ssh-key KEY checks/thread.checks
```

### OCI tests

OCI tests run containers and verify packages via check files:

```bash
drostify oci test fiber            # test fiber process container
drostify oci test fiber-lxc        # test fiber kento-bootable
drostify oci test all              # test all OCI tiers
```

### Check files

Check files live in `checks/` (one per tier, tab-separated format):

```
description<TAB>command[<TAB>ssh-only]
```

OCI check files use `@quiet <file>` directives to include parent tier
checks (run silently, failures still reported). Use `@stop` to mark a
section boundary — checks after `@stop` are not included by child tiers.

## Image Layout

```
checks/              Check files (one per tier, tab-separated)
scripts/             Build, boot, and test scripts
ansible/             Ansible playbooks (one per VM tier)
packer/              Packer HCL configs (one per VM tier)
containers/          OCI Containerfiles (one dir per tier)
  droste-seed/       Seed build script + target package list
  droste-fiber/      Fiber Containerfile
  droste-fiber-lxc/  Fiber-lxc Containerfile
  ...                (one directory per OCI tier)
oci/                 OCI build support files
  seed-oci-exclude.txt  Packages stripped from seed (reinstalled in -lxc)
output-droste-*/     Built QCOW2 images (gitignored)
```
