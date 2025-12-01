#!/bin/bash

# RocketWelder Version Update Script
# Updates the version in rocketwelder.version file and docker-compose.yml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="rocketwelder.azurecr.io"
IMAGE_NAME="rocketwelder"
VERSION_FILE="$SCRIPT_DIR/rocketwelder.version"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
FORMAT="text"  # Default format: text or json

# Logging functions - redirect to stderr when JSON format is enabled
log_info() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${GREEN}[INFO]${NC} $1" >&2
    else
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_error() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    else
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

log_warn() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    else
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

show_help() {
    cat << EOF
RocketWelder Version Update Script

USAGE:
    ./update-version.sh [command] [options]

COMMANDS:
    check                   Show current version
    update                  Update to latest version from ACR
    set <version>           Set specific version (e.g., 2.1.0)
    list                    List available versions from ACR
    help                    Show this help message

OPTIONS:
    --format=json           Output result as JSON (for scripting)

EXAMPLES:
    ./update-version.sh check                # Show current version
    ./update-version.sh update               # Update to latest version
    ./update-version.sh set 2.1.0            # Set to specific version
    ./update-version.sh list                 # List available versions
    ./update-version.sh set 2.1.0 --format=json  # Set version with JSON output

JSON OUTPUT FORMAT:
    {"success": true, "version": "2.1.0"}
    {"success": false, "error": "error message"}

EOF
}

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" | tr -d '\n'
    else
        # Try to extract from docker-compose.yml
        if [ -f "$COMPOSE_FILE" ]; then
            grep -E "image:.*$IMAGE_NAME:" "$COMPOSE_FILE" | head -1 | sed "s/.*$IMAGE_NAME:\([^[:space:]]*\).*/\1/"
        else
            echo "unknown"
        fi
    fi
}

# Function to check if we have ACR credentials
check_acr_auth() {
    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Please run: az login"
        return 1
    fi
    
    if ! az acr repository show --name "${REGISTRY%%.*}" --repository "$IMAGE_NAME" &>/dev/null; then
        log_warn "Cannot access ACR. Trying with docker credentials..."
        # Try with docker if az fails
        if ! docker manifest inspect "$REGISTRY/$IMAGE_NAME:latest" &>/dev/null; then
            log_error "Cannot access ACR repository. Please ensure you're logged in:"
            echo "  az acr login --name ${REGISTRY%%.*}"
            echo "  OR"
            echo "  docker login $REGISTRY"
            return 1
        fi
    fi
    return 0
}

list_versions() {
    log_info "Fetching available versions from ACR..."
    
    if ! check_acr_auth; then
        return 1
    fi
    
    # Try Azure CLI first
    if az account show &>/dev/null; then
        versions=$(az acr repository show-tags --name "${REGISTRY%%.*}" --repository "$IMAGE_NAME" --orderby time_desc --output tsv 2>/dev/null | \
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
            sort -V -r | \
            head -20)
    else
        # Fallback: parse from docker manifest (limited functionality)
        log_warn "Using limited Docker manifest inspection. Install Azure CLI for full functionality."
        versions="latest"
    fi
    
    if [ -z "$versions" ]; then
        log_error "No versions found"
        return 1
    fi
    
    echo -e "${BLUE}Available versions:${NC}"
    echo "$versions" | while read -r version; do
        current=$(get_current_version)
        if [ "$version" = "$current" ]; then
            echo -e "  ${GREEN}→ $version (current)${NC}"
        else
            echo "    $version"
        fi
    done
}

get_latest_version() {
    log_info "Fetching latest version from ACR..." >&2
    
    if ! check_acr_auth; then
        exit 1
    fi
    
    local latest_version=""
    
    # Try Azure CLI first
    if az account show &>/dev/null; then
        latest_version=$(az acr repository show-tags --name "${REGISTRY%%.*}" --repository "$IMAGE_NAME" --orderby time_desc --output tsv 2>/dev/null | \
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
            sort -V | \
            tail -n1)
    fi
    
    if [ -z "$latest_version" ]; then
        log_error "Could not fetch latest version from ACR"
        exit 1
    fi
    
    echo "$latest_version"
}

update_version() {
    local new_version="$1"

    log_info "Updating RocketWelder version to $new_version"

    # Validate version format
    if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: $new_version. Expected format: X.Y.Z (e.g., 2.1.0)"
        return 1
    fi

    # Update the version file
    echo "$new_version" > "$VERSION_FILE"
    log_info "✓ Updated rocketwelder.version to $new_version"

    # Update docker-compose.yml
    if [ -f "$COMPOSE_FILE" ]; then
        # Create backup
        cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak"

        # Update the image version
        sed -i "s|image: $REGISTRY/$IMAGE_NAME:[^[:space:]]*|image: $REGISTRY/$IMAGE_NAME:$new_version|g" "$COMPOSE_FILE"
        log_info "✓ Updated docker-compose.yml image to $REGISTRY/$IMAGE_NAME:$new_version"

        # Also update architecture-specific compose files if they exist
        for arch_file in "$SCRIPT_DIR/docker-compose.x64.yml" "$SCRIPT_DIR/docker-compose.arm64.yml"; do
            if [ -f "$arch_file" ]; then
                sed -i "s|image: $REGISTRY/$IMAGE_NAME:[^[:space:]]*|image: $REGISTRY/$IMAGE_NAME:$new_version|g" "$arch_file"
                log_info "✓ Updated $(basename "$arch_file")"
            fi
        done
    fi

    if [ "$FORMAT" != "json" ]; then
        log_info "Version update completed!"
        echo
        echo "To apply the changes, run:"
        echo "  docker-compose pull"
        echo "  docker-compose up -d"
    fi
}

# Parse options first
COMMAND=""
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --format=json)
            FORMAT="json"
            ;;
        --*)
            log_error "Unknown option: $arg"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$arg"
            elif [ -z "$VERSION_ARG" ]; then
                VERSION_ARG="$arg"
            fi
            ;;
    esac
done

# Main script logic
if [ -z "$COMMAND" ]; then
    log_error "No command provided"
    show_help
    exit 1
fi

case "$COMMAND" in
    "check")
        current_version=$(get_current_version)
        if [ "$FORMAT" = "json" ]; then
            echo "{\"success\": true, \"version\": \"$current_version\"}"
        else
            log_info "Current version: $current_version"
        fi
        ;;
    "update")
        latest_version=$(get_latest_version)
        log_info "Latest version found: $latest_version"
        current_version=$(get_current_version)
        if [ "$latest_version" = "$current_version" ]; then
            log_info "Already at latest version: $latest_version"
            if [ "$FORMAT" = "json" ]; then
                echo "{\"success\": true, \"version\": \"$latest_version\", \"updated\": false}"
            fi
        else
            if update_version "$latest_version"; then
                if [ "$FORMAT" = "json" ]; then
                    echo "{\"success\": true, \"version\": \"$latest_version\", \"updated\": true}"
                fi
            else
                if [ "$FORMAT" = "json" ]; then
                    echo "{\"success\": false, \"error\": \"Failed to update version\"}"
                fi
                exit 1
            fi
        fi
        ;;
    "set")
        if [ -z "$VERSION_ARG" ]; then
            log_error "Please provide a version number"
            if [ "$FORMAT" != "json" ]; then
                echo "Usage: $0 set <version>"
            else
                echo "{\"success\": false, \"error\": \"Version number required\"}"
            fi
            exit 1
        fi
        if update_version "$VERSION_ARG"; then
            if [ "$FORMAT" = "json" ]; then
                echo "{\"success\": true, \"version\": \"$VERSION_ARG\"}"
            fi
        else
            if [ "$FORMAT" = "json" ]; then
                echo "{\"success\": false, \"error\": \"Failed to set version\"}"
            fi
            exit 1
        fi
        ;;
    "list")
        list_versions
        ;;
    "help")
        show_help
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac