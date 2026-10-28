resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name_prefix}-app-tg"
  port                 = var.target_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-app-tg"
  }
}

# HTTPS only: CloudFront (VPC origin) connects with TLS, nothing else can reach the ALB
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn # Listener eka mona ALB ekata da
  port              = 443             # HTTPS standard port
  protocol          = "HTTPS"         # ALB eka TLS terminate karanawa
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn # Module eka cert eka input ekak widihata gannawa

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn # Same module eke thiyena TG eka
  }
}

# ---------------------------------------------------------------
# Extra hostnames on the same listener (SNI picks the right certificate)
# ---------------------------------------------------------------
resource "aws_lb_listener_certificate" "extra" {
  for_each = var.additional_certificates

  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = each.value
}

# One target group per extra hostname (e.g. the admin web)
resource "aws_lb_target_group" "host" {
  for_each = var.host_routes

  name                 = "${var.name_prefix}-${each.key}-tg"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}-tg"
  }
}

# Host header -> that target group; everything else goes to the default action (API)
resource "aws_lb_listener_rule" "host" {
  for_each = var.host_routes

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.host[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.host]
    }
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}



