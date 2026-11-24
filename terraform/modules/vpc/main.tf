resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

# Public Subnet: instance duoc gan Public IP, route ra Internet qua IGW
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-subnet", Tier = "public" }
}

# Private Subnet: khong co Public IP, ra Internet qua NAT Gateway
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-private-subnet", Tier = "private" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# Default Security Group cua VPC: chi cho phep cac tai nguyen cung SG noi chuyen
# voi nhau, khong mo bat ky port nao ra Internet.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  ingress {
    description = "Allow all traffic from members of this SG"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    description = "Allow all outbound"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-default-sg" }
}
