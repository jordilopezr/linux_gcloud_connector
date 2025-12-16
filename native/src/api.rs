use crate::gcloud;
use crate::tunnel;
use crate::remmina;

// Re-export structs for FRB
pub use crate::gcloud::GcpProject;
pub use crate::gcloud::GcpInstance;

pub fn greet() -> String {
    "Hello from Rust! Gcloud integration ready.".to_string()
}

pub fn check_gcloud_installed() -> bool {
    gcloud::is_gcloud_installed()
}

pub fn check_gcloud_auth() -> bool {
    gcloud::is_gcloud_authenticated()
}

pub fn gcloud_login() -> anyhow::Result<()> {
    gcloud::execute_login()
}

pub fn gcloud_logout() -> anyhow::Result<()> {
    gcloud::execute_logout()
}

pub fn list_projects() -> anyhow::Result<Vec<GcpProject>> {
    gcloud::get_projects()
}

pub fn list_instances(project_id: String) -> anyhow::Result<Vec<GcpInstance>> {
    gcloud::get_instances(&project_id)
}

// Tunneling
pub fn start_connection(project_id: String, zone: String, instance_name: String, remote_port: u16) -> anyhow::Result<u16> {
    tunnel::start_tunnel(&project_id, &zone, &instance_name, remote_port)
}

pub fn stop_connection(instance_name: String) -> anyhow::Result<()> {
    tunnel::stop_tunnel(&instance_name)
}

// Remote Desktop
pub fn launch_rdp(port: u16, instance_name: String) -> anyhow::Result<()> {
    remmina::launch_remmina(port, &instance_name)
}

// SSH
pub fn launch_ssh(project_id: String, zone: String, instance_name: String) -> anyhow::Result<()> {
    gcloud::launch_ssh(&project_id, &zone, &instance_name)
}