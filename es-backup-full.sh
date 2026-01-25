#!/bin/bash

# EventStore Full Backup Script (Updated)
# Based on official EventStore backup procedure
# Uses atomic operations with temporary files

set -euo pipefail

# Configuration
DATA_DIR="/var/docker/data/eventstore/data"
BACKUP_BASE="/var/docker/data/backups"
RETENTION_DAYS=7
LOCK_FILE="/tmp/eventstore-backup.lock"

# Create timestamped backup names
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_BASE/backup-$TIMESTAMP"
TEMP_BACKUP_FILE="$BACKUP_BASE/.backup-$TIMESTAMP.tar.gz.tmp"
FINAL_BACKUP_FILE="$BACKUP_BASE/backup-$TIMESTAMP.tar.gz"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] BACKUP: $1" >&2
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    # Remove lock file
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
    
    # Remove temporary backup directory
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
    fi
    
    # Remove temporary tar file
    if [ -f "$TEMP_BACKUP_FILE" ]; then
        rm -f "$TEMP_BACKUP_FILE"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Check if backup is already running
check_not_running() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            error_exit "Backup is already running (PID: $lock_pid)"
        else
            log "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
}

# Create lock file
create_lock() {
    echo $$ > "$LOCK_FILE"
    log "Created lock file with PID $$"
}

# Check EventStore data directory exists
check_data_directory() {
    if [ ! -d "$DATA_DIR" ]; then
        error_exit "EventStore data directory not found: $DATA_DIR"
    fi
    
    # Check if there's actually data to backup
    if [ ! -d "$DATA_DIR/index" ] && ! ls "$DATA_DIR"/*.chk >/dev/null 2>&1; then
        error_exit "No EventStore data found in: $DATA_DIR"
    fi
}

# Perform the actual backup
perform_backup() {
    log "Starting EventStore backup to: $BACKUP_DIR"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Follow official EventStore backup order:
    
    # 1. Copy index checkpoints first
    log "Copying index checkpoints..."
    if [ -d "$DATA_DIR/index" ]; then
        rsync -aIR "$DATA_DIR/./index/**/*.chk" "$BACKUP_DIR/" 2>/dev/null || {
            log "Warning: No index checkpoint files found"
        }
    fi
    
    # 2. Copy other index files (excluding checkpoints)
    log "Copying index files..."
    if [ -d "$DATA_DIR/index" ]; then
        rsync -aI --exclude '*.chk' "$DATA_DIR/index" "$BACKUP_DIR/" 2>/dev/null || {
            log "Warning: No index files found"
        }
    fi
    
    # 3. Copy database checkpoints
    log "Copying database checkpoints..."
    rsync -aI "$DATA_DIR"/*.chk "$BACKUP_DIR/" 2>/dev/null || {
        log "Warning: No database checkpoint files found"
    }
    
    # 4. Copy chunk files
    log "Copying chunk files..."
    rsync -a "$DATA_DIR"/*.0* "$BACKUP_DIR/" 2>/dev/null || {
        log "Warning: No chunk files found"
    }
    
    # Verify backup directory has content
    if [ ! "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        error_exit "Backup directory is empty - no data was copied"
    fi
    
    log "Data copy completed successfully"
}

# Create compressed backup with atomic operation
create_compressed_backup() {
    log "Creating compressed backup (temporary file)..."
    
    # Create tar file to temporary location
    if ! tar -czf "$TEMP_BACKUP_FILE" -C "$BACKUP_BASE" "$(basename "$BACKUP_DIR")"; then
        error_exit "Failed to create compressed backup"
    fi
    
    # Verify tar file was created and has content
    if [ ! -f "$TEMP_BACKUP_FILE" ] || [ ! -s "$TEMP_BACKUP_FILE" ]; then
        error_exit "Compressed backup file is missing or empty"
    fi
    
    # Atomic rename to final location
    log "Moving backup to final location..."
    if ! mv "$TEMP_BACKUP_FILE" "$FINAL_BACKUP_FILE"; then
        error_exit "Failed to move backup to final location"
    fi
    
    # Verify final file
    if [ ! -f "$FINAL_BACKUP_FILE" ] || [ ! -s "$FINAL_BACKUP_FILE" ]; then
        error_exit "Final backup file is missing or empty"
    fi
    
    log "Compressed backup created successfully"
}

# Get backup size and statistics
get_backup_stats() {
    local backup_size
    local file_count
    
    if [ -f "$FINAL_BACKUP_FILE" ]; then
        backup_size=$(du -h "$FINAL_BACKUP_FILE" | cut -f1)
        file_count=$(tar -tzf "$FINAL_BACKUP_FILE" 2>/dev/null | wc -l || echo "unknown")

        log "Backup statistics: Size: $backup_size, Files: $file_count"
        echo "Size: $backup_size, Files: $file_count" >&2
    else
        error_exit "Cannot get backup statistics - file missing"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (older than $RETENTION_DAYS days)..."
    
    local deleted_count=0
    local old_backups
    
    # Find and delete old backups
    old_backups=$(find "$BACKUP_BASE" -name "backup-*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null || true)
    
    if [ -n "$old_backups" ]; then
        while IFS= read -r old_backup; do
            if [ -f "$old_backup" ]; then
                log "Deleting old backup: $(basename "$old_backup")"
                rm -f "$old_backup"
                ((++deleted_count))
            fi
        done <<< "$old_backups"
    fi
    
    if [ $deleted_count -gt 0 ]; then
        log "Deleted $deleted_count old backup(s)"
    else
        log "No old backups to delete"
    fi
}

# Main backup function
main() {
    log "EventStore backup started"
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_BASE"
    
    # Pre-flight checks
    check_not_running
    check_data_directory
    create_lock
    
    # Perform backup steps
    perform_backup
    create_compressed_backup
    
    # Remove temporary directory (final cleanup will happen in trap)
    rm -rf "$BACKUP_DIR"
    
    # Get statistics
    local stats
    stats=$(get_backup_stats)
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Success
    log "Backup completed successfully: backup-$TIMESTAMP.tar.gz ($stats)"
    
    # Remove lock file (will also be handled by trap)
    rm -f "$LOCK_FILE"
}

# Run main function
main "$@"
