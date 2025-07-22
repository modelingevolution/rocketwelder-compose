#!/bin/bash

# EventStore Data & Logs Cleanup Script
# Usage: ./es-cleanup.sh [data|logs|all] [--backup] [--force] [--restart]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENTSTORE_BASE="/var/docker/data/eventstore"
DATA_DIR="$EVENTSTORE_BASE/data"
LOGS_DIR="$EVENTSTORE_BASE/logs"
BACKUP_BASE="/var/docker/data/backups"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
LOG_FILE="/var/docker/data/maintenance.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global options
BACKUP_BEFORE_CLEAN=false
FORCE_CLEAN=false
RESTART_AFTER=false
CLEAN_TARGET="all"

# Logging functions
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] CLEANUP: $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

warn() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] CLEANUP WARNING: $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] CLEANUP ERROR: $1"
    echo -e "${RED}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}$1${NC}"
}

# Show usage
show_usage() {
    cat << EOF
EventStore Data & Logs Cleanup Script

USAGE:
    $0 [TARGET] [OPTIONS]

TARGETS:
    data        Clean only EventStore data directory
    logs        Clean only EventStore logs directory  
    all         Clean both data and logs (default)

OPTIONS:
    --backup    Create backup before cleaning data
    --force     Skip confirmation prompts
    --restart   Restart EventStore after cleanup
    --help      Show this help message

EXAMPLES:
    $0 data --backup --restart          # Clean data with backup and restart
    $0 logs --force                     # Clean logs without confirmation
    $0 all --backup --force --restart   # Full clean with backup, no prompts, restart
    $0 --help                          # Show this help

DIRECTORIES:
    Data: $DATA_DIR
    Logs: $LOGS_DIR
    Backups: $BACKUP_BASE

WARNING:
    Cleaning data will permanently delete all EventStore events and state!
    Use --backup option to create a backup before cleaning data.

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            data|logs|all)
                CLEAN_TARGET="$1"
                shift
                ;;
            --backup)
                BACKUP_BEFORE_CLEAN=true
                shift
                ;;
            --force)
                FORCE_CLEAN=true
                shift
                ;;
            --restart)
                RESTART_AFTER=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
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
        return 0
    else
        log "EventStore was not running"
        return 1
    fi
}

# Start EventStore
start_eventstore() {
    log "Starting EventStore..."
    
    if ! docker compose -f "$COMPOSE_FILE" start eventstore.db; then
        error "Failed to start EventStore"
    fi
    
    log "EventStore started successfully"
}

# Create backup of data before cleaning
create_backup() {
    if [ ! -d "$DATA_DIR" ] || [ ! "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
        log "No data to backup - data directory is empty or doesn't exist"
        return 0
    fi
    
    log "Creating backup before cleanup..."
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="cleanup-backup-$timestamp"
    local backup_dir="$BACKUP_BASE/$backup_name"
    local backup_file="$BACKUP_BASE/$backup_name.tar.gz"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Copy data using same method as backup script
    log "Copying EventStore data for backup..."
    
    # Copy index checkpoints
    if [ -d "$DATA_DIR/index" ]; then
        rsync -aIR "$DATA_DIR/./index/**/*.chk" "$backup_dir/" 2>/dev/null || true
    fi
    
    # Copy other index files
    if [ -d "$DATA_DIR/index" ]; then
        rsync -aI --exclude '*.chk' "$DATA_DIR/index" "$backup_dir/" 2>/dev/null || true
    fi
    
    # Copy database checkpoints
    rsync -aI "$DATA_DIR"/*.chk "$backup_dir/" 2>/dev/null || true
    
    # Copy chunk files
    rsync -a "$DATA_DIR"/*.0* "$backup_dir/" 2>/dev/null || true
    
    # Create compressed backup
    log "Compressing backup..."
    tar -czf "$backup_file" -C "$BACKUP_BASE" "$backup_name"
    rm -rf "$backup_dir"
    
    local backup_size
    backup_size=$(du -h "$backup_file" | cut -f1)
    log "Backup created: $backup_name.tar.gz ($backup_size)"
}

# Get directory size and file count
get_directory_info() {
    local dir="$1"
    local name="$2"
    
    if [ -d "$dir" ]; then
        local size
        local files
        size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
        files=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
        echo "$name: $size ($files files)"
    else
        echo "$name: Directory doesn't exist"
    fi
}

# Show what will be cleaned
show_cleanup_summary() {
    info "=== Cleanup Summary ==="
    echo
    echo "Target: $CLEAN_TARGET"
    echo "Backup before clean: $([ "$BACKUP_BEFORE_CLEAN" = true ] && echo "Yes" || echo "No")"
    echo "Force mode: $([ "$FORCE_CLEAN" = true ] && echo "Yes" || echo "No")"
    echo "Restart after: $([ "$RESTART_AFTER" = true ] && echo "Yes" || echo "No")"
    echo
    
    case $CLEAN_TARGET in
        data)
            get_directory_info "$DATA_DIR" "EventStore Data"
            ;;
        logs)
            get_directory_info "$LOGS_DIR" "EventStore Logs"
            ;;
        all)
            get_directory_info "$DATA_DIR" "EventStore Data"
            get_directory_info "$LOGS_DIR" "EventStore Logs"
            ;;
    esac
    echo
}

# Confirm cleanup action
confirm_cleanup() {
    if [ "$FORCE_CLEAN" = true ]; then
        return 0
    fi
    
    show_cleanup_summary
    
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    
    case $CLEAN_TARGET in
        data)
            echo -e "${RED}This will permanently delete ALL EventStore data (events, streams, projections)!${NC}"
            ;;
        all)
            echo -e "${RED}This will permanently delete ALL EventStore data AND logs!${NC}"
            ;;
    esac
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Clean data directory
clean_data() {
    log "Cleaning EventStore data directory..."
    
    if [ -d "$DATA_DIR" ]; then
        # Remove all contents but keep the directory
        rm -rf "${DATA_DIR:?}"/*
        log "EventStore data directory cleaned"
    else
        log "Data directory doesn't exist, creating: $DATA_DIR"
        mkdir -p "$DATA_DIR"
    fi
    
    # Set proper permissions
    chown root:root "$DATA_DIR"
    chmod 755 "$DATA_DIR"
}

# Clean logs directory
clean_logs() {
    log "Cleaning EventStore logs directory..."
    
    if [ -d "$LOGS_DIR" ]; then
        # Remove all log files
        rm -rf "${LOGS_DIR:?}"/*
        log "EventStore logs directory cleaned"
    else
        log "Logs directory doesn't exist, creating: $LOGS_DIR"
        mkdir -p "$LOGS_DIR"
    fi
    
    # Set proper permissions
    chown root:root "$LOGS_DIR"
    chmod 755 "$LOGS_DIR"
}

# Main cleanup function
main() {
    log "Starting EventStore cleanup (target: $CLEAN_TARGET)"
    
    # Show what will be cleaned and get confirmation
    confirm_cleanup
    
    # Stop EventStore if running
    local was_running=false
    if stop_eventstore; then
        was_running=true
    fi
    
    # Create backup if requested and cleaning data
    if [ "$BACKUP_BEFORE_CLEAN" = true ] && [[ "$CLEAN_TARGET" =~ ^(data|all)$ ]]; then
        create_backup
    fi
    
    # Perform cleanup based on target
    case $CLEAN_TARGET in
        data)
            clean_data
            ;;
        logs)
            clean_logs
            ;;
        all)
            clean_data
            clean_logs
            ;;
    esac
    
    # Restart EventStore if requested or if it was running before
    if [ "$RESTART_AFTER" = true ] || [ "$was_running" = true ]; then
        start_eventstore
    fi
    
    log "Cleanup completed successfully"
    
    # Show final status
    echo
    info "=== Final Status ==="
    case $CLEAN_TARGET in
        data)
            get_directory_info "$DATA_DIR" "EventStore Data"
            ;;
        logs)
            get_directory_info "$LOGS_DIR" "EventStore Logs"
            ;;
        all)
            get_directory_info "$DATA_DIR" "EventStore Data"
            get_directory_info "$LOGS_DIR" "EventStore Logs"
            ;;
    esac
}

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Parse arguments
parse_arguments "$@"

# Run main function
main