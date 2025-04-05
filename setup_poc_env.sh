#!/bin/bash

echo "🚀 Setting up PoC Environment"
echo "==================================="

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        return 1
    fi
}

echo -e "\n📋 Checking Platform Requirements..."
# Check OS version
if [ -f /etc/redhat-release ]; then
    print_status "RHEL-based system detected"
else
    echo -e "${YELLOW}!${NC} Not a RHEL-based system, some features might not work as expected"
fi

# Check Python version
python3 --version | grep -q "Python 3.[89]" || python3 --version | grep -q "Python 3.1[0-9]"
print_status "Python 3.8 or later"

echo -e "\n📦 Installing Python packages..."
if command_exists pip3; then
    pip3 install --user awxkit>=9.3.0 openshift kubernetes
    print_status "Python packages installed"
else
    echo -e "${RED}✗${NC} pip3 not found. Please install python3-pip first."
    exit 1
fi

echo -e "\n📦 Installing Ansible collections..."
if command_exists ansible-galaxy; then
    ansible-galaxy collection install -r requirements.yml -f
    print_status "Ansible collections installed"
else
    echo -e "${RED}✗${NC} ansible-galaxy not found. Please install ansible-core first."
    exit 1
fi

echo -e "\n🔧 Setting up environment variables..."
export CONTROLLER_HOST="ansible-controller-aap.apps.ansible-cluster.sandbox2641.opentlc.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="vJ064m0NP0QUFpBPN3BwCWgGvp7uTJ6B"
export KUBECONFIG="/home/lab-user/cluster/auth/kubeconfig"
print_status "Environment variables set"

echo -e "\n🔍 Running Verification Steps..."

# Test controller connectivity
echo "Testing Controller API..."
if curl -k -s "https://${CONTROLLER_HOST}/api/v2/ping/" > /dev/null; then
    print_status "Controller API accessible"
else
    echo -e "${RED}✗${NC} Controller API not accessible"
fi

# Verify OpenShift/Kubernetes access
echo "Testing OpenShift/Kubernetes access..."
if [ -f "$KUBECONFIG" ]; then
    print_status "Kubeconfig found"
    if oc whoami &>/dev/null; then
        print_status "OpenShift authenticated"
        if oc get nodes &>/dev/null; then
            print_status "Cluster access verified"
        fi
    else
        echo -e "${RED}✗${NC} OpenShift authentication failed"
    fi
else
    echo -e "${RED}✗${NC} Kubeconfig not found at $KUBECONFIG"
fi

# Verify installed collections
echo -e "\n📦 Verifying installed collections..."
expected_collections=(
    "ansible.posix:2.0.0"
    "ansible.utils:5.1.2"
    "community.kubernetes:2.0.1"
    "infra.controller_configuration:3.0.2"
    "kubernetes.core:5.2.0"
    "awx.awx:>=21.0.0"
)

for collection in "${expected_collections[@]}"; do
    name=$(echo $collection | cut -d: -f1)
    version=$(echo $collection | cut -d: -f2)
    if ansible-galaxy collection list | grep -q "$name"; then
        print_status "Collection $name found"
    else
        echo -e "${RED}✗${NC} Collection $name not found"
    fi
done

# Verify Python packages
echo -e "\n📦 Verifying Python packages..."
required_packages=("awxkit" "openshift" "kubernetes")
for package in "${required_packages[@]}"; do
    if pip3 list | grep -q "^$package"; then
        print_status "Package $package installed"
    else
        echo -e "${RED}✗${NC} Package $package not installed"
    fi
done

# Verify external tools
echo -e "\n🔧 Verifying external tools..."
required_tools=("git" "curl" "openssl" "oc" "kubectl")
for tool in "${required_tools[@]}"; do
    if command_exists "$tool"; then
        print_status "Tool $tool found"
    else
        echo -e "${RED}✗${NC} Tool $tool not found"
    fi
done

echo -e "\n✨ Environment setup complete!"
echo -e "\nEnvironment Status:"
echo -e "- Controller URL: ${CONTROLLER_HOST}"
echo -e "- OpenShift Config: ${KUBECONFIG}"
echo -e "- Python Version: $(python3 --version 2>&1)"
echo -e "- Ansible Version: $(ansible --version 2>&1 | head -n1)"

# Enable debug mode if specified in system-card.yml
export ANSIBLE_DEBUG=1
export ANSIBLE_VERBOSITY=2

echo -e "\nFor troubleshooting, check:"
echo -e "- Environment variables with: env | grep -E 'CONTROLLER|KUBE|ANSIBLE'"
echo -e "- Ansible logs in: ./ansible.log"
echo -e "- Collection list with: ansible-galaxy collection list" 