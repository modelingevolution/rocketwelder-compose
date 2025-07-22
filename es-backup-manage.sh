#!/bin/bash

# EventStore Backup Management Script
# Usage: ./es-backup-manage.sh [list|status|backup|restore|cleanup|help]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/var/docker/data"
BACKUP_DIR="/var/docker/data/backups"
EVENTSTORE_DATA_DIR="/var/docker/data/eventstore/data"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
LOG_FILE="/var/docker/data/maintenance.log"
RETENTION_DAYS=7

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

warn() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
}

error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${message}${NC}"
    echo "$message" >> "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}$1${NC}"
}

# Check if EventStore is running
check_eventstore_status() {
    if docker compose -f "$COMPOSE_FILE" ps eventstore.db | grep -q "Up"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Check if EventStore is healthy
check_eventstore_health() {
    if curl -sf http://localhost:2113/health/live >/dev/null 2>&1; then
        return 0  # Healthy
    else
        return 1  # Not healthy
    fi
}

# List all available backups
list_backups() {
    info "=== Available EventStore Backups ==="
    
    if [ ! -d "$BACKUP_DIR" ]; then
        warn "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi
    
    # Check if any backups exist
    if ! ls "$BACKUP_DIR"/backup-*.tar.gz >/dev/null 2>&1; then
        warn "No backups found in $BACKUP_DIR"
        return 0
    fi
    
    echo
    printf "%-25s %-10s %-20s\n" "BACKUP FILE" "SIZE" "DATE CREATED"
    printf "%-25s %-10s %-20s\n" "-----------" "----" "------------"
    
    for backup in "$BACKUP_DIR"/backup-*.tar.gz; do
        if [ -f "$backup" ]; then
            filename=$(basename "$backup")
            size=$(du -h "$backup" | cut -f1)
            date_created=$(stat -c %y "$backup" | cut -d'.' -f1)
            printf "%-25s %-10s %-20s\n" "$filename" "$size" "$date_created"
        fi
    done
    
    echo
    local backup_count=$(ls "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | wc -l)
    info "Total backups: $backup_count"
}

# Show backup status and disk usage
backup_status() {
    info "=== EventStore Backup Status ==="
    echo
    
    # EventStore service status
    if check_eventstore_status; then
        if check_eventstore_health; then
            echo -e "EventStore Status: ${GREEN}Running & Healthy${NC}"
        else
            echo -e "EventStore Status: ${YELLOW}Running but Unhealthy${NC}"
        fi
    else
        echo -e "EventStore Status: ${RED}Stopped${NC}"
    fi
    
    echo
    
    # Backup directory info
    if [ -d "$BACKUP_DIR" ]; then
        echo "Backup Directory: $BACKUP_DIR"
        
        # Total backup space usage
        local total_backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
        echo "Total Backup Size: $total_backup_size"
        
        # Number of backups
        local backup_count=$(ls "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | wc -l || echo "0")
        echo "Number of Backups: $backup_count"
        
        # Oldest and newest backup
        if [ "$backup_count" -gt 0 ]; then
            local oldest=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz | tail -1)
            local newest=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz | head -1)
            echo "Oldest Backup: $(basename "$oldest")"
            echo "Newest Backup: $(basename "$newest")"
        fi
    else
        warn "Backup directory does not exist: $BACKUP_DIR"
    fi
    
    echo
    
    # Disk space information
    info "=== Disk Space Usage ==="
    df -h "$BACKUP_DIR" 2>/dev/null || df -h /var/docker/data
    
    echo
    
    # EventStore data size
    if [ -d "$EVENTSTORE_DATA_DIR" ]; then
        local eventstore_size=$(du -sh "$EVENTSTORE_DATA_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "EventStore Data Size: $eventstore_size"
    fi
    
    echo
    
    # Retention policy info
    info "=== Backup Retention Policy ==="
    echo "Retention Period: $RETENTION_DAYS days"
    
    # Show backups that will be cleaned up
    local old_backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null | wc -l || echo "0")
    if [ "$old_backups" -gt 0 ]; then
        echo -e "Backups to cleanup: ${YELLOW}$old_backups files${NC}"
    else
        echo -e "Backups to cleanup: ${GREEN}None${NC}"
    fi
}

# Trigger manual backup
manual_backup() {
    info "=== Starting Manual EventStore Backup ==="
    
    # Check if EventStore is running
    if ! check_eventstore_status; then
        error "EventStore is not running. Cannot perform backup."
    fi
    
    # Check if backup script exists
    local backup_script="$SCRIPT_DIR/es-backup-full.sh"
    if [ ! -f "$backup_script" ]; then
        error "Backup script not found: $backup_script"
    fi
    
    if [ ! -x "$backup_script" ]; then
        error "Backup script is not executable: $backup_script"
    fi
    
    log "Executing manual backup..."
    
    # Execute backup script
    if "$backup_script"; then
        log "Manual backup completed successfully"
        echo
        info "Latest backup:"
        ls -lah "$BACKUP_DIR"/backup-*.tar.gz | tail -1
    else
        error "Manual backup failed"
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    info "=== Restoring EventStore from Backup ==="
    
    # Validate backup file
    if [ -z "$backup_file" ]; then
        error "Please specify a backup file to restore"
    fi
    
    # Check if backup file exists
    local full_backup_path="$BACKUP_DIR/$backup_file"
    if [ ! -f "$full_backup_path" ]; then
        error "Backup file not found: $full_backup_path"
    fi
    
    # Check if restore script exists
    local restore_script="$SCRIPT_DIR/es-restore.sh"
    if [ ! -f "$restore_script" ]; then
        error "Restore script not found: $restore_script"
    fi
    
    if [ ! -x "$restore_script" ]; then
        error "Restore script is not executable: $restore_script"
    fi
    
    # Confirmation prompt
    echo -e "${YELLOW}WARNING: This will stop EventStore and replace all data!${NC}"
    echo "Backup file: $backup_file"
    echo "Backup size: $(du -h "$full_backup_path" | cut -f1)"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        info "Restore cancelled by user"
        return 0
    fi
    
    log "Starting restore from backup: $backup_file"
    
    # Execute restore script
    if "$restore_script" "$backup_file"; then
        log "Restore completed successfully"
        
        # Wait a moment and check health
        sleep 5
        if check_eventstore_health; then
            echo -e "${GREEN}EventStore is running and healthy after restore${NC}"
        else
            warn "EventStore may not be fully ready yet. Check logs if issues persist."
        fi
    else
        error "Restore failed"
    fi
}

# Cleanup old backups
cleanup_backups() {
    info "=== Cleaning up Old Backups ==="
    
    if [ ! -d "$BACKUP_DIR" ]; then
        warn "Backup directory does not exist: $BACKUP_DIR"
        return 0
    fi
    
    # Find old backups
    local old_backups
    old_backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null || true)
    
    if [ -z "$old_backups" ]; then
        log "No old backups to clean up"
        return 0
    fi
    
    echo "Backups older than $RETENTION_DAYS days:"
    echo "$old_backups"
    echo
    
    local count=$(echo "$old_backups" | wc -l)
    read -p "Delete $count old backup(s)? (yes/no): " confirmation
    
    if [ "$confirmation" = "yes" ]; then
        echo "$old_backups" | while read -r backup; do
            if [ -n "$backup" ]; then
                log "Deleting old backup: $(basename "$backup")"
                rm -f "$backup"
            fi
        done
        log "Cleanup completed"
    else
        info "Cleanup cancelled by user"
    fi
}

# Show help
show_help() {
    cat << EOF
EventStore Backup Management Script

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    list                    List all available backups
    status                  Show backup status and disk usage
    backup                  Trigger manual backup
    restore <backup-file>   Restore from specified backup file
    cleanup                 Clean up old backups (older than $RETENTION_DAYS days)
    help                    Show this help message

EXAMPLES:
    $0 list
    $0 status
    $0 backup
    $0 restore backup-20250613-020000.tar.gz
    $0 cleanup

CONFIGURATION:
    Backup Directory: $BACKUP_DIR
    EventStore Data: $EVENTSTORE_DATA_DIR
    Retention Period: $RETENTION_DAYS days
    Log File: $LOG_FILE

EOF
}

# Main script logic
main() {
    # Ensure directories exist
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"
    
    case "${1:-help}" in
        list|ls)
            list_backups
            ;;
        status|info)
            backup_status
            ;;
        backup|manual)
            manual_backup
            ;;
        restore)
            if [ $# -lt 2 ]; then
                error "Please specify a backup file to restore. Use '$0 list' to see available backups."
            fi
            restore_backup "$2"
            ;;
        cleanup|clean)
            cleanup_backups
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
