#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get the root directory (one level up from scripts)
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Check if .env file exists in root directory
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo "Error: .env file not found in project root!"
    echo "Please copy scripts/.env.template to .env in the project root and update with your values"
    exit 1
fi

# Load environment variables
set -a
source "$ROOT_DIR/.env"
set +a

# Optional: Display loaded variables (commented out for security)
# echo "Environment variables loaded:"
# env | grep -E 'CONTROLLER|ANSIBLE|KUBECONFIG'

echo "Environment variables loaded successfully!" 