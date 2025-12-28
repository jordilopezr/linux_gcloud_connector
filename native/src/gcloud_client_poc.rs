/// Google Cloud Client Libraries - Proof of Concept
///
/// Este módulo demuestra el uso de Google Cloud Client Libraries
/// en lugar de gcloud CLI para interactuar con GCP.
///
/// Objetivo del PoC:
/// 1. Autenticación con OAuth2
/// 2. Listar proyectos usando Resource Manager API
/// 3. Comparar performance vs gcloud CLI

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::time::Instant;
use std::path::PathBuf;
use std::env;
use tracing::{info, debug, error};

// ==========================================
// AUTENTICACIÓN - Versión Simplificada
// ==========================================

/// Gestor de autenticación para Google Cloud
///
/// Usa gcloud Application Default Credentials existentes
pub struct GcpAuthClient {
    credentials_path: PathBuf,
}

impl GcpAuthClient {
    /// Inicializar cliente de autenticación
    /// Usa las credenciales que ya tiene gcloud configuradas
    pub async fn new() -> Result<Self> {
        info!("🔐 Initializing GCP authentication (using gcloud ADC)");

        // Buscar credenciales en ~/.config/gcloud/application_default_credentials.json
        let home = env::var("HOME")
            .or_else(|_| env::var("USERPROFILE"))
            .map_err(|_| anyhow!("Could not determine home directory"))?;

        let creds_path = PathBuf::from(home)
            .join(".config")
            .join("gcloud")
            .join("application_default_credentials.json");

        if !creds_path.exists() {
            return Err(anyhow!(
                "Application Default Credentials not found.\n\n\
                 Please run: gcloud auth application-default login\n\
                 \n\
                 This will create credentials at:\n\
                 {}",
                creds_path.display()
            ));
        }

        info!("✓ Found credentials at: {}", creds_path.display());

        Ok(Self {
            credentials_path: creds_path,
        })
    }

    /// Obtener access token usando yup-oauth2
    pub async fn get_access_token(&self) -> Result<String> {
        debug!("Getting access token from gcloud credentials");

        // Leer el archivo de credenciales
        let creds_json = std::fs::read_to_string(&self.credentials_path)
            .map_err(|e| anyhow!("Failed to read credentials: {}", e))?;

        // Parse credentials
        let creds: serde_json::Value = serde_json::from_str(&creds_json)?;

        // Para este PoC, vamos a usar el refresh token para obtener un access token
        // usando la API de OAuth2 directamente
        let client_id = creds["client_id"].as_str()
            .ok_or_else(|| anyhow!("No client_id in credentials"))?;
        let client_secret = creds["client_secret"].as_str()
            .ok_or_else(|| anyhow!("No client_secret in credentials"))?;
        let refresh_token = creds["refresh_token"].as_str()
            .ok_or_else(|| anyhow!("No refresh_token in credentials"))?;

        debug!("Using OAuth2 credentials to get access token");

        // Usar reqwest para hacer el token exchange
        let client = reqwest::Client::new();
        let params = [
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("refresh_token", refresh_token),
            ("grant_type", "refresh_token"),
        ];

        let response = client
            .post("https://oauth2.googleapis.com/token")
            .form(&params)
            .send()
            .await
            .map_err(|e| anyhow!("Token request failed: {}", e))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            // SECURITY: Log full error for debugging but return sanitized error to user
            debug!("Token exchange failed with error: {}", error_text);
            return Err(anyhow!("Authentication failed. Please try logging in again with: gcloud auth application-default login"));
        }

        let token_response: serde_json::Value = response.json().await?;
        let access_token = token_response["access_token"].as_str()
            .ok_or_else(|| anyhow!("No access_token in response"))?
            .to_string();

        debug!("✓ Got valid access token");
        Ok(access_token)
    }
}

// ==========================================
// RESOURCE MANAGER API - PROYECTOS
// ==========================================

/// Google Cloud Project (Client Library version)
/// This struct is used by the Client Libraries implementation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GcpProjectClientLib {
    pub project_id: String,
    pub name: Option<String>,
    pub project_number: String,
    pub state: String,
}

// Keep internal version for backwards compatibility
type GcpProject = GcpProjectClientLib;

/// Google Cloud Compute Instance (Client Library version)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GcpInstanceClientLib {
    pub name: String,
    pub status: String,
    pub zone: String,
    pub machine_type: String,
    pub cpu_count: Option<u32>,
    pub memory_mb: Option<u32>,
    pub disk_gb: Option<u32>,
}

/// Cliente para interactuar con Resource Manager API
pub struct ResourceManagerClient {
    auth: GcpAuthClient,
    base_url: String,
}

impl ResourceManagerClient {
    pub async fn new() -> Result<Self> {
        let auth = GcpAuthClient::new().await?;

        Ok(Self {
            auth,
            base_url: "https://cloudresourcemanager.googleapis.com/v1".to_string(),
        })
    }

    /// Listar todos los proyectos accesibles
    ///
    /// ANTES (gcloud CLI):
    /// ```
    /// gcloud projects list --format=json
    /// ```
    ///
    /// AHORA (Client Library):
    /// Hace request directo a Resource Manager API
    pub async fn list_projects(&self) -> Result<Vec<GcpProject>> {
        info!("📁 Listing GCP projects via REST API");
        let start = Instant::now();

        // Obtener access token
        let token = self.auth.get_access_token().await?;

        // Crear HTTP client
        let client = reqwest::Client::new();

        // Request a la API
        let url = format!("{}/projects", self.base_url);

        debug!("Making request to: {}", url);

        let response = client
            .get(&url)
            .bearer_auth(&token)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send request: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            error!("API request failed: {} - {}", status, error_text);
            return Err(anyhow!("API error {}: {}", status, error_text));
        }

        // Parse response
        let response_text = response.text().await?;
        debug!("Response received: {} bytes", response_text.len());

        let response_json: serde_json::Value = serde_json::from_str(&response_text)
            .map_err(|e| anyhow!("Failed to parse JSON: {}", e))?;

        // Extraer proyectos del response (API v1 format)
        let projects_array = response_json["projects"]
            .as_array()
            .ok_or_else(|| anyhow!("No projects array in response"))?;

        let mut projects = Vec::new();

        for project_obj in projects_array {
            projects.push(GcpProject {
                project_id: project_obj["projectId"]
                    .as_str()
                    .unwrap_or_default()
                    .to_string(),
                name: project_obj["name"]
                    .as_str()
                    .map(|s| s.to_string()),
                project_number: project_obj["projectNumber"]
                    .as_u64()
                    .map(|n| n.to_string())
                    .or_else(|| project_obj["projectNumber"].as_str().map(|s| s.to_string()))
                    .unwrap_or_default(),
                state: project_obj["lifecycleState"]
                    .as_str()
                    .unwrap_or("UNKNOWN")
                    .to_string(),
            });
        }

        let elapsed = start.elapsed();
        info!(
            "✓ Listed {} projects in {:?} (Client Library)",
            projects.len(),
            elapsed
        );

        Ok(projects)
    }
}

// ==========================================
// FUNCIONES PÚBLICAS PARA FFI BRIDGE
// ==========================================

/// Comparar performance: Client Library vs gcloud CLI (async version)
pub async fn benchmark_list_projects_async() -> Result<String> {
    info!("🏁 Starting benchmark: Client Library vs gcloud CLI");

    // Benchmark 1: Client Library
    info!("\n=== Test 1: Google Cloud Client Library ===");
    let start_client = Instant::now();

    let client = ResourceManagerClient::new().await?;
    let projects_client = client.list_projects().await?;

    let time_client = start_client.elapsed();
    info!("✓ Client Library: {} projects in {:?}", projects_client.len(), time_client);

    // Benchmark 2: gcloud CLI (para comparación)
    info!("\n=== Test 2: gcloud CLI (existing implementation) ===");
    let start_cli = Instant::now();

    let projects_cli = crate::gcloud::get_projects_async().await?;

    let time_cli = start_cli.elapsed();
    info!("✓ gcloud CLI: {} projects in {:?}", projects_cli.len(), time_cli);

    // Calcular mejora
    let speedup = time_cli.as_secs_f64() / time_client.as_secs_f64();

    let result = format!(
        "📊 BENCHMARK RESULTS\n\
         ==================\n\
         \n\
         Client Library: {:?}\n\
         gcloud CLI:     {:?}\n\
         \n\
         Speed improvement: {:.2}x faster 🚀\n\
         \n\
         Projects found:\n\
         - Client Library: {} projects\n\
         - gcloud CLI:     {} projects\n\
         \n\
         {} Match: {}",
        time_client,
        time_cli,
        speedup,
        projects_client.len(),
        projects_cli.len(),
        if projects_client.len() == projects_cli.len() { "✅" } else { "⚠️" },
        if projects_client.len() == projects_cli.len() {
            "Results are consistent!"
        } else {
            "Warning: Different number of projects"
        }
    );

    info!("\n{}", result);
    Ok(result)
}

/// Test simple de autenticación (async version)
pub async fn test_authentication_async() -> Result<String> {
    info!("🔐 Testing GCP authentication");

    let auth = GcpAuthClient::new().await?;
    let token = auth.get_access_token().await?;

    // Verificar que el token no está vacío
    if token.is_empty() {
        return Err(anyhow!("Received empty access token"));
    }

    let message = "✅ Authentication successful!\n\
         \n\
         You are now authenticated with Google Cloud!".to_string();

    info!("{}", message);
    debug!("Token received, length: {} characters", token.len());
    Ok(message)
}

/// Listar proyectos (interfaz simplificada para FFI)
pub async fn list_projects_simple_async() -> Result<Vec<GcpProject>> {
    let client = ResourceManagerClient::new().await?;
    client.list_projects().await
}

// ==========================================
// COMPUTE ENGINE API - INSTANCIAS
// ==========================================

/// Extract CPU and memory specs from machine type name
/// Supports standard machine types by parsing their pattern (e.g., "e2-standard-4" → 4 CPUs)
/// Returns (cpu_count, memory_mb) if the machine type can be determined
fn get_machine_specs(machine_type: &str) -> Option<(u32, u32)> {
    // Special cases (micro, small, medium)
    match machine_type {
        "e2-micro" => return Some((2, 1024)),
        "e2-small" => return Some((2, 2048)),
        "e2-medium" => return Some((2, 4096)),
        "f1-micro" => return Some((1, 614)),
        "g1-small" => return Some((1, 1740)),
        _ => {}
    }

    // Parse standard machine types: {series}-{type}-{cpus}
    // Examples: e2-standard-4, n1-standard-8, n2-highmem-16, c2-standard-30
    let parts: Vec<&str> = machine_type.split('-').collect();

    if parts.len() >= 3 {
        let series = parts[0];      // e2, n1, n2, n2d, c2, c3, t2d, etc.
        let type_name = parts[1];   // standard, highmem, highcpu, custom

        // Try to parse CPU count from the last part
        if let Ok(cpu_count) = parts[2].parse::<u32>() {
            // Calculate memory based on type and series
            let memory_mb = match (series, type_name) {
                // E2 series (cost-optimized): 4GB per vCPU for standard
                ("e2", "standard") => cpu_count * 4096,
                ("e2", "highmem") => cpu_count * 8192,
                ("e2", "highcpu") => cpu_count * 1024,

                // N1 series: 3.75GB per vCPU for standard
                ("n1", "standard") => cpu_count * 3840,
                ("n1", "highmem") => cpu_count * 6656,
                ("n1", "highcpu") => cpu_count * 922,

                // N2/N2D series: 4GB per vCPU for standard
                ("n2" | "n2d", "standard") => cpu_count * 4096,
                ("n2" | "n2d", "highmem") => cpu_count * 8192,
                ("n2" | "n2d", "highcpu") => cpu_count * 1024,

                // C2 series (compute-optimized): 4GB per vCPU
                ("c2", "standard") => cpu_count * 4096,

                // C3 series (newer compute): 4GB per vCPU
                ("c3", "standard") => cpu_count * 4096,
                ("c3", "highmem") => cpu_count * 8192,
                ("c3", "highcpu") => cpu_count * 2048,

                // T2D series (AMD): 4GB per vCPU
                ("t2d", "standard") => cpu_count * 4096,

                // M1/M2/M3 series (memory-optimized): Much higher memory
                ("m1", "megamem") => cpu_count * 14336,  // 14GB per vCPU
                ("m1", "ultramem") => cpu_count * 24576, // 24GB per vCPU
                ("m2", "megamem") => cpu_count * 14336,
                ("m2", "ultramem") => cpu_count * 24576,
                ("m3", "megamem") => cpu_count * 14336,
                ("m3", "ultramem") => cpu_count * 24576,

                // A2 series (GPU): 12GB per vCPU
                ("a2", _) => cpu_count * 12288,

                // Default fallback: assume 4GB per vCPU (most common)
                _ => cpu_count * 4096,
            };

            return Some((cpu_count, memory_mb));
        }
    }

    // If we can't parse it, return None
    None
}

/// Cliente para interactuar con Compute Engine API
pub struct ComputeEngineClient {
    auth: GcpAuthClient,
    base_url: String,
}

impl ComputeEngineClient {
    pub async fn new() -> Result<Self> {
        let auth = GcpAuthClient::new().await?;

        Ok(Self {
            auth,
            base_url: "https://compute.googleapis.com/compute/v1".to_string(),
        })
    }

    /// Listar todas las instancias en un proyecto
    ///
    /// ANTES (gcloud CLI):
    /// ```
    /// gcloud compute instances list --project=PROJECT_ID --format=json
    /// ```
    ///
    /// AHORA (Client Library):
    /// GET https://compute.googleapis.com/compute/v1/projects/{project}/aggregatedList/instances
    pub async fn list_instances(&self, project: &str) -> Result<Vec<GcpInstanceClientLib>> {
        info!("🖥️  Listing instances for project: {}", project);
        let start = Instant::now();

        // Obtener access token
        let token = self.auth.get_access_token().await?;

        // Crear HTTP client
        let client = reqwest::Client::new();

        // Request a la API (aggregatedList para obtener de todas las zonas)
        let url = format!("{}/projects/{}/aggregated/instances", self.base_url, project);

        debug!("Making request to: {}", url);

        let response = client
            .get(&url)
            .bearer_auth(&token)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send request: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            error!("API request failed: {} - {}", status, error_text);
            return Err(anyhow!("API error {}: {}", status, error_text));
        }

        // Parse response
        let response_text = response.text().await?;
        debug!("Response received: {} bytes", response_text.len());

        let response_json: serde_json::Value = serde_json::from_str(&response_text)
            .map_err(|e| anyhow!("Failed to parse JSON: {}", e))?;

        // Extraer instancias del response (aggregatedList format)
        let mut instances = Vec::new();

        if let Some(items) = response_json["items"].as_object() {
            for (_zone_name, zone_data) in items {
                if let Some(zone_instances) = zone_data["instances"].as_array() {
                    for instance_obj in zone_instances {
                        let name = instance_obj["name"]
                            .as_str()
                            .unwrap_or_default()
                            .to_string();

                        let status = instance_obj["status"]
                            .as_str()
                            .unwrap_or("UNKNOWN")
                            .to_string();

                        // Extract zone from URL (e.g., "zones/us-central1-a" -> "us-central1-a")
                        let zone = instance_obj["zone"]
                            .as_str()
                            .and_then(|z| z.split('/').last())
                            .unwrap_or_default()
                            .to_string();

                        // Extract machine type from URL
                        let machine_type = instance_obj["machineType"]
                            .as_str()
                            .and_then(|mt| mt.split('/').last())
                            .unwrap_or_default()
                            .to_string();

                        // Extract disk size from boot disk
                        let disk_gb = instance_obj["disks"]
                            .as_array()
                            .and_then(|disks| {
                                disks.iter()
                                    .find(|d| d["boot"].as_bool().unwrap_or(false))
                                    .or_else(|| disks.first())
                            })
                            .and_then(|disk| disk["diskSizeGb"].as_str())
                            .and_then(|size| size.parse::<u32>().ok());

                        // Extract CPU and memory from machine type name
                        let (cpu_count, memory_mb) = get_machine_specs(&machine_type)
                            .map(|(cpu, mem)| (Some(cpu), Some(mem)))
                            .unwrap_or((None, None));

                        instances.push(GcpInstanceClientLib {
                            name,
                            status,
                            zone,
                            machine_type,
                            cpu_count,
                            memory_mb,
                            disk_gb,
                        });
                    }
                }
            }
        }

        let elapsed = start.elapsed();
        info!(
            "✓ Listed {} instances in {:?} (Client Library)",
            instances.len(),
            elapsed
        );

        Ok(instances)
    }

    /// Iniciar una instancia detenida
    ///
    /// ANTES (gcloud CLI):
    /// ```
    /// gcloud compute instances start INSTANCE --zone=ZONE --project=PROJECT
    /// ```
    ///
    /// AHORA (Client Library):
    /// POST https://compute.googleapis.com/compute/v1/projects/{project}/zones/{zone}/instances/{instance}/start
    pub async fn start_instance(&self, project: &str, zone: &str, instance: &str) -> Result<()> {
        info!("▶️  Starting instance: {} in {}/{}", instance, project, zone);

        let token = self.auth.get_access_token().await?;
        let client = reqwest::Client::new();

        let url = format!(
            "{}/projects/{}/zones/{}/instances/{}/start",
            self.base_url, project, zone, instance
        );

        let response = client
            .post(&url)
            .bearer_auth(&token)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send request: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("API error {}: {}", status, error_text));
        }

        info!("✓ Instance start operation initiated");
        Ok(())
    }

    /// Detener una instancia en ejecución
    ///
    /// POST https://compute.googleapis.com/compute/v1/projects/{project}/zones/{zone}/instances/{instance}/stop
    pub async fn stop_instance(&self, project: &str, zone: &str, instance: &str) -> Result<()> {
        info!("⏹️  Stopping instance: {} in {}/{}", instance, project, zone);

        let token = self.auth.get_access_token().await?;
        let client = reqwest::Client::new();

        let url = format!(
            "{}/projects/{}/zones/{}/instances/{}/stop",
            self.base_url, project, zone, instance
        );

        let response = client
            .post(&url)
            .bearer_auth(&token)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send request: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("API error {}: {}", status, error_text));
        }

        info!("✓ Instance stop operation initiated");
        Ok(())
    }

    /// Reiniciar una instancia
    ///
    /// POST https://compute.googleapis.com/compute/v1/projects/{project}/zones/{zone}/instances/{instance}/reset
    pub async fn reset_instance(&self, project: &str, zone: &str, instance: &str) -> Result<()> {
        info!("🔄 Resetting instance: {} in {}/{}", instance, project, zone);

        let token = self.auth.get_access_token().await?;
        let client = reqwest::Client::new();

        let url = format!(
            "{}/projects/{}/zones/{}/instances/{}/reset",
            self.base_url, project, zone, instance
        );

        let response = client
            .post(&url)
            .bearer_auth(&token)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("Failed to send request: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("API error {}: {}", status, error_text));
        }

        info!("✓ Instance reset operation initiated");
        Ok(())
    }
}

/// List instances using Client Libraries (public API for FFI)
pub async fn list_instances_client_lib(project: &str) -> Result<Vec<GcpInstanceClientLib>> {
    let client = ComputeEngineClient::new().await?;
    client.list_instances(project).await
}

/// Start instance using Client Libraries (public API for FFI)
pub async fn start_instance_client_lib(project: &str, zone: &str, instance: &str) -> Result<()> {
    let client = ComputeEngineClient::new().await?;
    client.start_instance(project, zone, instance).await
}

/// Stop instance using Client Libraries (public API for FFI)
pub async fn stop_instance_client_lib(project: &str, zone: &str, instance: &str) -> Result<()> {
    let client = ComputeEngineClient::new().await?;
    client.stop_instance(project, zone, instance).await
}

/// Reset instance using Client Libraries (public API for FFI)
pub async fn reset_instance_client_lib(project: &str, zone: &str, instance: &str) -> Result<()> {
    let client = ComputeEngineClient::new().await?;
    client.reset_instance(project, zone, instance).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_auth_initialization() {
        let result = GcpAuthClient::new().await;
        assert!(result.is_ok(), "Authentication should succeed");
    }

    #[tokio::test]
    async fn test_get_access_token() {
        let auth = GcpAuthClient::new().await.unwrap();
        let token = auth.get_access_token().await.unwrap();
        assert!(!token.is_empty(), "Token should not be empty");
        assert!(token.len() > 50, "Token should be substantial");
    }

    #[tokio::test]
    async fn test_list_projects() {
        let projects = list_projects_simple_async().await.unwrap();

        assert!(!projects.is_empty(), "Should have at least one project");

        for project in &projects {
            assert!(!project.project_id.is_empty(), "Project ID should not be empty");
            println!("✓ Found project: {} ({})",
                project.name.as_ref().unwrap_or(&project.project_id),
                project.project_id
            );
        }
    }

    #[tokio::test]
    async fn test_benchmark() {
        let result = benchmark_list_projects_async().await;
        assert!(result.is_ok(), "Benchmark should complete successfully");
        println!("{}", result.unwrap());
    }
}
