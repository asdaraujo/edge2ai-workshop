resource "aws_key_pair" "bootcamp_key_pair" {
  key_name   = var.key_name
  public_key = file(var.ssh_public_key)
}

