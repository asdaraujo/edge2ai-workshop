resource "null_resource" "deploy_web" {
  count = (var.launch_web_server ? 1 : 0)

  connection {
    host        = (var.use_elastic_ip ? aws_eip.eip_web.0.public_ip : aws_instance.web.0.public_ip)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.web_ssh_private_key)
  }

  provisioner "file" {
    source      = "../web"
    destination = "/home/${var.ssh_username}/web"
  }

  provisioner "file" {
    source      = "../resources/check-setup-status.sh"
    destination = "/home/${var.ssh_username}/web/check-setup-status.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o errexit",
      "set -o xtrace",
      "cd web/",
      "nohup bash -x ./start-web.sh > ./start-web.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}
