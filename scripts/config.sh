#!/bin/bash

# Configuration for Firebase Hosting deployment

# Get project name from the directory of the main 'go.sh' script
_PROJECT_NAME=${_GO_SCRIPT_DIR:+"$(basename "$_GO_SCRIPT_DIR")"}
readonly JSON_CONFIG_FILE="$_GO_SCRIPT_DIR/config.json"

# Helper function to get GCP Project ID
get_project_id() {
    gcloud config get-value project 2>/dev/null || echo "(unset)"
}

# Global configuration variables
CFG_SSL_EMAIL=""
CFG_EXTERNAL_URL=""
CFG_LOCAL_HTTP_PORT="5000"
CFG_DEPLOYMENT_NAME="portfolio"
CFG_GCP_PROJECT_ID=""

# Load saved configuration
load_config() {
    if ! check_jq; then return 1; fi

    if [ -f "$JSON_CONFIG_FILE" ]; then
        CFG_SSL_EMAIL=$(jq -r '.ssl_email // ""' "$JSON_CONFIG_FILE")
        CFG_EXTERNAL_URL=$(jq -r '.external_url // ""' "$JSON_CONFIG_FILE")
        CFG_LOCAL_HTTP_PORT=$(jq -r '.local_http_port // "5000"' "$JSON_CONFIG_FILE")
        CFG_DEPLOYMENT_NAME=$(jq -r '.deployment_name // "portfolio"' "$JSON_CONFIG_FILE")
        CFG_GCP_PROJECT_ID=$(jq -r '.gcp_project_id // ""' "$JSON_CONFIG_FILE")
    fi
    
    # If project ID is empty, try to get it from gcloud
    if [ -z "$CFG_GCP_PROJECT_ID" ]; then
        CFG_GCP_PROJECT_ID=$(get_project_id)
        [ "$CFG_GCP_PROJECT_ID" == "(unset)" ] && CFG_GCP_PROJECT_ID=""
    fi
}

# Save configuration
save_config() {
    if ! check_jq; then return 1; fi

    local config_json
    config_json=$(jq -n \
        --arg email "$CFG_SSL_EMAIL" \
        --arg ext_url "$CFG_EXTERNAL_URL" \
        --arg local_port "$CFG_LOCAL_HTTP_PORT" \
        --arg name "$CFG_DEPLOYMENT_NAME" \
        --arg gcp_project "$CFG_GCP_PROJECT_ID" \
        '{ssl_email: $email, external_url: $ext_url, local_http_port: $local_port, deployment_name: $name, gcp_project_id: $gcp_project}')
    echo "$config_json" > "$JSON_CONFIG_FILE"
}

# Configuration for local deployment
configure_local_deployment() {
    read -p "Enter Local HTTP Port [$CFG_LOCAL_HTTP_PORT]: " local_port_input
    CFG_LOCAL_HTTP_PORT="${local_port_input:-$CFG_LOCAL_HTTP_PORT}"
    
    echo "Local deployment configured."
    save_config
}

# Configuration for remote deployment
configure_remote_deployment() {
    local main_script_dir="$1"
    
    # First, load the config to get deployment name
    load_config
    
    # Prompt for project reconfiguration if ID is already set
    if [ -n "$CFG_GCP_PROJECT_ID" ]; then
        read -p "Use current project ID '$CFG_GCP_PROJECT_ID'? (y/n) [default: y]: " use_current
        if [[ "${use_current:-y}" =~ ^[Nn]$ ]]; then
            export FORCE_RECONFIGURE_PROJECT=true
        fi
    fi

    # Ensure GCP configuration is set up (this now handles creation/finding)
    echo "Checking GCP configuration..."
    check_gcp || { echo "Error: GCP setup failed." >&2; return 1; }
    
    CFG_GCP_PROJECT_ID=$(get_project_id)
    echo "Using GCP project: $CFG_GCP_PROJECT_ID"
    
    read -p "Enter SSL email for Let's Encrypt [$CFG_SSL_EMAIL]: " ssl_email_input
    CFG_SSL_EMAIL="${ssl_email_input:-$CFG_SSL_EMAIL}"
    while [ -z "$CFG_SSL_EMAIL" ]; do
        echo "Error: SSL email cannot be empty for remote deployment."
        read -p "Enter SSL email: " CFG_SSL_EMAIL
    done
    
    read -p "Enter external URL/domain [$CFG_EXTERNAL_URL]: " ext_url_input
    CFG_EXTERNAL_URL="${ext_url_input:-$CFG_EXTERNAL_URL}"
    while [ -z "$CFG_EXTERNAL_URL" ]; do
        echo "Error: External URL cannot be empty."
        read -p "Enter external URL: " CFG_EXTERNAL_URL
    done
    
    save_config
    echo "Remote deployment configured."
}

# Main configuration function
configure_deployment() {
    local main_script_dir="$1"
    local deployment_type="$2"
    
    load_config
    
    case "$deployment_type" in
        "local")
            configure_local_deployment
            ;;
        "remote")
            configure_remote_deployment "$main_script_dir"
            ;;
        *)
            echo "Error: Invalid deployment type '$deployment_type'."
            return 1
            ;;
    esac
}

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi
