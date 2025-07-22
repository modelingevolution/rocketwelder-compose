#!/bin/bash

# RocketWelder Restore Script for AutoUpdater Migration System
# This script invokes the existing es-restore.sh and supports --file and --format=json parameters

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTORE_SCRIPT="$SCRIPT_DIR/es-restore.sh"

BACKUP_FILE=""
FORMAT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file=*)
            BACKUP_FILE="${1#*=}"
            shift
            ;;
        --file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --format=json)
            FORMAT="json"
            shift
            ;;
        --format)
            if [ "$2" = "json" ]; then
                FORMAT="json"
            fi
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Check if backup file was provided
if [ -z "$BACKUP_FILE" ]; then
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Backup file not specified. Use --file=path_to_backup\"}"
    else
        echo "ERROR: Backup file not specified. Use --file=path_to_backup"
    fi
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Backup file not found: $BACKUP_FILE\"}"
    else
        echo "ERROR: Backup file not found: $BACKUP_FILE"
    fi
    exit 1
fi

# Check if restore script exists
if [ ! -f "$RESTORE_SCRIPT" ]; then
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Restore script not found: $RESTORE_SCRIPT\"}"
    else
        echo "ERROR: Restore script not found: $RESTORE_SCRIPT"
    fi
    exit 1
fi

# Extract just the filename if full path was provided
BACKUP_FILENAME=$(basename "$BACKUP_FILE")

# Execute the EventStore restore script
if "$RESTORE_SCRIPT" "$BACKUP_FILENAME"; then
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": true}"
    else
        echo "Restore completed successfully"
    fi
else
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Restore script execution failed\"}"
    else
        echo "ERROR: Restore script execution failed"
    fi
    exit 1
fi