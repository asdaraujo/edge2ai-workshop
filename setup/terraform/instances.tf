resource "aws_instance" "cluster" {
  count                  = var.cluster_count
  ami                    = var.cluster_ami
  instance_type          = var.cluster_instance_type
  availability_zone      = aws_subnet.subnet1.availability_zone
  key_name               = aws_key_pair.workshop_key_pair.key_name
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.workshop_main_sg.id]

  depends_on = [
    aws_main_route_table_association.rtb_assoc,
  ]

  timeouts {
    create = "10m"
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "100"
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp2"
    volume_size           = "200"
  }

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-cluster-${count.index}"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }

  provisioner "file" {
    source      = "resources"
    destination = "/tmp/resources"

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/resources/*sh",
      "sudo bash -x /tmp/resources/setup.sh aws /tmp/resources/cdsw_template.json \"\" noprompt",
    ]

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }
}

