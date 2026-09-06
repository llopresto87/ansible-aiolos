#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

strict_validation="${STRICT_VALIDATION:-1}"

is_strict_validation() {
  [[ "${strict_validation}" == "1" ]]
}

warn_or_fail() {
  local message="$1"

  if is_strict_validation; then
    echo "Validation error: ${message}" >&2
    exit 1
  fi

  echo "Validation warning: ${message}"
}

require_command() {
  local command_name="$1"
  local message="$2"

  if command -v "${command_name}" >/dev/null 2>&1; then
    return 0
  fi

  warn_or_fail "required command '${command_name}' is not available. ${message}"
  return 1
}

collect_changed_yaml() {
  local candidates

  candidates="$({
    git diff --name-only --diff-filter=ACMRTUXB
    git ls-files --others --exclude-standard
  } || true)"

  if command -v rg >/dev/null 2>&1; then
    printf '%s\n' "${candidates}" | rg '\.ya?ml$' || true
  else
    printf '%s\n' "${candidates}" | grep -E '\.ya?ml$' || true
  fi
}

check_inventory_group_vars() {
  local inventory_dir="$1"
  local inventory_file
  if [[ -f "${inventory_dir}/inventory.ini" ]]; then
    inventory_file="${inventory_dir}/inventory.ini"
  elif [[ -f "${inventory_dir}/inventory.yaml" ]]; then
    inventory_file="${inventory_dir}/inventory.yaml"
  elif [[ -f "${inventory_dir}/inventory.yml" ]]; then
    inventory_file="${inventory_dir}/inventory.yml"
  else
    inventory_file="${inventory_dir}/inventory.ini"
  fi
  local group_vars_dir="${inventory_dir}/group_vars"
  local inventory_groups
  local has_drift=0

  if [[ ! -f "${inventory_file}" ]] || [[ ! -d "${group_vars_dir}" ]]; then
    return 0
  fi

  if [[ "${inventory_file}" == *.ini ]]; then
    inventory_groups="$(awk '/^\[[^]]+\]$/ {
        group_name = substr($0, 2, length($0) - 2)
        if (group_name !~ /:vars$/ && group_name !~ /:children$/ && group_name != "all") {
          print group_name
        }
      }' "${inventory_file}" | sort -u)"
  else
    # YAML inventory — extract top-level group names under all.children
    inventory_groups="$(python3 -c "
import yaml, sys
with open('${inventory_file}') as f:
    inv = yaml.safe_load(f)
if inv and 'all' in inv and 'children' in inv['all']:
    for g in inv['all']['children']:
        print(g)
" 2>/dev/null | sort -u)"
  fi

  while IFS= read -r group_var_file; do
    local group_name

    [[ -z "${group_var_file}" ]] && continue

    group_name="$(basename "${group_var_file}")"
    group_name="${group_name%.yaml}"
    group_name="${group_name%.yml}"

    if [[ "${group_name}" == "all" ]]; then
      continue
    fi

    # Skip example/template files
    if [[ "${group_name}" == *"example"* ]] || [[ "${group_name}" == *"rhel_guest"* ]]; then
      continue
    fi

    if [[ -n "${inventory_groups}" ]] && printf '%s\n' "${inventory_groups}" | grep -Fxq "${group_name}"; then
      continue
    fi

    echo "Group vars mismatch: ${group_var_file} has no matching group in ${inventory_file}" >&2
    has_drift=1
  done < <(find "${group_vars_dir}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

  return "${has_drift}"
}

echo "[1/5] Running yamllint on changed YAML files"
if require_command yamllint "yamllint is required by repository quality gates."; then
  changed_yaml="$(collect_changed_yaml)"

  if [[ -n "${changed_yaml}" ]]; then
    while IFS= read -r yaml_file; do
      [[ -z "${yaml_file}" ]] && continue
      yamllint "${yaml_file}"
    done <<< "${changed_yaml}"
  else
    echo "No changed YAML files detected"
  fi
fi

echo "[2/5] Validating inventory/group_vars coherence"
inventory_drift_detected=0

for inventory_dir in 01_proxmox 02_lxc 02_vm 03_applications 04_openwrt; do
  if ! check_inventory_group_vars "${inventory_dir}"; then
    inventory_drift_detected=1
  fi
done

if [[ "${inventory_drift_detected}" -ne 0 ]]; then
  echo "Warning: inventory/group_vars coherence drift detected (see above)"
fi

echo "[3/5] Running syntax checks"
if require_command ansible-playbook "ansible-playbook is required for syntax checks."; then
  if [[ -f "./ansible_initialize.sh" ]]; then
    # shellcheck disable=SC1091
    source ./ansible_initialize.sh >/dev/null
  fi

  if [[ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]]; then
    warn_or_fail "ANSIBLE_VAULT_PASSWORD_FILE is not set. Run 'source ./ansible_initialize.sh' first."
  elif [[ ! -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]]; then
    warn_or_fail "vault password file not found at ${ANSIBLE_VAULT_PASSWORD_FILE}"
  fi

  syntax_matrix=(
    # Proxmox host management
    "01_proxmox/inventory.ini playbooks/proxmox/initial_config.yaml"
    "01_proxmox/inventory.ini playbooks/proxmox/change_governor.yaml"
    "01_proxmox/inventory.ini playbooks/proxmox/reboot.yaml"
    "01_proxmox/inventory.ini playbooks/proxmox/check_network_configuration.yaml"
    # LXC provisioning
    "02_lxc/inventory.yaml playbooks/proxmox/create_lxc.yaml"
    "02_lxc/inventory.yaml playbooks/proxmox/destroy_by_vmid.yaml"
    # VM provisioning
    "02_lxc/inventory.yaml playbooks/proxmox/create_vm.yaml"
    "02_vm/inventory.yaml playbooks/proxmox/create_vm_from_groupvars.yaml"
    "02_vm/inventory.yaml playbooks/proxmox/destroy_and_create_vm.yaml"
    "02_vm/inventory.yaml playbooks/proxmox/ensure_vm_template.yaml"
    # SSH bootstrap
    "01_proxmox/inventory.ini playbooks/ssh_key_handling/initialize_ssh.yaml"
    # Guest runtime
    "03_applications/inventory.ini playbooks/lxc/initialize.yaml"
    "03_applications/inventory.ini playbooks/lxc/onboard_app.yaml"
    "03_applications/inventory.ini playbooks/common_manual/install_docker.yaml"
    # Pi-hole
    "03_applications/inventory.ini playbooks/pihole/update_dns.yaml"
    "03_applications/inventory.ini playbooks/pihole/update_list.yaml"
    # PKI
    "playbooks/pki/bootstrap_local_ca.yaml"
    "03_applications/inventory.ini playbooks/pki/distribute_local_ca.yaml"
    # OpenWrt
    "04_openwrt/inventory.ini playbooks/openwrt/bootstrap.yaml"
    "04_openwrt/inventory.ini playbooks/openwrt/reprovision.yaml"
    "04_openwrt/inventory.ini playbooks/openwrt/retrieve_config.yaml"
    "04_openwrt/inventory.ini playbooks/openwrt/sysupgrade.yaml"
    "04_openwrt/inventory.ini playbooks/openwrt/update_config.yaml"
    # Common manual operations
    "02_lxc/inventory.yaml playbooks/common_manual/validate_contracts.yaml"
    "02_lxc/inventory.yaml playbooks/common_manual/start_lxc.yaml"
    "02_lxc/inventory.yaml playbooks/common_manual/stop_lxc.yaml"
    "02_lxc/inventory.yaml playbooks/common_manual/generate_group_vars_from_probe.yaml"
    "03_applications/inventory.ini playbooks/common_manual/install_packages.yaml"
    "03_applications/inventory.ini playbooks/common_manual/update_deb_os.yaml"
    "03_applications/inventory.ini playbooks/common_manual/update_config_files.yaml"
  )

  for mapping in "${syntax_matrix[@]}"; do
    if [[ "${mapping}" == *" "* ]]; then
      inventory_file="${mapping%% *}"
      playbook_file="${mapping#* }"
      ansible-playbook --syntax-check -i "${inventory_file}" "${playbook_file}"
    else
      # No inventory — localhost-only playbook
      ansible-playbook --syntax-check "${mapping}"
    fi
  done
fi

echo "[4/5] Running ansible-lint"
if require_command ansible-lint "ansible-lint is required for role/playbook linting."; then
  ansible-lint playbooks roles
fi

echo "[5/5] Validation runner complete"
