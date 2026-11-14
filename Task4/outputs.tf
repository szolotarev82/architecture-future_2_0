output "vpc_id" {
  description = "ID созданной облачной сети VPC"
  value       = yandex_vpc_network.main_vpc.id
}

output "nat_gateway_id" {
  description = "ID созданного NAT-шлюза для выхода приватных ВМ в интернет"
  value       = yandex_vpc_gateway.nat_gateway.id
}

output "gateway_public_ip" {
  description = "Публичный IP-адрес API Gateway / Bastion для подключения"
  value       = yandex_compute_instance.gateway_vm.network_interface[0].nat_ip_address
}

output "data_core_private_ip" {
  description = "Внутренний IP-адрес сервера ClickHouse + DataHub (закрытый контур)"
  value       = yandex_compute_instance.data_core_vm.network_interface[0].ip_address
}

output "bi_portal_private_ip" {
  description = "Внутренний IP-адрес портала самообслуживания Apache Superset (закрытый контур)"
  value       = yandex_compute_instance.bi_portal_vm.network_interface[0].ip_address
}

output "datalake_bucket_name" {
  description = "Имя S3-бакета для Data Lake и бэкапов"
  value       = yandex_storage_bucket.datalake_bucket.bucket
}
