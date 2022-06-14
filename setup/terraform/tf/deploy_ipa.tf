resource "null_resource" "deploy_ipa" {
  count      = (var.use_ipa ? 1 : 0)
  depends_on = [aws_security_group_rule.workshop_public_ips_sg_rule]

  connection {
    host        = aws_eip.eip_ipa.0.public_ip
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "../ipa"
    destination = "/home/${var.ssh_username}/ipa"
  }

  provisioner "file" {
    source      = "../resources/check-setup-status.sh"
    destination = "/home/${var.ssh_username}/ipa/check-setup-status.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o errexit",
      "set -o xtrace",
      "cd ipa/",
      "sudo nohup bash -x ./setup-ipa.sh > ./setup-ipa.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}
