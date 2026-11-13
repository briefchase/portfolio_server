#!/bin/bash

# Helper function to get GCP Project ID
get_project_id() {
    gcloud config get-value project 2>/dev/null
}

# Function to find or create a GCP project
# Returns the project ID
ensure_project() {
    local target_name="$1"
    local timestamp=$(date +%s)
    
    echo "Searching for project with display name matching '$target_name'..." >&2
    
    # Try to find existing project by display Name (not ID)
    local existing_project=$(gcloud projects list --filter="name='$target_name'" --format="value(projectId)" --limit=1)
    
    if [ -n "$existing_project" ]; then
        echo "Found existing project: $existing_project" >&2
        echo "$existing_project"
        return 0
    fi
    
    echo "Project with display name '$target_name' not found. Creating a new one..." >&2
    local new_project_id="${target_name}-${timestamp}"
    
    # Create the project
    gcloud projects create "$new_project_id" --name="$target_name" --quiet >&2 || {
        echo "Error: Failed to create project '$new_project_id'." >&2
        return 1
    }
    
    echo "Created new project: $new_project_id" >&2
    echo "$new_project_id"
}

# Function to check and setup GCP SDK and environment
check_gcp() {
    if ! command -v gcloud &>/dev/null; then
        echo "Google Cloud SDK is not installed. Attempting installation."
        local gcloud_repo="deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main"
        local repo_file="/etc/apt/sources.list.d/google-cloud-sdk.list"
        
        if [ ! -f "$repo_file" ] || ! grep -qF "$gcloud_repo" "$repo_file"; then
            echo "$gcloud_repo" | sudo tee "$repo_file" > /dev/null || { echo "Error: Adding the GCloud repository failed." >&2; return 1; }
        fi
        
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - || { echo "Error: Adding the GCloud key failed." >&2; return 1; }
        sudo apt update && sudo apt install -y google-cloud-sdk google-cloud-sdk-app-engine-python google-cloud-sdk-app-engine-python-extras google-cloud-sdk-beta || { echo "Error: Installing the GCloud SDK and components failed." >&2; return 1; }
        echo "Google Cloud SDK and beta components were installed successfully."
    else
        echo "Google Cloud SDK installation was verified. Ensuring beta components are present..."
        if ! gcloud components list --filter="id:beta" --format="value(id)" | grep -q "beta"; then
            echo "GCloud beta components not found. Attempting installation..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y google-cloud-sdk-beta || echo "Warning: Could not install google-cloud-sdk-beta via apt. Trying gcloud components install..."
            fi
            gcloud components install beta --quiet || echo "Warning: Failed to install beta components. Some commands may fail."
        else
            echo "GCloud beta components verified."
        fi
    fi

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo "Google Cloud authentication is required."
        gcloud auth login --no-launch-browser || { echo "Error: GCloud login failed." >&2; return 1; }
        echo "Google Cloud authentication succeeded."
    else
        echo "Google Cloud authentication was verified."
    fi

    local project_id=$(get_project_id)
    if [ -z "$project_id" ] || [ "$project_id" = "(unset)" ] || [ -n "$FORCE_RECONFIGURE_PROJECT" ]; then
        echo "Selecting or creating GCP project..."
        local default_name="${CFG_DEPLOYMENT_NAME:-portfolio}"
        read -p "Enter project name or ID [$default_name]: " target_name
        target_name="${target_name:-$default_name}"
        
        project_id=$(ensure_project "$target_name") || return 1
        gcloud config set project "$project_id" || { echo "Error: Setting the project failed." >&2; return 1; }
        echo "The GCP project was set to: $project_id."
    else
        echo "The GCP project is configured: $project_id."
    fi

    # Check billing status (Warning only)
    local billing_status=$(gcloud billing projects describe "$project_id" --format="get(billingEnabled)" 2>/dev/null)
    if [ "$billing_status" != "True" ]; then
        echo "--------------------------------------------------"
        echo "WARNING: No billing account is linked to project $project_id."
        echo "You can still deploy to the Firebase Free (Spark) tier."
        echo "If you exceed free limits, deployment will fail."
        echo "Visit https://console.cloud.google.com/billing to link an account."
        echo "--------------------------------------------------"
    else
        echo "Billing was verified for project $project_id."
    fi

    # Enable necessary APIs for Firebase deployment
    echo "Enabling required Google Cloud services..."
    gcloud services enable firebasehosting.googleapis.com cloudresourcemanager.googleapis.com --project="$project_id" || { echo "Error: Enabling one or more required GCP services failed." >&2; return 1; }
    echo "Required Google Cloud services were enabled."
}

# Function to check and install Node.js
check_nodejs() {
    if command -v node &>/dev/null; then
        echo "Node.js installation was verified."
        check_npm || return 1
        return 0
    fi
    echo "Node.js is not installed. Attempting installation."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || { echo "Error: Failed to add Node.js repository." >&2; return 1; }
    sudo apt-get install -y nodejs || { echo "Error: Failed to install Node.js." >&2; return 1; }
    echo "Node.js was installed successfully."
    check_npm || return 1
}

# Function to check and install npm
check_npm() {
    if command -v npm &>/dev/null; then
        echo "npm installation was verified."
        return 0
    fi
    echo "npm is not installed. Attempting installation..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y npm || { echo "Error: Failed to install npm via apt." >&2; return 1; }
    else
        echo "Error: npm is missing and apt-get was not found. Please install npm manually." >&2
        return 1
    fi
    if command -v npm &>/dev/null; then
        echo "npm was installed successfully."
        return 0
    else
        echo "Error: npm installation failed." >&2
        return 1
    fi
}

# Function to check and install Firebase CLI
check_firebase_cli() {
    if command -v firebase &>/dev/null; then
        echo "Firebase CLI installation was verified."
        return 0
    fi
    echo "Firebase CLI not found. Attempting clean installation..."
    sudo rm -rf /usr/lib/node_modules/firebase-tools /usr/lib/node_modules/.firebase-tools* 2>/dev/null
    sudo npm install -g firebase-tools || { echo "Error: Firebase CLI installation failed." >&2; return 1; }
    if command -v firebase &>/dev/null; then
        echo "Firebase CLI was installed successfully."
        return 0
    fi
    echo "Error: Firebase CLI was installed but still cannot be found in PATH." >&2
    return 1
}

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Attempting to install..."
    if command -v sudo &> /dev/null && command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v sudo &> /dev/null && command -v yum &> /dev/null; then
        sudo yum install -y jq
    elif command -v sudo &> /dev/null && command -v dnf &> /dev/null; then
        sudo dnf install -y jq
    else
        echo "Error: Could not install jq automatically. Please install it manually using your system's package manager." >&2
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: jq installation failed. Please install it manually." >&2
        return 1
    fi
    echo "jq has been successfully installed."
fi

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi
