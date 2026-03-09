variable "pnet_api_url" {
  description = "PNETLab/EVE-NG API base URL (optional for SSH mode). Example: https://192.168.214.132."
  type        = string
  default     = ""
}

variable "pnet_api_user" {
  description = "PNETLab/EVE-NG API username (optional for SSH mode)."
  type        = string
  default     = ""
}

variable "pnet_api_password" {
  description = "PNETLab/EVE-NG API password (optional for SSH mode)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "pnet_ssh_host" {
  description = "PNETLab SSH host/IP."
  type        = string
}

variable "pnet_ssh_user" {
  description = "PNETLab SSH username (typically root)."
  type        = string
  default     = "root"
}

variable "pnet_ssh_password" {
  description = "PNETLab SSH password (optional if using key)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "pnet_ssh_key_path" {
  description = "Path to SSH private key for PNETLab (optional)."
  type        = string
  default     = ""
}

variable "pnet_tenant_id" {
  description = "PNETLab tenant/user id for unl_wrapper actions (often 1 for admin)."
  type        = number
  default     = 1
}

variable "pnet_lab_path" {
  description = "Target lab path (ex: User1/Wallix-Auto.unl)."
  type        = string
}

variable "pnet_build_lab_path" {
  description = "Build lab path for template creation (ex: User1/Wallix-TemplateBuild.unl)."
  type        = string
}

variable "pnet_mgmt_network_name" {
  description = "Name of the MGMT network inside the lab."
  type        = string
  default     = "MGMT"
}

variable "pnet_mgmt_network_type" {
  description = "Network type to use for external connectivity (often pnet0/pnet1...)."
  type        = string
  default     = "pnet0"
}

variable "mgmt_subnet" {
  description = "Subnet to scan for the WALLIX node IP (ex: 192.168.214.0/24)."
  type        = string
}

variable "wallix_discovery_timeout_sec" {
  description = "Max seconds to wait for WALLIX to be reachable on /api/version."
  type        = number
  default     = 1800
}

variable "wallix_iso_path" {
  description = "Path to WALLIX ISO file (used to upload into PNETLab)."
  type        = string
}

variable "wallix_image_name" {
  description = "QEMU image folder name under /opt/unetlab/addons/qemu/ (ex: linux-wallix-bastion-12.0.17)."
  type        = string
}

variable "wallix_disk_size" {
  description = "Base disk size for WALLIX (qemu-img create)."
  type        = string
  default     = "120G"
}

variable "wallix_node_template" {
  description = "EVE/PNET template to use for the QEMU node."
  type        = string
  default     = "linux"
}

variable "wallix_build_node_name" {
  description = "Name for the build node (template installation)."
  type        = string
  default     = "wallix-build"
}

variable "wallix_target_node_name" {
  description = "Name for the final node."
  type        = string
  default     = "wallix"
}

variable "wallix_cpu" {
  description = "vCPU count for WALLIX node."
  type        = number
  default     = 4
}

variable "wallix_ram_mb" {
  description = "RAM for WALLIX node in MB."
  type        = number
  default     = 8192
}

variable "wallix_ethernet" {
  description = "Number of NICs for WALLIX node."
  type        = number
  default     = 1
}

variable "wallix_pod_id" {
  description = "PNET/EVE pod id (usually 0). Used for overlay commit path."
  type        = number
  default     = 0
}
