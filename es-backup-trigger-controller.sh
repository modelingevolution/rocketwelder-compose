#!/bin/bash

# EventStore Backup Trigger Controller
# Runs every 30 minutes to check if today's backup exists
# If not, triggers backup creation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/docker/data/backups"
LOG_FILE="/var/docker/data/maintenance.log"
BACKUP_SCRIPT="$SCRIPT_DIR/es-backup-full.sh"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Get today's date for backup file matching
TODAY=$(date +%Y%m%d)

# Logging function
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] CONTROLLER: $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Check if EventStore is running and healthy
check_eventstore_health() {
    # Check if container is running
    if ! docker compose -f "$COMPOSE_FILE" ps eventstore.db | grep -q "Up"; then
        return 1
    fi
    
    # Check if EventStore responds to health check
    if ! curl -sf http://localhost:2113/health/live >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Check if backup for today already exists
check_todays_backup() {
    if [ ! -d "$BACKUP_DIR" ]; then
        return 1  # No backup directory, definitely no backup
    fi
    
    # Look for backup file with today's date
    if ls "$BACKUP_DIR"/backup-${TODAY}-*.tar.gz >/dev/null 2>&1; then
        return 0  # Today's backup exists
    else
        return 1  # No backup for today
    fi
}

# Check if backup is currently running
check_backup_running() {
    # Check for lock file or running backup process
    if [ -f "/tmp/eventstore-backup.lock" ]; then
        return 0  # Backup is running
    fi
    
    # Check if backup script is currently running
    if pgrep -f "es-backup-full.sh" >/dev/null 2>&1; then
        return 0  # Backup script is running
    fi
    
    return 1  # No backup running
}

# Get info about existing backups
get_backup_info() {
    local latest_backup=""
    local backup_count=0
    
    if [ -d "$BACKUP_DIR" ]; then
        # Count total backups
        backup_count=$(ls "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | wc -l || echo "0")
        
        # Get latest backup
        if [ "$backup_count" -gt 0 ]; then
            latest_backup=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "none")
        fi
    fi
    
    echo "total_backups:$backup_count,latest:$latest_backup"
}

# Trigger backup if needed
trigger_backup() {
    log "No backup found for today ($TODAY), triggering backup..."
    
    # Check if backup script exists and is executable
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log "ERROR: Backup script not found: $BACKUP_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$BACKUP_SCRIPT" ]; then
        log "ERROR: Backup script is not executable: $BACKUP_SCRIPT"
        return 1
    fi
    
    # Execute backup script
    if "$BACKUP_SCRIPT" >> "$LOG_FILE" 2>&1; then
        log "Backup triggered successfully"
        return 0
    else
        log "ERROR: Backup failed"
        return 1
    fi
}

# Main controller logic
main() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
    
    log "Backup controller check started"
    
    # Check if EventStore is healthy
    if ! check_eventstore_health; then
        log "EventStore is not running or unhealthy, skipping backup check"
        return 0
    fi
    
    # Check if backup is currently running
    if check_backup_running; then
        log "Backup is already running, skipping"
        return 0
    fi
    
    # Get backup information
    backup_info=$(get_backup_info)
    total_backups=$(echo "$backup_info" | cut -d',' -f1 | cut -d':' -f2)
    latest_backup=$(echo "$backup_info" | cut -d',' -f2 | cut -d':' -f2)
    
    # Check if today's backup exists
    if check_todays_backup; then
        log "Today's backup already exists (Total: $total_backups, Latest: $latest_backup)"
        return 0
    else
        log "No backup for today found (Total: $total_backups, Latest: $latest_backup)"
        
        # Trigger backup
        if trigger_backup; then
            log "Backup controller completed successfully"
        else
            log "Backup controller failed"
            return 1
        fi
    fi
}

# Run main function
main "$@"
