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
BACKUP_DIR="/var/docker/data/backups"

# Parse arguments
VERSION=""
FORMAT=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        list)
            COMMAND="list"
            shift
            ;;
        --version=*)
            VERSION="${1#*=}"
            shift
            ;;
        --version)
            VERSION="$2"
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

# Handle list command
if [ "$COMMAND" == "list" ]; then
    if [ ! -d "$BACKUP_DIR" ]; then
        if [ "$FORMAT" == "json" ]; then
            echo '{"backups": []}'
        else
            echo "No backups found"
        fi
        exit 0
    fi

    # Find all backup files
    BACKUPS=()

    while IFS= read -r backup_file; do
        if [ -f "$backup_file" ]; then
            filename=$(basename "$backup_file")
            size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo "0")

            # Try to extract version from metadata file
            version="unknown"
            version_file="${backup_file}.version"
            if [ -f "$version_file" ]; then
                version=$(cat "$version_file")
            fi

            # Format size
            if [ $size_bytes -lt 1024 ]; then
                size="${size_bytes} B"
            elif [ $size_bytes -lt 1048576 ]; then
                size="$(( size_bytes / 1024 )) KB"
            elif [ $size_bytes -lt 1073741824 ]; then
                size="$(( size_bytes / 1048576 )) MB"
            else
                size="$(( size_bytes / 1073741824 )) GB"
            fi

            BACKUPS+=("{\"filename\": \"$filename\", \"version\": \"$version\", \"size\": \"$size\", \"size_bytes\": $size_bytes, \"full_path\": \"$backup_file\"}")
        fi
    done < <(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [ "$FORMAT" == "json" ]; then
        # Build JSON array
        backup_list=$(IFS=,; echo "${BACKUPS[*]}")
        echo "{\"backups\": [$backup_list]}"
    else
        echo "Found ${#BACKUPS[@]} backup(s)"
        for backup in "${BACKUPS[@]}"; do
            echo "$backup"
        done
    fi
    exit 0
fi

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
    if [ "$FORMAT" == "json" ]; then
        echo "{\"file\": \"\"}"
    else
        echo "Fresh installation detected - no backup needed"
    fi
    exit 0
fi

# Check if backup script exists
if [ ! -f "$BACKUP_SCRIPT" ]; then
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Backup script not found: $BACKUP_SCRIPT\"}"
    else
        echo "ERROR: Backup script not found: $BACKUP_SCRIPT"
    fi
    exit 1
fi

# Execute the EventStore backup script
if "$BACKUP_SCRIPT"; then
    # Find the most recent backup file
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1 || echo "")

    if [ -n "$LATEST_BACKUP" ]; then
        # Save version metadata if provided
        if [ -n "$VERSION" ]; then
            echo "$VERSION" > "${LATEST_BACKUP}.version"
        fi

        if [ "$FORMAT" == "json" ]; then
            echo "{\"file\": \"$LATEST_BACKUP\"}"
        else
            echo "Backup created: $LATEST_BACKUP"
            if [ -n "$VERSION" ]; then
                echo "Version: $VERSION"
            fi
        fi
    else
        if [ "$FORMAT" == "json" ]; then
            echo "{\"success\": false, \"error\": \"No backup file found after backup execution\"}"
        else
            echo "ERROR: No backup file found after backup execution"
        fi
        exit 1
    fi
else
    if [ "$FORMAT" == "json" ]; then
        echo "{\"success\": false, \"error\": \"Backup script execution failed\"}"
    else
        echo "ERROR: Backup script execution failed"
    fi
    exit 1
fi
