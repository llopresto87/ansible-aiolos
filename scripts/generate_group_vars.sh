#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Usage: scripts/generate_group_vars.sh -i INVENTORY [-l LIMIT] [-m MODE] [--allow-become]

inventory="02_lxc/inventory.yaml"
limit=""
mode="full-scan"
allow_become=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--inventory)
      inventory="$2"
      shift 2
      ;;
    -l|--limit)
      limit="$2"
      shift 2
      ;;
    -m|--mode)
      mode="$2"
      shift 2
      ;;
    --allow-become)
      allow_become=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 -i INVENTORY [-l LIMIT] [-m MODE] [--allow-become]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Source repo ansible initialization (vault password file, etc.) if present
if [[ -f ./ansible_initialize.sh ]]; then
  # shellcheck disable=SC1091
  . ./ansible_initialize.sh
fi

extra_args=()
extra_args+=("-e" "host_probe_mode=${mode}")
extra_args+=("-e" "host_probe_output_root=generated")
if [[ "${allow_become}" == "true" ]]; then
  extra_args+=("-e" "host_probe_allow_become=true")
fi

cmd=(ansible-playbook -i "${inventory}" playbooks/common_manual/generate_group_vars_from_probe.yaml "${extra_args[@]}")
if [[ -n "${limit}" ]]; then
  cmd+=(--limit "${limit}")
fi

echo "Running: ${cmd[*]}"
"${cmd[@]}"
