# Unit test module VPC (chay offline voi mock provider, khong ton tien AWS)
mock_provider "aws" {}

variables {
  name                = "test"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone   = "ap-southeast-1a"
}

run "vpc_is_created_with_dns" {
  command = apply

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR sai"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "VPC phai bat DNS support va DNS hostnames"
  }
}

run "public_subnet_maps_public_ip" {
  command = apply

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_subnet.public.map_public_ip_on_launch == true
    error_message = "Public subnet phai tu gan Public IP"
  }

  assert {
    condition     = aws_subnet.public.vpc_id == aws_vpc.this.id && aws_subnet.public.cidr_block == "10.0.1.0/24"
    error_message = "Public subnet phai thuoc VPC va dung CIDR"
  }
}

run "private_subnet_has_no_public_ip" {
  command = apply

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_subnet.private.map_public_ip_on_launch == false
    error_message = "Private subnet khong duoc gan Public IP"
  }

  assert {
    condition     = aws_subnet.private.vpc_id == aws_vpc.this.id && aws_subnet.private.cidr_block == "10.0.2.0/24"
    error_message = "Private subnet phai thuoc VPC va dung CIDR"
  }
}

run "internet_gateway_attached_to_vpc" {
  command = apply

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_internet_gateway.this.vpc_id == aws_vpc.this.id
    error_message = "IGW phai gan vao VPC"
  }
}

run "default_security_group_locked_to_self" {
  command = apply

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_default_security_group.this.vpc_id == aws_vpc.this.id
    error_message = "Default SG phai thuoc VPC"
  }

  assert {
    condition     = alltrue([for r in aws_default_security_group.this.ingress : r.self && length(coalesce(r.cidr_blocks, [])) == 0])
    error_message = "Default SG chi duoc nhan traffic tu chinh no, khong mo CIDR nao"
  }
}

run "invalid_vpc_cidr_is_rejected" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  variables {
    vpc_cidr = "not-a-cidr"
  }

  expect_failures = [var.vpc_cidr]
}
