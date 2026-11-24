output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  value = module.vpc.private_subnet_id
}

output "internet_gateway_id" {
  value = module.vpc.internet_gateway_id
}

output "default_security_group_id" {
  value = module.vpc.default_security_group_id
}

output "nat_gateway_id" {
  value = module.nat_gateway.nat_gateway_id
}

output "nat_public_ip" {
  value = module.nat_gateway.public_ip
}

output "public_route_table_id" {
  value = module.route_tables.public_route_table_id
}

output "private_route_table_id" {
  value = module.route_tables.private_route_table_id
}

output "public_sg_id" {
  value = module.security_groups.public_sg_id
}

output "private_sg_id" {
  value = module.security_groups.private_sg_id
}

output "public_instance_id" {
  value = module.public_ec2.instance_id
}

output "public_instance_public_ip" {
  value = module.public_ec2.public_ip
}

output "private_instance_id" {
  value = module.private_ec2.instance_id
}

output "private_instance_private_ip" {
  value = module.private_ec2.private_ip
}

output "ssh_public_command" {
  value = "ssh -i ~/.ssh/nt548-lab1 ec2-user@${module.public_ec2.public_ip}"
}

output "ssh_private_command" {
  description = "SSH vao Private EC2 qua Public EC2 (ProxyJump, private key khong bi copy len bastion)"
  value       = "ssh -i ~/.ssh/nt548-lab1 -J ec2-user@${module.public_ec2.public_ip} ec2-user@${module.private_ec2.private_ip}"
}
