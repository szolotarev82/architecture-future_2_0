terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.100.0"
    }
  }
}

# Провайдер автоматически считывает YC_TOKEN, YC_CLOUD_ID и YC_FOLDER_ID из переменных окружения
provider "yandex" {
  zone = var.yc_zone
}

# Получение актуального ID каталога из контекста провайдера
data "yandex_client_config" "client" {}

# Получение минимального образа Debian 11
data "yandex_compute_image" "linux" {
  family = var.image_family
}

# 1. Сетевая инфраструктура (VPC, подсети, NAT-шлюз, маршрутизация)
resource "yandex_vpc_network" "main_vpc" {
  name        = "${var.project_prefix}-vpc"
  description = "Облачная сеть платформы данных Будущее 2.0"
}

resource "yandex_vpc_gateway" "nat_gateway" {
  name = "${var.project_prefix}-nat-gw"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private_rt" {
  name       = "${var.project_prefix}-private-rt"
  network_id = yandex_vpc_network.main_vpc.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

resource "yandex_vpc_subnet" "public_subnet" {
  name           = "${var.project_prefix}-public-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main_vpc.id
  v4_cidr_blocks = ["10.10.1.0/24"]
}

resource "yandex_vpc_subnet" "private_subnet" {
  name           = "${var.project_prefix}-private-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main_vpc.id
  v4_cidr_blocks = ["10.10.2.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# 2. Группы безопасности (Firewall)
resource "yandex_vpc_security_group" "public_sg" {
  name        = "${var.project_prefix}-public-sg"
  description = "Правила безопасности для API Gateway и Bastion"
  network_id  = yandex_vpc_network.main_vpc.id

  ingress {
    protocol       = "TCP"
    description    = "Разрешить SSH только с доверенного адреса"
    v4_cidr_blocks = [var.admin_cidr]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Разрешить HTTPS доступ к порталу самообслуживания"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "Разрешить весь исходящий трафик"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "private_sg" {
  name        = "${var.project_prefix}-private-sg"
  description = "Правила безопасности для закрытого контура данных (ClickHouse, DataHub, Superset)"
  network_id  = yandex_vpc_network.main_vpc.id

  ingress {
    protocol          = "ANY"
    description       = "Весь трафик внутри закрытого контура"
    predefined_target = "self_security_group"
  }

  ingress {
    protocol          = "TCP"
    description       = "Доступ от шлюза/бастиона к внутренним сервисам"
    security_group_id = yandex_vpc_security_group.public_sg.id
    from_port         = 0
    to_port           = 65535
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий трафик через NAT-шлюз (обновления и Docker-образы)"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Дополнительный диск для аналитических витрин ClickHouse (ужат под квоту)
resource "yandex_compute_disk" "analytics_data_disk" {
  name     = "${var.project_prefix}-clickhouse-data-disk"
  type     = "network-hdd"
  zone     = var.yc_zone
  size     = var.data_disk_size
}

# 4. Виртуальные машины (API Gateway/Bastion, ClickHouse+DataHub, Superset BI)
resource "yandex_compute_instance" "gateway_vm" {
  name        = "${var.project_prefix}-gateway-bastion"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.linux.id
      size     = var.boot_disk_size
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public_subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.public_sg.id]
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
  }
}

resource "yandex_compute_instance" "data_core_vm" {
  name        = "${var.project_prefix}-clickhouse-datahub"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.linux.id
      size     = var.boot_disk_size
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id     = yandex_compute_disk.analytics_data_disk.id
    device_name = "clickhouse-data"
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_subnet.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.private_sg.id]
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
  }
}

resource "yandex_compute_instance" "bi_portal_vm" {
  name        = "${var.project_prefix}-superset-bi"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.linux.id
      size     = var.boot_disk_size
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private_subnet.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.private_sg.id]
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(pathexpand(var.ssh_public_key_path))}"
  }
}

# 5. Объектное хранилище S3 (Data Lake и резервные копии)
resource "yandex_iam_service_account" "sa_storage" {
  name        = "${var.project_prefix}-sa-storage"
  description = "Сервисный аккаунт для работы с S3 бакетом Data Lake"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_editor" {
  folder_id = data.yandex_client_config.client.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa_storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa_static_key" {
  service_account_id = yandex_iam_service_account.sa_storage.id
  description        = "Статический ключ доступа для S3"
}

resource "yandex_storage_bucket" "datalake_bucket" {
  bucket        = "${var.project_prefix}-${var.bucket_suffix}"
  access_key    = yandex_iam_service_account_static_access_key.sa_static_key.access_key
  secret_key    = yandex_iam_service_account_static_access_key.sa_static_key.secret_key
  force_destroy = true
}
