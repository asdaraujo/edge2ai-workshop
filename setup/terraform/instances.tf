resource "aws_instance" "cluster" {
  count             = var.cluster_count
  ami               = var.cluster_ami
  instance_type     = var.cluster_instance_type
  availability_zone = aws_subnet.subnet1.availability_zone
  key_name          = aws_key_pair.workshop_key_pair.key_name

  user_data = "#cloud-config\nbootcmd:\n  - echo \"export CLUSTER_ID=${count.index}\" >> /etc/workshop.conf"

  network_interface {
    network_interface_id = aws_network_interface.eni_cluster[count.index].id
    device_index         = 0
  }

  depends_on = [
    aws_route_table_association.rtb_assoc,
    aws_main_route_table_association.main_rtb_assoc,
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

  provisioner "file" {
    source      = "smm"
    destination = "/tmp/smm"

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "set -o nounset",
      "set -o errexit",
      "set -o pipefail",
      "sudo mkdir -p /opt/dataloader/",
      "sudo cp /tmp/smm/* /opt/dataloader/",
      "sudo chmod 755 /opt/dataloader/*.sh",
      "chmod +x /tmp/resources/*sh",
      "sudo bash -x /tmp/resources/setup.sh aws \"${var.ssh_username}\" \"${var.ssh_password}\" \"${var.namespace}\" 2>&1 | tee /tmp/resources/setup.log",
    ]

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }
}

resource "aws_network_interface" "eni_cluster" {
  count           = var.cluster_count
  subnet_id       = aws_subnet.subnet1.id
  security_groups = [aws_security_group.workshop_cluster_sg.id]

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-cluster-eni-${count.index}"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_eip" "eip_cluster" {
  count             = (var.use_elastic_ip ? var.cluster_count : 0)
  network_interface = aws_network_interface.eni_cluster[count.index].id
  vpc               = true

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-cluster-eip-${count.index}"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_instance" "web" {
  ami               = var.base_ami
  instance_type     = "t2.medium"
  availability_zone = aws_subnet.subnet1.availability_zone
  key_name          = aws_key_pair.workshop_web_key_pair.key_name

  network_interface {
    network_interface_id = aws_network_interface.eni_web.id
    device_index         = 0
  }

  depends_on = [
    aws_route_table_association.rtb_assoc,
    aws_main_route_table_association.main_rtb_assoc,
  ]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "8"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-web"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }

  provisioner "file" {
    source      = "web"
    destination = "/home/${var.ssh_username}/web"

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.web_ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "cd web/",
      "bash -x ./start-web.sh 2>&1 | tee ./start-web.log",
    ]

    connection {
      host        = coalesce(self.public_ip, self.private_ip)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.web_ssh_private_key)
    }
  }
}

resource "aws_network_interface" "eni_web" {
  subnet_id       = aws_subnet.subnet1.id
  security_groups = [aws_security_group.workshop_web_sg.id]

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-web-eni"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}

resource "aws_eip" "eip_web" {
  count             = (var.use_elastic_ip ? 1 : 0)
  network_interface = aws_network_interface.eni_web.id
  vpc               = true

  tags = {
    Name    = "${var.owner}-${var.name_prefix}-web-eip"
    owner   = var.owner
    project = var.project
    enddate = var.enddate
  }
}
