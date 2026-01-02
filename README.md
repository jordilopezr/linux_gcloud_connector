# Linux Cloud Connector (LCC) ☁️🐧

**Linux Cloud Connector** es una aplicación de escritorio nativa para Linux diseñada para simplificar y asegurar la conexión a instancias de Google Cloud Platform (GCP) mediante **Identity-Aware Proxy (IAP)**.

Desarrollada por **Jordi Lopez Reyes** con **Flutter** y **Rust** para un rendimiento y seguridad óptimos.

![Status](https://img.shields.io/badge/Status-Stable%20v1.9.0-brightgreen)
![Platform](https://img.shields.io/badge/Platform-Linux-blue)
![License](https://img.shields.io/badge/License-MIT-purple)
![Security](https://img.shields.io/badge/Security-Hardened-success)
![Multi-Tunnel](https://img.shields.io/badge/Multi--Tunnel-Enabled-blue)
![Metrics](https://img.shields.io/badge/Instance%20Metrics-Enabled-orange)
![SFTP](https://img.shields.io/badge/SFTP-Enabled-green)
![API](https://img.shields.io/badge/Client%20Libraries-Integrated-blue)
![Notifications](https://img.shields.io/badge/Notifications-Enabled-yellow)

<img width="1024" height="768" alt="image" src="https://github.com/user-attachments/assets/b510f43b-2a42-462b-9a4e-bfe8618068a5" />

## ✨ Características Clave

### 🔔 Sistema de Notificaciones Desktop (v1.9.0) - NUEVO
*   **📬 Notificaciones Nativas:** Notificaciones desktop de Linux para eventos importantes
*   **🔄 Cambios de Estado VM:** Alertas automáticas cuando VMs cambian de RUNNING ↔ STOPPED
*   **⚠️ Alertas de Túneles IAP:** Notificación inmediata cuando un túnel se cae inesperadamente
*   **✅ Lifecycle Operations:** Notificaciones de éxito/fallo en start/stop/reset
*   **⚙️ Configuración Flexible:** Habilitar/deshabilitar notificaciones desde Settings
*   **🎨 Iconos y Acciones:** Notificaciones con iconos contextuales y acciones rápidas

### ⚙️ Configuración Personalizable (v1.9.0) - NUEVO
*   **🎛️ Settings Dialog:** Panel de configuración completo y organizado
*   **⏱️ Intervalos de Auto-Refresh:** 10s, 30s, 60s, 120s, 300s, o personalizado (5-600s)
*   **🔕 Control de Notificaciones:** Activar/desactivar notificaciones desktop
*   **💾 Persistencia:** Todas las configuraciones se guardan entre sesiones
*   **🎯 UI Intuitiva:** Interfaz clara con explicaciones y validación en tiempo real

### ⚡ Google Cloud Client Libraries Integration (v1.8.0)
*   **🚀 Dual API Support:** Alterna entre gcloud CLI y Google Cloud Client Libraries (REST API)
*   **📊 Performance Boost:** Client Libraries son 1.3-1.5x más rápidas que CLI (sin overhead de procesos)
*   **🔄 Smart Switching:** Toggle en AppBar para cambiar entre métodos en tiempo real
*   **💾 Persistent Preferences:** La selección de método API se guarda entre sesiones
*   **🧪 Testing Suite:** Screen dedicado con 3 tabs para comparar performance y funcionalidad
*   **📈 Real-time Benchmarks:** Compara tiempos de ejecución y calcula speedups automáticamente
*   **🎯 Unified Interface:** Misma UI funciona con ambos métodos transparentemente

### 🔄 Auto-Refresh Inteligente (v1.8.0) - NUEVO
*   **⏱️ Polling Automático:** Refresca lista de instancias cada 30 segundos (configurable)
*   **🔔 State Change Detection:** Detecta y loguea cambios de estado (RUNNING ↔ STOPPED)
*   **⚡ Client Libraries Optimized:** Usa REST API cuando está habilitado para menor latencia
*   **🎛️ UI Toggle:** Botón en AppBar con indicador visual (verde = activo)
*   **💚 Smart Monitoring:** Solo refresca cuando hay proyecto seleccionado
*   **🛡️ Memory Safe:** Timer se cancela automáticamente al cerrar la app

### 🖥️ VM Lifecycle Management (v1.8.0) - NUEVO
*   **▶️ Start Instances:** Inicia VMs detenidas con un click
*   **⏹️ Stop Instances:** Detiene VMs en ejecución de forma segura
*   **🔄 Reset Instances:** Reinicia VMs (hard reset) para troubleshooting
*   **⚡ Dual Method Support:** Usa CLI o Client Libraries según la configuración
*   **📊 Status Indicators:** Botones habilitados/deshabilitados según estado de VM
*   **⏳ Progress Feedback:** SnackBars informativos durante operaciones (30-120s)

### 🧪 Enhanced Testing Suite (v1.8.0) - NUEVO
*   **📑 Tab-Based Organization:** 3 tabs (API Testing, Lifecycle Ops, Performance Stats)
*   **🔬 Comprehensive Tests:** Auth, Projects, Instances, Lifecycle operations
*   **📊 Performance Metrics:** Speedup calculations, improvement percentages
*   **⚖️ Side-by-Side Comparisons:** CLI vs Client Libraries en paralelo
*   **🎯 "Run All Tests" Button:** Ejecuta todos los benchmarks con un click
*   **📈 Visual Analytics:** Métricas cards con iconos y colores diferenciados

### 📊 Enhanced Instance Metrics (v1.8.0)
*   **💾 Información de Recursos:** CPU, RAM y Disco con parser inteligente mejorado
*   **🎯 Universal Machine Types:** Soporta todas las series de GCP (E2, N1, N2, N2D, C2, C3, T2D, M1/M2/M3, A2)
*   **🔍 Pattern Recognition:** Parsea tipos estándar (`{serie}-{tipo}-{cpus}`) automáticamente
*   **📐 Ratio-Based Calculation:** Memoria calculada según serie (e.g., N1: 3.75GB/vCPU, E2: 4GB/vCPU)
*   **🌐 Custom & Special Types:** Soporta micro, small, medium, y custom machine types
*   **✨ No API Calls Needed:** Parser local elimina latencia de lookups remotos

### 📁 SFTP File Transfer Browser (v1.7.0)
*   **🗂️ Navegador de Archivos:** Interfaz gráfica completa para explorar archivos remotos vía SFTP
*   **⬆️ Upload Files:** Sube archivos locales a la instancia remota con progreso visual
*   **⬇️ Download Files:** Descarga archivos desde la instancia a tu máquina local
*   **📂 Directory Management:** Crea nuevas carpetas y elimina archivos/directorios remotos
*   **🔒 Secure Transfer:** Conexiones SFTP sobre túneles SSH IAP (puerto 22)
*   **🔄 Auto-Tunnel:** Crea automáticamente túnel SSH si no existe al abrir el navegador
*   **🎨 File Type Icons:** Iconos diferenciados por tipo de archivo (documentos, imágenes, código, etc.)
*   **📏 Size Formatting:** Formateo automático de tamaños (B, KB, MB, GB)
*   **❌ Error Handling:** Mensajes de error claros y manejables con opción de reintentar

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
*   **💾 Persistencia:** Recuerda tu último proyecto seleccionado, método API y configuración.
*   **🔒 Auth Integration:** Login integrado con Google Cloud (`gcloud auth login`).
*   **🛡️ IAP Multi-Tunneling:** Gestión automática de túneles TCP ilimitados por VM con monitoreo de salud independiente.
*   **🖥️ Smart RDP:** Lanza **Remmina** automáticamente con configuraciones avanzadas (pantalla completa, resolución).
*   **💻 SSH Support:** Detecta tu terminal favorita (`gnome-terminal`, `konsole`, etc.) y lanza sesiones SSH nativas.
*   **⚡ Native Backend:** Lógica crítica escrita en Rust para máxima velocidad y seguridad.

## 🔗 Repositorio y Contacto

*   **Código Fuente:** [https://github.com/jordilopezr/linux_gcloud_connector](https://github.com/jordilopezr/linux_gcloud_connector)
*   **Desarrollador:** Jordi Lopez Reyes
*   **Email:** [aim@jordilopezr.com](mailto:aim@jordilopezr.com)

## ☕ Apoya el Desarrollo

Si encuentras útil esta herramienta y quieres apoyar su desarrollo continuo, considera invitarme un café:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support%20Development-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/jordimlopezr)

**🌟 [buymeacoffee.com/jordimlopezr](https://buymeacoffee.com/jordimlopezr)**

Tu apoyo ayuda a:
- ✨ Desarrollar nuevas características
- 🐛 Corregir bugs y mejorar la estabilidad
- 📚 Mantener la documentación actualizada
- 🚀 Mejorar el rendimiento y la experiencia de usuario

¡Cualquier contribución es muy apreciada! 💙

## 🛠️ Requisitos del Sistema

1.  **Google Cloud SDK (`gcloud`):** Instalado y en el PATH.
2.  **Remmina:** Cliente RDP (Nativo o Flatpak).
3.  **Librerías del Sistema:** `libsecret-1-dev`, `libjsoncpp-dev` (para almacenamiento seguro).
4.  **SSH Agent:** Para autenticación SFTP (usualmente ya incluido en distribuciones Linux modernas).
5.  **Application Default Credentials:** Para usar Client Libraries (opcional, requiere `gcloud auth application-default login`).

## 🚀 Compilación e Instalación

### 1. Clonar
```bash
git clone https://github.com/jordilopezr/linux_gcloud_connector.git
cd linux_gcloud_connector
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

### 5. (Opcional) Habilitar Client Libraries
Para usar Google Cloud Client Libraries en lugar de gcloud CLI:
```bash
# Configurar Application Default Credentials
gcloud auth application-default login

# Dentro de la app, usa el toggle en el AppBar para cambiar entre CLI y Client Libraries
```

## 📊 Performance Comparison

| Operación | gcloud CLI | Client Libraries | Mejora |
|-----------|------------|------------------|--------|
| List Projects | ~200ms | ~150ms | **1.3x más rápido** |
| List Instances | ~300ms | ~220ms | **1.4x más rápido** |
| Start/Stop/Reset | ~2-5s | ~1.5-4s | **1.2x más rápido** |

*Benchmarks medidos en sistema con conexión estable y autenticación previa.*

## 🎯 Roadmap

### v2.0.0 (Planeado)
- [ ] Historial de conexiones recientes
- [ ] Modo oscuro (Dark Mode)
- [ ] Búsqueda avanzada y filtros múltiples
- [ ] Dashboard de métricas de Cloud Monitoring API
- [ ] Soporte para múltiples cuentas GCP
- [ ] Operaciones adicionales de Compute Engine (resize, attach disk, snapshots)

### v1.9.0 (Actual) ✅
- [x] Sistema de notificaciones desktop
- [x] Configuración personalizable de auto-refresh
- [x] Settings dialog con preferencias persistentes
- [x] Notificaciones de cambios de estado de VMs
- [x] Notificaciones de túneles IAP caídos
- [x] Notificaciones de lifecycle operations

### v1.8.0 ✅
- [x] Google Cloud Client Libraries integration
- [x] API method toggle (CLI vs Client Libraries)
- [x] Auto-refresh inteligente con detección de cambios
- [x] VM lifecycle management (start/stop/reset)
- [x] Enhanced testing suite con 3 tabs
- [x] Improved CPU/RAM parsing para todos los machine types

## 🍎 Nota sobre macOS

Este proyecto es compatible con macOS (Intel/Silicon) con ajustes mínimos en el lanzador RDP (usando `open` en lugar de `remmina`) y en la configuración de Xcode.

## 🤝 Contribuciones

Las contribuciones son bienvenidas! Por favor:
1. Fork el repositorio
2. Crea una feature branch (`git checkout -b feature/amazing-feature`)
3. Commit tus cambios (`git commit -m 'Add amazing feature'`)
4. Push a la branch (`git push origin feature/amazing-feature`)
5. Abre un Pull Request

## 📝 Changelog

### v1.9.0 (2026-01-02)
- 🔔 Sistema de notificaciones desktop para eventos de VMs y túneles
- ⚙️ Configuración personalizable de intervalos de auto-refresh (10s-600s)
- 🎛️ Settings dialog completo con preferencias persistentes
- 📬 Notificaciones de cambios de estado (RUNNING ↔ STOPPED)
- ⚠️ Alertas automáticas de túneles IAP caídos
- ✅ Notificaciones de lifecycle operations (start/stop/reset)
- 💾 Persistencia de todas las configuraciones del usuario
- 🎨 UI mejorada con validación en tiempo real

### v1.8.0 (2025-12-27)
- ✨ Google Cloud Client Libraries integration con dual API support
- ⚡ Auto-refresh inteligente para instance monitoring (30s interval)
- 🖥️ VM lifecycle management (start/stop/reset) con dual method support
- 🧪 Enhanced testing suite con 3 tabs y benchmarks visuales
- 📊 Improved CPU/RAM parsing para todos los machine types de GCP
- 💾 Persistencia de método API y preferencias del usuario
- 🎯 Performance improvements de 1.3-1.5x con Client Libraries

### v1.7.1 (2025-01-15)
- 🗂️ Native SFTP browser con upload/download/delete
- 🔄 Auto-tunnel creation para SFTP
- 🎨 File type icons y size formatting

### v1.7.0 (2025-01-10)
- 📁 SFTP File Transfer browser completo
- ⬆️⬇️ Upload/Download con progreso visual
- 📂 Directory management (create/delete)

### v1.6.0 (2025-01-05)
- 📊 Instance resource metrics (CPU/RAM/Disk)
- 🎯 Machine type intelligence

### v1.5.0 (2024-12-20)
- 🔌 Generic port forwarding
- ♾️ Multi-tunnel support por VM
- 🎛️ Custom tunnel dialog con presets

---
La documentación ha sido revisada y optimizada utilizando Claude de Anthropic
---
© 2025 Jordi Lopez Reyes. Distribuido bajo licencia MIT.
