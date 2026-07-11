variable "proxmox_api_url" {
  type        = string
  description = "Proxmox's API URL"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox's API Token"
}

variable "image_url" {
  type        = string
  description = "Image container's URL"
}

variable "ssh_key_public_key" {
  type        = string
  description = "Container's public ssh key"
}

variable "gateway" {
  type        = string
  description = "Container's gateway"
  default     = "192.168.1.1"
}

variable "vms" {
  type = map(object({
    deployment_node = string
    memory          = number
    cpu             = number
    disk_size       = number
    network = object({
      address = string
      prefix  = string
    }),
    file_name = string
  }))
  default = {}
}

