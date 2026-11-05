output "control_plane_private_ips" {
  value = aws_instance.control_plane[*].private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "control_plane_endpoint" {
  value = aws_lb.control_plane.dns_name
}
