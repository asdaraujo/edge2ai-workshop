resource "null_resource" "deploy_ecs" {
  count = (var.pvc_data_services ? var.cluster_count : 0)
  depends_on = [
    aws_security_group_rule.workshop_cluster_public_ips_sg_rule,
    aws_security_group_rule.workshop_ecs_public_ips_sg_rule
  ]

  connection {
    host        = element((var.use_elastic_ip ? aws_eip.eip_ecs.*.public_ip : aws_instance.ecs.*.public_ip), count.index)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "${var.base_dir}/resources"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o errexit",
      "set -o xtrace",
      "sudo nohup bash -x /tmp/resources/setup-ecs.sh install-prereqs aws \"${var.ssh_username}\" \"${var.ssh_password}\" \"${var.namespace}\" \"${(var.use_ipa ? "ipa.${aws_eip.eip_ipa[0].public_ip}.nip.io" : "")}\" \"${(var.use_ipa ? aws_instance.ipa[0].private_ip : "")}\" > /tmp/resources/setup-ecs.install-prereqs.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}

