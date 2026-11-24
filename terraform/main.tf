data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  az = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

# 1. VPC + Subnets + Internet Gateway + Default Security Group
module "vpc" {
  source = "./modules/vpc"

  name                = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = local.az
}

# 2. NAT Gateway (dat trong Public Subnet)
module "nat_gateway" {
  source = "./modules/nat_gateway"

  name                = var.project_name
  public_subnet_id    = module.vpc.public_subnet_id
  internet_gateway_id = module.vpc.internet_gateway_id
}

# 3. Route Tables cho Public va Private Subnet
module "route_tables" {
  source = "./modules/route_tables"

  name                = var.project_name
  vpc_id              = module.vpc.vpc_id
  public_subnet_id    = module.vpc.public_subnet_id
  private_subnet_id   = module.vpc.private_subnet_id
  internet_gateway_id = module.vpc.internet_gateway_id
  nat_gateway_id      = module.nat_gateway.nat_gateway_id
}

# 4. Security Groups cho Public va Private EC2
module "security_groups" {
  source = "./modules/security_groups"

  name             = var.project_name
  vpc_id           = module.vpc.vpc_id
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

# 5. EC2 Instances
module "public_ec2" {
  source = "./modules/ec2"

  name                        = "${var.project_name}-public-ec2"
  ami_id                      = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnet_id
  security_group_ids          = [module.security_groups.public_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  depends_on = [module.route_tables]
}

module "private_ec2" {
  source = "./modules/ec2"

  name                        = "${var.project_name}-private-ec2"
  ami_id                      = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.private_subnet_id
  security_group_ids          = [module.security_groups.private_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = false

  # Can NAT + route san sang de instance cap nhat goi khi khoi dong
  depends_on = [module.route_tables]
}
