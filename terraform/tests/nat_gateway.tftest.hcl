mock_provider "aws" {}

variables {
  name                = "test"
  public_subnet_id    = "subnet-public123"
  internet_gateway_id = "igw-123"
}

run "nat_gateway_in_public_subnet_with_eip" {
  command = apply

  module {
    source = "./modules/nat_gateway"
  }

  assert {
    condition     = aws_nat_gateway.this.subnet_id == "subnet-public123"
    error_message = "NAT Gateway phai nam trong Public Subnet"
  }

  assert {
    condition     = aws_nat_gateway.this.allocation_id == aws_eip.nat.id
    error_message = "NAT Gateway phai dung Elastic IP"
  }

  assert {
    condition     = aws_nat_gateway.this.connectivity_type == "public"
    error_message = "NAT Gateway phai la loai public"
  }

  assert {
    condition     = aws_eip.nat.domain == "vpc"
    error_message = "EIP phai thuoc domain vpc"
  }
}
