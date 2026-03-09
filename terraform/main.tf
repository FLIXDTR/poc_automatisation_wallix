locals {
  use_guest_customization = var.enable_guest_customization
  use_static_ip           = local.use_guest_customization && trim(var.bastion_ip) != ""
  normalized_vm_hostname  = substr(regexreplace(lower(var.vm_name), "[^a-z0-9-]", "-"), 0, 63)
  resolved_bastion_ip     = trim(var.bastion_ip) != "" ? trim(var.bastion_ip) : try(vsphere_virtual_machine.bastion.default_ip_address, "")
  bastion_url_host        = local.resolved_bastion_ip != "" ? local.resolved_bastion_ip : var.vm_name
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "bastion" {
  name             = var.vm_name
  folder           = trim(var.vm_folder) == "" ? null : var.vm_folder
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.vm_cpu
  memory   = var.vm_memory_mb

  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  firmware  = data.vsphere_virtual_machine.template.firmware

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = try(data.vsphere_virtual_machine.template.network_interface_types[0], "vmxnet3")
  }

  disk {
    label            = "disk0"
    size             = max(var.vm_disk_gb, data.vsphere_virtual_machine.template.disks[0].size)
    thin_provisioned = try(data.vsphere_virtual_machine.template.disks[0].thin_provisioned, true)
  }

  wait_for_guest_net_timeout  = local.use_static_ip ? 0 : 15
  wait_for_guest_net_routable = false

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    linked_clone  = false
    timeout       = 30

    dynamic "customize" {
      for_each = local.use_guest_customization ? [1] : []
      content {
        linux_options {
          host_name = local.normalized_vm_hostname
          domain    = var.bastion_domain
        }

        network_interface {
          ipv4_address = local.use_static_ip ? var.bastion_ip : null
          ipv4_netmask = local.use_static_ip ? var.bastion_netmask : null
        }

        ipv4_gateway    = local.use_static_ip ? var.bastion_gateway : null
        dns_server_list = var.dns_servers
      }
    }
  }

  annotation = "Managed by Terraform PoC for WALLIX Bastion."
}
