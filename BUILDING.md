# Building

```bash
scripts/drostify build thread          # build + test thread
scripts/drostify build yarn            # build + test yarn
scripts/drostify test fabric           # test an existing fabric image
scripts/drostify test all              # smoke test all tiers
scripts/drostify build all             # build all tiers (requires --force if images exist)
scripts/drostify all jacquard          # build prerequisites + jacquard
```

Requires KVM and Packer. Each tier auto-builds its prerequisites if missing.

## Default Credentials

| Field | Value |
|-------|-------|
| Username | `droste` |
| Password | locked (no login password) |
| UID/GID | 1000 |
| Sudo | passwordless (NOPASSWD) |
| SSH | key auth only (password auth disabled) |

## SSH Key Injection

VM images have no login password. You must provide an SSH public key via
cloud-init on first boot. The `boot-droste.sh` script handles this:

```bash
scripts/boot-droste.sh --ssh-key ~/.ssh/id_ed25519.pub
```

Without an SSH key, the VM will boot but you will have no way to log in
(no console password, no SSH password auth). The `--ssh-key` flag is
required.

For deployments outside `boot-droste.sh` (libvirt, Proxmox, OpenStack),
pass a cloud-init user-data that includes `ssh_authorized_keys` for the
`droste` user. See `cloud-init/user-data.yml` for the template.

### Build-time vs runtime authentication

During Packer builds, the inline cloud-init in each `.pkr.hcl` creates a
temporary password so Packer can SSH in for provisioning. The ansible
playbook then locks the password and disables SSH password auth before
the image is finalized. The password in the Packer configs is build-only
and never present in shipped images.

## Testing

**SSH smoke tests** run after boot, verifying the current tier's packages are present:

```bash
scripts/ssh-smoke-test.sh --port 2222 --ssh-key KEY checks/thread.checks
```

Check files use tab-separated format: `description<TAB>command[<TAB>ssh-only]`

**Guest regression tests** run inside packer during the build, verifying that all *previous* tier packages survived the current tier's provisioning. This catches accidental package removal early — before the image is finalized.

## Image Layout

```
checks/              Check definition files (one per tier, tab-separated)
scripts/             Build, boot, and test scripts
ansible/             Ansible playbooks (one per tier)
packer/              Packer HCL configs (one per tier)
output-droste-*/     Built QCOW2 images (gitignored)
```
