#!/bin/bash

# Script Output Conventions:
# - Use complete sentences for all output messages.
# - Report actions only *after* they have been successfully completed or failed, using the past tense.

#======================================
# Helper & Task Functions
#======================================
_GO_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source scripts in a way that makes functions available in current shell
source "$_GO_SCRIPT_DIR/scripts/install.sh" || { echo "Error: Failed to source install.sh" >&2; exit 1; }
source "$_GO_SCRIPT_DIR/scripts/config.sh" || { echo "Error: Failed to source config.sh" >&2; exit 1; }
source "$_GO_SCRIPT_DIR/scripts/deploy.sh" || { echo "Error: Failed to source deploy.sh" >&2; exit 1; }
# Ensure all required tools are installed before proceeding
check_all_dependencies || { echo "Error: Dependency check failed. Exiting." >&2; exit 1; }

#======================================
# Main Menu & Script Execution
#======================================

show_menu() {
    echo "--- Firebase Hosting Menu ---"
    echo " 1. Deploy Local (Emulator)"
    echo " 2. Deploy Remote (Firebase)"
    echo " 3. Nuke Menu"
    echo " 4. Exit"
    echo "-------------------------"
}

show_nuke_menu() {
    echo "--- Nuke Menu ---"
    echo "1. Nuke Local (Clean Public)"
    echo "2. Back to Main Menu"
    echo "-------------------"
}

# Main script execution loop
while true; do
    show_menu
    read -p "Enter choice [1-4]: " choice
    echo ""

    operation_failed=false
    deployment_type=""

    case $choice in
        1) # Deploy Local
           deployment_type="local"
           echo "Starting local Firebase deployment..."
           
           configure_deployment "$_GO_SCRIPT_DIR" "$deployment_type" || operation_failed=true
           
           if [ "$operation_failed" = false ]; then
               deploy "$deployment_type" "portfolio-local" || operation_failed=true
           fi
           ;;
        2) # Deploy Remote
           deployment_type="remote"
           echo "Starting remote Firebase deployment..."
           
           configure_deployment "$_GO_SCRIPT_DIR" "$deployment_type" || operation_failed=true
           
           if [ "$operation_failed" = false ]; then
               deploy "$deployment_type" "portfolio-remote" || operation_failed=true
           fi
           ;;
        3) # Nuke Menu
            while true; do
                show_nuke_menu
                read -p "Nuke Menu - Enter choice [1-2]: " nuke_choice
                echo ""
                case $nuke_choice in
                    1) # Nuke Local
                        echo "Cleaning public directory..."
                        rm -rf "$_GO_SCRIPT_DIR/public"/*
                        echo "Public directory cleaned."
                        break
                        ;;
                    2) # Back to Main Menu
                        echo "Returning to main menu..."
                        break
                        ;;
                    *)
                        echo "Invalid choice for Nuke Menu [1-2]." >&2
                        operation_failed=true
                        ;;
                esac
            done
            ;;
        4) # Exit
           echo "Exiting."
           exit 0
           ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4." >&2
            operation_failed=true
            ;;
    esac

    if [ "$operation_failed" = true ] && [[ "$choice" -ge 1 && "$choice" -le 3 ]]; then
      echo "-------------------------"
      echo "Operation ($choice) failed. See messages above for details." >&2
      echo "-------------------------"
    fi

    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
    clear
done
