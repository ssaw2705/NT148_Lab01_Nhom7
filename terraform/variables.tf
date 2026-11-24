variable "aws_region" {
  description = "AWS region de trien khai"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tien to dat ten cho tat ca tai nguyen"
  type        = string
  default     = "nt548-lab1"
}

variable "vpc_cidr" {
  description = "CIDR block cua VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR cua Public Subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR cua Private Subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ dat subnet. De trong thi lay AZ dau tien cua region"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "IP duy nhat duoc SSH vao Public EC2, dang x.x.x.x/32 (vi du: IP cua ban)"
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0)) && endswith(var.allowed_ssh_cidr, "/32")
    error_message = "allowed_ssh_cidr phai la mot IP cu the dang x.x.x.x/32 (khong dung 0.0.0.0/0)."
  }
}

variable "instance_type" {
  description = "Loai EC2 instance"
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Duong dan file public key SSH (vd ~/.ssh/nt548-lab1.pub) de tao Key Pair"
  type        = string
  default     = "~/.ssh/nt548-lab1.pub"
}

variable "ami_ssm_parameter" {
  description = "SSM parameter chua AMI ID moi nhat (mac dinh Amazon Linux 2023)"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
