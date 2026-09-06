#!/usr/bin/env bash

# Default names for SSH keys
DEFAULT_KEYS=("cluster" "infrastructure" "standard" "test")

# Parse command-line arguments
# Example usage:
#   ./generate.sh --names "pippo,pluto,paperino"
#
SSH_KEYS=()  # Will store either the user-provided names or default names.

while [[ $# -gt 0 ]]; do
  case "$1" in
    --names)
      shift
      # Split the next argument by commas into an array
      IFS=',' read -ra SSH_KEYS <<< "$1"
      shift
      ;;
    *)
      # Unknown argument; skip or handle as needed
      shift
      ;;
  esac
done

# If no --names were provided, use the default list
if [[ ${#SSH_KEYS[@]} -eq 0 ]]; then
  SSH_KEYS=("${DEFAULT_KEYS[@]}")
fi

# 1) Create the directory for SSH keys
mkdir -p files/ssh_keys/

# 2) Check and generate the ansible_password file
ANSIBLE_PASSWORD_FILE="./ansible_password"
if [[ -f "$ANSIBLE_PASSWORD_FILE" ]]; then
  echo "Error: '$ANSIBLE_PASSWORD_FILE' already exists. Skipping generation."
else
  openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c 32 > "$ANSIBLE_PASSWORD_FILE"
  echo "Ansible vault password generated successfully at: $ANSIBLE_PASSWORD_FILE"
fi

# 3) Check and generate each SSH key pair
for key in "${SSH_KEYS[@]}"; do
  KEY_PATH="files/ssh_keys/$key"
  if [[ -f "$KEY_PATH" ]]; then
    echo "SSH private key '$KEY_PATH' already exists. Skipping generation."
  else
    ssh-keygen -t ed25519 -f "$KEY_PATH" -q -N ""
    echo "SSH key pair generated for '$key': $KEY_PATH and $KEY_PATH.pub"
  fi
done

# 4) Vault-encrypt generated private keys
if [[ -f "$ANSIBLE_PASSWORD_FILE" ]]; then
  export ANSIBLE_VAULT_PASSWORD_FILE="$ANSIBLE_PASSWORD_FILE"
  for key in "${SSH_KEYS[@]}"; do
    KEY_PATH="files/ssh_keys/$key"
    if [[ -f "$KEY_PATH" ]]; then
      header=$(head -1 "$KEY_PATH")
      if [[ "$header" != '$ANSIBLE_VAULT'* ]]; then
        ansible-vault encrypt "$KEY_PATH"
        echo "Vault-encrypted: $KEY_PATH"
      fi
    fi
  done
fi

echo "Script completed."
