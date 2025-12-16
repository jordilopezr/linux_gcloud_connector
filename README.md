# Linux Cloud Connector (LCC) ☁️🐧

**Linux Cloud Connector** es una aplicación de escritorio nativa para Linux diseñada para simplificar y asegurar la conexión a instancias de Google Cloud Platform (GCP) mediante **Identity-Aware Proxy (IAP)**.

Desarrollada por **Jordi Lopez Reyes** con **Flutter** y **Rust** para un rendimiento y seguridad óptimos.

![Status](https://img.shields.io/badge/Status-Stable-green)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-purple)

## ✨ Características Clave

*   **🔍 Auto-Discovery:** Detecta automáticamente tus proyectos de GCP e instancias (VMs).
*   **🔒 Auth Integration:** Login integrado con Google Cloud (`gcloud auth login`).
*   **🛡️ IAP Tunneling:** Gestión automática de túneles TCP seguros.
*   **🖥️ Smart RDP:** Lanza **Remmina** automáticamente, gestionando el túnel y la configuración en un solo clic.
*   **💻 SSH Support:** Detecta tu terminal favorita (`gnome-terminal`, `konsole`, etc.) y lanza sesiones SSH nativas.
*   **⚡ Native Backend:** Lógica crítica escrita en Rust para máxima velocidad y seguridad de memoria.

## 🔗 Repositorio y Contacto

*   **Código Fuente:** [https://github.com/jordilopezr/linux_gcloud_connector](https://github.com/jordilopezr/linux_gcloud_connector)
*   **Desarrollador:** Jordi Lopez Reyes
*   **Email:** [aim@jordilopezr.com](mailto:aim@jordilopezr.com)

## 🛠️ Requisitos del Sistema

1.  **Google Cloud SDK (`gcloud`):** Instalado y en el PATH.
2.  **Remmina:** Cliente RDP (Nativo o Flatpak).
3.  **Flutter & Rust:** Para compilación desde fuente.

## 🚀 Compilación e Instalación

### 1. Clonar
```bash
git clone https://github.com/jordilopezr/linux_gcloud_connector.git
cd linux_cloud_connector
```

### 2. Preparar Entorno
```bash
flutter pub get
cargo install flutter_rust_bridge_codegen
```

### 3. Generar Bridge
```bash
flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root native --dart-output lib/src/bridge/api.dart
```

### 4. Ejecutar
```bash
flutter run -d linux
```

## 🍎 Nota sobre macOS

Este proyecto es compatible con macOS (Intel/Silicon) con ajustes mínimos en el lanzador RDP (usando `open` en lugar de `remmina`) y en la configuración de Xcode.

---
© 2025 Jordi Lopez Reyes. Distribuido bajo licencia MIT.