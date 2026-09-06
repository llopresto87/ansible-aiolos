# Aiolos

Ansible automation for a self-hosted Proxmox VE homelab. One control
node configures the hypervisors, creates LXC containers and KVM virtual
machines from YAML contracts, deploys Docker Compose applications behind
an nginx reverse proxy, and manages an OpenWrt router.

The name comes from Aiolos, the Greek keeper of the winds, who released
them on command.

## What it does

The repository is split into four stages. Each stage has its own
inventory and `group_vars/` directory, and each host or application is
described once in a YAML file.

| Stage | Directory | What happens |
|-------|-----------|--------------|
| 1. Host baseline | `01_proxmox/` | SSH hardening, package repositories, CPU governor, VFIO/GPU passthrough, i915 power management, network interfaces |
| 2. Guest provisioning | `02_lxc/`, `02_vm/` | LXC containers and KVM VMs created from contracts: templates, cloud-init, clone lifecycle, state control |
| 3. Application delivery | `03_applications/` | Docker engine, Compose projects rendered from a library, generated secrets, nginx routes, local CA certificates, Pi-hole DNS records |
| 4. Router management | `04_openwrt/` | OpenWrt bootstrap, package and service setup, raw UCI config push, config retrieval, sysupgrade with preserved settings |

41 roles do the work. The `playbooks/` directory holds the entry points,
grouped by stage (`proxmox/`, `lxc/`, `openwrt/`, `pihole/`, `pki/`,
`ssh_key_handling/`, `common_manual/`).

## Quick start

Requirements: Ansible, SSH access to a Proxmox node, and the
collections listed in `collections/requirements.yml`.

```bash
git clone https://github.com/llopresto87/ansible-aiolos.git
cd ansible-aiolos
ansible-galaxy collection install -r collections/requirements.yml

# Create the vault password file (gitignored) and load the environment
echo 'your-vault-password' > ansible_password
source ./ansible_initialize.sh

# Stage 1: baseline a Proxmox host
ansible-playbook -i 01_proxmox/inventory.ini playbooks/proxmox/initial_config.yaml

# Stage 2: create an LXC container from its contract
ansible-playbook -i 02_lxc/inventory.yaml playbooks/proxmox/create_lxc.yaml --limit example

# Stage 3: initialize the guest and deploy an application
ansible-playbook -i 03_applications/inventory.ini playbooks/lxc/initialize.yaml --limit wordpress
ansible-playbook -i 03_applications/inventory.ini playbooks/lxc/onboard_app.yaml --limit wordpress

# Stage 4: bootstrap an OpenWrt router
ansible-playbook -i 04_openwrt/inventory.ini playbooks/openwrt/bootstrap.yaml
```

The shipped inventories and `group_vars/` are examples. Hostnames use
`example.lan`, addresses come from the `192.0.2.0/24` documentation
range, and every secret is a placeholder. Copy an example, rename it,
and fill in your own values.

## Contracts

A contract is the `group_vars` file for one host or application. Roles
validate it before they act on it. Two examples from the repository:

An LXC container (`02_lxc/group_vars/example.yaml`):

```yaml
proxmox_container:
  vmid: 207
  container_name: example-lxc
  template_name: ubuntu-24.04-standard_24.04-2_amd64.tar.zst
  storage_pool: local-btrfs
  memory: 4096
  cores: 4
  disk: 128
  ip_address: 192.0.2.23/24
  gateway: 192.0.2.1
  password: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    ...
  autostart_lxc: true
```

An application (`03_applications/group_vars/wordpress.yaml`, shortened):

```yaml
install_docker: true
main_user: wordpress

compose_projects:
  - compose_directory: wordpress
    compose_source: template

compose_secret_vars:
  - WORDPRESS_DB_ROOT_PASSWORD
  - WORDPRESS_DB_PASSWORD

proxy_publish:
  - domain: wordpress.example.lan
    upstream_host: 192.0.2.126
    upstream_port: 8080
```

`compose_secret_vars` are generated on first run with random values,
unless the environment already provides them, and kept under the
gitignored `tmp/` directory on the control node.
`proxy_publish` is read by two roles: one writes the nginx site and
requests a certificate from the local CA, the other publishes the DNS
record to Pi-hole.

The full schemas for LXC, VM, and application contracts are in
[`.claude/skills/ansible-infra/SKILL.md`](.claude/skills/ansible-infra/SKILL.md).

## Secrets

All secrets go through `ansible-vault`. The vault password lives in
`ansible_password`, which is gitignored. To add a value:

```bash
ansible-vault encrypt_string 'the-secret' --name 'proxmox_api_password'
```

Generated SSH keys, certificates, and application secrets are written
under `files/ssh_keys/`, `generated/`, and `tmp/`, all excluded from
version control. `vault_keys.sh`
encrypts or decrypts the key directory in one step.

## Validation

```bash
./scripts/validate_repo.sh
```

This runs `yamllint`, checks that every inventory host has a matching
`group_vars` file, syntax-checks each playbook against its inventory,
and runs `ansible-lint` when it is installed.

## Working with AI coding agents

`AGENTS.md` is a short guide for coding agents such as Claude Code,
Codex, and Copilot. The Claude Code skill in `.claude/skills/ansible-infra/`
explains how to run the playbooks and how to write a contract.

## License

MIT. See [LICENSE](LICENSE).
