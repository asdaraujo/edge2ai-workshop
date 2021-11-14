resource "null_resource" "deploy_ipa" {
  count                 = (var.use_ipa ? 1 : 0)

  connection {
    host        = aws_instance.ipa[0].public_ip
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "ipa"
    destination = "/home/${var.ssh_username}/ipa"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o nounset",
      "set -o errexit",
      "set -o pipefail",
      "set -o xtrace",
      "trap 'echo Return code: $?' 0",
      "cd ipa/",
      "sudo bash -x ./setup-ipa.sh 2>&1 | tee ./setup-ipa.log",
    ]
  }
}
