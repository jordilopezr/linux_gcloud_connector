# Project Status Report

## 📅 Date: December 17, 2025
## 🚀 Current State: Stable & Functional (v1.2.1)

This document serves as a context anchor for AI agents continuing development on **Linux Cloud Connector**.

### ✅ Completed Features
1.  **Smart Search & Filtering (v1.2.1)**:
    -   Added real-time search bar for instances.
    -   Added filter chips for "Running" vs "Stopped" instances.
    -   UI refactored to `ConsumerStatefulWidget` to handle local view state.
2.  **Credential Persistence & Security (v1.2.0)**:
    -   **Secure Storage:** Uses `libsecret` (Linux Keyring) to store RDP credentials (User, Pass, Domain).
    -   **Project Persistence:** Remembers the last selected GCP project via `shared_preferences`.
    -   **Auto-Fill:** RDP dialog automatically fills known credentials.
3.  **Multi-Tunnel Support**:
    -   Manages multiple simultaneous IAP tunnels via `activeConnectionsProvider`.
4.  **Advanced RDP Settings**:
    -   Configurable Resolution, Fullscreen, and Auth settings injected into `.remmina` files.
5.  **Robust Error Handling**:
    -   UI handles API permissions errors gracefully (scrollable details).
    -   Compilation and Import issues resolved.

### 🏗️ Architecture Snapshot

#### Frontend (Flutter + Riverpod)
-   **`lib/main.dart`**: Contains `DashboardScreen`, and the new `ResourceTree` (with Search/Filter logic).
-   **`lib/src/features/gcloud_provider.dart`**: Manages GCP state and persistence logic.
-   **`lib/src/services/storage_service.dart`**: Abstraction layer for `flutter_secure_storage` and `shared_preferences`.

#### Backend (Rust - `native/src`)
-   **`remmina.rs`**: RDP logic.
-   **`tunnel.rs`**: Process management.
-   **`gcloud.rs`**: CLI wrapping.

### 📂 Critical Files
| File | Responsibility |
| :--- | :--- |
| `lib/main.dart` | UI, Search, Filter, RDP Dialog |
| `lib/src/services/storage_service.dart` | Persistence & Security |
| `lib/src/features/gcloud_provider.dart` | Business Logic & State |
| `linux/CMakeLists.txt` | Build configuration (Install Prefix fixed) |

### 📝 Backlog & Next Steps
1.  **Generic TCP Tunnels (Port Forwarding)**:
    -   Allow users to open tunnels for arbitrary ports (DBs, Web UIs) not just RDP (3389).
2.  **File Transfer (SFTP)**:
    -   Implement a basic file manager over SSH/SFTP.
3.  **Monitoring Dashboard**:
    -   Show CPU/RAM usage graphs for instances.
4.  **Packaging**:
    -   Create `.deb` and `.AppImage` releases.

### ⚠️ Operational Notes
-   **System Dependencies:** Building now requires `libsecret-1-dev` and `libjsoncpp-dev` on the host machine.
-   **GCP API Requirement**: Compute Engine API must be enabled.

---
*End of Status Report*