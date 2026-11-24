variable "name" {
  type = string
}

variable "public_subnet_id" {
  description = "Public Subnet chua NAT Gateway"
  type        = string
}

variable "internet_gateway_id" {
  description = "ID cua IGW (dung de tao phu thuoc: IGW phai co truoc NAT)"
  type        = string
}
