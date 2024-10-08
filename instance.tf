data "oci_core_images" "bastion" {
  compartment_id            = var.sc_compartment_ocid
  shape                     = var.inst_params_bast.shape
  sort_by                   = "TIMECREATED"
  sort_order                = "DESC"
  filter {
    name                    = "display_name"
    values                  = [var.inst_params_bast.image]
    regex                   = true
  }
}

resource "tls_private_key" "ssh" {
  algorithm                 = "RSA"
  rsa_bits                  = "4096"
}

resource "oci_core_instance" "bastion" {
  compartment_id            = var.sc_compartment_ocid
  display_name              = var.inst_params_bast.display_name
  availability_domain       = var.sc_ad
  shape                     = var.inst_params_bast.shape
  create_vnic_details {
    subnet_id               = oci_core_subnet.sub["public"].id
    assign_public_ip        = true
  }
  source_details {
    #source_id               = data.oci_core_images.bastion.images[0].id
    source_id                = var.sc_bastion_image
    source_type             = "image"
    boot_volume_size_in_gbs = var.inst_params_bast.boot_vol_size
  }
  metadata                  = {
    ssh_authorized_keys     = "${var.sc_ssh_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data               = "${base64encode(file("./user_data/cloud-init_bast.cfg"))}"
  }
  preserve_boot_volume      = false
}

resource "null_resource" "bastion" {
  depends_on                = [oci_core_instance.bastion]
  triggers                  = {
    bastion                 = oci_core_instance.bastion.id
  }
  provisioner "file" {
    content                 = tls_private_key.ssh.private_key_pem
    destination             = "/home/${var.user_name}/.ssh/id_rsa"
    connection {
      host                  = oci_core_instance.bastion.public_ip
      type                  = "ssh"
      user                  = var.user_name
      private_key           = tls_private_key.ssh.private_key_pem
      timeout               = "20m"
    }
  }
  provisioner "remote-exec" {
    inline                  = [
      "chmod 600 /home/${var.user_name}/.ssh/id_rsa",
    ]
    connection {
      host                  = oci_core_instance.bastion.public_ip
      type                  = "ssh"
      user                  = var.user_name
      private_key           = tls_private_key.ssh.private_key_pem
    }
  }
  provisioner "remote-exec" {
    inline                  = [
      for instance in data.oci_core_instance.cn_instances :
        "echo ${instance.display_name} | sudo tee -a ~${var.user_name}/hostlist.txt"
    ]
    connection {
      host                  = oci_core_instance.bastion.public_ip
      type                  = "ssh"
      user                  = var.user_name
      private_key           = tls_private_key.ssh.private_key_pem
    }
  }
}
