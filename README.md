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
    d = "192.168.30.0/24"
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

#### Подготавливаем виртуальные машины Compute Cloud для создания Kubernetes-кластера

1. Добавим в файлы 
* [locals.tf](src/terraform/locals.tf):
```hcl
locals {
  ssh_public_key = file("~/.ssh/id_rsa.pub")
  ubuntu_ssh_key = "ubuntu:${local.ssh_public_key}"
}
```
* [variables.tf](src/terraform/variables.tf):
```hcl
variable "ubuntu_image_id" {
  type        = string
  default     = "fd88bokmvjups3o0uqes"
  description = "ubuntu-22-04-lts-v20240603"
}
```
* [main.tf](src/terraform/main.tf):
```hcl
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

output "external_ip_address_master" {
  value = yandex_compute_instance.node-master.network_interface.0.nat_ip_address
}
```
2. Для конфигурации Kubespray создадим манифесты с помощью terraform:
```hcl
# Create init inventory file
resource "local_file" "inventory-init" {
  content    = <<EOF1
[kube-cloud]
${yandex_compute_instance.node-master.network_interface.0.nat_ip_address}
%{ for worker in yandex_compute_instance.node-worker }
${worker.network_interface.0.nat_ip_address}
%{ endfor }
  EOF1
  filename   = "../ansible/inventory-init"
  depends_on = [yandex_compute_instance.node-master, yandex_compute_instance.node-worker]
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
%{ for worker in yandex_compute_instance.node-worker }
    ${worker.fqdn}:
      ansible_host: ${worker.network_interface.0.ip_address}
      ip: ${worker.network_interface.0.ip_address}
      access_ip: ${worker.network_interface.0.ip_address}
%{ endfor }
  children:
    kube_control_plane:
      hosts:
        ${yandex_compute_instance.node-master.fqdn}:
    kube_node:
      hosts:
%{ for worker in yandex_compute_instance.node-worker }
        ${worker.fqdn}:
%{ endfor }
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
```
3. Применим
![](.README_images/1e330d2c.png)
> В процессе внешний ip-адрес мастер ноды будет меняться...

![](.README_images/9299dd9b.png)
4. На выходе получили 2 файла
   * [inventory-init](src/ansible/inventory-init)
   * [inventory-kubespray](src/ansible/inventory-kubespray)

#### Деплой Kubernetes

1. Выполним подготовку `ansible-playbook -i inventory-init -b -v -u ubuntu init.yaml`
   ![](.README_images/d120a42b.png)

2. Дополним файлики
   - `vim kubespray/inventory/diplom-cluster/group_vars/k8s_cluster/addons.yml`

       ```yaml
       helm_enabled: true
       ingress_nginx_enabled: true
       ingress_nginx_host_network: true
       ```
   - `vim kubespray/inventory/diplom-cluster/group_vars/k8s_cluster/k8s-cluster.yml`

       ```yaml
       supplementary_addresses_in_ssl_keys: [158.160.100.70] - внешний ip
       ```
     
3. Подключаемся на мастер ноду, которая будет control plane, и запускаем плейбук kybespray
    ```bash
    cd kubespray/
    sudo ansible-playbook -i inventory/diplom-cluster/inventory-kubespray -u ubuntu -b -v --private-key=/home/ubuntu/.ssh/id_rsa cluster.yml
    ```
   ![](.README_images/c1d0d8fb.png)
3. Настроим kubectl
    ```bash
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    ```
4. Развернутый кластер
    ![](.README_images/ed01aaa8.png)
    ![](.README_images/2d9d5412.png)

5. Заберем конфиг на локальную машину для удобства
    ![](.README_images/0a9bc902.png)
    Теперь управление кластером доступно локально

#### Создание тестового приложения

##### Пререквизиты
* установлен docker
![](.README_images/f2e29efe.png)

###### Образ

1. Создадим отдельный публичный репозиторий https://github.com/zemlyachev/diplops-app
2. Возьмем для примера любой шаблон
3. Напишем простейший Dokerfile
4. Проверим сборку и запуск локально
    ![](.README_images/a76b0d9b.png)
5. Поправим пару моментов в шаблоне
6. Проверим работоспособность образа
    ![](.README_images/befc37ee.png)
7. Локально работает
    ![](.README_images/b01459cb.png)

###### Yandex Container Registry, созданный также с помощью terraform

1. Дополним наш [`main.tf`](src/terraform/main.tf) директивой для хранилища образов
    ```hcl
    # Yandex Container Registry
    resource "yandex_container_registry" "diplops-reg" {
      name = "diplops-registry"
      folder_id = var.YC_FOLDER_ID
    }
    
    output "first_part_of_docker_image_tag" {
      value = "cr.yandex/${yandex_container_registry.diplops-reg.id}/"
    }
    ```
2. Применим
    ![](.README_images/260a245b.png)

###### Деплой образа в реестр

1. Образы необходимо создавать с тегом, или добавить тек в последствии для деплоя его в реестр
2. Добавим тег к ранее собранному образу
    ![](.README_images/5ba58fdc.png)
3. Настроем докер на YCR
    ![](.README_images/01986553.png)
4. Запушим в реестр
    ![](.README_images/f8d31ff8.png)
    ![](.README_images/e0b8b4dd.png)

#### Подготовка cистемы мониторинга и деплой приложения

##### Мониторинг

1. Клонируем репозитарий 
    `git clone https://github.com/prometheus-operator/kube-prometheus`
    
    ![](.README_images/b0ad6fd1.png)
    
2. Выполняем
    ```bash
    kubectl apply --server-side -f manifests/setup
    kubectl wait \
        --for condition=Established \
        --all CustomResourceDefinition \
        --namespace=monitoring
    kubectl apply -f manifests/
    ```
    ![](.README_images/512cccc8.png)
    ![](.README_images/e69b12cb.png)
    ![](.README_images/2b2c8bd8.png)

3. Ждем
    ![](.README_images/da686eb6.png)

4. Для подключения к grafana из вне, поменяем тип сервиса на NodePort и допишем номер порта, например 31001
    `kubectl edit svc stable-grafana -n monitoring`
    ![](.README_images/2b3064aa.png)
5. Зайдем на http://158.160.100.70:31001, авторизуемся с помощью стандартного логина и пароля (admin/admin, получим предложение поменять пароль, поменяем на что-то)
    ![](.README_images/661e3ce0.png)

##### Деплой

1. Создадим манифест для ранее созданного приложения [app-dp-svc.yaml](https://github.com/zemlyachev/diplops-app/blob/main/app-dp-svc.yaml)
2. Для доступа к реестру создадим сервисный аккаунт [kuber-registry-sa.tf](src/terraform/kuber-registry-sa.tf)
![](.README_images/bde179ec.png)
3. Создадим ключ
![](.README_images/d11e5d9c.png)
4. Авторизуемся этим ключем
![](.README_images/7a9d0d9e.png)
5. Создадим секрет для добавления его в Deployment
![](.README_images/ef703b25.png)
6. Выполним манифест `kubectl apply -f app-dp-svc.yaml`
![](.README_images/8193d4e1.png)
На http://158.160.100.70:30080 появился наш сайт

##### Автоматизация

1. Создадим новый репозитарий [diplops-terraform](https://github.com/zemlyachev/diplops-terraform)
2. Перенесем все необходимые файлы
3. Добавим секреты для доступа к Yandex.Cloud и хранилищу состояния
   ![](.README_images/1c7d88d7.png)
4. Напишем pipeline для GitHub Actions [terraform-ci-cd.yml](https://github.com/zemlyachev/diplops-terraform/blob/main/.github/workflows/terraform-ci-cd.yml)
5. Пушим в main и видим что сборка прошла успешно (почти с первого раза)
   ![](.README_images/b14fab71.png)
6. По результатам в бакете должны увидеть инвентори для ansible
   ![](.README_images/33bc7965.png)

