locals {
  discover_wallix_script = "${path.module}/../../scripts/pnetlab/discover_wallix.py"
  check_template_script  = "${path.module}/../../scripts/pnetlab/check_template_ready.py"
  prepare_image_script   = "${path.module}/../../scripts/pnetlab/prepare_image.sh"
  commit_template_script = "${path.module}/../../scripts/pnetlab/commit_template.sh"
  upload_lab_script      = "${path.module}/../../scripts/pnetlab/upload_lab.sh"
  node_power_script      = "${path.module}/../../scripts/pnetlab/unl_node_power.sh"
  lab_template           = "${path.module}/templates/lab.unl.tftpl"

  build_node_id  = 1
  target_node_id = 1
}

data "external" "wallix_template_ready" {
  program = ["python3", local.check_template_script]
  query = {
    image_name = var.wallix_image_name
  }
}

resource "null_resource" "pnet_prepare_image" {
  triggers = {
    iso_sha256 = filesha256(var.wallix_iso_path)
    image      = var.wallix_image_name
    disk_size  = var.wallix_disk_size
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.prepare_image_script}' '${var.wallix_image_name}' '${var.wallix_iso_path}' '${var.wallix_disk_size}'"
  }
}

resource "random_uuid" "build_lab_id" {}
resource "random_uuid" "target_lab_id" {}
resource "random_uuid" "build_node_uuid" {}
resource "random_uuid" "target_node_uuid" {}

locals {
  wallix_template_ready      = try(tobool(data.external.wallix_template_ready.result.ready), false)
  wallix_need_template_build = !local.wallix_template_ready

  build_mac_seed = substr(md5(random_uuid.build_node_uuid.result), 0, 10)
  build_firstmac = format(
    "02:%s:%s:%s:%s:%s",
    substr(local.build_mac_seed, 0, 2),
    substr(local.build_mac_seed, 2, 2),
    substr(local.build_mac_seed, 4, 2),
    substr(local.build_mac_seed, 6, 2),
    substr(local.build_mac_seed, 8, 2),
  )

  target_mac_seed = substr(md5(random_uuid.target_node_uuid.result), 0, 10)
  target_firstmac = format(
    "02:%s:%s:%s:%s:%s",
    substr(local.target_mac_seed, 0, 2),
    substr(local.target_mac_seed, 2, 2),
    substr(local.target_mac_seed, 4, 2),
    substr(local.target_mac_seed, 6, 2),
    substr(local.target_mac_seed, 8, 2),
  )

  build_lab_xml = templatefile(local.lab_template, {
    lab_name      = "Wallix-TemplateBuild"
    lab_id        = random_uuid.build_lab_id.result
    description   = "Template build for WALLIX image ${var.wallix_image_name}"
    author        = tostring(var.pnet_tenant_id)
    node_id       = tostring(local.build_node_id)
    node_uuid     = random_uuid.build_node_uuid.result
    firstmac      = local.build_firstmac
    node_name     = var.wallix_build_node_name
    node_template = var.wallix_node_template
    image_name    = var.wallix_image_name
    cpu           = tostring(var.wallix_cpu)
    ram           = tostring(var.wallix_ram_mb)
    ethernet      = tostring(var.wallix_ethernet)
    qemu_nic      = "virtio-net-pci"
    qemu_options  = "-cpu host -machine type=pc,accel=kvm -vga virtio -usbdevice tablet -boot order=c,once=d"
    network_name  = var.pnet_mgmt_network_name
    network_type  = var.pnet_mgmt_network_type
  })

  target_lab_xml = templatefile(local.lab_template, {
    lab_name      = "Wallix-Auto"
    lab_id        = random_uuid.target_lab_id.result
    description   = "WALLIX Bastion lab (auto)"
    author        = tostring(var.pnet_tenant_id)
    node_id       = tostring(local.target_node_id)
    node_uuid     = random_uuid.target_node_uuid.result
    firstmac      = local.target_firstmac
    node_name     = var.wallix_target_node_name
    node_template = var.wallix_node_template
    image_name    = var.wallix_image_name
    cpu           = tostring(var.wallix_cpu)
    ram           = tostring(var.wallix_ram_mb)
    ethernet      = tostring(var.wallix_ethernet)
    qemu_nic      = "virtio-net-pci"
    qemu_options  = "-cpu host -machine type=pc,accel=kvm -vga virtio -usbdevice tablet -boot order=c"
    network_name  = var.pnet_mgmt_network_name
    network_type  = var.pnet_mgmt_network_type
  })
}

resource "local_file" "build_lab_unl" {
  filename = "${path.module}/build_lab.generated.unl"
  content  = local.build_lab_xml
}

resource "local_file" "target_lab_unl" {
  filename = "${path.module}/target_lab.generated.unl"
  content  = local.target_lab_xml
}

resource "null_resource" "upload_build_lab" {
  count = local.wallix_need_template_build ? 1 : 0

  triggers = {
    content_sha256 = sha256(local.build_lab_xml)
    lab_path       = var.pnet_build_lab_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.upload_lab_script}' '${local_file.build_lab_unl.filename}' '${var.pnet_build_lab_path}'"
  }

  depends_on = [null_resource.pnet_prepare_image, local_file.build_lab_unl]
}

resource "null_resource" "start_build_node" {
  count = local.wallix_need_template_build ? 1 : 0

  triggers = {
    lab_sha   = sha256(local.build_lab_xml)
    lab_path  = var.pnet_build_lab_path
    tenant_id = tostring(var.pnet_tenant_id)
    node_id   = tostring(local.build_node_id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.node_power_script}' start '${var.pnet_build_lab_path}' '${var.pnet_tenant_id}' '${local.build_node_id}'"
  }

  depends_on = [null_resource.upload_build_lab]
}

data "external" "discover_build_wallix" {
  count   = local.wallix_need_template_build ? 1 : 0
  program = ["python3", local.discover_wallix_script]
  query = {
    mgmt_subnet  = var.mgmt_subnet
    timeout_sec  = tostring(var.wallix_discovery_timeout_sec)
    expected_ver = "12."
    node_mac     = local.build_firstmac
  }

  depends_on = [null_resource.start_build_node]
}

resource "null_resource" "stop_build_node" {
  count = local.wallix_need_template_build ? 1 : 0

  triggers = {
    lab_sha   = sha256(local.build_lab_xml)
    lab_path  = var.pnet_build_lab_path
    tenant_id = tostring(var.pnet_tenant_id)
    node_id   = tostring(local.build_node_id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.node_power_script}' stop '${var.pnet_build_lab_path}' '${var.pnet_tenant_id}' '${local.build_node_id}'"
  }

  depends_on = [data.external.discover_build_wallix]
}

resource "null_resource" "commit_template" {
  count = local.wallix_need_template_build ? 1 : 0

  triggers = {
    build_lab_id  = random_uuid.build_lab_id.result
    build_node_id = tostring(local.build_node_id)
    image         = var.wallix_image_name
    pod           = tostring(var.wallix_pod_id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.commit_template_script}' '${self.triggers.build_lab_id}' '${self.triggers.build_node_id}' '${var.wallix_image_name}' '${var.wallix_pod_id}'"
  }

  depends_on = [null_resource.stop_build_node]
}

resource "null_resource" "wipe_build_node" {
  count = local.wallix_need_template_build ? 1 : 0

  triggers = {
    lab_sha   = sha256(local.build_lab_xml)
    lab_path  = var.pnet_build_lab_path
    tenant_id = tostring(var.pnet_tenant_id)
    node_id   = tostring(local.build_node_id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.node_power_script}' wipe '${var.pnet_build_lab_path}' '${var.pnet_tenant_id}' '${local.build_node_id}'"
  }

  depends_on = [null_resource.commit_template]
}

resource "null_resource" "upload_target_lab" {
  triggers = {
    content_sha256 = sha256(local.target_lab_xml)
    lab_path       = var.pnet_lab_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.upload_lab_script}' '${local_file.target_lab_unl.filename}' '${var.pnet_lab_path}'"
  }

  depends_on = [null_resource.pnet_prepare_image, null_resource.wipe_build_node, local_file.target_lab_unl]
}

resource "null_resource" "start_target_node" {
  triggers = {
    lab_sha   = sha256(local.target_lab_xml)
    lab_path  = var.pnet_lab_path
    tenant_id = tostring(var.pnet_tenant_id)
    node_id   = tostring(local.target_node_id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash '${local.node_power_script}' start '${var.pnet_lab_path}' '${var.pnet_tenant_id}' '${local.target_node_id}'"
  }

  depends_on = [null_resource.upload_target_lab]
}

data "external" "discover_target_wallix" {
  program = ["python3", local.discover_wallix_script]
  query = {
    mgmt_subnet  = var.mgmt_subnet
    timeout_sec  = tostring(var.wallix_discovery_timeout_sec)
    expected_ver = "12."
    node_mac     = local.target_firstmac
  }

  depends_on = [null_resource.start_target_node]
}
