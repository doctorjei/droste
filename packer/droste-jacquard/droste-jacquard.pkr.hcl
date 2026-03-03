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
  default = "../../output-droste-loom/droste-loom.qcow2"
}

variable "disk_size" {
  type    = string
  default = "8G"
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cpus" {
  type    = number
  default = 2
}

# ── Source ──────────────────────────────────────────────────────────
source "qemu" "droste-jacquard" {
  vm_name      = "droste-jacquard.qcow2"
  disk_image   = true
  iso_url      = var.base_image
  iso_checksum = "none"
  disk_size    = var.disk_size
  format       = "qcow2"

  accelerator  = "kvm"
  cpus         = var.cpus
  memory       = var.memory

  headless     = true
  vnc_port_min = 5900
  vnc_port_max = 5999

  # Bootstrap cloud-init: re-enable password auth so Packer can SSH in.
  # The playbook re-hardens SSH before shutdown.
  cd_content = {
    "meta-data" = ""
    "user-data" = <<-EOF
      #cloud-config
      users:
        - name: agent
          uid: "1000"
          groups: sudo
          shell: /bin/bash
          sudo: ALL=(ALL) NOPASSWD:ALL
          lock_passwd: false
          plain_text_passwd: packer
      ssh_pwauth: true
    EOF
  }
  cd_label = "cidata"

  ssh_username = "agent"
  ssh_password = "packer"
  ssh_timeout  = "10m"

  boot_wait = "30s"

  shutdown_command = "sudo shutdown -P now"

  output_directory = "../../output-droste-jacquard"

  qemuargs = [
    ["-cpu", "host"],
  ]
}

# ── Build ───────────────────────────────────────────────────────────
build {
  sources = ["source.qemu.droste-jacquard"]

  provisioner "ansible" {
    playbook_file = "../../ansible/droste-jacquard.yml"
    user          = "agent"
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SCP_EXTRA_ARGS=-O",
      "ANSIBLE_COW_PATH=${path.root}/../../ansible/files",
      "ANSIBLE_COW_SELECTION=droste",
    ]
    extra_arguments = [
      "--become",
    ]
  }

  post-processor "shell-local" {
    inline = [
      "qemu-img convert -O qcow2 -c ../../output-droste-jacquard/droste-jacquard.qcow2 ../../output-droste-jacquard/droste-jacquard-compressed.qcow2",
      "mv ../../output-droste-jacquard/droste-jacquard-compressed.qcow2 ../../output-droste-jacquard/droste-jacquard.qcow2",
    ]
  }
}
