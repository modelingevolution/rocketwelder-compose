#!/bin/bash

# RocketWelder Compose Release Script
# Manages version tagging for the docker-compose repository

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
FORMAT="text"  # Default format: text or json

# Functions
print_usage() {
    echo -e "${BLUE}RocketWelder Compose Release Script${NC}"
    echo
    echo "Usage: ./release.sh [VERSION] [OPTIONS]"
    echo
    echo "Arguments:"
    echo "  VERSION     Semantic version (e.g., 1.2.3, 2.0.0)"
    echo "              If not provided, uses version from rocketwelder.version file"
    echo "              If that version already exists, adds suffix (e.g., 1.2.3-1)"
    echo
    echo "Options:"
    echo "  -m, --message TEXT    Commit message (default: 'Release vX.Y.Z')"
    echo "  -p, --patch           Auto-increment patch version from latest tag"
    echo "  -n, --minor           Auto-increment minor version from latest tag"
    echo "  -M, --major           Auto-increment major version from latest tag"
    echo "  --no-image-update     Skip updating rocketwelder image version"
    echo "  --dry-run             Show what would be done without executing"
    echo "  --format=json         Output result as JSON (for scripting)"
    echo "  -h, --help            Show this help message"
    echo
    echo "Examples:"
    echo "  ./release.sh                                 # Use rocketwelder.version (default)"
    echo "  ./release.sh 1.2.3                          # Release specific version"
    echo "  ./release.sh 1.2.3 -m \"Added new features\"  # With custom message"
    echo "  ./release.sh --minor -m \"New components\"    # Auto-increment minor from latest tag"
    echo "  ./release.sh --patch                        # Auto-increment patch from latest tag"
    echo "  ./release.sh --no-image-update              # Skip image version update"
    echo "  ./release.sh --dry-run                      # Preview release"
    echo "  ./release.sh --patch -m \"Fixes\" --format=json  # JSON output for scripting"
    echo
    echo "JSON OUTPUT FORMAT:"
    echo "  {\"success\": true, \"version\": \"1.2.3\"}"
    echo "  {\"success\": false, \"error\": \"error message\"}"
}

print_error() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${RED}Error: $1${NC}" >&2
    else
        echo -e "${RED}Error: $1${NC}" >&2
    fi
}

print_warning() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${YELLOW}Warning: $1${NC}" >&2
    else
        echo -e "${YELLOW}Warning: $1${NC}"
    fi
}

print_success() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${GREEN}$1${NC}" >&2
    else
        echo -e "${GREEN}$1${NC}"
    fi
}

print_info() {
    if [ "$FORMAT" = "json" ]; then
        echo -e "${BLUE}$1${NC}" >&2
    else
        echo -e "${BLUE}$1${NC}"
    fi
}

# Validate semantic version format (with optional suffix)
validate_version() {
    if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]; then
        print_error "Invalid version format: $1. Expected format: X.Y.Z or X.Y.Z-N (e.g., 1.2.3 or 1.2.3-1)"
        return 1
    fi
}

# Get the latest version tag for this repository
get_latest_version() {
    git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | sed 's/^v//' || echo "0.0.0"
}

# Get rocketwelder version from rocketwelder.version file
get_rocketwelder_version() {
    if [[ -f "rocketwelder.version" ]]; then
        cat "rocketwelder.version" | tr -d '\n' | tr -d ' '
    else
        print_error "rocketwelder.version file not found"
        return 1
    fi
}

# Find available version with suffix if needed
find_available_version() {
    local base_version=$1
    local version=$base_version
    local suffix=1
    
    while git tag -l | grep -q "^v$version$"; do
        print_warning "Tag v$version already exists" >&2
        version="${base_version}-${suffix}"
        suffix=$((suffix + 1))
    done
    
    if [[ "$version" != "$base_version" ]]; then
        print_warning "Using version $version instead of $base_version" >&2
    fi
    
    echo "$version"
}

# Increment version
increment_version() {
    local version=$1
    local part=$2
    
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}
    
    case $part in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch"|*)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Check if working directory is clean (optional check)
check_working_directory() {
    if [[ -n $(git status --porcelain) ]]; then
        print_warning "Working directory has uncommitted changes:"
        git status --short
        return 0
    fi
}

# Update rocketwelder image version
update_image_version() {
    local skip_update=$1

    if [[ "$skip_update" == "true" ]]; then
        print_info "Skipping rocketwelder image version update (--no-image-update)"
        return 0
    fi

    print_info "Updating rocketwelder image version..."
    if [[ -f "./update-version.sh" ]]; then
        if [[ "$FORMAT" = "json" ]]; then
            # Use JSON format and capture result
            local result=$(./update-version.sh update --format=json)
            if echo "$result" | grep -q '"success": *true'; then
                print_success "✓ Updated rocketwelder image version"
            else
                print_error "update-version.sh failed"
                return 1
            fi
        else
            ./update-version.sh update
            print_success "✓ Updated rocketwelder image version"
        fi
    else
        print_error "update-version.sh not found"
        return 1
    fi
}

# Commit changes
commit_changes() {
    local version=$1
    local message=$2
    
    # Check if there are changes to commit
    if [[ -z $(git status --porcelain) ]]; then
        print_warning "No changes to commit"
        return 0
    fi
    
    print_info "Committing changes..."
    git add .
    
    if [[ -n "$message" ]]; then
        git commit -m "$message"
    else
        git commit -m "Release v$version"
    fi
    
    print_success "✓ Changes committed"
}

# Create and push tag
create_tag() {
    local version=$1
    local tag="v$version"
    
    if git tag -l | grep -q "^$tag$"; then
        print_error "Tag $tag already exists"
        return 1
    fi
    
    print_info "Creating tag: $tag"
    git tag "$tag"
    
    print_info "Pushing tag to origin..."
    git push origin "$tag"
    
    print_success "✅ Tag $tag created and pushed successfully"
}

# Main script logic
main() {
    local version=""
    local increment_type="patch"
    local message=""
    local dry_run=false
    local no_image_update=false
    local auto_increment_requested=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-image-update)
                no_image_update=true
                shift
                ;;
            --format=json)
                FORMAT="json"
                shift
                ;;
            -m|--message)
                message="$2"
                shift 2
                ;;
            -p|--patch)
                increment_type="patch"
                auto_increment_requested=true
                shift
                ;;
            -n|--minor)
                increment_type="minor"
                auto_increment_requested=true
                shift
                ;;
            -M|--major)
                increment_type="major"
                auto_increment_requested=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                if [[ -z "$version" ]]; then
                    version="$1"
                else
                    print_error "Too many arguments"
                    print_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # If no version specified, use rocketwelder version or auto-increment
    if [[ -z "$version" ]]; then
        if [[ "$auto_increment_requested" == true ]]; then
            # User explicitly requested auto-increment
            local latest_version=$(get_latest_version)
            version=$(increment_version "$latest_version" "$increment_type")
            print_info "Auto-incrementing $increment_type version: $latest_version → $version"
        else
            # Default behavior: use rocketwelder version
            local rocketwelder_version=$(get_rocketwelder_version) || exit 1
            version=$(find_available_version "$rocketwelder_version")
            print_info "Using RocketWelder version: $rocketwelder_version"
            if [[ "$version" != "$rocketwelder_version" ]]; then
                print_warning "RocketWelder version $rocketwelder_version already exists, using $version"
            fi
        fi
    fi
    
    # Validate version format
    validate_version "$version" || exit 1
    
    if [[ "$dry_run" == true ]]; then
        print_info "🔍 DRY RUN - Would perform the following actions:"
        print_info "1. Update rocketwelder image version: $([ "$no_image_update" == "true" ] && echo "SKIP" || echo "YES")"
        print_info "2. Commit changes with message: ${message:-"Release v$version"}"
        print_info "3. Push commit to origin"
        print_info "4. Create and push tag: v$version"
        exit 0
    fi
    
    print_info "🚀 Starting RocketWelder Compose release process..."
    print_info "Version: $version"
    if [[ -n "$message" ]]; then
        print_info "Message: $message"
    fi
    
    # Update rocketwelder image version (unless skipped)
    update_image_version "$no_image_update" || exit 1
    
    # Commit changes (this will add all changes including any uncommitted files)
    commit_changes "$version" "$message" || exit 1
    
    # Push commit to remote
    print_info "Pushing commit to origin..."
    git push origin || exit 1
    print_success "✓ Commit pushed to origin"
    
    # Create and push tag
    create_tag "$version" || exit 1

    if [[ "$FORMAT" = "json" ]]; then
        echo "{\"success\": true, \"version\": \"$version\"}"
    else
        print_success "🎉 Release $version completed successfully!"
        print_info ""
        print_info "Tag v$version has been created and pushed."
        print_info "View tags: https://github.com/modelingevolution/rocketwelder-compose/tags"
    fi
}

# Run main function
main "$@"