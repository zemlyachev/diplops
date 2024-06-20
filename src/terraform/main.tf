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



