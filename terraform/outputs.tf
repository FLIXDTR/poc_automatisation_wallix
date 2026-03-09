output "bastion_vm_name" {
  description = "WALLIX Bastion VM name."
  value       = vsphere_virtual_machine.bastion.name
}

output "bastion_vm_id" {
  description = "WALLIX Bastion VM managed object ID."
  value       = vsphere_virtual_machine.bastion.id
}

output "bastion_ip" {
  description = "Resolved Bastion IP address (static value or guest reported IP)."
  value       = local.resolved_bastion_ip
}

output "bastion_url" {
  description = "Bastion base URL used by Ansible/API smoke tests."
  value       = "https://${local.bastion_url_host}"
}
