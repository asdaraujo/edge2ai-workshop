resource "aws_security_group" "bootcamp_sg" {
  name_prefix = "${var.owner}-${var.name_prefix}-sg-"
  description = "New Hire Bootcamp Security Group"
  vpc_id      = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.my_public_ip}/32"]
    self        = true
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-sg"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}
