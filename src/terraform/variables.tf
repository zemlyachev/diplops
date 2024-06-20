variable "YC_TOKEN" { type = string }
variable "YC_FOLDER_ID" { type = string }
variable "YC_CLOUD_ID" { type = string }
variable "YC_ZONE" { type = string }

#variable "subnets1" {
#  type = set(object({
#    name = string
#    zone = string
#    cidr = list(string)
#  }))
#  default = [
#    { name = "subnet-a", zone = "ru-central1-a", cidr = ["192.168.10.0/24"] },
#    { name = "subnet-b", zone = "ru-central1-b", cidr = ["192.168.20.0/24"] },
#    { name = "subnet-c", zone = "ru-central1-c", cidr = ["192.168.30.0/24"] }
#  ]
#}/**/
variable "subnets" {
  type    = map(string)
  default = ({
    a = "192.168.10.0/24",
    b = "192.168.20.0/24",
    c = "192.168.30.0/24"
  })
}
