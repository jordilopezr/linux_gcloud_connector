use std::process::Command;
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use tracing;
use crate::validation::{validate_project_id, validate_zone, validate_instance_name, sanitize_zone_from_url};
use tokio::process::Command as TokioCommand;
use tokio::time::{timeout, Duration};

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")] // gcloud JSON often uses camelCase
pub struct GcpProject {
    pub project_id: String,
    pub name: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct GcpInstance {
    pub name: String,
    pub status: String,
    pub zone: String,
    pub machine_type: String,
    pub cpu_count: Option<u32>,
    pub memory_mb: Option<u32>,
    pub disk_gb: Option<u32>,
}

#[derive(Deserialize)]
struct RawDisk {
    #[serde(rename = "diskSizeGb")]
    disk_size_gb: Option<String>,
    boot: Option<bool>,
}

#[derive(Deserialize)]
struct RawInstance {
    name: String,
    status: String,
    zone: String,
    #[serde(rename = "machineType")]
    machine_type: Option<String>,
    disks: Option<Vec<RawDisk>>,
}

pub fn is_gcloud_installed() -> bool {
    Command::new("gcloud")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn is_gcloud_authenticated() -> bool {
    let output = Command::new("gcloud")
        .args(["auth", "list", "--filter=status:ACTIVE", "--format=json"])
        .output();

    match output {
        Ok(o) => {
             if !o.status.success() { return false; }
             let stdout = String::from_utf8_lossy(&o.stdout);
             stdout.trim() != "[]"
        },
        Err(_) => false,
    }
}

/// Async version with timeout
async fn get_projects_async() -> Result<Vec<GcpProject>> {
    // 10 second timeout for listing projects
    let output = timeout(
        Duration::from_secs(10),
        TokioCommand::new("gcloud")
            .args(["projects", "list", "--format=json"])
            .output()
    )
    .await
    .map_err(|_| anyhow!("Timeout: gcloud projects list took longer than 10 seconds"))?
    .map_err(|e| anyhow!("Failed to execute gcloud: {}", e))?;

    if !output.status.success() {
        return Err(anyhow!("gcloud error: {}", String::from_utf8_lossy(&output.stderr)));
    }

    let projects: Vec<GcpProject> = serde_json::from_slice(&output.stdout)
        .map_err(|e| anyhow!("Failed to parse projects JSON: {}", e))?;
    Ok(projects)
}

/// Synchronous wrapper for FFI bridge
pub fn get_projects() -> Result<Vec<GcpProject>> {
    // Create a tokio runtime for this call
    let rt = tokio::runtime::Runtime::new()
        .map_err(|e| anyhow!("Failed to create tokio runtime: {}", e))?;
    rt.block_on(get_projects_async())
}

/// Extract CPU and memory specs from machine type name
/// Returns (cpu_count, memory_mb) if the machine type is recognized
fn get_machine_specs(machine_type: &str) -> Option<(u32, u32)> {
    match machine_type {
        // E2 series (cost-optimized)
        "e2-micro" => Some((2, 1024)),
        "e2-small" => Some((2, 2048)),
        "e2-medium" => Some((2, 4096)),
        "e2-standard-2" => Some((2, 8192)),
        "e2-standard-4" => Some((4, 16384)),
        "e2-standard-8" => Some((8, 32768)),
        "e2-standard-16" => Some((16, 65536)),
        "e2-standard-32" => Some((32, 131072)),

        // N1 series (balanced)
        "n1-standard-1" => Some((1, 3840)),
        "n1-standard-2" => Some((2, 7680)),
        "n1-standard-4" => Some((4, 15360)),
        "n1-standard-8" => Some((8, 30720)),
        "n1-standard-16" => Some((16, 61440)),
        "n1-standard-32" => Some((32, 122880)),

        // N2 series (balanced, newer)
        "n2-standard-2" => Some((2, 8192)),
        "n2-standard-4" => Some((4, 16384)),
        "n2-standard-8" => Some((8, 32768)),
        "n2-standard-16" => Some((16, 65536)),
        "n2-standard-32" => Some((32, 131072)),

        // N2D series (AMD)
        "n2d-standard-2" => Some((2, 8192)),
        "n2d-standard-4" => Some((4, 16384)),
        "n2d-standard-8" => Some((8, 32768)),

        // C2 series (compute-optimized)
        "c2-standard-4" => Some((4, 16384)),
        "c2-standard-8" => Some((8, 32768)),
        "c2-standard-16" => Some((16, 65536)),

        // Add more as needed
        _ => None,
    }
}

/// Async version with timeout
async fn get_instances_async(project_id: &str) -> Result<Vec<GcpInstance>> {
    // Validate project ID before passing to shell command
    validate_project_id(project_id)?;

    // 10 second timeout for listing instances
    let output = timeout(
        Duration::from_secs(10),
        TokioCommand::new("gcloud")
            .args(["compute", "instances", "list", "--project", project_id, "--format=json"])
            .output()
    )
    .await
    .map_err(|_| anyhow!("Timeout: gcloud instances list took longer than 10 seconds"))?
    .map_err(|e| anyhow!("Failed to execute gcloud: {}", e))?;

    if !output.status.success() {
        return Err(anyhow!("gcloud error: {}", String::from_utf8_lossy(&output.stderr)));
    }

    let raw_instances: Vec<RawInstance> = serde_json::from_slice(&output.stdout)
        .map_err(|e| anyhow!("Failed to parse instances JSON: {}", e))?;

    let instances = raw_instances.into_iter().map(|raw| {
        // Use sanitize_zone_from_url instead of fragile split
        let zone_name = sanitize_zone_from_url(&raw.zone)
            .unwrap_or_else(|_| {
                // Fallback to old method if validation fails
                raw.zone.split('/').last().unwrap_or(&raw.zone).to_string()
            });

        let machine_type = raw.machine_type
            .as_deref()
            .map(|url| url.split('/').last().unwrap_or(url))
            .unwrap_or("Unknown")
            .to_string();

        // Extract CPU and memory from machine type
        let (cpu_count, memory_mb) = get_machine_specs(&machine_type)
            .map(|(cpu, mem)| (Some(cpu), Some(mem)))
            .unwrap_or((None, None));

        // Extract disk size from boot disk (first disk marked as boot=true)
        let disk_gb = raw.disks
            .as_ref()
            .and_then(|disks| {
                disks.iter()
                    .find(|d| d.boot.unwrap_or(false))
                    .or_else(|| disks.first())
            })
            .and_then(|disk| disk.disk_size_gb.as_ref())
            .and_then(|size_str| size_str.parse::<u32>().ok());

        GcpInstance {
            name: raw.name,
            status: raw.status,
            zone: zone_name,
            machine_type,
            cpu_count,
            memory_mb,
            disk_gb,
        }
    }).collect();

    Ok(instances)
}

/// Synchronous wrapper for FFI bridge
pub fn get_instances(project_id: &str) -> Result<Vec<GcpInstance>> {
    // Create a tokio runtime for this call
    let rt = tokio::runtime::Runtime::new()
        .map_err(|e| anyhow!("Failed to create tokio runtime: {}", e))?;
    rt.block_on(get_instances_async(project_id))
}

pub fn execute_login() -> Result<()> {
    // gcloud auth login launches the browser. We wait for it to complete.
    let status = Command::new("gcloud")
        .args(["auth", "login", "--quiet"]) 
        .status()
        .map_err(|e| anyhow!("Failed to execute gcloud login: {}", e))?;

    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("Login failed or was cancelled."))
    }
}

pub fn launch_ssh(project_id: &str, zone: &str, instance_name: &str) -> anyhow::Result<()> {
    // SECURITY: Validate all inputs before passing to command
    validate_project_id(project_id)?;
    validate_zone(zone)?;
    validate_instance_name(instance_name)?;

    tracing::info!(
        project_id = project_id,
        zone = zone,
        instance_name = instance_name,
        "Launching SSH connection"
    );

    // Detect available terminal
    let (terminal_bin, terminal_args) = if Command::new("gnome-terminal").arg("--version").output().is_ok() {
        ("gnome-terminal", vec!["--", "gcloud", "compute", "ssh"])
    } else if Command::new("konsole").arg("--version").output().is_ok() {
        ("konsole", vec!["-e", "gcloud", "compute", "ssh"])
    } else if Command::new("xterm").arg("-version").output().is_ok() {
        ("xterm", vec!["-e", "gcloud", "compute", "ssh"])
    } else {
        return Err(anyhow::anyhow!("No suitable terminal found (gnome-terminal, konsole, xterm). Please install one."));
    };

    // SECURITY: Pass arguments individually to avoid shell interpolation
    // This prevents command injection even if validation is bypassed
    let mut cmd = Command::new(terminal_bin);
    cmd.args(terminal_args)
        .arg("--project")
        .arg(project_id)
        .arg("--zone")
        .arg(zone)
        .arg(instance_name)
        .spawn()
        .map_err(|e| anyhow::anyhow!("Failed to launch terminal for SSH: {}", e))?;

    Ok(())
}

pub fn execute_logout() -> Result<()> {
    tracing::info!("Revoking all gcloud credentials");

    // --quiet evita prompts, --all borra todas las cuentas activas
    let _ = Command::new("gcloud")
        .args(&["auth", "revoke", "--all", "--quiet"]) 
        .status(); // Ignoramos el resultado, si falla es probable que ya no haya credenciales.

    Ok(())
}

