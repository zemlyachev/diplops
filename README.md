# Дипломный практикум в Yandex.Cloud
* [Цели:](#цели)
* [Этапы выполнения:](#этапы-выполнения)
    * [Создание облачной инфраструктуры](#создание-облачной-инфраструктуры)
    * [Создание Kubernetes кластера](#создание-kubernetes-кластера)
    * [Создание тестового приложения](#создание-тестового-приложения)
    * [Подготовка cистемы мониторинга и деплой приложения](#подготовка-cистемы-мониторинга-и-деплой-приложения)
    * [Установка и настройка CI/CD](#установка-и-настройка-cicd)
* [Что необходимо для сдачи задания?](#что-необходимо-для-сдачи-задания)
* [Как правильно задавать вопросы дипломному руководителю?](#как-правильно-задавать-вопросы-дипломному-руководителю)

**Перед началом работы над дипломным заданием изучите [Инструкция по экономии облачных ресурсов](https://github.com/netology-code/devops-materials/blob/master/cloudwork.MD).**

---
## Цели:

1. Подготовить облачную инфраструктуру на базе облачного провайдера Яндекс.Облако.
2. Запустить и сконфигурировать Kubernetes кластер.
3. Установить и настроить систему мониторинга.
4. Настроить и автоматизировать сборку тестового приложения с использованием Docker-контейнеров.
5. Настроить CI для автоматической сборки и тестирования.
6. Настроить CD для автоматического развёртывания приложения.

---
## Этапы выполнения:

### Создание облачной инфраструктуры

Предварительная подготовка к установке и запуску Kubernetes кластера.

#### Конфигурация и сервисный аккаунт

1. Установим новую версию терраформа `brew install hashicorp/tap/terraform` так как `brew install terraform` - deprecated версия 1.5.7
2. Настроим доступ согласно [официальной инструкции](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart#configure-terraform) 
3. Добавим аутентификационные данные в переменные окружения:
```bash
export TF_VAR_YC_TOKEN=$(yc iam create-token)
export TF_VAR_YC_CLOUD_ID=$(yc config get cloud-id)
export TF_VAR_YC_FOLDER_ID=$(yc config get folder-id)
export TF_VAR_YC_ZONE=$(yc config get compute-default-zone)
```
> Если `yc config get compute-default-zone`, то предварительно выполним `yc config set compute-default-zone "ru-central1-a"`
4. Создадим файл [`main.tf`](src/terraform/main.tf) для Terraform с информацией об облачном провайдере:
```hcl
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.YC_TOKEN
  cloud_id  = var.YC_CLOUD_ID
  folder_id = var.YC_FOLDER_ID
  zone      = var.YC_ZONE
}
```
5. Добавим описание основных переменных для провайдера из переменных окружения в файл [`variables.tf`](src/terraform/variables.tf)
```hcl
variable "YC_TOKEN" { type = string }
variable "YC_FOLDER_ID" { type = string }
variable "YC_CLOUD_ID" { type = string }
variable "YC_ZONE" { type = string }
```
6. Дополним [`main.tf`](src/terraform/main.tf) сервисным аккаунтом `sa-ter-diplom` с ролью `editor`:
```hcl
resource "yandex_iam_service_account" "sa-ter-diplom" {
  folder_id = var.YC_FOLDER_ID
  name      = "sa-ter-diplom"
}
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.YC_FOLDER_ID
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-diploma.id}"
}
```

#### Backend Terraform 

1. Подготовим bucket для backend
```hcl
 Backend bucket access key
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
```
2. Выполним `terraform init`:
![](.README_images/b04580f6.png)
3. Проверим `terraform validate`:
![](.README_images/ee3d56e0.png)
4. Выполним `terraform plan` и `terraform apply`:
![](.README_images/6a5dc30e.png)
![](.README_images/ef3003e2.png)
5. Получим ключи доступа для сервисного аккаунта
```bash
yc iam service-account list
yc iam access-key create --service-account-name sa-ter-diplom
```
![](.README_images/79be10d3.png)
6. Прихраним ключи в переменных окружения
```bash
export SA_TER_ACCESS_KEY="<идентификатор_ключа>"
export SA_TER_SECRET_KEY="<секретный_ключ>"
```
![](.README_images/ec90afcd.png)
7. Добавим описание бекенда в [`main.tf`](src/terraform/main.tf)
```hcl
terraform {
  ...  
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
```
8. Для переноса состояния выполним `terraform init -backend-config="access_key=$SA_TER_ACCESS_KEY" -backend-config="secret_key=$SA_TER_SECRET_KEY"
![](.README_images/8f0ba50d.png)
![](.README_images/440b76ba.png)

#### Создайте VPC с подсетями в разных зонах доступности

1. Для начала опишем variable:
```hcl
variable "subnets" {
  type    = map(string)
  default = ({
    a = "192.168.10.0/24",
    b = "192.168.20.0/24",
    c = "192.168.30.0/24"
  })
}
```
2. Опишем в [`main.tf`](src/terraform/main.tf) VPC и подсети
```hcl
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
```
3. Применим
![](.README_images/98557de6.png)
![](.README_images/0dff70d0.png)
4. Terraform сконфигурирован и создание инфраструктуры посредством Terraform возможно без дополнительных ручных действий.

### Создание Kubernetes кластера

