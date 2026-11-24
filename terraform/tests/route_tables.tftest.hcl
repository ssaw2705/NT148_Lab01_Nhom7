mock_provider "aws" {}

variables {
  name                = "test"
  vpc_id              = "vpc-123"
  public_subnet_id    = "subnet-public"
  private_subnet_id   = "subnet-private"
  internet_gateway_id = "igw-123"
  nat_gateway_id      = "nat-123"
}

run "public_route_table_routes_to_igw" {
  command = apply

  module {
    source = "./modules/route_tables"
  }

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0" && aws_route.public_internet.gateway_id == "igw-123"
    error_message = "Public RT phai dinh tuyen 0.0.0.0/0 qua Internet Gateway"
  }

  assert {
    condition     = aws_route_table_association.public.subnet_id == "subnet-public" && aws_route_table_association.public.route_table_id == aws_route_table.public.id
    error_message = "Public RT phai gan vao Public Subnet"
  }
}

run "private_route_table_routes_to_nat" {
  command = apply

  module {
    source = "./modules/route_tables"
  }

  assert {
    condition     = aws_route.private_nat.destination_cidr_block == "0.0.0.0/0" && aws_route.private_nat.nat_gateway_id == "nat-123"
    error_message = "Private RT phai dinh tuyen 0.0.0.0/0 qua NAT Gateway"
  }

  assert {
    condition     = aws_route.private_nat.gateway_id == null || aws_route.private_nat.gateway_id == ""
    error_message = "Private RT khong duoc di thang ra Internet Gateway"
  }

  assert {
    condition     = aws_route_table_association.private.subnet_id == "subnet-private" && aws_route_table_association.private.route_table_id == aws_route_table.private.id
    error_message = "Private RT phai gan vao Private Subnet"
  }
}
