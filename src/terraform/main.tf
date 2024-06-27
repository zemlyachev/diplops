terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
    backend "s3" {
      endpoints = {
        s3 = "https://storage.yandexcloud.net"
      }
      bucket = "diplom-terraform-state"
      region = "ru-central1-a"
      key    = "terraform.tfstate"

      skip_region_validation      = true
      skip_credentials_validation = true
      skip_requesting_account_id  = true # Необходимая опция Terraform для версии 1.6.1 и старше.
      skip_s3_checksum            = true # Необходимая опция при описании бэкенда для Terraform версии 1.6.3 и старше.
    }
}
provider "yandex" {
  token     = var.YC_TOKEN
  cloud_id  = var.YC_CLOUD_ID
  folder_id = var.YC_FOLDER_ID
  zone      = var.YC_ZONE
}

# Main Terraform SA
resource "yandex_iam_service_account" "sa-ter-diplom" {
  folder_id = var.YC_FOLDER_ID
  name      = "sa-ter-diplom"
}
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.YC_FOLDER_ID
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-ter-diplom.id}"
}

# Backend bucket access key
resource "yandex_iam_service_account_static_access_key" "accesskey-bucket" {
  service_account_id = yandex_iam_service_account.sa-ter-diplom.id
}

# Backend bucket
resource "yandex_storage_bucket" "diplom-terraform-state" {
  access_key            = yandex_iam_service_account_static_access_key.accesskey-bucket.access_key
  secret_key            = yandex_iam_service_account_static_access_key.accesskey-bucket.secret_key
  bucket                = "diplom-terraform-state"
  default_storage_class = "STANDARD"
  acl                   = "public-read"
  force_destroy         = "true"
  depends_on            = [yandex_iam_service_account_static_access_key.accesskey-bucket]
  anonymous_access_flags {
    read        = true
    list        = true
    config_read = true
  }
}

# VPC
resource "yandex_vpc_network" "network-diplom" {
  name      = "network-diplom"
  folder_id = var.YC_FOLDER_ID
}
# Subnets
resource "yandex_vpc_subnet" "subnet" {
  for_each       = tomap(var.subnets)
  name           = "subnet-${each.key}"
  zone           = "ru-central1-${each.key}"
  network_id     = yandex_vpc_network.network-diplom.id
  v4_cidr_blocks = [each.value]
}

########## Cluster k8s ##########

# VM Worker Nodes
resource "yandex_compute_instance" "node-worker" {
  for_each                  = tomap(var.subnets)
  name                      = "node-worker-${each.key}"
  zone                      = "ru-central1-${each.key}"
  hostname                  = "node-worker-${each.key}"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  boot_disk {
    initialize_params {
      image_id = var.ubuntu_image_id
      size     = 10
    }
  }
  scheduling_policy {
    preemptible = true
  }
  network_interface {
    subnet_id = "${yandex_vpc_subnet.subnet[each.key].id}"
    nat       = true
  }
  metadata = {
    serial-port-enable = 1
    ssh-keys           = local.ubuntu_ssh_key
  }
}

# VM kube master node
resource "yandex_compute_instance" "node-master" {
  name                      = "node-master-a"
  hostname                  = "node-master-a"
  zone                      = "ru-central1-a"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = var.ubuntu_image_id
      size     = 10
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet["a"].id
    nat       = true
  }
  metadata = {
    serial-port-enable = 1
    ssh-keys           = local.ubuntu_ssh_key
  }
}

# Create init inventory file
resource "local_file" "inventory-init" {
  content    = <<EOF1
[kube-master]
${yandex_compute_instance.node-master.network_interface.0.nat_ip_address}
  EOF1
  filename   = "../ansible/inventory-init"
  depends_on = [yandex_compute_instance.node-master]
}

# Create Kubespray inventory
resource "local_file" "inventory-kubespray" {
  content    = <<EOF2
all:
  hosts:
    ${yandex_compute_instance.node-master.fqdn}:
      ansible_host: ${yandex_compute_instance.node-master.network_interface.0.ip_address}
      ip: ${yandex_compute_instance.node-master.network_interface.0.ip_address}
      access_ip: ${yandex_compute_instance.node-master.network_interface.0.ip_address}
%{ for worker in yandex_compute_instance.node-worker ~}
    ${worker.fqdn}:
      ansible_host: ${worker.network_interface.0.ip_address}
      ip: ${worker.network_interface.0.ip_address}
      access_ip: ${worker.network_interface.0.ip_address}
%{ endfor ~}
  children:
    kube_control_plane:
      hosts:
        ${yandex_compute_instance.node-master.fqdn}:
    kube_node:
      hosts:
%{ for worker in yandex_compute_instance.node-worker ~}
        ${worker.fqdn}:
%{ endfor ~}
    etcd:
      hosts:
        ${yandex_compute_instance.node-master.fqdn}:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
  EOF2
  filename   = "../ansible/inventory-kubespray"
  depends_on = [yandex_compute_instance.node-master, yandex_compute_instance.node-worker]
}

output "external_ip_address_master" {
  value = yandex_compute_instance.node-master.network_interface.0.nat_ip_address
}



