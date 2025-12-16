use std::process::Command;
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};

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
}

#[derive(Deserialize)]
struct RawInstance {
    name: String,
    status: String,
    zone: String, 
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

pub fn get_projects() -> Result<Vec<GcpProject>> {
    let output = Command::new("gcloud")
        .args(["projects", "list", "--format=json"])
        .output()
        .map_err(|e| anyhow!("Failed to execute gcloud: {}", e))?;

    if !output.status.success() {
        return Err(anyhow!("gcloud error: {}", String::from_utf8_lossy(&output.stderr)));
    }

    let projects: Vec<GcpProject> = serde_json::from_slice(&output.stdout)
        .map_err(|e| anyhow!("Failed to parse projects JSON: {}", e))?;
    Ok(projects)
}

pub fn get_instances(project_id: &str) -> Result<Vec<GcpInstance>> {
    let output = Command::new("gcloud")
        .args(["compute", "instances", "list", "--project", project_id, "--format=json"])
        .output()
        .map_err(|e| anyhow!("Failed to execute gcloud: {}", e))?;

    if !output.status.success() {
        return Err(anyhow!("gcloud error: {}", String::from_utf8_lossy(&output.stderr)));
    }

    let raw_instances: Vec<RawInstance> = serde_json::from_slice(&output.stdout)
        .map_err(|e| anyhow!("Failed to parse instances JSON: {}", e))?;
    
    let instances = raw_instances.into_iter().map(|raw| {
        let zone_name = raw.zone.split('/').next_back().unwrap_or(&raw.zone).to_string();
        GcpInstance {
            name: raw.name,
            status: raw.status,
            zone: zone_name,
        }
    }).collect();

    Ok(instances)
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
    println!("RUST: Launching SSH for instance: {}", instance_name);

    // Construir el comando gcloud SSH
    let gcloud_ssh_command = format!(
        "gcloud compute ssh --project={} --zone={} {}",
        project_id, zone, instance_name
    );

    // Intentar encontrar la terminal adecuada
    let terminal_command_prefix = if Command::new("gnome-terminal").arg("--version").output().is_ok() {
        "gnome-terminal --"
    } else if Command::new("konsole").arg("--version").output().is_ok() {
        "konsole -e"
    } else if Command::new("xterm").arg("-version").output().is_ok() {
        "xterm -e"
    } else {
        return Err(anyhow::anyhow!("No suitable terminal found (gnome-terminal, konsole, xterm). Please install one."));
    };

    // Ejecutar el comando en la terminal
    Command::new("sh")
        .arg("-c")
        .arg(format!("{} {}", terminal_command_prefix, gcloud_ssh_command))
        .spawn()
        .map_err(|e| anyhow::anyhow!("Failed to launch terminal for SSH: {}", e))?;

    Ok(())
}

