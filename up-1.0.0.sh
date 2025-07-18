#!/bin/bash
# Migration script for version 1.0.0 - Initial RocketWelder deployment
# This script prepares the system for RocketWelder with all necessary setup

set -e

echo "Running initial RocketWelder migration script for version 1.0.0..."

# Create Docker data directories (system/config data)
echo "Creating Docker data directories..."
sudo mkdir -p /var/docker/data/app/
sudo rm -rf /var/docker/data/app/appsettings.runtime.json  
echo "{}" | sudo tee /var/docker/data/app/appsettings.runtime.json > /dev/null
sudo chmod 666 /var/docker/data/app/appsettings.runtime.json # Allow all users to read/write
sudo mkdir -p /var/docker/data/eventstore/{data,logs}
sudo mkdir -p /var/docker/data/backups

# Create user data directories on dedicated partition
echo "Creating user data directories..."
sudo mkdir -p /var/data/rocketwelder/app/recordings


# Install additional system dependencies
if command -v apt-get &> /dev/null; then
    echo "Installing monitoring tools..."
    sudo apt-get update
    sudo apt-get install -y htop iotop
    echo "Installed additional monitoring tools"
fi

# Set up log rotation for application logs
if [ ! -f "/etc/logrotate.d/rocketwelder" ]; then
    echo "Setting up log rotation..."
    sudo tee /etc/logrotate.d/rocketwelder > /dev/null << 'EOF'
/var/docker/data/app/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
}
EOF
    echo "Configured log rotation for RocketWelder"
fi

# Set proper permissions
echo "Setting permissions..."
sudo chown -R $USER:$USER /var/docker/data/app
sudo chown -R $USER:$USER /var/docker/data/app/appsettings.runtime.json

sudo chown -R 1000:1000 /var/docker/data/eventstore  # EventStore requires UID 1000
sudo chown -R $USER:$USER /var/docker/data/backups
sudo chown -R $USER:$USER /var/data/rocketwelder

# Check ARM64 NVIDIA drivers if applicable
if [ "$(uname -m)" = "aarch64" ] && [ -d "/usr/lib/aarch64-linux-gnu/gstreamer-1.0" ]; then
    echo "ARM64 system detected - checking NVIDIA driver status"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi
        echo "NVIDIA drivers are working correctly"
    else
        echo "Warning: NVIDIA drivers may need attention"
    fi
fi

# Clean up any old log files if they exist
if [ -d "/var/docker/data/app/logs" ]; then
    find /var/docker/data/app/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true
    echo "Cleaned up old log files (older than 30 days)"
fi

echo "Initial RocketWelder migration script 1.0.0 completed successfully"
