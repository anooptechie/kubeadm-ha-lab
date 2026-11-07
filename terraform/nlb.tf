resource "aws_lb" "control_plane" {
  name                             = "kubeadm-ha-cp-nlb"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = aws_subnet.private[*].id
  enable_cross_zone_load_balancing = true

  tags = { Name = "kubeadm-ha-cp-nlb" }
}

resource "aws_lb_target_group" "api" {
  name        = "kubeadm-ha-api"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # Without this, a control-plane server that calls the load balancer and gets
  # routed back to itself fails to connect. Turning it off avoids that.
  preserve_client_ip = "false"

  deregistration_delay = 30

  health_check {
    protocol            = "HTTPS"
    path                = "/readyz"
    matcher             = "200"
    port                = "6443"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "kubeadm-ha-api" }
}

resource "aws_lb_target_group_attachment" "api" {
  count = var.control_plane_count

  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.control_plane.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
