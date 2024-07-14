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
