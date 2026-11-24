mock_provider "aws" {}

variables {
  name             = "test"
  vpc_id           = "vpc-123"
  allowed_ssh_cidr = "203.0.113.10/32"
}

run "public_sg_allows_ssh_only_from_given_ip" {
  command = apply

  module {
    source = "./modules/security_groups"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.public_ssh.from_port == 22 && aws_vpc_security_group_ingress_rule.public_ssh.to_port == 22
    error_message = "Public SG chi mo port 22"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.public_ssh.cidr_ipv4 == "203.0.113.10/32"
    error_message = "Public SG chi cho SSH tu IP duoc chi dinh"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.public_ssh.security_group_id == aws_security_group.public_ec2.id
    error_message = "Rule SSH phai gan vao Public SG"
  }
}

run "private_sg_only_accepts_public_sg" {
  command = apply

  module {
    source = "./modules/security_groups"
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.private_from_public : r.referenced_security_group_id == aws_security_group.public_ec2.id && r.cidr_ipv4 == null])
    error_message = "Private SG chi nhan ket noi tu Public SG, khong tu CIDR"
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.private_from_public) == ["22"]
    error_message = "Mac dinh Private SG chi mo SSH"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.private_icmp_from_public.referenced_security_group_id == aws_security_group.public_ec2.id
    error_message = "ICMP chi tu Public SG"
  }
}

run "open_ssh_to_world_is_rejected" {
  command = plan

  module {
    source = "./modules/security_groups"
  }

  variables {
    allowed_ssh_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.allowed_ssh_cidr]
}
