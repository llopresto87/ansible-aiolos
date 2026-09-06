#!/bin/bash

# Set your vault password as an environment variable
# Path to the directory containing files
FILES_DIR="files/ssh_keys"

# Encrypt all files in the directory
encrypt_files() {
    for file in "$FILES_DIR"/*; do
        ansible-vault encrypt "$file"
    done
}

# Decrypt all files in the directory
decrypt_files() {
    for file in "$FILES_DIR"/*; do
        ansible-vault decrypt "$file"
    done
}

# Main script logic
case "$1" in
    -e)
        encrypt_files
        ;;
    -d)
        decrypt_files
        ;;
    *)
        echo "Usage: $0 {-e|-d}"
        exit 1
        ;;
esac
