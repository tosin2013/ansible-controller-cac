#!/bin/bash

# Colors for status output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Timestamp function for logging
timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Status reporting function
log_status() {
    local status=$1
    local message=$2
    echo -e "[$(timestamp)] ${status}: ${message}"
}

# Success/failure reporting
success() {
    log_status "${GREEN}SUCCESS${NC}" "$1"
}

failure() {
    log_status "${RED}FAILURE${NC}" "$1"
    return 1
}

warning() {
    log_status "${YELLOW}WARNING${NC}" "$1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    echo "Validating prerequisites..."
    
    # Check KUBECONFIG
    if [ -z "$KUBECONFIG" ] || [ ! -f "$KUBECONFIG" ]; then
        failure "KUBECONFIG is not set or file does not exist"
        return 1
    fi
    success "KUBECONFIG is valid: $KUBECONFIG"

    # Check oc CLI
    if ! command_exists oc; then
        failure "oc CLI is not installed"
        return 1
    fi
    success "oc CLI is installed"

    # Check tkn CLI
    if ! command_exists tkn; then
        failure "tkn CLI is not installed"
        return 1
    fi
    success "tkn CLI is installed"

    # Verify cluster access
    if ! oc whoami &>/dev/null; then
        failure "Cannot access OpenShift cluster"
        return 1
    fi
    success "OpenShift cluster access verified"
}

# Setup namespace
setup_namespace() {
    echo "Setting up namespace..."
    if ! oc get namespace aap &>/dev/null; then
        if ! oc create namespace aap; then
            failure "Failed to create namespace 'aap'"
            return 1
        fi
        success "Namespace 'aap' created"
    else
        success "Namespace 'aap' already exists"
    fi
}

# Apply ServiceAccount and permissions
setup_service_account() {
    echo "Setting up ServiceAccount and permissions..."
    
    if ! oc apply -f tekton/sa-permissions.yaml -n aap; then
        failure "Failed to apply ServiceAccount permissions"
        return 1
    fi
    success "ServiceAccount and permissions applied"

    # Verify ServiceAccount and its resources exist
    echo "Verifying ServiceAccount and permissions..."
    
    # Check ServiceAccount
    if ! oc get sa pipeline-sa -n aap &>/dev/null; then
        failure "ServiceAccount pipeline-sa not found"
        return 1
    fi
    success "ServiceAccount pipeline-sa exists"

    # Check Role
    if ! oc get role pipeline-role -n aap &>/dev/null; then
        failure "Role pipeline-role not found"
        return 1
    fi
    success "Role pipeline-role exists"

    # Check RoleBinding
    if ! oc get rolebinding pipeline-role-binding -n aap &>/dev/null; then
        failure "RoleBinding pipeline-role-binding not found"
        return 1
    fi
    success "RoleBinding pipeline-role-binding exists"

    # Check ClusterRole
    if ! oc get clusterrole image-registry-access &>/dev/null; then
        failure "ClusterRole image-registry-access not found"
        return 1
    fi
    success "ClusterRole image-registry-access exists"

    # Check ClusterRoleBinding
    if ! oc get clusterrolebinding pipeline-registry-access &>/dev/null; then
        failure "ClusterRoleBinding pipeline-registry-access not found"
        return 1
    fi
    success "ClusterRoleBinding pipeline-registry-access exists"

    success "All ServiceAccount resources verified"
}

# Apply Tekton Tasks
apply_tasks() {
    echo "Applying Tekton Tasks..."
    local failed=0
    
    for task_file in tekton/tasks/*.yaml; do
        if [ -f "$task_file" ]; then
            echo "Applying task: $task_file"
            if ! oc apply -f "$task_file" -n aap; then
                warning "Failed to apply task: $task_file"
                ((failed++))
            else
                # Extract task name and verify it's created
                task_name=$(awk '/kind: Task/{getline; getline; print $2}' "$task_file")
                if [ -n "$task_name" ]; then
                    if ! oc wait --for=condition=Ready task/$task_name -n aap --timeout=30s; then
                        warning "Task $task_name not ready after 30s"
                        ((failed++))
                    else
                        success "Task $task_name ready"
                    fi
                fi
            fi
        fi
    done

    if [ $failed -gt 0 ]; then
        failure "$failed task(s) failed to apply or verify"
        return 1
    fi
    success "All tasks applied and verified successfully"
}

# Apply Tekton Pipelines
apply_pipelines() {
    echo "Applying Tekton Pipelines..."
    local failed=0
    
    for pipeline_file in tekton/pipelines/*.yaml; do
        if [ -f "$pipeline_file" ]; then
            echo "Applying pipeline: $pipeline_file"
            if ! oc apply -f "$pipeline_file" -n aap; then
                warning "Failed to apply pipeline: $pipeline_file"
                ((failed++))
            else
                # Extract pipeline name and verify it's created
                pipeline_name=$(awk '/kind: Pipeline/{getline; getline; print $2}' "$pipeline_file")
                if [ -n "$pipeline_name" ]; then
                    success "Pipeline $pipeline_name created"
                fi
            fi
        fi
    done

    if [ $failed -gt 0 ]; then
        failure "$failed pipeline(s) failed to apply"
        return 1
    fi
    success "All pipelines applied successfully"
}

# Verify Tekton resources
verify_tekton_resources() {
    echo "Verifying Tekton resources..."
    
    # Check Tasks with tkn
    echo "Installed Tasks:"
    if ! tkn task list -n aap; then
        failure "Failed to list Tekton tasks"
        return 1
    fi
    success "Tasks verified"

    # Check Pipelines with tkn
    echo "Installed Pipelines:"
    if ! tkn pipeline list -n aap; then
        failure "Failed to list Tekton pipelines"
        return 1
    fi
    success "Pipelines verified"

    # Verify required resources exist
    if ! oc get task build-execution-environment -n aap &>/dev/null; then
        failure "Required task 'build-execution-environment' not found"
        return 1
    fi
    if ! oc get pipeline build-deploy-ee-pipeline -n aap &>/dev/null; then
        failure "Required pipeline 'build-deploy-ee-pipeline' not found"
        return 1
    fi
    success "Required Tekton resources verified"
}

# Main execution
main() {
    echo "Starting Tekton pipeline setup at $(timestamp)"
    
    # Run all steps in sequence
    validate_prerequisites || exit 1
    setup_namespace || exit 1
    setup_service_account || exit 1
    apply_tasks || exit 1
    apply_pipelines || exit 1
    verify_tekton_resources || exit 1

    success "Tekton pipeline setup completed successfully"
    echo "You can now use 'run_tekton_pipeline.sh' to execute pipelines"
}

# Run main function
main 