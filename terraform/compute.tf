# Latest Ubuntu Server 24.04 LTS image from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "kubeadm-ha-lab"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = { Name = "kubeadm-ha-lab" }
}

resource "aws_instance" "control_plane" {
  count = var.control_plane_count

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[count.index % 3].id
  vpc_security_group_ids      = [aws_security_group.control_plane.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "kubeadm-ha-cp-${count.index + 1}"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[count.index % 3].id
  vpc_security_group_ids      = [aws_security_group.worker.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "kubeadm-ha-worker-${count.index + 1}"
    Role = "worker"
  }
}
