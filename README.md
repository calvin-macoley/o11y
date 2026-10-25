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
provisioned VM. Everything runs as rootless [Podman](https://podman.io/)
containers under a dedicated `o11y` user, orchestrated with `podman-compose`.

### What gets installed

- **Podman** (`podman` + `podman-compose`), configured for **rootless** use:
  sub-uid/sub-gid ranges, lingering enabled for the `o11y` user, and the
  per-user Podman socket started.
- **Grafana** — a single `grafana-enterprise` container.
- **Mimir** — a highly-available cluster: three `mimir` replicas that gossip
  over memberlist, fronted by an **nginx** load balancer (`:9009`) and backed
  by **MinIO** as the S3-compatible object store. Configuration is templated
  into `~/compose_files/config/` (`mimir.yaml`, `nginx.conf`,
  `alertmanager-fallback-config.yaml`) before the stack is brought up.
- _ClickHouse_ is scaffolded but currently disabled in the install playbook.

### Layout

| Path | Purpose |
|---|---|
| `o11y-deployment/inventory/hosts` | Target hosts (the `o11y` VM at `192.168.1.8`) |
| `o11y-deployment/group_vars/all.yml` | Per-service config (image, tag, ports, data/compose folders) |
| `o11y-deployment/ssh-cert.yml` | Playbook: gets the OpenBao SSH cert; imported first by the other playbooks |
| `o11y-deployment/o11y-commons.yml` | Playbook: base setup (utilities, `o11y` user, directories, SSH CA trust) |
| `o11y-deployment/o11y-install.yml` | Playbook: install Podman, Mimir and Grafana |
| `o11y-deployment/o11y-full-install.yml` | Playbook: runs commons then install, end to end |
| `o11y-deployment/roles/o11y_commons/` | Role: creates the `o11y` user and compose/data directories |
| `o11y-deployment/roles/o11y_install/` | Role: installs Podman and templates/starts the compose stacks |

Each role dispatches on an `*_actions` variable, looping over ordered task
files (e.g. `utilities` → `users` → `directories`, then `podman` → `mimir` →
`grafana`) so steps run in a deterministic order.

### Prerequisites

- [Ansible](https://www.ansible.com/) installed on the control machine
- The `deamen.podman` and [`calvin.openbao`](https://gitlab.com/homelab2522921/ansible-modules/ansible-openbao)
  collections: `ansible-galaxy collection install -r requirements.yml`
- SSH access to the target VM as the `ansible` user, with the private key at
  `~/.ssh/o11y` (outside the repo; set via `private_key_file` in `ansible.cfg`)

### SSH certificates (OpenBao)

Logins use a short-lived (30 min) SSH certificate signed by OpenBao's
`ssh-client-signer` engine (role `ansible`). Every playbook first imports
`ssh-cert.yml`, which runs `calvin.openbao.ssh_client_cert` on the control node:
it reuses `~/.ssh/o11y-cert.pub` while it is valid for 5 more minutes, otherwise
asks OpenBao for a new one. ssh picks the cert up automatically next to `~/.ssh/o11y`.

```sh
export BAO_TOKEN=<your token>           # never commit it; only needed to renew
# export BAO_ADDR=https://192.168.1.4:8200  # default
# export BAO_CACERT=~/.config/openbao/ca.pem # default: pinned self-signed OpenBao cert
```

OpenBao's TLS cert is self-signed, so it is pinned in `~/.config/openbao/ca.pem`
(outside the repo) instead of disabling verification. `o11y-commons.yml` makes
hosts trust the CA (`calvin.openbao.ssh_ca_trust`). New hosts must trust the CA once
(`ansible-playbook o11y-commons.yml`); plain key login keeps working as a fallback.

For the CI token (policy and how to create/renew it), see
[OPENBAO-CI-TOKEN.md](OPENBAO-CI-TOKEN.md).

### Usage

```sh
cd o11y-deployment
ansible-galaxy collection install -r requirements.yml
export BAO_TOKEN=<your token>
ansible-playbook o11y-full-install.yml
```

Grafana is then reachable on `:3000` and the Mimir write/read endpoint (behind
the nginx load balancer) on `:9009` of the VM.

### Notes

- The stack is derived from Grafana's
  [Play with Grafana Mimir](https://grafana.com/docs/mimir/latest/get-started/play-with-grafana-mimir/)
  example and is **not production-hardened**.
- The MinIO credentials are currently hardcoded (`MINIO_ROOT_PASSWORD=supersecret`,
  and the matching `secret_access_key` in `mimir.yaml`). For anything beyond a
  homelab demo these should be moved into an `ansible-vault`–encrypted variable
  so the compose file and Mimir config stay in sync.
