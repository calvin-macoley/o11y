proxmox_api_url    = "https://192.168.1.2:8006"
image_url          = "https://cloud.debian.org/images/cloud/trixie-backports/latest/debian-13-backports-generic-amd64.qcow2"
ssh_key_public_key = "ssh_keys/tofu-proxmox.pub"

vms = {
  "o11y" : { "deployment_node" : "asgard1", "memory" : 4096, cpu : 2, "disk_size" : 50, "network" : { "address" : "192.168.1.8", "prefix" : "24" }, "file_name" : "user-data-cloud-config-o11y" }
}

