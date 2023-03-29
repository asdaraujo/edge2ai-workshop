resource "null_resource" "deploy_cdp" {
  count = var.cluster_count
  depends_on = [
    aws_security_group_rule.workshop_cluster_public_ips_sg_rule,
    aws_security_group_rule.workshop_ecs_public_ips_sg_rule
  ]

  connection {
    host        = element((var.use_elastic_ip ? aws_eip.eip_cluster.*.public_ip : aws_instance.cluster.*.public_ip), count.index)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = var.ssh_private_key
    destination = "~/.ssh/${var.namespace}.pem"
  }

  provisioner "file" {
    source      = "${var.base_dir}/resources"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = (var.cdp_license_file == "" ? "/dev/null" : var.cdp_license_file)
    destination = "/tmp/resources/.license"
  }

  provisioner "remote-exec" {
    inline = [
      "set -o errexit",
      "set -o xtrace",
      "sudo bash -c 'echo -e \"export CLUSTERS_PUBLIC_DNS=${join(",", formatlist("cdp.%s.nip.io", var.use_elastic_ip ? aws_eip.eip_cluster.*.public_ip : aws_instance.cluster.*.public_ip))}\" >> /etc/workshop.conf'",
      "sudo nohup bash -x /tmp/resources/setup.sh aws \"${var.ssh_username}\" \"${var.ssh_password}\" \"${var.namespace}\" \"\" \"${(var.use_ipa ? "ipa.${aws_eip.eip_ipa[0].public_ip}.nip.io" : "")}\" \"${(var.use_ipa ? aws_instance.ipa[0].private_ip : "")}\" \"${(var.pvc_data_services ? "ecs.${(var.use_elastic_ip ? aws_eip.eip_ecs[count.index].public_ip : aws_instance.ecs[count.index].public_ip)}.nip.io" : "")}\" \"${(var.pvc_data_services ? aws_instance.ecs[count.index].private_ip : "")}\" > /tmp/resources/setup.log 2>&1 &",
      "sleep 1 # don't remove - needed for the nohup to work",
    ]
  }
}

