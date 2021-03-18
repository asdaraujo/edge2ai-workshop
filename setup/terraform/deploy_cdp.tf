resource "null_resource" "deploy_cdp" {
  count = var.cluster_count
  depends_on = [aws_security_group_rule.workshop_cdsw_sg_rule]

  connection {
    host        = element((var.use_elastic_ip ? aws_eip.eip_cluster.*.public_ip : aws_instance.cluster.*.public_ip), count.index)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "resources"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "smm"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o nounset",
      "set -o errexit",
      "set -o pipefail",
      "# Prepare resources",
      "sudo mkdir -p /opt/dataloader/",
      "sudo cp /tmp/smm/* /opt/dataloader/",
      "sudo chmod 755 /opt/dataloader/*.sh",
      "chmod +x /tmp/resources/*sh",
      "# Deploy workshop",
      "sudo bash -x /tmp/resources/setup.sh aws \"${var.ssh_username}\" \"${var.ssh_password}\" \"${var.namespace}\" 2>&1 | tee /tmp/resources/setup.log",
      "# Deploy CDSW setup",
      "nohup python -u /tmp/resources/cdsw_setup.py $(curl ifconfig.me 2>/dev/null) /tmp/resources/iot_model.pkl /tmp/resources/the_pwd.txt > /tmp/resources/cdsw_setup.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}
