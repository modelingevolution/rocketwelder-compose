#!/bin/bash

# RocketWelder Backup Script for AutoUpdater Migration System
# This script invokes the existing es-backup-full.sh and supports --format=json
# On fresh installations (empty EventStore data), it returns success without creating backup

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/es-backup-full.sh"
EVENTSTORE_DATA_DIR="/var/docker/data/eventstore/data"
EVENTSTORE_LOGS_DIR="/var/docker/data/eventstore/logs"

# Check if EventStore has data to backup
check_eventstore_data() {
    # Check if data directory exists and has content
    if [ ! -d "$EVENTSTORE_DATA_DIR" ]; then
        return 1  # No data directory = fresh installation
    fi
    
    # Check if data directory has any files (excluding hidden files)
    if [ ! "$(ls -A "$EVENTSTORE_DATA_DIR" 2>/dev/null)" ]; then
        return 1  # Empty data directory = fresh installation
    fi
    
    # Check for actual EventStore database files (chunks, checkpoints, or index)
    if ! ls "$EVENTSTORE_DATA_DIR"/*.chk >/dev/null 2>&1 && \
       ! ls "$EVENTSTORE_DATA_DIR"/*.0* >/dev/null 2>&1 && \
       ! [ -d "$EVENTSTORE_DATA_DIR/index" ]; then
        return 1  # No EventStore files = fresh installation
    fi
    
    return 0  # Has data to backup
}

# Check if this is a fresh installation
if ! check_eventstore_data; then
    # Fresh installation - no data to backup
    if [ "$1" == "--format=json" ]; then
        echo "{\"file\": \"\"}"
    else
        echo "Fresh installation detected - no backup needed"
    fi
    exit 0
fi

# Check if backup script exists
if [ ! -f "$BACKUP_SCRIPT" ]; then
    if [ "$1" == "--format=json" ]; then
        echo "{\"success\": false, \"error\": \"Backup script not found: $BACKUP_SCRIPT\"}"
    else
        echo "ERROR: Backup script not found: $BACKUP_SCRIPT"
    fi
    exit 1
fi

# Execute the EventStore backup script
if "$BACKUP_SCRIPT"; then
    # Find the most recent backup file
    BACKUP_DIR="/var/docker/data/backups"
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1 || echo "")
    
    if [ -n "$LATEST_BACKUP" ]; then
        if [ "$1" == "--format=json" ]; then
            echo "{\"file\": \"$LATEST_BACKUP\"}"
        else
            echo "Backup created: $LATEST_BACKUP"
        fi
    else
        if [ "$1" == "--format=json" ]; then
            echo "{\"success\": false, \"error\": \"No backup file found after backup execution\"}"
        else
            echo "ERROR: No backup file found after backup execution"
        fi
        exit 1
    fi
else
    if [ "$1" == "--format=json" ]; then
        echo "{\"success\": false, \"error\": \"Backup script execution failed\"}"
    else
        echo "ERROR: Backup script execution failed"
    fi
    exit 1
fi