module "o11y" {
  source = "git::git@gitlab.com:homelab2522921/terraform-modules/vm-provisionning.git?ref=v0.0.4"

  proxmox_api_url          = var.proxmox_api_url
  proxmox_api_token_secret = var.proxmox_api_token_secret
  image_url                = var.image_url
  ssh_key                  = var.ssh_key_public_key
  gateway                  = var.gateway
  vms                      = var.vms
}
