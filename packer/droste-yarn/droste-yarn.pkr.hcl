packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ── Variables ───────────────────────────────────────────────────────
variable "base_image" {
  type    = string
  default = "../../output-droste-thread/droste-thread.qcow2"
}

variable "disk_size" {
  type    = string
  default = "8G"
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cpus" {
  type    = number
  default = 2
}

# ── Source ──────────────────────────────────────────────────────────
source "qemu" "droste-yarn" {
  vm_name      = "droste-yarn.qcow2"
  disk_image       = true
  use_backing_file = true
  iso_url          = var.base_image
  iso_checksum = "none"
  disk_size    = var.disk_size
  format       = "qcow2"

  accelerator  = "kvm"
  cpus         = var.cpus
  memory       = var.memory

  headless     = true
  vnc_port_min = 5900
  vnc_port_max = 5999

  # Bootstrap cloud-init: create droste user with password so Packer
  # can SSH in. The final image keeps password auth enabled.
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-EOF
      #cloud-config
      users:
        - name: droste
          uid: "1000"
          groups: sudo
          shell: /bin/bash
          sudo: ALL=(ALL) NOPASSWD:ALL
          lock_passwd: false
          plain_text_passwd: droste
      ssh_pwauth: true
    EOF
  }
  cd_label = "cidata"

  ssh_username = "droste"
  ssh_password = "droste"
  ssh_timeout  = "10m"

  boot_wait = "30s"

  shutdown_command = "sudo shutdown -P now"

  output_directory = "../../output-droste-yarn"

  qemuargs = [
    ["-cpu", "host"],
  ]
}

# ── Build ───────────────────────────────────────────────────────────
build {
  sources = ["source.qemu.droste-yarn"]

  provisioner "ansible" {
    playbook_file = "../../ansible/droste-yarn.yml"
    user          = "droste"
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_DISPLAY_SKIPPED_HOSTS=false",
      "ANSIBLE_SCP_EXTRA_ARGS=-O",
      "COWPATH=${abspath("${path.root}/../../ansible/files")}",
      "ANSIBLE_COW_SELECTION=droste",
      "ANSIBLE_COW_ACCEPTLIST=droste",
      "PERL_UNICODE=SDA",
    ]
    extra_arguments = [
      "--become",
    ]
  }

  # ── Guest regression test (previous tiers) ──────────────────────
  provisioner "file" {
    source      = "../../checks"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "../../scripts/guest-regression-test.sh"
    destination = "/tmp/guest-regression-test.sh"
  }

  provisioner "shell" {
    inline = ["sudo bash /tmp/guest-regression-test.sh /tmp/checks/thread.checks"]
  }

  # ── Cleanup ──────────────────────────────────────────────────────
  provisioner "file" {
    source      = "../../scripts/cleanup-image.sh"
    destination = "/tmp/cleanup-image.sh"
  }

  provisioner "shell" {
    inline = ["sudo bash /tmp/cleanup-image.sh"]
  }

  # use_backing_file produces an overlay on thread (only changed blocks).
  # Produce both a standalone image and a portable diff.
  post-processor "shell-local" {
    inline = [
      # Diff image: create with real backing path, then rebase to bare filename for portability
      "qemu-img convert -O qcow2 -c -B ../output-droste-thread/droste-thread.qcow2 -F qcow2 ../../output-droste-yarn/droste-yarn.qcow2 ../../output-droste-yarn/droste-yarn-diff.qcow2",
      "qemu-img rebase -u -b droste-thread.qcow2 -F qcow2 ../../output-droste-yarn/droste-yarn-diff.qcow2",
      # Standalone image: flatten overlay into self-contained image
      "qemu-img convert -O qcow2 -c ../../output-droste-yarn/droste-yarn.qcow2 ../../output-droste-yarn/droste-yarn-standalone.qcow2",
      # Replace raw overlay with standalone
      "mv ../../output-droste-yarn/droste-yarn-standalone.qcow2 ../../output-droste-yarn/droste-yarn.qcow2",
    ]
  }
}
