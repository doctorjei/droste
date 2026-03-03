# Building

```bash
scripts/build.sh thread          # build + test thread
scripts/build.sh yarn build      # build yarn (no test)
scripts/build.sh fabric test     # test an existing fabric image
```

Requires KVM and Packer. Each tier auto-builds its prerequisites if missing.

## Testing

**SSH smoke tests** run after boot, verifying the current tier's packages are present:

```bash
scripts/ssh-smoke-test.sh --port 2222 --ssh-key KEY checks/thread.checks
```

**Guest regression tests** run inside packer during the build, verifying that all *previous* tier packages survived the current tier's provisioning. This catches accidental package removal early — before the image is finalized.

## Image Layout

```
checks/              Check definition files (one per tier)
scripts/             Build, boot, and test scripts
ansible/             Ansible playbooks (one per tier)
packer/              Packer HCL configs (one per tier)
output-droste-*/     Built QCOW2 images (gitignored)
```
