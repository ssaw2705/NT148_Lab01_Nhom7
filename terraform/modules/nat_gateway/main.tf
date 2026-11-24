resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.name}-nat-eip" }
}

# NAT Gateway phai nam trong Public Subnet va can IGW da duoc gan vao VPC
resource "aws_nat_gateway" "this" {
  allocation_id     = aws_eip.nat.id
  subnet_id         = var.public_subnet_id
  connectivity_type = "public"

  tags = { Name = "${var.name}-nat" }

  lifecycle {
    precondition {
      condition     = var.internet_gateway_id != ""
      error_message = "NAT Gateway can Internet Gateway da ton tai."
    }
  }
}
