resource "yandex_iam_service_account" "sa-ter-diplom" {
  folder_id = var.YC_FOLDER_ID
  name      = "sa-ter-diplom"
}
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.YC_FOLDER_ID
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-ter-diplom.id}"
}
