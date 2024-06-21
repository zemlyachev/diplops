locals {
  ssh_public_key = file("~/.ssh/id_rsa.pub")
  ubuntu_ssh_key = "ubuntu:${local.ssh_public_key}"
}
