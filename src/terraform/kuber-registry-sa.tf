# SA for yandex registry
resource "yandex_iam_service_account" "sa-registry-puller" {
  folder_id = var.YC_FOLDER_ID
  name      = "sa-registry-puller"
}
resource "yandex_resourcemanager_folder_iam_member" "puller" {
  folder_id = var.YC_FOLDER_ID
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.sa-registry-puller.id}"
}
