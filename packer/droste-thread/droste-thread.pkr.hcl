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
variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "debian_image_checksum" {
  type    = string
  default = "none"
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
source "qemu" "droste-thread" {
  vm_name      = "droste-thread.qcow2"
  disk_image   = true
  iso_url      = var.debian_image_url
  iso_checksum = var.debian_image_checksum
  disk_size    = var.disk_size
  format       = "qcow2"

  accelerator  = "kvm"
  cpus         = var.cpus
  memory       = var.memory

  headless     = true
  vnc_port_min = 5900
  vnc_port_max = 5999

  # Bootstrap cloud-init: create agent user with temporary password
  # so Packer can SSH in. The Ansible playbook then hardens SSH
  # (disables password auth), so the final image is key-only.
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

  # Give cloud-init time to create the user and start sshd
  boot_wait = "30s"

  shutdown_command = "sudo shutdown -P now"

  output_directory = "../../output-droste-thread"

  qemuargs = [
    ["-cpu", "host"],
  ]
}

# ── Build ───────────────────────────────────────────────────────────
build {
  sources = ["source.qemu.droste-thread"]

  # OpenSSH 9.0+ changed scp to use SFTP mode by default, which breaks
  # Packer's SSH proxy adapter. The -O flag forces legacy SCP mode.
  # See: https://github.com/hashicorp/packer-plugin-ansible/issues/100
  provisioner "ansible" {
    playbook_file = "../../ansible/droste-thread.yml"
    user          = "agent"
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SCP_EXTRA_ARGS=-O",
    ]
    extra_arguments = [
      "--become",
    ]
  }

  # Upload and run smoke tests inside the guest before shutdown.
  provisioner "file" {
    source      = "../../scripts/smoke-test-guest-thread.sh"
    destination = "/tmp/smoke-test-guest-thread.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/smoke-test-guest-thread.sh",
      "sudo /tmp/smoke-test-guest-thread.sh",
      "rm -f /tmp/smoke-test-guest-thread.sh",
    ]
  }

  # Compact the QCOW2 after provisioning. The playbook zeroes free space,
  # so qemu-img convert -c reclaims it effectively.
  post-processor "shell-local" {
    inline = [
      "qemu-img convert -O qcow2 -c ../../output-droste-thread/droste-thread.qcow2 ../../output-droste-thread/droste-thread-compressed.qcow2",
      "mv ../../output-droste-thread/droste-thread-compressed.qcow2 ../../output-droste-thread/droste-thread.qcow2",
    ]
  }
}
