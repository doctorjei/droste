packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# ── Variables ───────────────────────────────────────────────────────
variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

variable "debian_image_checksum" {
  type    = string
  default = "sha512:6da628d0f44ddcc8641d5ed1c7a1b4841ccf6608810a8f7aae860db51e9975e76b3c230728560337b615f8b610a34a760cf9d18e8ddb55c48608a06724ea0892"
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
source "qemu" "droste-lint" {
  vm_name      = "droste-lint.qcow2"
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

  output_directory = "../../output-droste-lint"

  qemuargs = [
    ["-cpu", "host"],
  ]
}

# ── Build ───────────────────────────────────────────────────────────
# Lint is genericcloud with the droste user baked in — nothing else.
# Cloud-init creates the user at boot; we just clean up and compress.
build {
  sources = ["source.qemu.droste-lint"]

  # ── Cleanup ──────────────────────────────────────────────────────
  provisioner "file" {
    source      = "../../scripts/cleanup-image.sh"
    destination = "/tmp/cleanup-image.sh"
  }

  provisioner "shell" {
    inline = ["sudo bash /tmp/cleanup-image.sh"]
  }

  post-processor "shell-local" {
    inline = [
      "qemu-img convert -O qcow2 -c ../../output-droste-lint/droste-lint.qcow2 ../../output-droste-lint/droste-lint-compressed.qcow2",
      "mv ../../output-droste-lint/droste-lint-compressed.qcow2 ../../output-droste-lint/droste-lint.qcow2",
    ]
  }
}
