resource "null_resource" "configure-cdsw" {
  count = var.deploy_cdsw_model ? var.cluster_count : 0
  depends_on = [aws_security_group_rule.allow_cdsw_healthcheck]

  connection {
    host        = element(aws_instance.cluster.*.public_ip, count.index)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "resources/cdsw_setup.py"
    destination = "/tmp/cdsw_setup.py"

    connection {
      host        = element(aws_instance.cluster.*.public_ip, count.index)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "file" {
    source      = "resources/iot_model.pkl"
    destination = "/tmp/iot_model.pkl"

    connection {
      host        = element(aws_instance.cluster.*.public_ip, count.index)
      type        = "ssh"
      user        = var.ssh_username
      private_key = file(var.ssh_private_key)
    }
  }

  provisioner "remote-exec" {
    inline = [
      "set -x",
      "set -e",
      "nohup python3 -u /tmp/cdsw_setup.py $(curl ifconfig.me 2>/dev/null) /tmp/iot_model.pkl > /tmp/cdsw_setup.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}
