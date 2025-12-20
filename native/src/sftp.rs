use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use ssh2::{Session, Sftp};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use tracing;

/// Represents a remote file or directory entry
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RemoteFileEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size: u64,
    pub modified: Option<i64>, // Unix timestamp
    pub permissions: Option<u32>,
}

/// SFTP connection parameters
#[derive(Debug, Clone)]
pub struct SftpConnectionParams {
    pub host: String,
    pub port: u16,
    pub username: String,
}

/// Create SSH session and authenticate
fn create_ssh_session(host: &str, port: u16, username: &str) -> Result<Session> {
    tracing::info!(
        host = host,
        port = port,
        username = username,
        "Creating SSH session for SFTP"
    );

    // Connect to the SSH server (via IAP tunnel on localhost)
    let tcp = TcpStream::connect(format!("{}:{}", host, port))
        .map_err(|e| anyhow!("Failed to connect to SSH server: {}", e))?;

    // Create SSH session
    let mut sess = Session::new()
        .map_err(|e| anyhow!("Failed to create SSH session: {}", e))?;

    sess.set_tcp_stream(tcp);
    sess.handshake()
        .map_err(|e| anyhow!("SSH handshake failed: {}", e))?;

    // Try SSH agent authentication first (most common for GCP)
    if let Err(e) = sess.userauth_agent(username) {
        tracing::warn!(error = ?e, "SSH agent authentication failed, trying default key");

        // Try default SSH key as fallback
        let home = dirs::home_dir()
            .ok_or_else(|| anyhow!("Could not determine home directory"))?;
        let key_path = home.join(".ssh").join("id_rsa");

        if key_path.exists() {
            sess.userauth_pubkey_file(username, None, &key_path, None)
                .map_err(|e| anyhow!("SSH key authentication failed: {}", e))?;
        } else {
            return Err(anyhow!(
                "No authentication method available. Please set up SSH keys or agent."
            ));
        }
    }

    if !sess.authenticated() {
        return Err(anyhow!("SSH authentication failed"));
    }

    tracing::info!("SSH session authenticated successfully");
    Ok(sess)
}

/// List directory contents via SFTP
pub fn sftp_list_directory(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
) -> Result<Vec<RemoteFileEntry>> {
    tracing::info!(
        remote_path = remote_path,
        "Listing SFTP directory"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    let path = Path::new(&remote_path);
    let entries = sftp.readdir(path)
        .map_err(|e| anyhow!("Failed to read directory '{}': {}", remote_path, e))?;

    let mut result = Vec::new();
    for (entry_path, stat) in entries {
        let name = entry_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();

        // Skip . and .. entries
        if name == "." || name == ".." {
            continue;
        }

        let is_directory = stat.is_dir();
        let size = stat.size.unwrap_or(0);
        let modified = stat.mtime.map(|t| t as i64);
        let permissions = stat.perm;

        result.push(RemoteFileEntry {
            name,
            path: entry_path.to_string_lossy().to_string(),
            is_directory,
            size,
            modified,
            permissions,
        });
    }

    // Sort: directories first, then by name
    result.sort_by(|a, b| {
        match (a.is_directory, b.is_directory) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    tracing::info!(count = result.len(), "Directory listing completed");
    Ok(result)
}

/// Download a file from remote server
pub fn sftp_download_file(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
    local_path: String,
) -> Result<u64> {
    tracing::info!(
        remote_path = remote_path,
        local_path = local_path,
        "Downloading file via SFTP"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    // Open remote file
    let mut remote_file = sftp.open(Path::new(&remote_path))
        .map_err(|e| anyhow!("Failed to open remote file '{}': {}", remote_path, e))?;

    // Create local file
    let mut local_file = std::fs::File::create(&local_path)
        .map_err(|e| anyhow!("Failed to create local file '{}': {}", local_path, e))?;

    // Copy data
    let bytes_copied = std::io::copy(&mut remote_file, &mut local_file)
        .map_err(|e| anyhow!("Failed to copy file data: {}", e))?;

    tracing::info!(bytes = bytes_copied, "File downloaded successfully");
    Ok(bytes_copied)
}

/// Upload a file to remote server
pub fn sftp_upload_file(
    host: String,
    port: u16,
    username: String,
    local_path: String,
    remote_path: String,
) -> Result<u64> {
    tracing::info!(
        local_path = local_path,
        remote_path = remote_path,
        "Uploading file via SFTP"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    // Open local file
    let mut local_file = std::fs::File::open(&local_path)
        .map_err(|e| anyhow!("Failed to open local file '{}': {}", local_path, e))?;

    // Create remote file
    let mut remote_file = sftp.create(Path::new(&remote_path))
        .map_err(|e| anyhow!("Failed to create remote file '{}': {}", remote_path, e))?;

    // Copy data
    let bytes_copied = std::io::copy(&mut local_file, &mut remote_file)
        .map_err(|e| anyhow!("Failed to copy file data: {}", e))?;

    tracing::info!(bytes = bytes_copied, "File uploaded successfully");
    Ok(bytes_copied)
}

/// Create a directory on remote server
pub fn sftp_create_directory(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
) -> Result<()> {
    tracing::info!(remote_path = remote_path, "Creating remote directory");

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    sftp.mkdir(Path::new(&remote_path), 0o755)
        .map_err(|e| anyhow!("Failed to create directory '{}': {}", remote_path, e))?;

    tracing::info!("Directory created successfully");
    Ok(())
}

/// Delete a file or directory on remote server
pub fn sftp_delete(
    host: String,
    port: u16,
    username: String,
    remote_path: String,
    is_directory: bool,
) -> Result<()> {
    tracing::info!(
        remote_path = remote_path,
        is_directory = is_directory,
        "Deleting remote path"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    let path = Path::new(&remote_path);
    if is_directory {
        sftp.rmdir(path)
            .map_err(|e| anyhow!("Failed to delete directory '{}': {}", remote_path, e))?;
    } else {
        sftp.unlink(path)
            .map_err(|e| anyhow!("Failed to delete file '{}': {}", remote_path, e))?;
    }

    tracing::info!("Path deleted successfully");
    Ok(())
}

/// Get current username from environment
pub fn get_current_username() -> Result<String> {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .map_err(|_| anyhow!("Could not determine current username"))
}
