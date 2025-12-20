use crate::gcloud;
use crate::tunnel;
use crate::remmina;
use crate::logging;
use crate::sftp;

// Re-export structs for FRB
pub use crate::gcloud::GcpProject;
pub use crate::gcloud::GcpInstance;
pub use crate::remmina::RdpSettings;
pub use crate::sftp::RemoteFileEntry;

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

pub fn stop_connection(instance_name: String, remote_port: u16) -> anyhow::Result<()> {
    tunnel::stop_tunnel(&instance_name, remote_port)
}

pub fn check_connection_health(instance_name: String, remote_port: u16) -> anyhow::Result<bool> {
    tunnel::check_tunnel_health(&instance_name, remote_port)
}

// Remote Desktop
pub fn launch_rdp(port: u16, instance_name: String, settings: RdpSettings) -> anyhow::Result<()> {
    remmina::launch_remmina(port, &instance_name, settings)
}

// SSH
pub fn launch_ssh(project_id: String, zone: String, instance_name: String) -> anyhow::Result<()> {
    gcloud::launch_ssh(&project_id, &zone, &instance_name)
}

// Logging
pub fn init_logging_system() -> anyhow::Result<()> {
    logging::init_logging()
}

pub fn export_logs_to_file() -> anyhow::Result<String> {
    let path = logging::export_logs()?;
    Ok(path.to_string_lossy().to_string())
}

pub fn get_log_file_path() -> anyhow::Result<String> {
    let path = logging::get_current_log_path()?;
    Ok(path.to_string_lossy().to_string())
}

// SFTP File Transfer
pub fn sftp_list_dir(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
) -> anyhow::Result<Vec<RemoteFileEntry>> {
    sftp::sftp_list_directory(host, port, username, remote_path)
}

pub fn sftp_download(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
    local_path: String,
) -> anyhow::Result<u64> {
    sftp::sftp_download_file(host, port, username, remote_path, local_path)
}

pub fn sftp_upload(
    host: String,
    port: u16,
    username: String,
    local_path: String,
    remote_path: String,
) -> anyhow::Result<u64> {
    sftp::sftp_upload_file(host, port, username, local_path, remote_path)
}

pub fn sftp_mkdir(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
) -> anyhow::Result<()> {
    sftp::sftp_create_directory(host, port, username, remote_path)
}

pub fn sftp_delete(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
    is_directory: bool,
) -> anyhow::Result<()> {
    sftp::sftp_delete(host, port, username, remote_path, is_directory)
}

pub fn get_username() -> anyhow::Result<String> {
    sftp::get_current_username()
}