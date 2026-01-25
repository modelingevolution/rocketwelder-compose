#!/bin/bash

# Hardware Auto-detection and Performance Monitor Configuration
# This script runs on the target machine to detect hardware and configure
# the Blazor Performance Monitor layout in appsettings.override.json
#
# Usage: sudo ./configure-perfmon.sh [--verbose]
#        sudo ./configure-perfmon.sh --help

set -e

# Try to source logging library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGGING_SH="${SCRIPT_DIR}/logging.sh"

if [ -f "$LOGGING_SH" ]; then
    source "$LOGGING_SH"
    init_logging "$@"
else
    # Fallback: define minimal logging functions
    log_info() { echo "[INFO] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# Configuration
APPSETTINGS_PATH="/var/docker/data/app/appsettings.runtime.json"

# Show help
if [ "$1" == "--help" ]; then
    cat <<EOF
Hardware Auto-detection and Performance Monitor Configuration

This script detects hardware on the local machine and configures the
Blazor Performance Monitor layout in appsettings.runtime.json.

Usage:
    sudo ./configure-perfmon.sh [--verbose]
    sudo ./configure-perfmon.sh --help

Options:
    --verbose, -v    Show detailed detection output
    --help           Show this help message

The script will detect:
    - CPU cores (including offline cores)
    - Network interfaces (primary + camera interfaces with MTU > 1500)
    - Disk devices (prioritizes /var/data mount, then first disk > 10GB)
    - GPU type (NVIDIA Jetson Tegra or standard NVIDIA)
    - Temperature sensors

Configuration is written to: $APPSETTINGS_PATH

EOF
    exit 0
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is not installed. Please install it first:"
    log_error "  sudo apt-get install -y jq"
    exit 1
fi

# Auto-detect hardware
autodetect_hardware() {
    log_info "=== Auto-detecting Hardware Configuration ===" >&2
    echo "" >&2

    # 1. CPU Detection
    log_info "Detecting CPU cores..." >&2
    local cpu_range=$(cat /sys/devices/system/cpu/present 2>/dev/null)
    local cpu_count

    if [[ $cpu_range =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local cpu_start=${BASH_REMATCH[1]}
        local cpu_end=${BASH_REMATCH[2]}
        cpu_count=$((cpu_end - cpu_start + 1))
    else
        cpu_count=$(nproc --all 2>/dev/null || echo "8")
    fi
    log_info "✓ Detected ${cpu_count} CPU cores" >&2

    # 2. Network Interface Detection
    log_info "Detecting network interfaces..." >&2
    local primary_interface=$(ip route show default | grep -oP 'dev \K\S+' | head -1 2>/dev/null)

    if [ -z "$primary_interface" ]; then
        primary_interface=$(ip -o link show | awk -F': ' '$2 !~ /^lo$/ && $3 ~ /UP/ {print $2; exit}' 2>/dev/null)
    fi

    if [ -z "$primary_interface" ]; then
        primary_interface="eth0"
    fi

    log_info "✓ Primary interface: ${primary_interface}" >&2

    # Detect camera interfaces (MTU > 1500, exclude lo and primary)
    local camera_interface=$(ip -o link show | awk '{
        iface = $2
        gsub(/:/, "", iface)
        for (i = 1; i <= NF; i++) {
            if ($i == "mtu" && $(i+1) > 1500) {
                print iface
            }
        }
    }' | grep -v "^lo$" | grep -v "^${primary_interface}$" | head -1 2>/dev/null)

    if [ -n "$camera_interface" ]; then
        log_info "✓ Camera interface detected: ${camera_interface}" >&2
    else
        log_info "  No camera interfaces detected" >&2
    fi

    # 3. Disk Device Detection
    log_info "Detecting disk devices..." >&2
    local data_disk_source=$(findmnt -n -o SOURCE /var/data 2>/dev/null)
    local data_disk

    if [ -n "$data_disk_source" ]; then
        # Extract base device name
        data_disk=$(echo "$data_disk_source" | sed 's|/dev/||' | sed -E 's/[0-9]+$//' | sed 's/p$//')

        # Special handling for nvme and mmcblk devices
        if [[ $data_disk =~ ^nvme[0-9]+n[0-9]+p?$ ]]; then
            data_disk=$(echo "$data_disk" | sed 's/p$//')
        elif [[ $data_disk =~ ^mmcblk[0-9]+p?$ ]]; then
            data_disk=$(echo "$data_disk" | sed 's/p$//')
        fi

        log_info "✓ Data disk from /var/data mount: ${data_disk}" >&2
    else
        # Fallback: find first disk > 10GB
        data_disk=$(lsblk -b -d -n -o NAME,SIZE,TYPE | awk '$3 == "disk" && $2 > 10737418240 {print $1; exit}' 2>/dev/null)

        if [ -z "$data_disk" ]; then
            data_disk="sda"
        fi

        log_info "✓ Primary disk: ${data_disk}" >&2
    fi

    # 4. GPU Detection
    log_info "Detecting GPU..." >&2
    local gpu_type=""

    if grep -qi jetson /proc/device-tree/model 2>/dev/null || command -v jetson_clocks &>/dev/null; then
        gpu_type="NvTegra"
        log_info "✓ NVIDIA Jetson Tegra detected" >&2
    elif command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null 2>&1; then
        gpu_type="NvSmi"
        local gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
        log_info "✓ NVIDIA GPU detected (${gpu_count} GPU(s))" >&2
    else
        log_info "  No GPU detected" >&2
    fi

    # 5. Temperature Sensor Detection
    log_info "Detecting temperature sensors..." >&2
    local temp_count=$(ls -1d /sys/class/thermal/thermal_zone* 2>/dev/null | wc -l)

    if [ "$temp_count" -gt 0 ]; then
        log_info "✓ Detected ${temp_count} temperature sensors" >&2
    else
        log_info "  No temperature sensors detected" >&2
        temp_count=0
    fi

    echo "" >&2

    # Return detected values (pipe-separated to preserve empty values)
    echo "${cpu_count}|${primary_interface}|${camera_interface}|${data_disk}|${gpu_type}|${temp_count}"
}

# Generate MonitorSettings JSON configuration
generate_monitor_settings() {
    local cpu_count=$1
    local primary_interface=$2
    local camera_interface=$3
    local data_disk=$4
    local gpu_type=$5
    local temp_count=$6

    log_info "=== Generating Layout Configuration ===" >&2

    # Build NetworkInterface value (comma-separated if camera interface exists)
    local network_interfaces="${primary_interface}"
    if [ -n "$camera_interface" ]; then
        network_interfaces="${network_interfaces},${camera_interface}"
    fi

    # Build first row as JSON array
    local row1_items=("\"CPU/${cpu_count}\"")
    if [ "$temp_count" -gt 0 ]; then
        row1_items+=("\"Temperature/${temp_count}\"")
    fi
    row1_items+=("\"Docker\"" "\"ComputeLoad/3|col-span:2\"")

    # Build second row as JSON array
    local row2_items=("\"Network:${primary_interface}/2\"")
    if [ -n "$camera_interface" ]; then
        row2_items+=("\"Network:${camera_interface}/2\"")
    fi
    row2_items+=("\"Disk:${data_disk}/2\"")

    # Join arrays with commas
    local row1_json=$(IFS=,; echo "${row1_items[*]}")
    local row2_json=$(IFS=,; echo "${row2_items[*]}")

    # Build JSON - always include GpuCollectorType, default to "none" if no GPU detected
    local gpu_value="${gpu_type:-none}"
    local gpu_json="\"GpuCollectorType\": \"${gpu_value}\","

    # Generate JSON
    cat <<EOF
{
  "NetworkInterface": "${network_interfaces}",
  "DiskDevice": "${data_disk}",
  "CollectionIntervalMs": 500,
  "DataPointsToKeep": 120,
  ${gpu_json}
  "Layout": [
    [ ${row1_json} ],
    [ ${row2_json} ]
  ]
}
EOF

    log_info "✓ Layout configuration generated" >&2
}

# Update appsettings.runtime.json
update_appsettings() {
    log_info "=== Updating appsettings.runtime.json ==="

    # Check if appsettings file exists
    if [ ! -f "$APPSETTINGS_PATH" ]; then
        log_warn "File not found: $APPSETTINGS_PATH"
        log_warn "Creating new file with default settings"
        echo '{}' > "$APPSETTINGS_PATH"
    fi

    # Backup existing file
    local backup_path="${APPSETTINGS_PATH}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$APPSETTINGS_PATH" "$backup_path"
    log_info "✓ Backup created: $backup_path"

    # Verify temp file exists and is valid JSON
    if [ ! -f /tmp/monitor_settings.json ]; then
        log_error "Temp file not found: /tmp/monitor_settings.json"
        return 1
    fi

    # Read existing settings and monitor settings
    local existing_settings=$(cat "$APPSETTINGS_PATH")
    local monitor_settings=$(cat /tmp/monitor_settings.json)

    # Validate monitor settings JSON
    if ! echo "$monitor_settings" | jq '.' >/dev/null 2>&1; then
        log_error "Invalid JSON in monitor settings"
        log_error "Content: $monitor_settings"
        rm -f /tmp/monitor_settings.json
        return 1
    fi

    # Merge MonitorSettings
    local merged_settings=$(echo "$existing_settings" | jq --argjson monitor "$monitor_settings" '. + {MonitorSettings: $monitor}' 2>&1)

    if [ $? -ne 0 ]; then
        log_error "Failed to merge settings"
        log_error "$merged_settings"
        rm -f /tmp/monitor_settings.json
        return 1
    fi

    # Write back to file
    echo "$merged_settings" | jq '.' > "$APPSETTINGS_PATH"

    log_info "✓ Configuration updated: $APPSETTINGS_PATH"

    # Cleanup temp file
    rm -f /tmp/monitor_settings.json
}

# Main execution
main() {
    log_info "Starting hardware auto-detection..."
    echo ""

    # Detect hardware
    local detection_result=$(autodetect_hardware)
    IFS='|' read cpu_count primary_interface camera_interface data_disk gpu_type temp_count <<< "$detection_result"

    # Generate MonitorSettings JSON to temp file
    generate_monitor_settings "$cpu_count" "$primary_interface" "$camera_interface" "$data_disk" "$gpu_type" "$temp_count" > /tmp/monitor_settings.json

    # Update appsettings.runtime.json
    update_appsettings

    echo ""
    log_info "=== Configuration Summary ==="
    log_info "CPU Cores: ${cpu_count}"
    log_info "Network: ${primary_interface}"
    if [ -n "$camera_interface" ]; then
        log_info "Camera Network: ${camera_interface}"
    fi
    log_info "Disk: ${data_disk}"
    log_info "GPU: ${gpu_type:-none}"
    if [ "$temp_count" -gt 0 ]; then
        log_info "Temperature Sensors: ${temp_count}"
    fi

    echo ""
    log_info "Configuration completed successfully!"
    log_info "Restart RocketWelder to apply changes:"
    log_info "  cd /var/docker/configuration/rocket-welder && sudo docker compose restart"
}

# Run main function
main
