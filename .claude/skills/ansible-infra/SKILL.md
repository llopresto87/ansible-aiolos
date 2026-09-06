---
name: ansible-infra
description: |
  Drive Ansible playbooks for Proxmox homelab IaC and author per-host YAML
  contracts. Use when running playbooks, provisioning LXC/VM, deploying
  applications, managing OpenWrt, or editing group_vars contract files.
---

# Ansible Infrastructure Skill

## Part A: Driving the Playbooks

### Order of operations

1. **01_proxmox** — Proxmox host baseline (networking, packages, hardening)
2. **02_lxc / 02_vm** — LXC container or KVM VM provisioning on Proxmox
3. **03_applications** — Guest bootstrap and dockerized application delivery
4. **04_openwrt** — OpenWrt router configuration and upgrades

### Playbook entrypoints

Initialize the environment first:

```bash
source ./ansible_initialize.sh
```

#### Proxmox host management (01_proxmox)

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/proxmox/initial_config.yaml` | `01_proxmox/inventory.ini` | Full host baseline |
| `playbooks/proxmox/change_governor.yaml` | `01_proxmox/inventory.ini` | CPU governor |
| `playbooks/proxmox/reboot.yaml` | `01_proxmox/inventory.ini` | Safe reboot |
| `playbooks/proxmox/check_network_configuration.yaml` | `01_proxmox/inventory.ini` | Network audit |

#### LXC provisioning (02_lxc)

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/proxmox/create_lxc.yaml` | `02_lxc/inventory.yaml` | Create LXC from contract |
| `playbooks/proxmox/destroy_by_vmid.yaml` | `02_lxc/inventory.yaml` | Destroy by VMID |
| `playbooks/common_manual/start_lxc.yaml` | `02_lxc/inventory.yaml` | Start containers |
| `playbooks/common_manual/stop_lxc.yaml` | `02_lxc/inventory.yaml` | Stop containers |
| `playbooks/common_manual/validate_contracts.yaml` | `02_lxc/inventory.yaml` | Validate contracts |

#### VM provisioning (02_vm)

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/proxmox/create_vm_from_groupvars.yaml` | `02_vm/inventory.yaml` | Create VM from contract |
| `playbooks/proxmox/destroy_and_create_vm.yaml` | `02_vm/inventory.yaml` | Recreate VM |
| `playbooks/proxmox/ensure_vm_template.yaml` | `02_vm/inventory.yaml` | Ensure cloud template |

#### Application delivery (03_applications)

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/lxc/initialize.yaml` | `03_applications/inventory.ini` | Full guest bootstrap |
| `playbooks/lxc/onboard_app.yaml` | `03_applications/inventory.ini` | Deploy compose apps |
| `playbooks/common_manual/install_docker.yaml` | `03_applications/inventory.ini` | Docker install |
| `playbooks/common_manual/install_packages.yaml` | `03_applications/inventory.ini` | OS packages |
| `playbooks/common_manual/update_deb_os.yaml` | `03_applications/inventory.ini` | OS updates |
| `playbooks/common_manual/update_config_files.yaml` | `03_applications/inventory.ini` | Push config files |
| `playbooks/pihole/update_dns.yaml` | `03_applications/inventory.ini` | Pi-hole DNS sync |

#### OpenWrt (04_openwrt)

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/openwrt/bootstrap.yaml` | `04_openwrt/inventory.ini` | Initial router setup |
| `playbooks/openwrt/reprovision.yaml` | `04_openwrt/inventory.ini` | Full reprovision |
| `playbooks/openwrt/update_config.yaml` | `04_openwrt/inventory.ini` | Config push |
| `playbooks/openwrt/sysupgrade.yaml` | `04_openwrt/inventory.ini` | Firmware upgrade |
| `playbooks/openwrt/retrieve_config.yaml` | `04_openwrt/inventory.ini` | Backup config |

#### PKI / SSH

| Playbook | Inventory | Purpose |
|----------|-----------|---------|
| `playbooks/pki/bootstrap_local_ca.yaml` | (localhost) | Create local CA |
| `playbooks/pki/distribute_local_ca.yaml` | `03_applications/inventory.ini` | Distribute CA cert |
| `playbooks/ssh_key_handling/initialize_ssh.yaml` | `01_proxmox/inventory.ini` | SSH key bootstrap |

### Vault workflow

```bash
# Set vault password file (run once per session)
source ./ansible_initialize.sh

# Encrypt a string for use in YAML
ansible-vault encrypt_string 'CHANGEME_secret' --name 'password'

# Edit an encrypted file
ansible-vault edit 02_lxc/group_vars/myhost.yaml

# Generate random vault-encrypted keys
./vault_keys.sh
```

### Useful patterns

```bash
# Limit to specific host
ansible-playbook -i 03_applications/inventory.ini playbooks/lxc/onboard_app.yaml --limit myapp

# Dry run (check mode)
ansible-playbook ... --check

# Show what would change
ansible-playbook ... --diff

# Run specific tags
ansible-playbook ... --tags "docker,compose"

# Skip tags
ansible-playbook ... --skip-tags "reboot"
```

### Validation gate

```bash
./scripts/validate_repo.sh
```

Runs yamllint, inventory coherence check, syntax-check matrix, and ansible-lint.

---

## Part B: Writing the YAML Contracts

Contracts are per-host files in `<section>/group_vars/<hostname>.yaml`.
The role code is the source of truth for field names.

### LXC contract (`proxmox_container`)

Located in `02_lxc/group_vars/<hostname>.yaml`.

**Required fields** (validated by `roles/proxmox_lxc_provision`):

| Field | Type | Description |
|-------|------|-------------|
| `vmid` | int | Container ID (unique across cluster) |
| `container_name` | string | Container hostname |
| `template_name` | string | OS template filename |
| `storage_pool` | string | Proxmox storage for rootfs |
| `cores` | int | CPU cores |
| `memory` | int | RAM in MB |
| `swap` | int | Swap in MB |
| `disk` | int | Root disk size in GB |
| `ip_address` | string | IP with CIDR (e.g., `192.0.2.10/24`) |
| `gateway` | string | Default gateway IP |
| `network_bridge` | string | Proxmox bridge (e.g., `vmbr0`) |
| `dns` | string | DNS server IP |
| `password` | vault | Root password (≥16 chars, mixed case/digit/special) |
| `ssh_public_key_path` | string | Path to SSH public key file |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `template_storage` | string | Storage containing template |
| `autostart_lxc` | bool | Start on host boot |
| `lxc_conf_lines` | list | Custom LXC config lines |
| `lxc_conf_cleanup_patterns` | list | Patterns to remove before applying lines |

**Example:**

```yaml
---
proxmox_api_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...

proxmox_container:
  vmid: 100
  container_name: myapp
  template_storage: local
  template_name: ubuntu-22.04-standard_22.04-1_amd64.tar.zst
  network_bridge: vmbr0
  storage_pool: local-lvm
  memory: 2048
  cores: 2
  disk: 16
  swap: 512
  ssh_public_key_path: files/ssh_keys/cluster.pub
  ip_address: 192.0.2.10/24
  gateway: 192.0.2.1
  password: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    ...encrypted...
  dns: 192.0.2.1
  autostart_lxc: true
```

### VM contract (`proxmox_vm_provision_proxmox_vm`)

Located in `02_vm/group_vars/<hostname>.yaml`.

**Required fields** (validated by `roles/proxmox_vm_provision`):

| Field | Type | Description |
|-------|------|-------------|
| `node` | string | Proxmox node name |
| `vmid` | int | VM ID (unique across cluster) |
| `name` | string | VM name |
| `ciuser` | string | Cloud-init user (non-default) |
| `cipassword` | vault | Cloud-init password (≥16 chars, strong) |

**Optional fields:**

| Field | Type | Description |
|-------|------|-------------|
| `clone` | int | Template VMID to clone from |
| `cores` | int | CPU cores |
| `memory` | int | RAM in MB |
| `sockets` | int | CPU sockets |
| `net0` | string | Network config |
| `scsihw` | string | SCSI controller type |
| `boot` | string | Boot order |
| `agent` | int | QEMU guest agent (1=enabled) |
| `ssh_public_key_path` | string | Path to SSH public key |
| `cloud_init_user_data` | dict | Cloud-init user-data config |

**Example:**

```yaml
---
proxmox_api_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...

proxmox_vm_provision_proxmox_vm:
  node: pve0
  vmid: 200
  name: myvm
  clone: 9000
  cores: 4
  memory: 8192
  sockets: 1
  net0: "virtio,bridge=vmbr0"
  ciuser: youruser
  cipassword: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    ...encrypted...
  ssh_public_key_path: files/ssh_keys/cluster.pub
  agent: 1
```

### Application contracts

Located in `03_applications/group_vars/<hostname>.yaml`.

**Core variables:**

| Variable | Type | Used by | Purpose |
|----------|------|---------|---------|
| `main_user` | string | `guest_user_bootstrap` | Application user name |
| `compose_projects` | list | `guest_compose_deploy` | Docker Compose projects to deploy |
| `composer` | dict | `guest_compose_deploy` | Inline Compose definition (Jinja2 rendered) |
| `compose_secret_vars` | list | `compose_secret_generate` | Secrets to auto-generate |
| `proxy_publish` | list | `nginx_proxy_configure` | Reverse proxy routes |
| `send_config_from_scratch` | list | `config_files` | Config files to push |
| `managed_services` | list | `systemd_manager` | Systemd services to manage |
| `package_list` | list | `guest_base_packages` | Extra OS packages |

**`compose_projects` schema:**

```yaml
compose_projects:
  - compose_directory: myapp          # Directory under ~main_user/
    compose_source: template          # 'template', 'library', or 'file'
    compose_file: myapp.yaml          # Source file (for library/file)
    config_dir: myapp_config          # Optional config directory
```

**`proxy_publish` schema:**

```yaml
proxy_publish:
  - domain: myapp.example.lan
    upstream_port: 8080
    ssl: true
    ssl_certificate: /etc/nginx/certs/myapp.crt
    ssl_certificate_key: /etc/nginx/certs/myapp.key
```

**Full application example:**

```yaml
---
host_distro_type: debian
install_docker: true
main_user: youruser
use_compose: true
ssh_key_type: standard

compose_projects:
  - compose_directory: myapp
    compose_source: template

compose_secret_vars:
  - name: db_password
    length: 32
  - name: api_key
    length: 64

composer:
  services:
    app:
      image: myapp:latest
      ports:
        - "8080:8080"
      environment:
        DB_PASSWORD: "{{ db_password }}"
      volumes:
        - app_data:/data
    db:
      image: postgres:15
      environment:
        POSTGRES_PASSWORD: "{{ db_password }}"
      volumes:
        - db_data:/var/lib/postgresql/data
  volumes:
    app_data: {}
    db_data: {}

proxy_publish:
  - domain: myapp.example.lan
    upstream_port: 8080
    ssl: true
    ssl_certificate: /etc/nginx/certs/local-proxy.crt
    ssl_certificate_key: /etc/nginx/certs/local-proxy.key

package_list:
  - htop
  - vim

managed_services:
  - name: docker
    state: started
    enabled: true
```

### Validation

Before provisioning, validate contracts:

```bash
ansible-playbook -i 02_lxc/inventory.yaml playbooks/common_manual/validate_contracts.yaml
```

The roles enforce:
- Password strength (≥16 chars, mixed case/digit/special)
- Non-default usernames (not root, admin, ubuntu, etc.)
- SSH key path resolution
- Required field presence
