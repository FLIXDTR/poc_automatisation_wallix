variable "vsphere_server" {
  description = "vCenter endpoint (hostname or IP)."
  type        = string
}

variable "vsphere_user" {
  description = "vCenter username."
  type        = string
}

variable "vsphere_password" {
  description = "vCenter password."
  type        = string
  sensitive   = true
}

variable "vsphere_allow_unverified_ssl" {
  description = "Allow insecure TLS to vCenter (PoC convenience)."
  type        = bool
  default     = true
}

variable "datacenter" {
  description = "vSphere datacenter name."
  type        = string
}

variable "cluster" {
  description = "vSphere compute cluster name."
  type        = string
}

variable "datastore" {
  description = "vSphere datastore name."
  type        = string
}

variable "network" {
  description = "vSphere network name."
  type        = string
}

variable "resource_pool" {
  description = "vSphere resource pool name."
  type        = string
}

variable "template_name" {
  description = "Seed template VM name created from WALLIX ISO."
  type        = string
  default     = "wallix-bastion-base-v1"
}

variable "vm_name" {
  description = "Deployed WALLIX Bastion VM name."
  type        = string
}

variable "vm_folder" {
  description = "Optional VM folder in vSphere inventory."
  type        = string
  default     = ""
}

variable "vm_cpu" {
  description = "Number of vCPUs."
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Memory in MB."
  type        = number
  default     = 8192
}

variable "vm_disk_gb" {
  description = "Primary disk size in GB."
  type        = number
  default     = 120
}

variable "enable_guest_customization" {
  description = "Enable clone guest customization for networking/hostname."
  type        = bool
  default     = false
}

variable "bastion_ip" {
  description = "Static IPv4 for Bastion (optional). Leave empty for template/DHCP."
  type        = string
  default     = ""
}

variable "bastion_netmask" {
  description = "IPv4 netmask bits used when static IP is set."
  type        = number
  default     = 24
}

variable "bastion_gateway" {
  description = "IPv4 gateway used when static IP is set."
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "DNS server list passed to guest customization."
  type        = list(string)
  default     = []
}

variable "bastion_domain" {
  description = "Guest customization domain."
  type        = string
  default     = "localdomain"
}
