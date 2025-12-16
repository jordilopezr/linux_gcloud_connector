# PROJECT_BLUEPRINT.md

## 1. Project Overview (Visión General)
**Nombre del Proyecto:** Linux Cloud IAP Connector (LCC)
**Descripción:** Una aplicación de escritorio nativa para Linux diseñada para simplificar la conexión a instancias de Google Cloud Platform (GCP) mediante IAP (Identity-Aware Proxy).
**Objetivo Principal:** Reemplazar el flujo manual de terminal (gcloud CLI) por una interfaz gráfica segura, intuitiva y compatible con múltiples distribuciones Linux (Distro-Agnostic).
**Filosofía:** "Security First" (Seguridad ante todo) y "Wrapper Pattern" (Orquestación de herramientas probadas en lugar de reimplementación de protocolos).

---

## 2. Tech Stack Definition (Arquitectura Tecnológica)

### Frontend (UI & UX)
* **Framework:** **Flutter** (Versión Stable).
* **Lenguaje:** Dart.
* **Diseño:** Material Design 3 (Google Style).
* **State Management:** Riverpod (por su seguridad de tipos y testabilidad).
* **Justificación:** Garantiza consistencia visual en cualquier entorno de escritorio (GNOME, KDE, Tiling WMs) y facilita el desarrollo rápido de UI.

### Backend Logic (Core & Security)
* **Lenguaje:** **Rust**.
* **Rol:** Manejo de procesos del sistema, gestión de hilos para túneles, parsing seguro de JSON y lógica de negocio crítica.
* **Justificación:** Seguridad de memoria (Memory Safety), rendimiento y cero dependencia de intérpretes en el sistema del usuario.

### Integration Bridge
* **Herramienta:** **flutter_rust_bridge**.
* **Función:** Comunicación bidireccional segura entre la UI (Dart) y el Core (Rust).

### System Dependencies (External Tools)
La aplicación actuará como un orquestador seguro de las siguientes herramientas ya instaladas en el sistema:
1.  **Google Cloud SDK (`gcloud`):** Para autenticación y establecimiento del túnel IAP.
2.  **Remmina (o xfreerdp):** Cliente RDP/SSH externo que será invocado por la app.
3.  **Flatpak:** Formato de distribución y sandboxing.

---

## 3. Architecture & Security Model

### Flujo de Datos
1.  **Discovery:** Rust invoca `gcloud compute instances list --format=json`, parsea el resultado en estructuras seguras (`structs`) y lo envía a Flutter.
2.  **Tunneling:** Rust genera un subproceso (`std::process::Command`) que ejecuta `gcloud start-iap-tunnel`.
    * *Reto:* Capturar el puerto local efímero asignado por el OS o definir uno aleatorio disponible.
3.  **Connection:** Una vez el túnel está activo, Rust genera un archivo de configuración temporal (`.remmina`) apuntando a `localhost:PUERTO` y lanza el proceso de Remmina.

### Estrategia de Seguridad (Non-Negotiable)
1.  **Auth Delegation:** La app **NO** manejará credenciales de usuario directamente (usuario/contraseña). Usará el contexto de autenticación existente de `gcloud auth login` o invocará el flujo web oficial.
2.  **Zero-Persistence:** Los archivos temporales de conexión (.remmina) deben crearse en `/tmp` (o memoria) y destruirse inmediatamente después de cerrar la conexión.
3.  **Sandboxing:** El objetivo final es empaquetar en **Flatpak**, solicitando permisos explícitos solo para:
    * Red (Network).
    * IPC (Inter-Process Communication) para invocar Remmina/Gcloud.
    * Sistema de archivos (solo lectura en directorios de configuración de gcloud).

---

## 4. MVP Functional Requirements (Requisitos Mínimos)

### Fase 1: Discovery & Listado
* Detectar si `gcloud` está instalado y autenticado.
* Listar Proyectos de GCP disponibles.
* Listar Instancias (VMs) filtradas por Zona y Proyecto.
* Mostrar estado de la VM (RUNNING/STOPPED) y OS (Windows/Linux).

### Fase 2: Tunneling Engine
* Botón "Conectar" que inicie el túnel IAP en segundo plano.
* Indicador visual en la UI de que el túnel está activo.
* Gestión de errores: Si el túnel cae, notificar a la UI.

### Fase 3: RDP Integration
* Lanzamiento automático de Remmina apuntando al túnel local.
* Detección automática de credenciales (si están guardadas en gcloud) o prompt para usuario/pass de Windows.

---

## 5. Development Guidelines for AI Agents (Instrucciones para la IA)

Si estás generando código para este proyecto, sigue estas reglas estrictas:

1.  **Rust Safety:** No uses bloques `unsafe` en Rust a menos que sea estrictamente necesario y esté documentado.
2.  **Error Handling:** Usa `Result<T, E>` y `Option<T>` en Rust. Nunca uses `.unwrap()` en código de producción; maneja el error y envíalo al frontend.
3.  **Clean Code:**
    * Separa la lógica de negocio (Rust) de la presentación (Dart).
    * Usa modelos de datos tipados en ambos lados (Structs en Rust, Classes/Freezed en Dart).
4.  **No Hardcoding:** Nunca incluyas rutas absolutas (`/home/user/...`). Usa librerías estándar para detectar rutas del sistema (`dirs` crate en Rust).

---

## 6. Project Structure (Scaffold Recomendado)

```text
/linux_cloud_connector
├── android/            # (Ignorar para Linux Desktop)
├── ios/                # (Ignorar para Linux Desktop)
├── lib/                # Código Flutter (Dart)
│   ├── main.dart
│   ├── src/
│   │   ├── bridge/     # Código generado por flutter_rust_bridge
│   │   ├── features/   # instances_list, tunneling, settings
│   │   └── models/     # Modelos de datos Dart
├── native/             # Código Rust
│   ├── src/
│   │   ├── api.rs      # API expuesta a Flutter
│   │   ├── gcloud.rs   # Wrapper para comandos gcloud
│   │   └── remmina.rs  # Lógica para lanzar cliente RDP
│   └── Cargo.toml
├── linux/              # Configuración nativa Linux (CMake, etc.)
├── pubspec.yaml        # Dependencias Dart
└── PROJECT_BLUEPRINT.md
