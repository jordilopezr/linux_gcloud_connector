# Linux Cloud Connector - Project Status

## Current Version: v1.7.0 (Stable)

**Status**: ✅ Production Ready - Full SFTP file transfer capabilities

---

## 📋 Feature Status

### ✅ Implemented & Working

| Feature | Status | Quality | Notes |
|---------|--------|---------|-------|
| **Google Cloud Auth** | ✅ Working | Good | Integrated with `gcloud auth login` |
| **Project Discovery** | ✅ Working | Good | Lists all GCP projects |
| **Instance Listing** | ✅ Working | Excellent | Grouped by zone, real-time status |
| **Search & Filtering** | ✅ Working | Excellent | Filter by name and status (Running/Stopped) |
| **IAP Tunnel Management** | ✅ Working | Excellent | Creates tunnels with automated health monitoring (30s intervals) |
| **RDP Connection** | ✅ Working | Excellent | Launches Remmina with saved credentials (secure file permissions) |
| **SSH Connection** | ✅ Working | Excellent | Opens native terminal with validated input (no command injection) |
| **Credential Storage** | ✅ Working | Excellent | Encrypted with libsecret (Linux Keyring) |
| **Project Persistence** | ✅ Working | Excellent | Remembers last selected project |
| **Multi-Tunnel Support** | ✅ Working | Good | Multiple simultaneous tunnels per instance |
| **Flatpak Compatibility** | ✅ Working | Good | Supports both native and Flatpak Remmina |
| **Structured Logging** | ✅ Working | Excellent | Persistent logs with rotation, export functionality |
| **Tunnel Metrics Dashboard** | ✅ Working | Excellent | Real-time uptime, health status, last check timestamp |
| **Observability** | ✅ Working | Excellent | Comprehensive monitoring and debugging capabilities |
| **Instance Resource Metrics** | ✅ Working | Excellent | Displays CPU, RAM, and Disk for all instances with machine type intelligence |
| **Generic Port Forwarding** | ✅ Working | Excellent | Universal TCP port forwarding with unlimited simultaneous tunnels |
| **SFTP File Transfer** | ✅ Working | Excellent | Full-featured file browser with upload/download/delete over secure SSH tunnels |

### ⚠️ Partially Implemented / Known Issues

| Feature | Status | Issue | Planned Fix |
|---------|--------|-------|-------------|
| **Auto-reconnect** | ⚠️ Missing | Tunnels don't automatically reconnect after failure | v1.5.0 (Priority 3) |

### ❌ Not Implemented (Future Enhancements)

| Feature | Planned Version | Notes |
|---------|----------------|-------|
| **Connection Persistence** | v2.0.0 | Restore tunnels on app restart |
| **Automated Testing** | v2.0.0 | Currently only placeholder tests |
| **Real-time CPU/RAM Usage** | v2.0.0 | Live monitoring metrics via GCP Monitoring API |
| **VM Lifecycle Management** | v2.0.0 | Start/stop/restart instances from UI |

---

## 🔍 Code Quality Metrics

### Lines of Code
- **Flutter/Dart**: ~2,350 lines (UI + state management + resource metrics + SFTP browser)
- **Rust**: ~2,520 lines (validation, health checks, timeouts, machine type specs, SFTP client)
- **Generated FFI Bridge**: ~2,300 lines (auto-generated, includes SFTP types)
- **Total**: ~7,170 lines

### Test Coverage
- **Rust**: 0% (no unit tests)
- **Flutter**: 0% (placeholder widget test only)
- **Target**: 70% by v2.0.0

### Technical Debt
- **High Priority**: ~~Tunnel health monitoring~~, ~~command timeouts~~ ✅ COMPLETED
- **Medium Priority**: ~~Input validation~~ ✅ COMPLETED, logging system
- **Low Priority**: Unused dependencies cleanup

---

## 🐛 Known Bugs

### Critical
- None currently reported

### High
- None currently reported (All P1 bugs fixed in v1.3.0!)

### Medium
- None currently reported

### Low
- None currently reported

**Note**: All major stability and security issues from v1.2.1 have been resolved in v1.3.0.

---

## 📊 Architecture Assessment

**Overall Rating**: 8.5/10 (Production-ready with strong security posture)

### Strengths
- ✅ Clean separation: Flutter UI + Rust backend
- ✅ Reactive state management (Riverpod)
- ✅ Small codebase (highly maintainable)
- ✅ Native performance (no Electron bloat)
- ✅ Comprehensive input validation (prevents command injection)
- ✅ Automated health monitoring (30s interval)
- ✅ Timeout protection on all external commands

### Weaknesses
- ⚠️ No automated tests
- ⚠️ Logging infrastructure missing

### Security Posture
- ✅ Credentials encrypted (libsecret)
- ✅ IAP integration (no direct VM access)
- ✅ Input validation prevents command injection
- ✅ File permissions explicitly set (0600 for .remmina files)
- ✅ No shell interpolation (arguments passed individually)

---

## 🚀 Active Development

### ✅ Completed: v1.7.0 - SFTP File Transfer
**Start Date**: 2025-12-20
**Release Date**: 2025-12-20 (Same day!)

**Completed Goals**:
- ✅ Full-featured SFTP file browser UI with navigation
- ✅ Upload files from local machine to remote instance
- ✅ Download files from remote instance to local machine
- ✅ Create and delete directories remotely
- ✅ Delete files remotely with confirmation dialog
- ✅ Auto-tunnel creation on SSH port 22
- ✅ File type detection with appropriate icons
- ✅ File size formatting (B, KB, MB, GB)
- ✅ Rust SFTP client implementation with ssh2 crate
- ✅ FFI bridge regeneration with SFTP functions

### Previous Sprint: v1.6.0 - Instance Resource Metrics
**Completed Goals**:
- ✅ Instance resource display (CPU, RAM, Disk)
- ✅ Machine type intelligence mapping (E2, N1, N2, N2D, C2 series)
- ✅ Disk size extraction from gcloud JSON API
- ✅ Visual resource dashboard with dedicated chips
- ✅ Automatic MB to GB conversion for RAM display
- ✅ FFI bridge updates for new GcpInstance fields

### Previous Sprint: v1.5.0 - Generic Port Forwarding
**Completed Goals**:
- ✅ Universal TCP port forwarding (any port, not just RDP)
- ✅ Unlimited simultaneous tunnels per VM
- ✅ Custom tunnel dialog with 8 service presets
- ✅ Individual tunnel management and health monitoring

### Previous Sprint: v1.4.0 - Observability & Monitoring
**Completed Goals**:
- ✅ Structured logging with tracing crate
- ✅ Log export functionality
- ✅ Tunnel metrics dashboard
- ✅ Real-time health monitoring

### Next Sprint: v1.8.0 - VM Lifecycle Management
**Planned Features**:
- Start/stop/restart instances from UI
- Instance status monitoring and auto-refresh
- Confirmation dialogs for destructive actions
- Error handling for lifecycle operations
- Visual feedback during state transitions

### Future: v2.0.0 - Advanced Features
**Planned Features**:
- Connection persistence (restore tunnels on restart)
- Automated testing infrastructure
- Real-time CPU/RAM usage monitoring via GCP Monitoring API
- Multi-session tabs for simultaneous connections

**See**: [roadmap.md](roadmap.md) for detailed implementation plan

---

## 🧪 Testing Status

### Manual Testing
- ✅ Debian 12 (GNOME)
- ✅ Ubuntu 24.04 LTS
- ⚠️ Fedora 40 (untested)
- ⚠️ Arch Linux (untested)

### Automated Testing
- ❌ No CI/CD pipeline
- ❌ No integration tests
- ❌ No unit tests

**Target**: GitHub Actions CI by v2.0.0

---

## 📦 Dependencies

### Rust (Cargo.toml)
- `flutter_rust_bridge` 2.11.1 - FFI code generation
- `anyhow` 1.0.100 - Error handling
- `serde` + `serde_json` - JSON parsing
- `tokio` 1.48.0 - Async runtime with timeouts (rt, time, process, io-util, fs features enabled)
- `regex` 1.11.1 - Input validation
- `tracing` 0.1.41 - Structured logging framework
- `tracing-subscriber` 0.3.19 - Log formatting and filtering (env-filter, fmt, json)
- `tracing-appender` 0.2.3 - Log rotation and file management
- `chrono` 0.4.38 - Timestamp handling for log exports
- `lazy_static` 1.5.0 - Global tunnel state
- `dirs` 6.0.0 - Standard paths
- `ssh2` 0.9.4 - SFTP client library for secure file transfers

### Flutter (pubspec.yaml)
- `flutter_riverpod` 3.0.3 - State management
- `flutter_rust_bridge` 2.11.1 - FFI bindings
- `flutter_secure_storage` 10.0.0 - Encrypted storage
- `shared_preferences` 2.5.4 - Preferences
- `file_picker` 8.1.6 - File and directory selection for SFTP operations
- `path` 1.9.0 - Path manipulation for SFTP file operations
- `freezed_annotation` - **UNUSED**
- `json_annotation` - **UNUSED**

**Cleanup Planned**: v2.0.0

---

## 🔗 References

- **Roadmap**: [roadmap.md](roadmap.md)
- **Source Code**: https://github.com/jordilopezr/linux_gcloud_connector
- **README**: [README.md](README.md)
- **Architecture Analysis**: me and Claude (2025-12-18)

---

## 📝 Recent Changes

### v1.7.0 (2025-12-20) - SFTP File Transfer Release
- ✅ **SFTP File Browser**: Full-featured graphical file browser for remote instances
- ✅ **File Upload**: Transfer files from local machine to remote instance via SFTP
- ✅ **File Download**: Download files from remote instance to local machine
- ✅ **Directory Operations**: Create new directories and delete files/folders remotely
- ✅ **Auto-Tunnel**: Automatic SSH tunnel creation on port 22 when opening file browser
- ✅ **File Type Icons**: Visual file type identification (documents, images, code, archives, etc.)
- ✅ **Size Formatting**: Human-readable file sizes (B, KB, MB, GB)
- ✅ **Error Handling**: Clear error messages with dismiss functionality
- ✅ **Rust SFTP Client**: Complete implementation using ssh2 crate
- ✅ **FFI Bridge**: Regenerated with sftpListDir, sftpUpload, sftpDownload, sftpMkdir, sftpDelete functions
- ✅ **State Management**: Riverpod Notifier pattern for SFTP browser state
- ✅ **Security**: All transfers over secure SSH tunnels via IAP

### v1.6.0 (2025-12-19) - Instance Resource Metrics Release
- ✅ **Resource Display**: Added CPU, RAM, and Disk visualization for all instances
- ✅ **Machine Type Intelligence**: Automatic mapping of machine types to specs (E2, N1, N2, N2D, C2)
- ✅ **Disk Detection**: Extract boot disk size from gcloud JSON API
- ✅ **Visual Dashboard**: New resource card with individual metric chips
- ✅ **Smart Conversions**: Automatic MB to GB conversion for better readability
- ✅ **FFI Bridge**: Extended GcpInstance struct with cpu_count, memory_mb, disk_gb fields
- ✅ **Backend Logic**: Added get_machine_specs() function with 30+ machine type mappings
- ✅ **UI Components**: Created _ResourceChip widget for clean metric display

### v1.5.0 (2025-12-19) - Generic Port Forwarding Release
- ✅ **Universal Port Forwarding**: Support for any TCP port (PostgreSQL, MySQL, HTTP, Redis, etc.)
- ✅ **Multi-Tunnel Support**: Unlimited simultaneous tunnels per instance
- ✅ **Custom Dialog**: 8 service presets + custom port input with validation
- ✅ **Individual Management**: Disconnect specific tunnels without affecting others
- ✅ **Health Monitoring**: Per-tunnel health checks and status display

### v1.4.0 (2025-12-18) - Observability & Monitoring Release
- ✅ **Structured Logging**: Replaced all println! with tracing (persistent logs with daily rotation)
- ✅ **Log Management**: Auto-cleanup (keeps 5 files, max 10MB each), logs in ~/.local/share/linux_cloud_connector/logs/
- ✅ **Export Logs**: UI button to consolidate and export all logs for troubleshooting
- ✅ **Tunnel Dashboard**: Real-time metrics display (uptime, last health check, dynamic status)
- ✅ **Health Visualization**: Color-coded status badges (Healthy/Degraded/Unhealthy)
- ✅ **Monitoring**: Auto-monitoring every 30s with timestamp tracking

### v1.3.0 (2025-12-18) - Major Security & Stability Release
- ✅ **Health Monitoring**: Automated tunnel health checks every 30 seconds (process + TCP verification)
- ✅ **Command Timeouts**: All gcloud commands wrapped with 10s timeout (prevents UI freezing)
- ✅ **Input Validation**: Regex-based validation prevents command injection attacks
- ✅ **Secure Permissions**: .remmina files created with mode 0600 (owner-only access)
- ✅ **UI Improvements**: Health status badges, "Test IAP Connection" button, project dropdown shows full ID
- ✅ **Bug Fixes**: Fixed project dropdown display, improved error messages

### v1.2.1 (2025-12-18)
- ✅ Smart search and filtering by instance name/status
- ✅ Enhanced UI with filter chips

### v1.2.0
- ✅ Project persistence with SharedPreferences
- ✅ Secure RDP credential storage (libsecret)

### v1.1.0
- ✅ Multi-tunnel connection management
- ✅ Configurable RDP settings (resolution, fullscreen)

### v1.0-beta2
- ✅ Initial stable release
- ✅ Basic IAP tunneling
- ✅ RDP/SSH launch support

---

**Last Updated**: 2025-12-20
**Maintained By**: Jordi Lopez Reyes
**Status Review Frequency**: After each major release
