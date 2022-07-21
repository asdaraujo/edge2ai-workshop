resource "aws_key_pair" "workshop_key_pair" {
  key_name   = var.key_name
  public_key = file(var.ssh_public_key)
}

resource "aws_key_pair" "workshop_web_key_pair" {
  key_name   = var.web_key_name
  public_key = file(var.web_ssh_public_key)
}

