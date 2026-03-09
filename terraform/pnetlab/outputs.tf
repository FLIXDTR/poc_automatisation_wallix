output "bastion_ip" {
  description = "WALLIX node IP discovered on the MGMT subnet."
  value       = data.external.discover_target_wallix.result.ip
}

output "bastion_url" {
  description = "WALLIX base URL discovered on the MGMT subnet."
  value       = data.external.discover_target_wallix.result.url
}

output "wallix_template_ready" {
  description = "Whether the WALLIX image on PNETLab has been committed to a reusable template (marker file exists)."
  value       = try(tobool(data.external.wallix_template_ready.result.ready), false)
}

output "wallix_build_skipped" {
  description = "True when template build phase was skipped because the template marker exists."
  value       = try(tobool(data.external.wallix_template_ready.result.ready), false)
}

output "wallix_build_firstmac" {
  description = "Deterministic first MAC address used for the build node (debug)."
  value       = local.build_firstmac
}

output "wallix_target_firstmac" {
  description = "Deterministic first MAC address used for the target node (debug)."
  value       = local.target_firstmac
}

output "wallix_ip" {
  description = "Alias for bastion_ip."
  value       = data.external.discover_target_wallix.result.ip
}

output "wallix_url" {
  description = "Alias for bastion_url."
  value       = data.external.discover_target_wallix.result.url
}

output "pnet_build_lab_id" {
  description = "Build lab id/uuid (used for overlay commit path)."
  value       = random_uuid.build_lab_id.result
}

output "pnet_build_node_id" {
  description = "Build node id."
  value       = tostring(local.build_node_id)
}
