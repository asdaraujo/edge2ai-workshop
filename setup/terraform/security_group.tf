resource "aws_security_group" "workshop_main_sg" {
  name_prefix = "${var.owner}-${var.name_prefix}-main-sg-"
  description = "Allow ingress connections from the user public IP"
  vpc_id      = (var.vpc_id != "" ? var.vpc_id : aws_vpc.vpc[0].id)

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.my_public_ip}/32"]
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-main-sg"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_security_group_rule" "allow_cdsw_healthcheck" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [ for ip in aws_instance.cluster.*.public_ip: "${ip}/32" ]
  security_group_id = aws_security_group.workshop_main_sg.id
}

resource "aws_security_group_rule" "dc-to-cloud" {
  count                    = length(distinct(flatten(data.aws_instance.vpc-instance.*.vpc_security_group_ids)))
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.workshop_main_sg.id
  security_group_id        = element(distinct(flatten(data.aws_instance.vpc-instance.*.vpc_security_group_ids)), count.index)
}

resource "aws_security_group_rule" "cloud-to-dc" {
  count                    = length(distinct(flatten(data.aws_instance.vpc-instance.*.vpc_security_group_ids)))
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = element(distinct(flatten(data.aws_instance.vpc-instance.*.vpc_security_group_ids)), count.index)
  security_group_id        = aws_security_group.workshop_main_sg.id
}

data "aws_instances" "vpc-instances" {
  count = (var.vpc_id != "" ? 1 : 0)
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  instance_state_names = ["running"]
}

data "aws_instance" "vpc-instance" {
  count = (length(data.aws_instances.vpc-instances) > 0 ? length(distinct(data.aws_instances.vpc-instances.0.ids)) : 0)
  instance_id = element(data.aws_instances.vpc-instances.0.ids, count.index)
}
