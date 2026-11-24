# Public EC2 SG: chi cho SSH (22) tu mot IP cu the
resource "aws_security_group" "public_ec2" {
  name        = "${var.name}-public-ec2-sg"
  description = "Allow SSH only from a specific IP"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-public-ec2-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "public_ssh" {
  security_group_id = aws_security_group.public_ec2.id
  description       = "SSH from allowed IP"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidr
}

resource "aws_vpc_security_group_egress_rule" "public_all" {
  security_group_id = aws_security_group.public_ec2.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Private EC2 SG: chi nhan ket noi tu cac instance mang Public EC2 SG
resource "aws_security_group" "private_ec2" {
  name        = "${var.name}-private-ec2-sg"
  description = "Allow inbound only from the Public EC2 security group"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-private-ec2-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "private_from_public" {
  for_each = toset([for p in var.private_ingress_ports : tostring(p)])

  security_group_id            = aws_security_group.private_ec2.id
  description                  = "Port ${each.value} from Public EC2 SG"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.public_ec2.id
}

resource "aws_vpc_security_group_ingress_rule" "private_icmp_from_public" {
  security_group_id            = aws_security_group.private_ec2.id
  description                  = "ICMP (ping) from Public EC2 SG"
  ip_protocol                  = "icmp"
  from_port                    = -1
  to_port                      = -1
  referenced_security_group_id = aws_security_group.public_ec2.id
}

resource "aws_vpc_security_group_egress_rule" "private_all" {
  security_group_id = aws_security_group.private_ec2.id
  description       = "Allow all outbound (to Internet via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
