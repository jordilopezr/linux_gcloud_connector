# Linux Cloud Connector - Roadmap

## Overview
This roadmap outlines planned improvements and features for Linux Cloud Connector based on architectural analysis and production readiness requirements.

---

## 🔴 Priority 1: Stability & Reliability ✅ COMPLETED (2025-12-18)

### 1.1 Tunnel Health Monitoring
**Status**: ✅ Completed
**Complexity**: Medium
**Impact**: High

**Current Issue**:
- Tunnels marked as "connected" without verifying the process is alive
- No detection when gcloud process crashes
- Users experience mysterious RDP connection failures

**Implementation**:
- ✅ Add TCP connection test before marking tunnel as "connected"
- ✅ Implement periodic health check (every 30 seconds)
- ⚠️ Auto-reconnect on tunnel failure with exponential backoff (deferred to v1.4.0)
- ✅ Add tunnel status to UI: "Healthy", "Degraded", "Failed"

**Files Modified**:
- ✅ `native/src/tunnel.rs` - Added `is_process_alive()`, `is_port_listening()`, `is_healthy()`
- ✅ `lib/src/features/gcloud_provider.dart` - Added Timer.periodic health checks with ref.onDispose()

---

### 1.2 Command Timeouts
**Status**: ✅ Completed
**Complexity**: Low
**Impact**: High

**Current Issue**:
- All `gcloud` commands can hang indefinitely if network is slow
- No user feedback during long-running operations
- Can cause UI freezes

**Implementation**:
- ✅ Wrap all `Command::new("gcloud")` calls with `tokio::time::timeout`
- ✅ Set default timeout: 10 seconds for all gcloud operations
- ✅ Return proper error messages on timeout
- ⚠️ Add progress indicators in UI for long operations (deferred to v1.4.0)

**Files Modified**:
- ✅ `native/src/gcloud.rs` - Converted to async with `tokio::time::timeout(Duration::from_secs(10), ...)`
- ✅ `native/Cargo.toml` - Enabled tokio features: rt, time, process, io-util

---

### 1.3 Input Validation
**Status**: ✅ Completed
**Complexity**: Low
**Impact**: Critical (Security)

**Current Issue**:
- No validation of project_id, zone, instance_name before passing to shell
- Potential command injection vulnerability in SSH launcher
- Fragile zone parsing from GCP API responses

**Implementation**:
- ✅ Add regex validation for project_id: `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`
- ✅ Add regex validation for zone: `^[a-z]+-[a-z]+[0-9]+-[a-z]$`
- ✅ Add regex validation for instance_name: `^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$`
- ✅ Replace `sh -c` with direct `Command` args (no shell interpolation)
- ⚠️ Add unit tests for validation functions (deferred to v2.0.0)

**Files Created/Modified**:
- ✅ `native/src/validation.rs` - NEW MODULE with comprehensive regex validation (250 lines)
- ✅ `native/src/gcloud.rs` - Added validation calls to all public functions
- ✅ `native/src/tunnel.rs` - Validate inputs before spawning processes
- ✅ `native/Cargo.toml` - Added regex = "1.11.1"

---

### 1.4 Secure File Permissions
**Status**: ✅ Completed
**Complexity**: Low
**Impact**: Medium (Security)

**Current Issue**:
- `.remmina` config files created with default permissions
- Username, domain, and display settings exposed if `~/.cache/` is world-readable

**Implementation**:
- ✅ Set file permissions to `0600` (owner read/write only) on `.remmina` files
- ✅ Verify parent directory permissions (handled by OS)
- ✅ Add error handling if permissions cannot be set

**Files Modified**:
- ✅ `native/src/remmina.rs` - Added `fs::set_permissions(path, Permissions::from_mode(0o600))`

---

## 🟡 Priority 2: Observability ✅ COMPLETED (2025-12-18)

### 2.1 Structured Logging
**Status**: ✅ Completed
**Complexity**: Medium
**Impact**: High

**Implementation**:
- ✅ Replace `println!` with `tracing` crate (tunnel.rs, gcloud.rs, remmina.rs)
- ✅ Log to `~/.local/share/linux_cloud_connector/logs/app.log`
- ✅ Implement log rotation (max 10MB, keep 5 files, daily rotation)
- ✅ Add log levels: ERROR, WARN, INFO, DEBUG (with EnvFilter)
- ✅ UI button: "Export Logs" for troubleshooting

**Files Created/Modified**:
- ✅ `native/src/logging.rs` - NEW MODULE (242 lines) with rotation, cleanup, export
- ✅ `native/Cargo.toml` - Added `tracing`, `tracing-subscriber`, `tracing-appender`, `chrono`
- ✅ `lib/main.dart` - Added export logs button and initialization

---

### 2.2 Tunnel Status Dashboard
**Status**: ✅ Completed
**Complexity**: Low
**Impact**: Medium

**Implementation**:
- ✅ Show tunnel health in UI: "Healthy", "Degraded", "Unhealthy"
- ✅ Display tunnel uptime (human-readable format)
- ✅ Show last health check timestamp (relative time)
- ✅ Dynamic color coding (green/orange/red based on status)
- ✅ Metric cards with icons and labels

**Files Modified**:
- ✅ `lib/src/features/gcloud_provider.dart` - Enhanced TunnelState with createdAt, lastHealthCheck
- ✅ `lib/main.dart` - Created _buildTunnelDashboard() and _MetricCard widget

---

### 2.3 Error Reporting
**Status**: ✅ Completed (Integrated)
**Complexity**: Low
**Impact**: Medium

**Implementation**:
- ✅ Error messages displayed in tunnel dashboard
- ✅ Structured error logging with tracing::error!
- ✅ Context and stack traces in log files
- ✅ Export logs functionality for sharing error logs

**Notes**: Error reporting is integrated throughout the UI with contextual error messages, error badges in tunnel dashboard, and comprehensive logging. A dedicated error panel was deemed unnecessary as errors are already well-displayed inline.

---

## 🟢 Priority 3: Features & Enhancements ✅ PARTIALLY COMPLETED (2025-12-18)

### 3.1 Generic Port Forwarding
**Status**: ✅ Completed (v1.5.0)
**Complexity**: Medium
**Impact**: High

**Previous Limitation**: Only RDP (port 3389) supported

**Implementation**:
- ✅ UI: "Custom Tunnel" dialog with port input and 8 service presets
- ✅ Support for common ports: RDP (3389), SSH (22), PostgreSQL (5432), MySQL (3306), HTTP (8080), HTTPS (443), MongoDB (27017), Redis (6379)
- ⚠️ Persistent tunnel configuration (save to SharedPreferences) - Deferred to v1.6.0
- ✅ Multiple simultaneous tunnels per instance (composite key pattern)

**Files Modified**:
- ✅ `native/src/tunnel.rs` - Composite key implementation ("instance:port")
- ✅ `native/src/api.rs` - FFI signature updates
- ✅ `lib/src/features/gcloud_provider.dart` - Multi-tunnel state management
- ✅ `lib/main.dart` - Custom tunnel dialog, multi-tunnel UI

---

### 3.2 Instance Metrics
**Status**: ✅ Completed (v1.6.0)
**Complexity**: Medium
**Impact**: Medium

**Implementation**:
- ✅ Fetch Machine Type (Capacity) via `gcloud compute instances list` JSON
- ✅ Display Machine Type (e.g., e2-medium) in Instance List and Detail Pane
- ✅ Extract CPU, RAM, and Disk specifications for all instances
- ✅ Machine type intelligence mapping (E2, N1, N2, N2D, C2 series)
- ✅ Visual resource dashboard with dedicated metric chips
- ✅ Automatic MB to GB conversion for better readability
- [ ] Fetch live CPU/RAM usage (Requires Cloud Monitoring API + Ops Agent) - **Deferred to v2.0.0** (High complexity/dependencies)
- [ ] Auto-refresh metrics every 30 seconds - **Deferred to v2.0.0**

**Files Modified**:
- ✅ `native/src/gcloud.rs` - Added `cpu_count`, `memory_mb`, `disk_gb` fields, `get_machine_specs()` function
- ✅ `lib/src/bridge/api.dart/gcloud.dart` - Extended GcpInstance class
- ✅ `native/src/frb_generated.rs` - Updated FFI bridge encoding/decoding
- ✅ `lib/src/bridge/api.dart/frb_generated.dart` - Updated FFI bridge serialization
- ✅ `lib/main.dart` - Added resource metrics card and _ResourceChip widget

---

### 3.3 Connection Persistence
**Status**: Planned
**Complexity**: High
**Impact**: Medium

**Implementation**:
- [ ] Save active tunnels to `~/.config/linux_cloud_connector/tunnels.json`
- [ ] Restore tunnels on app restart
- [ ] Option to "Run in Background" (system tray)
- [ ] Auto-reconnect on network resume

**Files to Create/Modify**:
- `native/src/persistence.rs` - New module for tunnel state persistence
- `lib/src/services/tunnel_persistence_service.dart`

---

### 3.4 SFTP Integration
**Status**: ✅ Completed (v1.7.0)
**Complexity**: Low
**Impact**: Medium

**Implementation**:
- ✅ "Open SFTP" button in InstanceDetailPane
- ✅ Auto-create IAP tunnel to port 22 (SSH)
- ✅ Launch default system file manager with `sftp://[user]@localhost:[port]` URI
- ✅ Automatic username detection (matches gcloud behavior)

**Files Modified**:
- `native/src/gcloud.rs` - Added `launch_sftp_browser` using `xdg-open`
- `lib/main.dart` - Added SFTP button logic

---

### 3.5 VM Lifecycle Management
**Status**: Planned (v1.8.0)
**Complexity**: Medium
**Impact**: High

**Implementation**:
- [ ] Start/stop/restart instances from UI
- [ ] Instance status monitoring and auto-refresh
- [ ] Confirmation dialogs for destructive actions
- [ ] Error handling for lifecycle operations
- [ ] Visual feedback during state transitions

**Files to Create/Modify**:
- `native/src/gcloud.rs` - Add `start_instance()`, `stop_instance()`, `reset_instance()`
- `lib/main.dart` - Add action buttons to InstanceDetailPane

---

## 🔵 Priority 4: Quality & Maintenance (3-4 days)

### 4.1 Automated Testing
**Status**: Planned
**Complexity**: High
**Impact**: High

**Implementation**:
- [ ] Rust unit tests for all modules (target: 70% coverage)
- [ ] Flutter widget tests for critical UI flows
- [ ] Integration tests with mock gcloud CLI
- [ ] CI/CD pipeline with GitHub Actions

**Files to Create**:
- `native/src/gcloud_test.rs`
- `native/src/tunnel_test.rs`
- `test/integration/auth_flow_test.dart`
- `.github/workflows/ci.yml`

---

### 4.2 Documentation
**Status**: Planned
**Complexity**: Low
**Impact**: Medium

**Implementation**:
- [ ] Inline comments for complex logic (tunnel state machine)
- [ ] Architecture Decision Records (ADRs)
- [ ] Contributing guide (CONTRIBUTING.md)
- [ ] API documentation for Rust modules (rustdoc)

---

### 4.3 Dependency Cleanup
**Status**: Planned
**Complexity**: Low
**Impact**: Low

**Implementation**:
- [ ] Remove unused `tokio` features (currently imported but not used)
- [ ] Remove unused `log` crate (replaced by `tracing`)
- [ ] Remove unused Flutter packages: `freezed_annotation`, `json_annotation`
- [ ] Audit dependencies for security vulnerabilities

**Files to Modify**:
- `native/Cargo.toml`
- `pubspec.yaml`

---

## 📊 Version Timeline

| Version | Priority | Status | Features |
|---------|----------|--------|----------|
| **v1.3.0** | P1 | ✅ Released (2025-12-18) | Stability improvements (health checks, timeouts, validation, secure permissions) |
| **v1.4.0** | P2 | ✅ Released (2025-12-18) | Observability (structured logging, tunnel dashboard, metrics, export logs) |
| **v1.5.0** | P3 | ✅ Released (2025-12-19) | Generic port forwarding, multi-tunnel support, custom tunnel dialog with 8 service presets |
| **v1.6.0** | P3 | ✅ Released (2025-12-19) | Instance resource metrics (CPU, RAM, Disk), machine type intelligence, visual dashboard |
| **v1.7.0** | P3 | ✅ Released (2025-12-20) | SFTP file transfer browser with upload/download/delete capabilities over secure SSH tunnels |
| **v1.8.0** | P3 | Planned | VM Lifecycle Management (start/stop/restart instances from UI) |
| **v2.0.0** | P3+P4 | Planned | Tunnel persistence, auto-reconnect, testing suite, dependency cleanup, live metrics, multi-session tabs |

---

## 🎯 Success Metrics

- **Stability**: Zero tunnel state mismatches (UI vs actual process)
- **Performance**: All gcloud calls complete within timeout or fail gracefully
- **Security**: No command injection vulnerabilities (validated inputs)
- **User Experience**: 95% of connections succeed on first attempt
- **Code Quality**: 70%+ test coverage

---

## Notes

- Priorities can shift based on user feedback
- Each feature requires testing before merge
- Breaking changes should bump major version (v2.0.0)
- Security fixes should be released ASAP regardless of roadmap

---

**Last Updated**: 2025-12-20
**Author**: Jordi Lopez Reyes (with architectural analysis by Claude)
