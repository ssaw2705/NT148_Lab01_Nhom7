variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "allowed_ssh_cidr" {
  description = "IP duoc phep SSH vao Public EC2 (x.x.x.x/32)"
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0" && can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr khong duoc la 0.0.0.0/0."
  }
}

variable "private_ingress_ports" {
  description = "Cac port TCP Private EC2 mo cho Public EC2 (mac dinh chi SSH)"
  type        = list(number)
  default     = [22]
}
