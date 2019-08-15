resource "aws_security_group_rule" "allow_cdsw_healthcheck" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["18.237.253.180/32"]
  security_group_id = "sg-02655505d49a0a620"
}
