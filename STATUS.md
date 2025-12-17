# Project Status Report

## 📅 Date: December 17, 2025
## 🚀 Current State: Stable & Functional (v1.1.0-dev)

This document serves as a context anchor for AI agents continuing development on **Linux Cloud Connector**.

### ✅ Completed Features
1.  **Multi-Tunnel Support**:
    -   The application now manages a map of active connections (`activeConnectionsProvider` in `gcloud_provider.dart`).
    -   Multiple instances can have active IAP tunnels simultaneously on different local ports.
2.  **Advanced RDP Settings**:
    -   Implemented `RdpSettings` in Rust (`native/src/remmina.rs`) and Dart.
    -   Users can now configure: **Fullscreen**, **Resolution (Width/Height)**, **Username**, **Password**, and **Domain**.
    -   Configuration is injected into dynamically generated `.remmina` files.
3.  **UI Stability & Error Handling**:
    -   **Crash Fix:** `ProjectSelector` now safely handles cases where the selected project ID is missing from the list.
    -   **Overflow Fix:** `InstanceDetailPane` is scrollable, preventing crashes when displaying long GCP error messages.
    -   **Error Propagation:** `projectsProvider` and `instancesProvider` now rethrow exceptions, allowing the UI to display critical setup errors (like "API Not Enabled").

### 🏗️ Architecture Snapshot

#### Frontend (Flutter + Riverpod)
-   **`lib/main.dart`**: Contains the core UI components (`DashboardScreen`, `ResourceTree`, `InstanceDetailPane`).
-   **`lib/src/features/gcloud_provider.dart`**: The "Brain" of the app. Manages:
    -   Authentication state.
    -   Project & Instance fetching.
    -   **Tunnel State Machine** (Connecting -> Connected -> Error).

#### Backend (Rust - `native/src`)
-   **`api.rs`**: Facade and FRB (Flutter Rust Bridge) exports.
-   **`gcloud.rs`**: Wraps `gcloud` CLI commands (JSON parsing for lists, process spawning for SSH).
-   **`remmina.rs`**: Handles `.remmina` profile generation and intelligent launching (Native vs Flatpak detection).
-   **`tunnel.rs`**: Manages `gcloud compute start-iap-tunnel` child processes and local port allocation.

### 📂 Critical Files
| File | Responsibility |
| :--- | :--- |
| `lib/main.dart` | Main UI Layout & Interaction Logic |
| `lib/src/features/gcloud_provider.dart` | State Management & Logic |
| `native/src/remmina.rs` | RDP Logic & Configuration |
| `native/src/tunnel.rs` | Tunnel Process Management |
| `pubspec.yaml` | Flutter Dependencies |

### 📝 Backlog & Next Steps
1.  **Persistence**:
    -   Save the "Last Selected Project" and "RDP Preference" (e.g., always fullscreen) using `shared_preferences`.
2.  **Error Parsing**:
    -   The current error display is raw text from `gcloud`. Implementing a parser to extract just the "Verification URL" or "Reason" would improve UX.
3.  **Packaging**:
    -   Verify the `package_deb.sh` script works with the new Rust binary structure.
    -   Consider adding AppImage support.
4.  **Unit Testing**:
    -   Add Rust unit tests for `gcloud` JSON output parsing.

### ⚠️ Operational Notes
-   **GCP API Requirement**: New projects *must* have the **Compute Engine API** enabled. The app handles this error gracefully now, showing the activation URL.
-   **Runtime Requirements**: `gcloud` CLI and `remmina` must be installed on the host system.

---
*End of Status Report*
