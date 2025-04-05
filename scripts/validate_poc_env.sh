#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Get the root directory (one level up from scripts)
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "=== Ansible Automation Platform PoC Environment Validation ==="
echo

# Load environment variables
if [ -f "$SCRIPT_DIR/load_env.sh" ]; then
    source "$SCRIPT_DIR/load_env.sh"
else
    echo -e "${RED}Error: load_env.sh not found!${NC}"
    echo "Please ensure load_env.sh exists and is executable"
    exit 1
fi

# Check required environment variables
required_vars=("CONTROLLER_HOST" "CONTROLLER_USERNAME" "CONTROLLER_PASSWORD" "KUBECONFIG")
missing_vars=0

echo "Checking environment variables..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}✗ $var is not set${NC}"
        missing_vars=$((missing_vars + 1))
    else
        echo -e "${GREEN}✓ $var is set${NC}"
    fi
done

if [ $missing_vars -gt 0 ]; then
    echo -e "\n${RED}Error: Missing required environment variables${NC}"
    exit 1
fi

# Check required tools
required_tools=("ansible" "ansible-playbook" "oc" "git" "curl" "ansible-galaxy")
missing_tools=0

echo -e "\nChecking required tools..."
for tool in "${required_tools[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}✗ $tool is not installed${NC}"
        missing_tools=$((missing_tools + 1))
    else
        echo -e "${GREEN}✓ $tool is installed${NC}"
        if [ "$tool" = "ansible" ]; then
            version=$(ansible --version | head -n1)
            echo -e "${YELLOW}  $version${NC}"
        fi
    fi
done

if [ $missing_tools -gt 0 ]; then
    echo -e "\n${RED}Error: Missing required tools${NC}"
    exit 1
fi

# Check OpenShift connectivity
echo -e "\nChecking OpenShift connectivity..."
if ! oc whoami &> /dev/null; then
    echo -e "${RED}✗ Not logged into OpenShift${NC}"
    exit 1
else
    echo -e "${GREEN}✓ OpenShift authentication successful${NC}"
    echo -e "${YELLOW}  Logged in as: $(oc whoami)${NC}"
fi

# Check AAP connectivity
echo -e "\nChecking AAP connectivity..."
if ! curl -k -s -o /dev/null -w "%{http_code}" -u $CONTROLLER_USERNAME:$CONTROLLER_PASSWORD https://$CONTROLLER_HOST/api/controller/ | grep -q "200"; then
    echo -e "${RED}✗ Cannot connect to AAP${NC}"
    exit 1
else
    echo -e "${GREEN}✓ AAP connectivity successful${NC}"
    echo -e "${YELLOW}  API Version: v2${NC}"
fi

# Change to root directory for remaining checks
cd "$ROOT_DIR"

# Check repository structure
echo -e "\nChecking repository structure..."
required_dirs=("roles" "vars" "docs" "scripts")
missing_dirs=0

for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${RED}✗ $dir directory is missing${NC}"
        missing_dirs=$((missing_dirs + 1))
    else
        echo -e "${GREEN}✓ $dir directory exists${NC}"
    fi
done

if [ $missing_dirs -gt 0 ]; then
    echo -e "\n${RED}Error: Missing required directories${NC}"
    exit 1
fi

# Check configuration files
echo -e "\nChecking configuration files..."
required_files=("configure_aap.yml" "vars/general.yaml" "vars/controller_configuration_control.yaml" "requirements.yml")
missing_files=0

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ $file is missing${NC}"
        missing_files=$((missing_files + 1))
    else
        echo -e "${GREEN}✓ $file exists${NC}"
    fi
done

if [ $missing_files -gt 0 ]; then
    echo -e "\n${RED}Error: Missing required files${NC}"
    exit 1
fi

# Check and install required collections
echo -e "\nChecking Ansible collections..."
if [ -f "requirements.yml" ]; then
    echo -e "${YELLOW}Installing required collections from requirements.yml...${NC}"
    # Create collections directory if it doesn't exist
    mkdir -p collections
    if ANSIBLE_COLLECTIONS_PATH="./collections" ansible-galaxy collection install -r requirements.yml; then
        echo -e "${GREEN}✓ Collections installed successfully${NC}"
    else
        echo -e "${RED}✗ Failed to install collections${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ requirements.yml not found${NC}"
    exit 1
fi

# Check if collections are installed
echo -e "\nVerifying installed collections..."
required_collections=(
    "awx.awx"
    "infra.controller_configuration"
    "community.kubernetes"
    "community.general"
    "ansible.utils"
    "ansible.posix"
)
missing_collections=0

for collection in "${required_collections[@]}"; do
    if ANSIBLE_COLLECTIONS_PATH="./collections" ansible-galaxy collection list | grep -q "$collection"; then
        echo -e "${GREEN}✓ $collection is installed${NC}"
    else
        echo -e "${RED}✗ $collection is missing${NC}"
        missing_collections=$((missing_collections + 1))
    fi
done

if [ $missing_collections -gt 0 ]; then
    echo -e "\n${RED}Error: Missing required collections${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ All validation checks passed successfully!${NC}"
echo "You can now proceed with the PoC demonstration." 