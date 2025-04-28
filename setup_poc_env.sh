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
# Improved ServiceAccount and namespace check
if ! oc get namespace aap &>/dev/null; then
    echo -e "${RED}✗${NC} Namespace 'aap' does not exist. Cannot check for pipeline-sa ServiceAccount."
else
    if ! oc get sa pipeline-sa -n aap &>/dev/null; then
        echo -e "${RED}✗${NC} ServiceAccount 'pipeline-sa' does not exist in namespace 'aap'."
    else
        print_status "pipeline-sa ServiceAccount exists in namespace aap"
    fi
fi

# Improved Controller route check
if ! oc get namespace aap &>/dev/null; then
    echo -e "${RED}✗${NC} Namespace 'aap' does not exist. Cannot check for Controller route."
elif ! oc get route ansible-controller -n aap &>/dev/null; then
    echo -e "${RED}✗${NC} Route 'ansible-controller' does not exist in namespace 'aap'."
else
    CONTROLLER_HOST=$(oc get route ansible-controller -n aap -o jsonpath='{.spec.host}')
    export CONTROLLER_HOST
    if [ -n "$CONTROLLER_HOST" ]; then
        echo "Testing Controller API at https://${CONTROLLER_HOST}/api/v2/ping/ ..."
        if curl -k -s "https://${CONTROLLER_HOST}/api/v2/ping/" > /dev/null; then
            print_status "Controller API accessible"
        else
            echo -e "${RED}✗${NC} Controller API not accessible at https://${CONTROLLER_HOST}/api/v2/ping/"
        fi
    else
        echo -e "${RED}✗${NC} Could not determine Controller host from route in namespace 'aap'."
    fi
fi

# Verify OpenShift/Kubernetes access
echo "Testing OpenShift/Kubernetes access..."
if oc whoami &>/dev/null; then
    print_status "OpenShift authenticated"
    if oc get nodes &>/dev/null; then
        print_status "Cluster access verified"
    fi
else
    echo -e "${RED}✗${NC} OpenShift authentication failed"
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
# Option 2: Use python -c for checking packages to avoid BrokenPipeError
required_packages=("awxkit" "openshift" "kubernetes")
for package in "${required_packages[@]}"; do
    # Map package name to import name if needed
    import_name="$package"
    if [ "$package" = "awxkit" ]; then
        import_name="awxkit"
    fi
    if python3 -c "import $import_name" 2>/dev/null; then
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

# --- Tekton & Namespace Checks ---

# Check for Tekton CRDs
TEKTON_CRDS=(pipelines.tekton.dev pipelineruns.tekton.dev tasks.tekton.dev)
TEKTON_MISSING=()
if command_exists kubectl; then
    for crd in "${TEKTON_CRDS[@]}"; do
        if ! kubectl get crd "$crd" &>/dev/null; then
            TEKTON_MISSING+=("$crd")
        fi
    done
    if [ ${#TEKTON_MISSING[@]} -eq 0 ]; then
        print_status "Tekton CRDs found"
    else
        echo -e "${YELLOW}!${NC} Missing Tekton CRDs: ${TEKTON_MISSING[*]}"
    fi
else
    echo -e "${YELLOW}!${NC} kubectl not found, skipping Tekton CRD check"
fi

# Ensure aap namespace exists
if command_exists oc; then
    if ! oc get namespace aap &>/dev/null; then
        echo -e "${YELLOW}!${NC} Namespace 'aap' not found. Creating..."
        oc create namespace aap
        print_status "Namespace 'aap' created"
    else
        print_status "Namespace 'aap' exists"
    fi
fi

# Check for required secret in aap namespace
if command_exists oc; then
    if ! oc get secret openshift-kubeconfig -n aap &>/dev/null; then
        echo -e "${YELLOW}!${NC} Secret 'openshift-kubeconfig' not found in namespace 'aap'. Attempting to create it using pipeline-sa token..."
        SA_TOKEN=$(oc create token pipeline-sa -n aap 2>/dev/null)
        APISERVER=$(oc whoami --show-server 2>/dev/null)
        if [ -n "$SA_TOKEN" ] && [ -n "$APISERVER" ]; then
            cat <<EOF > /tmp/pipeline-sa.kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: $APISERVER
    insecure-skip-tls-verify: true
  name: cluster
contexts:
- context:
    cluster: cluster
    user: pipeline-sa
  name: pipeline-sa@cluster
current-context: pipeline-sa@cluster
users:
- name: pipeline-sa
  user:
    token: $SA_TOKEN
EOF
            oc create secret generic openshift-kubeconfig --from-file=kubeconfig=/tmp/pipeline-sa.kubeconfig -n aap
            print_status "Secret 'openshift-kubeconfig' created using pipeline-sa token"
            rm -f /tmp/pipeline-sa.kubeconfig
        else
            echo -e "${RED}✗${NC} Could not generate kubeconfig: missing token or API server URL."
        fi
    else
        print_status "Secret 'openshift-kubeconfig' found in 'aap' namespace"
    fi
fi

# Check for pipeline YAMLs
PIPELINE_YAMLS=(tekton/pipelines/build-deploy-ee-pipeline.yaml tekton/pipelineruns/build-ee-test-run.yaml)
PIPELINE_MISSING=()
for yaml in "${PIPELINE_YAMLS[@]}"; do
    if [ ! -f "$yaml" ]; then
        PIPELINE_MISSING+=("$yaml")
    fi
done
if [ ${#PIPELINE_MISSING[@]} -eq 0 ]; then
    print_status "All required pipeline YAMLs found"
else
    echo -e "${YELLOW}!${NC} Missing pipeline YAMLs: ${PIPELINE_MISSING[*]}"
fi

# --- Check all PipelineRun YAMLs for serviceAccountName ---
PIPELINERUN_FILES=$(grep -rl 'kind: *PipelineRun' tekton/ | grep -E '\.ya?ml$')
PIPELINERUN_MISSING_SA=()
for file in $PIPELINERUN_FILES; do
    # Check for top-level serviceAccountName: pipeline-sa
    if ! grep -qE '^\s*serviceAccountName:\s*pipeline-sa' "$file"; then
        PIPELINERUN_MISSING_SA+=("$file")
    fi
done
if [ ${#PIPELINERUN_MISSING_SA[@]} -eq 0 ]; then
    print_status "All PipelineRun YAMLs have serviceAccountName: pipeline-sa"
else
    echo -e "${YELLOW}!${NC} The following PipelineRun YAMLs are missing serviceAccountName: pipeline-sa or have it misconfigured: ${PIPELINERUN_MISSING_SA[*]}"
fi

# --- End of Tekton & Namespace Checks ---

# --- Check for tkn CLI ---
if command_exists tkn; then
    print_status "Tekton CLI (tkn) found"
else
    echo -e "${YELLOW}!${NC} Tekton CLI (tkn) not found. Some Tekton operations require it. See https://tekton.dev/docs/cli/ for installation instructions."
fi

# --- Summary Output ---
echo -e "\n==============================="
echo -e "Setup Summary:"
echo -e "- KUBECONFIG: $KUBECONFIG"
echo -e "- pipeline-sa ServiceAccount: $(oc get sa pipeline-sa -n aap &>/dev/null && echo 'Present' || echo 'Missing')"
echo -e "- Tekton CRDs: $([ ${#TEKTON_MISSING[@]} -eq 0 ] && echo 'All present' || echo "Missing: ${TEKTON_MISSING[*]}")"
echo -e "- Namespace 'aap': $(oc get namespace aap &>/dev/null && echo 'Present' || echo 'Missing')"
echo -e "- Secret 'openshift-kubeconfig': $(oc get secret openshift-kubeconfig -n aap &>/dev/null && echo 'Present' || echo 'Missing')"
echo -e "- Pipeline YAMLs: $([ ${#PIPELINE_MISSING[@]} -eq 0 ] && echo 'All present' || echo "Missing: ${PIPELINE_MISSING[*]}")"
echo -e "==============================="

if [ ${#TEKTON_MISSING[@]} -ne 0 ] || [ ${#PIPELINE_MISSING[@]} -ne 0 ]; then
    echo -e "${YELLOW}!${NC} Some prerequisites are missing. Please review the warnings above before running Tekton pipelines."
fi

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
