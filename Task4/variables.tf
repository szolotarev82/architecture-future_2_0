variable "yc_zone" {
  description = "Зона доступности по умолчанию"
  type        = string
  default     = "ru-central1-a"
}

variable "project_prefix" {
  description = "Префикс для именования всех ресурсов проекта «Будущее 2.0»"
  type        = string
  default     = "future20"
}

variable "ssh_user" {
  description = "Имя пользователя для подключения по SSH"
  type        = string
  default     = "debian"
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_cidr" {
  description = "IP-адрес или подсеть администратора для безопасного доступа по SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "image_family" {
  description = "Семейство минимальных образов ОС для виртуальных машин"
  type        = string
  default     = "debian-11"
}

variable "boot_disk_size" {
  description = "Минимальный размер загрузочного диска ВМ (в ГБ)"
  type        = number
  default     = 3
}

variable "data_disk_size" {
  description = "Размер дополнительного диска для хранения витрин ClickHouse (в ГБ)"
  type        = number
  default     = 2
}

variable "bucket_suffix" {
  description = "Уникальный суффикс для имени S3-бакета Data Lake"
  type        = string
  default     = "datalake-2026-9482"
}
