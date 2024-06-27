# Yandex Container Registry
resource "yandex_container_registry" "diplops-reg" {
  name = "diplops-registry"
  folder_id = var.YC_FOLDER_ID
}

output "first_part_of_docker_image_tag" {
  value = "cr.yandex/${yandex_container_registry.diplops-reg.id}/"
}
