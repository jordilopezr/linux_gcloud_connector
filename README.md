# Linux Cloud Connector (LCC) ☁️🐧

**Linux Cloud Connector** es una aplicación de escritorio nativa para Linux diseñada para simplificar y asegurar la conexión a instancias de Google Cloud Platform (GCP) mediante **Identity-Aware Proxy (IAP)**.

Desarrollada por **Jordi Lopez Reyes** con **Flutter** y **Rust** para un rendimiento y seguridad óptimos.

![Status](https://img.shields.io/badge/Status-Stable%20v1.7.0-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-purple)
![Security](https://img.shields.io/badge/Security-Hardened-success)
![Multi-Tunnel](https://img.shields.io/badge/Multi--Tunnel-Enabled-blue)
![Metrics](https://img.shields.io/badge/Instance%20Metrics-Enabled-orange)
![SFTP](https://img.shields.io/badge/SFTP-Enabled-green)

<img width="1024" height="768" alt="image" src="https://github.com/user-attachments/assets/b510f43b-2a42-462b-9a4e-bfe8618068a5" />

## ✨ Características Clave

### 📁 SFTP File Transfer Browser (v1.7.0) - NUEVO
*   **🗂️ Navegador de Archivos:** Interfaz gráfica completa para explorar archivos remotos vía SFTP
*   **⬆️ Upload Files:** Sube archivos locales a la instancia remota con progreso visual
*   **⬇️ Download Files:** Descarga archivos desde la instancia a tu máquina local
*   **📂 Directory Management:** Crea nuevas carpetas y elimina archivos/directorios remotos
*   **🔒 Secure Transfer:** Conexiones SFTP sobre túneles SSH IAP (puerto 22)
*   **🔄 Auto-Tunnel:** Crea automáticamente túnel SSH si no existe al abrir el navegador
*   **🎨 File Type Icons:** Iconos diferenciados por tipo de archivo (documentos, imágenes, código, etc.)
*   **📏 Size Formatting:** Formateo automático de tamaños (B, KB, MB, GB)
*   **❌ Error Handling:** Mensajes de error claros y manejables con opción de reintentar

### 📊 Instance Resource Metrics (v1.6.0)
*   **💾 Información de Recursos:** Visualiza CPU, RAM y Disco de cada instancia en tiempo real
*   **🎯 Machine Type Intelligence:** Mapeo automático de tipos de máquina a especificaciones (e2-micro, n1-standard, n2, c2, etc.)
*   **📈 Dashboard Visual:** Tarjeta dedicada con chips individuales para cada métrica
*   **🔍 Detección de Disco:** Extracción automática del tamaño del disco boot desde la API de gcloud
*   **📐 Conversión Automática:** Muestra RAM en GB con conversión automática desde MB
*   **✨ Soporte Completo:** Compatible con series E2, N1, N2, N2D, C2 y más

### 🚀 Generic Port Forwarding & Multi-Tunnel (v1.5.0)
*   **🔌 Soporte Universal:** Conecta a CUALQUIER servicio TCP vía IAP (PostgreSQL, MySQL, HTTP, Redis, MongoDB, etc.)
*   **♾️ Túneles Simultáneos:** Ilimitados túneles por VM (ej: RDP + PostgreSQL + HTTP al mismo tiempo)
*   **🎛️ Custom Tunnel Dialog:** 8 presets de servicios comunes + entrada de puerto personalizado
*   **🎯 Gestión Individual:** Desconecta túneles específicos sin afectar los demás
*   **📊 Dashboard Multi-Túnel:** Visualiza todos los túneles activos con puerto remoto y estado de salud
*   **✅ Port Validation:** Validación en tiempo real (1-65535) con feedback visual

### 📊 Observabilidad y Monitoreo (v1.4.0)
*   **📝 Logging Estructurado:** Sistema persistente con rotación automática (10MB, 5 archivos)
*   **📤 Export Logs:** Botón UI para exportar logs consolidados para troubleshooting
*   **📈 Dashboard de Métricas:** Uptime, última verificación, estado de salud en tiempo real
*   **🎨 Visualización Dinámica:** Badges de estado con colores adaptativos (Verde/Naranja/Rojo)

### 🔒 Seguridad y Fiabilidad (v1.3.0)
*   **🛡️ Validación de Entradas:** Protección contra inyección de comandos mediante validación regex.
*   **⏱️ Timeouts Inteligentes:** Todos los comandos gcloud tienen timeout de 10s (evita bloqueos).
*   **💚 Monitoreo de Salud:** Verificación automática de túneles cada 30 segundos (proceso + puerto TCP).
*   **🔐 Permisos Seguros:** Archivos .remmina creados con modo 0600 (solo lectura del propietario).

### 🚀 Funcionalidad Principal
*   **🔍 Búsqueda y Filtros:** Filtra instancias por nombre y estado (Running/Stopped) en tiempo real.
*   **🔑 Gestión de Credenciales:** Guarda usuarios, contraseñas y dominios de forma segura (encriptado con `libsecret`).
*   **💾 Persistencia:** Recuerda tu último proyecto seleccionado y configuración.
*   **🔒 Auth Integration:** Login integrado con Google Cloud (`gcloud auth login`).
*   **🛡️ IAP Multi-Tunneling:** Gestión automática de túneles TCP ilimitados por VM con monitoreo de salud independiente.
*   **🖥️ Smart RDP:** Lanza **Remmina** automáticamente con configuraciones avanzadas (pantalla completa, resolución).
*   **💻 SSH Support:** Detecta tu terminal favorita (`gnome-terminal`, `konsole`, etc.) y lanza sesiones SSH nativas.
*   **⚡ Native Backend:** Lógica crítica escrita en Rust para máxima velocidad y seguridad.

## 🔗 Repositorio y Contacto

*   **Código Fuente:** [https://github.com/jordilopezr/linux_gcloud_connector](https://github.com/jordilopezr/linux_gcloud_connector)
*   **Desarrollador:** Jordi Lopez Reyes
*   **Email:** [aim@jordilopezr.com](mailto:aim@jordilopezr.com)

## 🛠️ Requisitos del Sistema

1.  **Google Cloud SDK (`gcloud`):** Instalado y en el PATH.
2.  **Remmina:** Cliente RDP (Nativo o Flatpak).
3.  **Librerías del Sistema:** `libsecret-1-dev`, `libjsoncpp-dev` (para almacenamiento seguro).
4.  **SSH Agent:** Para autenticación SFTP (usualmente ya incluido en distribuciones Linux modernas).

## 🚀 Compilación e Instalación

### 1. Clonar
```bash
git clone https://github.com/jordilopezr/linux_gcloud_connector.git
cd linux_cloud_connector
```

### 2. Preparar Entorno
```bash
# Instalar dependencias de compilación (Debian/Ubuntu)
sudo apt-get install libsecret-1-dev libjsoncpp-dev

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
La documentacion ha sido revisada y Optimizada utilizando Claude de Anthropic 
---
© 2025 Jordi Lopez Reyes. Distribuido bajo licencia MIT.
