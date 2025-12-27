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
            return Err(anyhow!("Token exchange failed: {}", error_text));
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GcpProject {
    pub project_id: String,
    pub name: Option<String>,
    pub project_number: String,
    pub state: String,
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

/// Comparar performance: Client Library vs gcloud CLI
pub async fn benchmark_list_projects() -> Result<String> {
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

    let projects_cli = crate::gcloud::get_projects()?;

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

/// Test simple de autenticación
pub async fn test_authentication() -> Result<String> {
    info!("🔐 Testing GCP authentication");

    let auth = GcpAuthClient::new().await?;
    let token = auth.get_access_token().await?;

    // Verificar que el token no está vacío
    if token.is_empty() {
        return Err(anyhow!("Received empty access token"));
    }

    let message = format!(
        "✅ Authentication successful!\n\
         \n\
         Token length: {} characters\n\
         Token prefix: {}...\n\
         \n\
         You are now authenticated with Google Cloud!",
        token.len(),
        &token[..token.len().min(20)]
    );

    info!("{}", message);
    Ok(message)
}

/// Listar proyectos (interfaz simplificada para FFI)
pub async fn list_projects_simple() -> Result<Vec<GcpProject>> {
    let client = ResourceManagerClient::new().await?;
    client.list_projects().await
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
        let client = ResourceManagerClient::new().await.unwrap();
        let projects = client.list_projects().await.unwrap();

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
        let result = benchmark_list_projects().await;
        assert!(result.is_ok(), "Benchmark should complete successfully");
        println!("{}", result.unwrap());
    }
}
