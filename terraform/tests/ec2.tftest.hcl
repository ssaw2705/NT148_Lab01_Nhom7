mock_provider "aws" {}

variables {
  name               = "test-ec2"
  ami_id             = "ami-0123456789abcdef0"
  instance_type      = "t3.micro"
  subnet_id          = "subnet-123"
  security_group_ids = ["sg-123"]
  key_name           = "test-key"
}

run "public_instance_gets_public_ip" {
  command = apply

  module {
    source = "./modules/ec2"
  }

  variables {
    associate_public_ip_address = true
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == true
    error_message = "Public EC2 phai co Public IP"
  }
}

run "private_instance_has_no_public_ip" {
  command = apply

  module {
    source = "./modules/ec2"
  }

  variables {
    associate_public_ip_address = false
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "Private EC2 khong duoc co Public IP"
  }
}

run "instance_is_hardened" {
  command = apply

  module {
    source = "./modules/ec2"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "EC2 phai bat buoc IMDSv2"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "Root volume phai duoc ma hoa"
  }

  assert {
    condition     = toset(aws_instance.this.vpc_security_group_ids) == toset(["sg-123"]) && aws_instance.this.subnet_id == "subnet-123"
    error_message = "EC2 phai dung dung subnet va security group"
  }
}
