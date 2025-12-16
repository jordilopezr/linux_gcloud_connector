# Linux Cloud Connector (LCC) ☁️🐧

**Linux Cloud Connector** es una aplicación de escritorio nativa para Linux diseñada para simplificar y asegurar la conexión a instancias de Google Cloud Platform (GCP) mediante **Identity-Aware Proxy (IAP)**.

Desarrollada con **Flutter** para una UI moderna y **Rust** para un backend seguro y de alto rendimiento.

![Status](https://img.shields.io/badge/Status-Stable-green)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)

## ✨ Características

*   **🔍 Auto-Discovery:** Detecta automáticamente tus proyectos de GCP e instancias (VMs) activas usando `gcloud`.
*   **🔒 Auth Integration:** Inicia sesión en Google Cloud directamente desde la aplicación.
*   **🛡️ IAP Tunneling:** Crea túneles TCP seguros dinámicamente, sin exponer puertos públicos en tus VMs.
*   **🖥️ RDP Integration:** Genera configuración y lanza automáticamente **Remmina** (soporta instalación Nativa y Flatpak) para conectar con un solo clic.
*   **⚡ Performance:** Lógica de túneles y procesos gestionada en Rust nativo.

## 🛠️ Requisitos del Sistema

Antes de compilar, asegúrate de tener instaladas las siguientes herramientas:

1.  **Google Cloud SDK (`gcloud`):**
    *   Debe estar instalado y en el PATH.
    *   [Guía de instalación](https://cloud.google.com/sdk/docs/install)
2.  **Remmina:**
    *   Cliente de escritorio remoto. Soporta versión nativa (`apt/dnf`) o Flatpak (`org.remmina.Remmina`).
    *   `sudo apt install remmina`
3.  **Flutter SDK:**
    *   Canal Stable.
    *   [Guía de instalación](https://docs.flutter.dev/get-started/install/linux)
4.  **Rust & Cargo:**
    *   `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
5.  **Dependencias de desarrollo Linux:**
    *   `sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`

## 🚀 Compilación e Instalación

Sigue estos pasos para clonar y ejecutar el proyecto:

### 1. Clonar el repositorio
```bash
git clone https://github.com/tu-usuario/linux_cloud_connector.git
cd linux_cloud_connector
```

### 2. Instalar dependencias
```bash
# Dependencias de Flutter
flutter pub get

# Instalar generador de código (solo necesario la primera vez)
cargo install flutter_rust_bridge_codegen
```

### 3. Generar Código del Puente (Bridge)
Este paso conecta Rust con Flutter. Ejecútalo si modificas código en `native/`.
```bash
flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root native --dart-output lib/src/bridge/api.dart
```

### 4. Ejecutar en modo Debug
```bash
flutter run -d linux
```

### 5. Compilar Release (Binario optimizado)
```bash
flutter build linux --release
```
El ejecutable estará en `build/linux/x64/release/bundle/linux_cloud_connector`.

## 🏗️ Arquitectura

*   **Frontend:** Flutter (Dart) + Riverpod (State Management).
*   **Backend:** Rust (Crate `native`).
*   **Bridge:** `flutter_rust_bridge` comunica Dart y Rust mediante FFI.
*   **External Tools:** Orquesta `gcloud` y `remmina` como subprocesos.

## 🍎 Nota sobre compatibilidad con macOS

El código base (Flutter + Rust) es multiplataforma, por lo que este proyecto podría compilarse para **macOS (Intel & Apple Silicon)** con algunos ajustes específicos:

1.  **RDP Launcher:** La lógica actual (`native/src/remmina.rs`) está diseñada para Linux (`remmina`). Para macOS, deberías usar compilación condicional e invocar el comando `open` con la URI `rdp://localhost:PUERTO` para lanzar *Microsoft Remote Desktop*.
2.  **Build System:** Debes habilitar el soporte (`flutter config --enable-macos-desktop`) y configurar Xcode para compilar y enlazar la librería dinámica de Rust (`.dylib`) en lugar de usar CMake.
3.  **Entorno:** Es posible que necesites especificar la ruta absoluta de `gcloud` (ej: `/opt/homebrew/bin/gcloud`) ya que las aplicaciones gráficas en macOS no siempre heredan el PATH de la shell.

> **Nota del Desarrollador:** *Lamentablemente no cuento con una Mac para probar o mantener esta implementación, pero en teoría, realizando los cambios mencionados debería funcionar perfectamente. ¡Buena suerte!* 🍀

## 🤝 Contribución

Las contribuciones son bienvenidas. Por favor, asegúrate de actualizar los tests y ejecutar el generador de código (`flutter_rust_bridge_codegen`) si modificas la lógica de Rust.

## 📄 Licencia

Este proyecto está bajo la licencia MIT.
