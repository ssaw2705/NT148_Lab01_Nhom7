# Test toan bo stack (root module) voi mock provider: kiem tra cac module
# duoc noi day dung voi nhau.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-1a", "ap-southeast-1b"]
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }
}

variables {
  allowed_ssh_cidr = "203.0.113.10/32"
  public_key_path  = "./tests/fixtures/test_key.pub"
}

run "full_stack_wiring" {
  command = apply

  assert {
    condition     = module.vpc.public_subnet_id != module.vpc.private_subnet_id
    error_message = "Phai co 2 subnet rieng"
  }

  assert {
    condition     = module.route_tables.public_route_table_id != module.route_tables.private_route_table_id
    error_message = "Phai co 2 route table rieng"
  }

  assert {
    condition     = output.public_instance_id != output.private_instance_id
    error_message = "Phai co 2 EC2 instance"
  }

  assert {
    condition     = module.nat_gateway.nat_gateway_id != ""
    error_message = "NAT Gateway phai duoc tao"
  }
}

run "missing_or_open_ssh_cidr_is_rejected" {
  command = plan

  variables {
    allowed_ssh_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.allowed_ssh_cidr]
}
