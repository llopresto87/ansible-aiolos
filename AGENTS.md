# Aiolos — Ansible Homelab IaC

> Aiolos, keeper of the winds — one control node releasing fleets of
> hosts, guests, and services on command.

Ansible infrastructure-as-code for Proxmox VE homelab management:
host baseline → LXC/VM provisioning → dockerized app delivery → OpenWrt.

## Repository layout

| Section | Purpose | Inventory |
|---------|---------|-----------|
| `01_proxmox/` | Proxmox host baseline and hardening | `inventory.ini` |
| `02_lxc/` | LXC container provisioning | `inventory.yaml` |
| `02_vm/` | KVM VM provisioning | `inventory.yaml` |
| `03_applications/` | Dockerized application delivery | `inventory.ini` |
| `04_openwrt/` | OpenWrt router management | `inventory.ini` |

Each section has its own `inventory.*` and `group_vars/` directory.
Per-host contracts are defined in `group_vars/<hostname>.yaml`.

## Running playbooks

```bash
# Initialize environment (sets vault password path)
source ./ansible_initialize.sh

# Run a playbook with the appropriate section inventory
ansible-playbook -i <section>/inventory.<ext> playbooks/<category>/<playbook>.yaml

# Examples:
ansible-playbook -i 01_proxmox/inventory.ini playbooks/proxmox/initial_config.yaml
ansible-playbook -i 02_lxc/inventory.yaml playbooks/proxmox/create_lxc.yaml
ansible-playbook -i 03_applications/inventory.ini playbooks/lxc/initialize.yaml
ansible-playbook -i 04_openwrt/inventory.ini playbooks/openwrt/bootstrap.yaml

# Limit to specific hosts
ansible-playbook -i 03_applications/inventory.ini playbooks/lxc/onboard_app.yaml --limit myapp
```

## Secrets policy

- All secrets use `ansible-vault` encryption
- Vault password file: `ansible_password` (gitignored, never commit)
- Generate vault keys: `./vault_keys.sh`
- Encrypt: `ansible-vault encrypt_string 'secret' --name 'var_name'`
- Edit vaulted file: `ansible-vault edit <file>`

**Never commit plaintext secrets.**

## Validation

Run the validation gate before committing:

```bash
./scripts/validate_repo.sh
```

This runs:
1. `yamllint` on changed YAML files
2. Inventory/group_vars coherence check
3. `ansible-playbook --syntax-check` on all playbook×inventory pairs
4. `ansible-lint` on playbooks and roles

## Collections

Install required collections:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

## Detailed documentation

See `.claude/skills/ansible-infra/SKILL.md` for:
- Playbook entrypoints and inventory pairings
- LXC and VM provisioning contract schemas
- Application delivery contract variables
- Tag and limit patterns
