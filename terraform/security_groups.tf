locals {
  workstation_cidr = data.aws_vpc.workstation.cidr_block

  sg_ids = {
    cp     = aws_security_group.control_plane.id
    worker = aws_security_group.worker.id
  }

  # Rules where the traffic comes from another security group
  sg_rules = {
    cp-etcd              = { target = "cp", source = "cp", protocol = "tcp", from_port = 2379, to_port = 2380 }
    cp-kubelet           = { target = "cp", source = "cp", protocol = "tcp", from_port = 10250, to_port = 10250 }
    cp-controllers       = { target = "cp", source = "cp", protocol = "tcp", from_port = 10257, to_port = 10259 }
    cp-vxlan-from-cp     = { target = "cp", source = "cp", protocol = "udp", from_port = 4789, to_port = 4789 }
    cp-vxlan-from-worker = { target = "cp", source = "worker", protocol = "udp", from_port = 4789, to_port = 4789 }
    cp-typha-from-cp     = { target = "cp", source = "cp", protocol = "tcp", from_port = 5473, to_port = 5473 }
    cp-typha-from-worker = { target = "cp", source = "worker", protocol = "tcp", from_port = 5473, to_port = 5473 }

    worker-kubelet-from-cp     = { target = "worker", source = "cp", protocol = "tcp", from_port = 10250, to_port = 10250 }
    worker-kubelet-from-worker = { target = "worker", source = "worker", protocol = "tcp", from_port = 10250, to_port = 10250 }
    worker-vxlan-from-cp       = { target = "worker", source = "cp", protocol = "udp", from_port = 4789, to_port = 4789 }
    worker-vxlan-from-worker   = { target = "worker", source = "worker", protocol = "udp", from_port = 4789, to_port = 4789 }
    worker-typha-from-cp       = { target = "worker", source = "cp", protocol = "tcp", from_port = 5473, to_port = 5473 }
    worker-typha-from-worker   = { target = "worker", source = "worker", protocol = "tcp", from_port = 5473, to_port = 5473 }
  }

  # Rules where the traffic comes from an IP range
  cidr_rules = {
    cp-ssh                      = { target = "cp", cidr = local.workstation_cidr, protocol = "tcp", from_port = 22, to_port = 22 }
    cp-api-from-workstation     = { target = "cp", cidr = local.workstation_cidr, protocol = "tcp", from_port = 6443, to_port = 6443 }
    cp-api-from-project-network = { target = "cp", cidr = aws_vpc.main.cidr_block, protocol = "tcp", from_port = 6443, to_port = 6443 }
    worker-ssh                  = { target = "worker", cidr = local.workstation_cidr, protocol = "tcp", from_port = 22, to_port = 22 }
    worker-nodeport-test        = { target = "worker", cidr = local.workstation_cidr, protocol = "tcp", from_port = 30000, to_port = 32767 }
  }
}

resource "aws_security_group" "control_plane" {
  name        = "kubeadm-ha-control-plane-sg"
  description = "Kubernetes control plane nodes"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "kubeadm-ha-control-plane-sg" }
}

resource "aws_security_group" "worker" {
  name        = "kubeadm-ha-worker-sg"
  description = "Kubernetes worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "kubeadm-ha-worker-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = local.sg_rules

  security_group_id            = local.sg_ids[each.value.target]
  referenced_security_group_id = local.sg_ids[each.value.source]
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = each.key

  tags = { Name = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = local.cidr_rules

  security_group_id = local.sg_ids[each.value.target]
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  description       = each.key

  tags = { Name = each.key }
}

resource "aws_vpc_security_group_egress_rule" "control_plane_all" {
  security_group_id = aws_security_group.control_plane.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}

resource "aws_vpc_security_group_egress_rule" "worker_all" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}
