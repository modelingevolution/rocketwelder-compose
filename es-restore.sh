#!/bin/bash

# EventStore Restore Script (Improved)
# Usage: ./es-restore.sh backup-20250613-020000.tar.gz

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_BASE="/var/docker/data/backups"
DATA_DIR="/var/docker/data/eventstore/data"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
LOG_FILE="/var/docker/data/maintenance.log"

# Global variables
TEMP_EXTRACT_DIR=""
EXTRACTED_BACKUP_DIR=""
BACKUP_DATA_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] RESTORE: $1"
    echo -e "${GREEN}${message}${NC}" >&2
    echo "$message" >> "$LOG_FILE"
}

warn() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] RESTORE WARNING: $1"
    echo -e "${YELLOW}${message}${NC}" >&2
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] RESTORE ERROR: $1"
    echo -e "${RED}${message}${NC}" >&2
    echo "$message" >> "$LOG_FILE"
    exit 1
}

# Cleanup function
cleanup_temp_files() {
    if [ -n "$TEMP_EXTRACT_DIR" ] && [ -d "$TEMP_EXTRACT_DIR" ]; then
        log "Cleaning up temporary extraction directory"
        rm -rf "$TEMP_EXTRACT_DIR"
    fi
    
    # Clean up any .bak directories created during this restore session
    if [ -n "$BACKUP_DATA_DIR" ] && [ -d "$BACKUP_DATA_DIR" ]; then
        log "Cleaning up backup data directory: $(basename "$BACKUP_DATA_DIR")"
        rm -rf "$BACKUP_DATA_DIR"
    fi
}

# Trap to ensure cleanup
trap cleanup_temp_files EXIT

# Clean up old .bak directories from previous failed restores
cleanup_old_backups() {
    local eventstore_dir
    eventstore_dir=$(dirname "$DATA_DIR")
    
    # Find .bak directories older than 24 hours
    local old_bak_dirs
    old_bak_dirs=$(find "$eventstore_dir" -maxdepth 1 -name "data.bak.*" -type d -mtime +1 2>/dev/null || true)
    
    if [ -n "$old_bak_dirs" ]; then
        log "Found old backup directories from previous restores:"
        echo "$old_bak_dirs" | while read -r bak_dir; do
            if [ -n "$bak_dir" ]; then
                log "Removing old backup: $(basename "$bak_dir")"
                rm -rf "$bak_dir"
            fi
        done
    fi
}

# Show usage
show_usage() {
    cat << EOF
EventStore Restore Script

USAGE:
    $0 <backup-file>

EXAMPLE:
    $0 backup-20250613-020000.tar.gz

DESCRIPTION:
    Restores EventStore from a backup file. The backup file should be
    located in $BACKUP_BASE/

BACKUP FILES AVAILABLE:
EOF
    if ls "$BACKUP_BASE"/backup-*.tar.gz >/dev/null 2>&1; then
        ls -1 "$BACKUP_BASE"/backup-*.tar.gz | xargs -I {} basename {}
    else
        echo "    No backup files found" >&2
    fi
}

# Validate inputs
validate_inputs() {
    if [ $# -eq 0 ]; then
        error "No backup file specified"
    fi
    
    local backup_file="$1"
    
    # Check if backup file has correct format
    if [[ ! "$backup_file" =~ ^backup-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]]; then
        error "Backup file must be in format: backup-YYYYMMDD-HHMMSS.tar.gz"
    fi
    
    # Check if backup file exists
    if [ ! -f "$BACKUP_BASE/$backup_file" ]; then
        error "Backup file not found: $BACKUP_BASE/$backup_file"
    fi
    
    # Check if backup file is readable and not empty
    if [ ! -r "$BACKUP_BASE/$backup_file" ] || [ ! -s "$BACKUP_BASE/$backup_file" ]; then
        error "Backup file is not readable or is empty: $backup_file"
    fi
    
    log "Backup file validation passed: $backup_file"
}

# Check if EventStore is running
check_eventstore_status() {
    if docker compose -f "$COMPOSE_FILE" ps eventstore.db | grep -q "Up"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Stop EventStore safely
stop_eventstore() {
    log "Stopping EventStore..."
    
    if check_eventstore_status; then
        if ! docker compose -f "$COMPOSE_FILE" stop eventstore.db; then
            error "Failed to stop EventStore"
        fi
        
        # Wait for complete shutdown
        local timeout=30
        while [ $timeout -gt 0 ] && check_eventstore_status; do
            sleep 1
            ((timeout--))
        done
        
        if check_eventstore_status; then
            warn "EventStore did not stop gracefully, forcing stop"
            docker compose -f "$COMPOSE_FILE" kill eventstore.db
        fi
        
        log "EventStore stopped successfully"
    else
        log "EventStore was not running"
    fi
}

# Clear existing data
clear_existing_data() {
    log "Clearing existing EventStore data..."
    
    if [ ! -d "$DATA_DIR" ]; then
        log "Data directory doesn't exist, creating: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    else
        # Backup current data just in case (to a .bak directory)
        if [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
            BACKUP_DATA_DIR="$DATA_DIR/../data.bak.$(date +%Y%m%d-%H%M%S)"
            log "Backing up existing data to: $BACKUP_DATA_DIR"
            mv "$DATA_DIR" "$BACKUP_DATA_DIR"
            mkdir -p "$DATA_DIR"
        fi
    fi
    
    log "Data directory cleared"
}

# Extract backup
extract_backup() {
    local backup_file="$1"
    local backup_path="$BACKUP_BASE/$backup_file"
    
    log "Extracting backup: $backup_file"
    
    # Create temporary extraction directory
    TEMP_EXTRACT_DIR="$BACKUP_BASE/.restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$TEMP_EXTRACT_DIR"
    
    # Extract backup
    if ! tar -xzf "$backup_path" -C "$TEMP_EXTRACT_DIR"; then
        error "Failed to extract backup file: $backup_file"
    fi
    
    # Get the extracted directory name
    local backup_dir_name
    backup_dir_name=$(basename "$backup_file" .tar.gz)
    local extracted_dir="$TEMP_EXTRACT_DIR/$backup_dir_name"
    
    # Verify extraction
    if [ ! -d "$extracted_dir" ]; then
        error "Extracted backup directory not found: $extracted_dir"
    fi
    
    if [ ! "$(ls -A "$extracted_dir" 2>/dev/null)" ]; then
        error "Extracted backup directory is empty"
    fi
    
    log "Backup extracted successfully to: $extracted_dir"
    
    # Store the path in a global variable instead of echo
    EXTRACTED_BACKUP_DIR="$extracted_dir"
}

# Restore data files
restore_data_files() {
    local extracted_dir="$1"
    
    log "Copying backup data to EventStore data directory..."
    
    # Copy all files from backup to data directory
    if ! cp -r "$extracted_dir"/* "$DATA_DIR/"; then
        error "Failed to copy backup data to data directory"
    fi
    
    log "Data files copied successfully"
}

# Create truncate.chk from chaser.chk (Critical EventStore requirement)
create_truncate_checkpoint() {
    log "Creating truncate.chk from chaser.chk..."
    
    local chaser_file="$DATA_DIR/chaser.chk"
    local truncate_file="$DATA_DIR/truncate.chk"
    
    # Check if chaser.chk exists
    if [ ! -f "$chaser_file" ]; then
        error "Critical file missing: chaser.chk not found in backup"
    fi
    
    # Create truncate.chk from chaser.chk
    if ! cp "$chaser_file" "$truncate_file"; then
        error "Failed to create truncate.chk from chaser.chk"
    fi
    
    log "truncate.chk created successfully"
}

# Fix file permissions
fix_permissions() {
    log "Fixing file permissions..."
    
    # For EventStore running in Docker with user: root
    # We need to ensure files are owned by root and have correct permissions
    
    # Set ownership to root:root (EventStore container runs as root)
    chown -R root:root "$DATA_DIR"
    
    # Set proper file permissions for EventStore
    # EventStore needs read/write access to all files
    find "$DATA_DIR" -type f -exec chmod 644 {} \;
    find "$DATA_DIR" -type d -exec chmod 755 {} \;
    
    # EventStore checkpoint files need special permissions
    if ls "$DATA_DIR"/*.chk >/dev/null 2>&1; then
        chmod 644 "$DATA_DIR"/*.chk
    fi
    
    # Index directory needs proper permissions
    if [ -d "$DATA_DIR/index" ]; then
        chmod 755 "$DATA_DIR/index"
        find "$DATA_DIR/index" -type f -exec chmod 644 {} \;
        find "$DATA_DIR/index" -type d -exec chmod 755 {} \;
    fi
    
    log "Permissions fixed - all files owned by root:root with EventStore-compatible permissions"
}

# Start EventStore
start_eventstore() {
    log "Starting EventStore..."
    
    if ! docker compose -f "$COMPOSE_FILE" start eventstore.db; then
        error "Failed to start EventStore"
    fi
    
    log "EventStore start command executed"
}

# Verify EventStore health
verify_eventstore_health() {
    log "Waiting for EventStore to become healthy..."
    
    local timeout=60
    local healthy=false
    
    while [ $timeout -gt 0 ]; do
        if curl -sf http://localhost:2113/health/live >/dev/null 2>&1; then
            healthy=true
            break
        fi
        
        sleep 2
        ((timeout--))
        
        if [ $((timeout % 10)) -eq 0 ]; then
            log "Still waiting for EventStore... ($timeout seconds remaining)"
        fi
    done
    
    if [ "$healthy" = true ]; then
        log "EventStore is healthy and responding"
        
        # Additional verification - check if we can access basic stats
        if curl -sf http://localhost:2113/stats >/dev/null 2>&1; then
            log "EventStore stats endpoint accessible"
        else
            warn "EventStore health check passed but stats endpoint not accessible"
        fi
    else
        error "EventStore failed to become healthy within timeout period"
    fi
}

# Main restore function
main() {
    local backup_file="$1"
    
    log "Starting EventStore restore from: $backup_file"
    
    # Validation
    validate_inputs "$@"
    
    # Clean up any old .bak directories from previous failed restores
    cleanup_old_backups
    
    # Confirmation prompt
    echo -e "${YELLOW}WARNING: This will stop EventStore and replace all data!${NC}" >&2
    echo "Backup file: $backup_file" >&2
    echo "Backup size: $(du -h "$BACKUP_BASE/$backup_file" | cut -f1)" >&2
    echo "Current data will be backed up to .bak directory" >&2
    echo >&2
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Restore cancelled by user"
        exit 0
    fi
    
    # Restore process
    stop_eventstore
    clear_existing_data
    
    # Extract backup (sets EXTRACTED_BACKUP_DIR global variable)
    extract_backup "$backup_file"
    
    restore_data_files "$EXTRACTED_BACKUP_DIR"
    create_truncate_checkpoint
    fix_permissions
    start_eventstore
    verify_eventstore_health
    
    log "Restore completed successfully!"
    
    # Clean up the backup data directory on successful restore
    if [ -n "$BACKUP_DATA_DIR" ] && [ -d "$BACKUP_DATA_DIR" ]; then
        log "Removing backup of old data: $(basename "$BACKUP_DATA_DIR")"
        rm -rf "$BACKUP_DATA_DIR"
        BACKUP_DATA_DIR=""  # Clear the variable so cleanup doesn't try to remove it again
    fi
    
    echo -e "${GREEN}EventStore has been restored from backup: $backup_file${NC}" >&2
}

# Handle help requests
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"
