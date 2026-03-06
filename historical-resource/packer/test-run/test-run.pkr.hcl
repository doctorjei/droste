packer {
  required_plugins {
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "null" "cow" {
  communicator = "none"
}

build {
  sources = ["source.null.cow"]

  # Test 1: raw UTF-8 echo through Packer's output handler
  provisioner "shell-local" {
    inline = [
      "echo '--- Direct UTF-8 echo ---'",
      "echo '╔═╤═╤════╗'",
      "echo '╟─┘■│    ║'",
      "echo '╟───┘ ██ ║'",
      "echo '║        ║'",
      "echo '╚════════╝'",
    ]
  }

  # Test 2: Ansible with droste cow (full pipeline: cowsay → Ansible → Packer)
  provisioner "shell-local" {
    environment_vars = [
      "PERL_UNICODE=SDA",
      "COWPATH=${abspath("${path.root}/../../ansible/files")}",
      "ANSIBLE_COW_SELECTION=droste",
      "ANSIBLE_COW_ACCEPTLIST=droste",
    ]
    inline = [
      "ansible-playbook ${abspath("${path.root}/test-run-playbook.yml")}",
    ]
  }
}
