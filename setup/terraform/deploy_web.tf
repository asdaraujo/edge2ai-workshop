resource "null_resource" "deploy_web" {
  connection {
    host        = (var.use_elastic_ip ? aws_eip.eip_web.0.public_ip : aws_instance.web.public_ip)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.web_ssh_private_key)
  }

  provisioner "file" {
    source      = "web"
    destination = "/home/${var.ssh_username}/web"
  }

  provisioner "remote-exec" {
    inline = [
      "cd web/",
      "bash -x ./start-web.sh 2>&1 | tee ./start-web.log",
    ]
  }
}
