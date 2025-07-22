#!/bin/bash
# Rollback script for version 1.0.0 - Initial RocketWelder deployment
# This script undoes changes made by up-1.0.0.sh

set -e

echo "Running rollback script for version 1.0.0..."

# Remove log rotation configuration
if [ -f "/etc/logrotate.d/rocketwelder" ]; then
    echo "Removing RocketWelder log rotation configuration..."
    sudo rm -f /etc/logrotate.d/rocketwelder
fi

# Remove configuration directory if empty
if [ -d "/var/docker/data/app/config" ]; then
    if [ -z "$(ls -A /var/docker/data/app/config 2>/dev/null)" ]; then
        echo "Removing empty configuration directory..."
        sudo rmdir /var/docker/data/app/config
    else
        echo "Configuration directory not empty, leaving intact: /var/docker/data/app/config"
    fi
fi

# Remove empty directories (safe cleanup)
echo "Removing empty directories..."

# Function to safely remove empty directory
remove_if_empty() {
    local dir="$1"
    if [ -d "$dir" ]; then
        if [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Removing empty directory: $dir"
            sudo rmdir "$dir" 2>/dev/null || echo "Could not remove $dir (may have hidden files)"
        else
            echo "Directory not empty, leaving intact: $dir"
        fi
    fi
}

# Remove app directories if empty
remove_if_empty "/var/docker/data/app/logs"
remove_if_empty "/var/docker/data/app/models"
remove_if_empty "/var/docker/data/app"

# Remove EventStore directories if empty
remove_if_empty "/var/docker/data/eventstore/data"
remove_if_empty "/var/docker/data/eventstore/logs"
remove_if_empty "/var/docker/data/eventstore"

# Remove backup directory if empty
remove_if_empty "/var/docker/data/backups"

# Remove user data directories if empty
remove_if_empty "/var/data/rocketwelder/app/recordings"
remove_if_empty "/var/data/rocketwelder/app"
remove_if_empty "/var/data/rocketwelder"

# Try to remove parent docker data directory if completely empty
remove_if_empty "/var/docker/data"

# Note: We don't uninstall system packages (htop, iotop) during rollback
# as they may be used by other applications
echo "Note: System packages (htop, iotop) were not removed for safety"
echo "Rollback script 1.0.0 completed successfully"