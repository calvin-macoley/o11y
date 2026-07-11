# o11y

Observability stack for the homelab: an OpenTofu configuration
([`IaC/`](IaC)) provisions the o11y VM on the Proxmox cluster, then Ansible
([`o11y-deployment/`](o11y-deployment)) installs the monitoring stack on it.

## Infrastructure as Code (`IaC/`)

The OpenTofu configuration delegates VM creation to the reusable
[vm-provisionning](https://gitlab.com/homelab2522921/terraform-modules/vm-provisionning)
module (`v0.0.4`), which downloads a Debian cloud image, renders a cloud-init
snippet and creates the VM(s) through the `bpg/proxmox` provider (v0.111.0).

### What gets created

For each entry in the `vms` map, the module creates on the target Proxmox node:

- a **cloud-init snippet** (hostname + injected SSH public key)
- a **Debian cloud image** download (imported once per node)
- a **VM** with the requested CPU / memory / disk, a static IPv4 address on
  `vmbr0`, and the QEMU guest agent enabled

Current deployment (see [`IaC/tofu.auto.tfvars`](IaC/tofu.auto.tfvars)):

| VM | Node | CPU | RAM | Disk | Address |
|---|---|---|---|---|---|
| `o11y` | `asgard1` | 2 cores | 4096 MB | 50 GB | `192.168.1.8/24` |

### Layout

| File | Purpose |
|---|---|
| `IaC/provider.tf` | `bpg/proxmox` provider configuration |
| `IaC/main.tf` | Call to the `vm-provisionning` module |
| `IaC/variables.tf` | Input variables |
| `IaC/ouputs.tf` | Exposes the provisioned VMs' IP addresses |
| `IaC/tofu.auto.tfvars` | Concrete values for this deployment |
| `IaC/ssh_keys/` | Public SSH key(s) injected into the VMs via cloud-init |

### Variables

| Variable | Description | Default |
|---|---|---|
| `proxmox_api_url` | Proxmox API endpoint, e.g. `https://192.168.1.2:8006` | — |
| `proxmox_api_token_secret` | Proxmox API token (**sensitive**), e.g. `root@pam!terraform=xxxx…` | — |
| `image_url` | URL of the Debian cloud image (qcow2) to import | — |
| `ssh_key_public_key` | Path to the public SSH key injected into the VMs | — |
| `gateway` | IPv4 gateway for the VMs | `192.168.1.1` |
| `vms` | Map of VM definitions: `deployment_node`, `memory` (MB), `cpu` (cores), `disk_size` (GB), `network` (`address` + `prefix`), `file_name` (cloud-init snippet name) | `{}` |

### Prerequisites

- [OpenTofu](https://opentofu.org/) installed
- A Proxmox API token with permissions to create VMs, files and downloads
- SSH access to the Proxmox node as `root` with your key loaded in the agent
  (the provider uses `ssh { agent = true }` for snippet uploads)
- Access to the private GitLab module (`git@gitlab.com` SSH access), since
  `main.tf` sources the module over SSH

### Usage

The API token is intentionally kept out of the tfvars file — provide it via
an environment variable:

```sh
export TF_VAR_proxmox_api_token_secret='root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

cd IaC
tofu init
tofu plan
tofu apply
```

All other values are picked up automatically from `tofu.auto.tfvars`.

### Outputs

| Output | Description |
|---|---|
| `vms_addresses` | Map of VM name → IP address, as reported by the module |

### Notes

- `insecure = true` is set on the provider because the Proxmox endpoint uses
  a self-signed certificate.
- The imported cloud image is created with `overwrite_unmanaged = true` and
  `ignore_changes = all`, so re-applies won't re-download it needlessly.

## Deployment (`o11y-deployment/`)

Ansible playbooks that install and configure the observability stack on the
provisioned VM. See the playbooks in [`o11y-deployment/`](o11y-deployment).
