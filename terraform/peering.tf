# Look up the workstation VPC and its main route table
data "aws_vpc" "workstation" {
  id = var.workstation_vpc_id
}

data "aws_route_table" "workstation_main" {
  vpc_id = var.workstation_vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# The peering connection (same account and region, so it can auto-accept)
resource "aws_vpc_peering_connection" "workstation" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = var.workstation_vpc_id
  auto_accept = true

  tags = { Name = "kubeadm-ha-to-workstation" }
}

# Project side: private subnets can reach the workstation network
resource "aws_route" "private_to_workstation" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = data.aws_vpc.workstation.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.workstation.id
}

# Workstation side: the workstation can reach the project network
resource "aws_route" "workstation_to_project" {
  route_table_id            = data.aws_route_table.workstation_main.id
  destination_cidr_block    = aws_vpc.main.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.workstation.id
}
