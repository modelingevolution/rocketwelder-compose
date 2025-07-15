# RocketWelder Docker Compose

Production deployment configuration for RocketWelder using Docker Compose with AutoUpdater integration.

## 🚀 Quick Start

```bash
# Create required directories
sudo mkdir -p /var/data/{app/{recordings,logs,models},eventstore/{data,logs}}

# Set proper permissions
sudo chown -R $USER:$USER /var/data/

# Start services with architecture detection
docker compose up -d

# Or explicitly specify architecture:
# For x64 systems:
docker compose -f docker-compose.yml -f docker-compose.x64.yml up -d

# For ARM64 systems with NVIDIA GPU:
docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d

# View logs
docker compose logs -f
```

## 📁 Configuration Files

### Docker Compose Files
- **docker-compose.yml** - Base configuration (generic, architecture-neutral)
- **docker-compose.x64.yml** - x64-specific overrides (standard EventStore image)
- **docker-compose.arm64.yml** - ARM64-specific overrides with NVIDIA GPU support and ARM64 EventStore image
- **up-{version}.sh** - Migration scripts executed during updates (e.g., `up-1.0.0.sh`)
- **down-{version}.sh** - Rollback scripts for safe migration reversal (e.g., `down-1.0.0.sh`)
- **backup.sh** - Creates EventStore backup before migrations (supports `--format=json`)
- **restore.sh** - Restores from backup file (supports `--file` and `--format=json`)

### Directory Structure

```
/var/data/
├── app/
│   ├── recordings/              # Video recordings storage
│   ├── logs/                    # Application logs
│   ├── models/                  # AI/ML models
│   └── appsettings.runtime.json # Runtime configuration
└── eventstore/
    ├── data/                    # EventStore database files
    └── logs/                    # EventStore logs
```

## 🔧 Services

### RocketWelder Application
- **URL**: http://localhost:80
- **Image**: `rocketwelder.azurecr.io/rocketwelder:latest`
- **Features**: Video processing, streaming, pipeline design
- **Hardware Access**: USB cameras, GPU acceleration (privileged mode)

### EventStore Database
- **URL**: http://localhost:2113 (localhost only)
- **Image**: `eventstore/eventstore:24.10.5`
- **Features**: Event sourcing, projections, HTTP API

## 🔄 AutoUpdater Integration

This compose configuration is designed to work with the [ModelingEvolution AutoUpdater](https://github.com/modelingevolution/autoupdater):

- **Service Name**: `rocket-welder` (matches compose project name)
- **Auto-Updates**: Monitors for new image versions
- **Status Checking**: Real-time container status via SSH
- **Zero-Downtime**: Graceful container restarts during updates
- **Architecture Detection**: Automatically selects appropriate compose files

### Multi-File Architecture Support

The AutoUpdater automatically detects the target architecture and uses the appropriate compose files:

- **x64 Systems**: Uses `docker-compose.yml` + `docker-compose.x64.yml`
- **ARM64 Systems**: Uses `docker-compose.yml` + `docker-compose.arm64.yml` (with NVIDIA support)

### AutoUpdater Configuration

The AutoUpdater will automatically:
1. Detect system architecture via `uname -m`
2. Select appropriate Docker Compose override files
3. Monitor `rocketwelder.azurecr.io/rocketwelder:latest` for updates
4. Check service status via `docker compose ls --format json`
5. Execute migration scripts between versions (see Migration Scripts below)
6. Pull new images and restart containers when updates are available
7. Maintain data persistence through mounted volumes

### Migration Scripts

The AutoUpdater supports automatic execution of migration scripts with backup/restore capabilities:

#### Script Naming Convention
- **Format**: `up-{version}.sh` and `down-{version}.sh` (e.g., `up-1.0.0.sh`, `down-1.0.0.sh`)
- **Location**: Same directory as `docker-compose.yml`
- **Permissions**: Made executable automatically by AutoUpdater

#### Migration System Features
- **Backup/Restore**: `backup.sh` and `restore.sh` provide safe rollback capabilities
- **Fresh Installation Detection**: Automatically detects empty EventStore data
- **Bidirectional Migrations**: UP scripts for deployment, DOWN scripts for rollback
- **Error Recovery**: Automatic rollback on migration failures

#### Current Migration Scripts
- **`up-1.0.0.sh`**: Initial deployment setup (directories, permissions, monitoring tools, log rotation)
- **`down-1.0.0.sh`**: Rollback for initial deployment (safe cleanup)
- **`backup.sh`**: Creates EventStore backup (skips if fresh installation)
- **`restore.sh`**: Restores from backup file

#### Migration Script Best Practices
- **Idempotent**: Scripts should be safe to run multiple times
- **Error Handling**: Use `set -e` to fail on errors
- **Logging**: Echo progress messages for debugging
- **Validation**: Check for required conditions before making changes
- **Permissions**: Use `sudo` for system-level changes when needed

## 🐳 Image Tags

- **Production**: `latest` (stable, promoted from preview)
- **Development**: `preview` (development builds)
- **Versioned**: `1.2.3`, `1.2`, `1` (semantic versioning)

## 📋 System Requirements

- **Docker Engine**: 20.10+ with compose plugin
- **Platform**: Linux x64/ARM64 (multi-architecture support)
- **Hardware**: USB cameras, optional NVIDIA GPU
- **Network**: Host networking for real-time streaming
- **Storage**: Persistent volumes for recordings and database

## 🔒 Security

- **EventStore**: Localhost binding only (127.0.0.1:2113)
- **Privileged Mode**: Required for hardware access (cameras, USB)
- **User Context**: Root for device access and container management

## 📊 Monitoring

```bash
# Check service status
docker compose ps

# View real-time logs
docker compose logs -f

# Check EventStore health
curl -f http://localhost:2113/health/live

# Monitor resource usage
docker stats
```

## 🛠️ Troubleshooting

### Container Won't Start
```bash
# Check logs
docker compose logs app

# Verify permissions
sudo chown -R $USER:$USER /var/data/

# Restart services
docker compose restart
```

### EventStore Issues
```bash
# Check EventStore logs
docker compose logs eventstore

# Test health endpoint
curl -f http://localhost:2113/health/live

# Reset EventStore data (⚠️ destroys all data!)
docker compose down
sudo rm -rf /var/data/eventstore/data/*
docker compose up -d
```

### Hardware Access Problems
```bash
# Verify device access
ls -la /dev/video*

# Check udev rules
sudo udevadm info --query=all --name=/dev/video0

# Restart with clean state
docker compose down && docker compose up -d
```

## 🔗 Related Projects

- [RocketWelder](https://github.com/modelingevolution/rocket-welder2) - Main application
- [AutoUpdater](https://github.com/modelingevolution/autoupdater) - Automated deployment system
- [Deployments](https://github.com/modelingevolution/Deployments) - Production configurations

---

**Deployment**: Multi-architecture Docker Compose  
**Registry**: Azure Container Registry (rocketwelder.azurecr.io)  
**Auto-Updates**: Integrated with ModelingEvolution AutoUpdater