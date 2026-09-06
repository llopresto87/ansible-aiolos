#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Set environment variable for ansible vault password file
export ANSIBLE_VAULT_PASSWORD_FILE="${PWD}/ansible_password"

echo "ANSIBLE_VAULT_PASSWORD_FILE set to '${PWD}/ansible_password'"

if [[ ! -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]]; then
    echo "Warning: ansible_password file not found at ${ANSIBLE_VAULT_PASSWORD_FILE}" >&2
fi

# Change prompt if running interactively
if [[ -n "${PS1:-}" ]] && [[ "$PS1" != *"(initialize)"* ]]; then
    PS1="(initialize) $PS1"
fi

