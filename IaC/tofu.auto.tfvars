proxmox_api_url    = "https://192.168.1.2:8006"
image_url          = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
ssh_key_public_key = "./ssh_keys/ansible_ed25519.pub"
is_nesting         = true

containers = {
  "o11y-collector" : { "deployment_node": "asgard1", "memory" : 1024, cpu : 1, "disk_size" : 10, "network" : { "address" : "192.168.1.5", "prefix" : "24" } }
}

