
variable "workstation_vpc_id" {
  description = "VPC that hosts the workstation"
  type        = string
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.11.0/24", "10.20.12.0/24", "10.20.13.0/24"]
}

variable "control_plane_count" {
  type    = number
  default = 1
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/kubeadm-lab.pub"
}
