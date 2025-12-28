use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use ssh2::Session;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use tracing;

/// Maximum file size for transfers (10 GB)
/// This prevents DoS attacks via disk exhaustion
const MAX_FILE_SIZE: u64 = 10 * 1024 * 1024 * 1024;

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
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct SftpConnectionParams {
    pub host: String,
    pub port: u16,
    pub username: String,
}

/// Copy data from reader to writer with size limit to prevent DoS attacks
///
/// This function prevents disk exhaustion attacks by limiting the maximum
/// amount of data that can be transferred in a single operation.
///
/// # Security
/// This prevents CWE-400 (Uncontrolled Resource Consumption) attacks
fn copy_with_limit<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    max_size: u64,
) -> Result<u64> {
    let mut buffer = [0u8; 8192]; // 8KB buffer
    let mut total_bytes = 0u64;

    loop {
        // Read chunk from source
        let bytes_read = reader.read(&mut buffer)
            .map_err(|e| anyhow!("Read error during file transfer: {}", e))?;

        if bytes_read == 0 {
            break; // EOF reached
        }

        // Check size limit BEFORE writing
        total_bytes += bytes_read as u64;
        if total_bytes > max_size {
            let max_gb = max_size / (1024 * 1024 * 1024);
            return Err(anyhow!(
                "File size exceeds maximum allowed size of {} GB ({} bytes). Transfer aborted.",
                max_gb,
                max_size
            ));
        }

        // Write chunk to destination
        writer.write_all(&buffer[..bytes_read])
            .map_err(|e| anyhow!("Write error during file transfer: {}", e))?;
    }

    Ok(total_bytes)
}

/// Validate and normalize remote path to prevent path traversal attacks
///
/// This function ensures that:
/// 1. The username is valid (POSIX format)
/// 2. The path does not contain ".." components (parent directory references)
/// 3. The resolved path stays within the user's home directory
/// 4. The path is properly normalized
///
/// # Security
/// This is a critical security function that prevents CWE-22 (Path Traversal) attacks
fn validate_and_normalize_path(remote_path: &str, username: &str) -> Result<PathBuf> {
    // SECURITY: Validate username first to prevent path injection
    crate::validation::validate_username(username)?;

    let path = Path::new(remote_path);

    // Security check: Reject paths with parent directory components
    if path.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
        tracing::warn!(
            remote_path = remote_path,
            username = username,
            "Path traversal attempt detected"
        );
        return Err(anyhow!("Path traversal not allowed (.. components forbidden)"));
    }

    // Define allowed base directory (user's home directory)
    let allowed_base = PathBuf::from(format!("/home/{}", username));

    // Resolve to full path
    let full_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        allowed_base.join(path)
    };

    // Normalize the path by processing components
    let normalized = full_path.components()
        .fold(PathBuf::new(), |mut acc, component| {
            match component {
                std::path::Component::ParentDir => {
                    // Pop if not at root
                    acc.pop();
                },
                std::path::Component::Normal(c) => {
                    acc.push(c);
                },
                std::path::Component::RootDir => {
                    acc.push("/");
                },
                std::path::Component::CurDir => {
                    // Skip current directory references
                },
                std::path::Component::Prefix(_) => {
                    // Windows paths not applicable on Linux
                },
            }
            acc
        });

    // Security check: Verify normalized path is within allowed bounds
    if !normalized.starts_with(&allowed_base) {
        tracing::warn!(
            remote_path = remote_path,
            normalized_path = %normalized.display(),
            allowed_base = %allowed_base.display(),
            username = username,
            "Access denied: path outside user directory"
        );
        return Err(anyhow!(
            "Access denied: path must be within /home/{}",
            username
        ));
    }

    tracing::debug!(
        original_path = remote_path,
        normalized_path = %normalized.display(),
        "Path validated successfully"
    );

    Ok(normalized)
}

/// Validate local file path for downloads/uploads
///
/// This function ensures that:
/// 1. The path does not contain ".." components (parent directory traversal)
/// 2. The path is within allowed directories (user's home)
/// 3. The path is properly normalized
///
/// # Security
/// Prevents writing to arbitrary system locations (CWE-22)
fn validate_local_path(local_path: &str) -> Result<PathBuf> {
    let path = Path::new(local_path);

    // Security check: Reject paths with parent directory components
    if path.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
        tracing::warn!(
            local_path = local_path,
            "Local path traversal attempt detected"
        );
        return Err(anyhow!("Local path traversal not allowed (.. components forbidden)"));
    }

    // Get user's home directory
    let home_dir = dirs::home_dir()
        .ok_or_else(|| anyhow!("Could not determine home directory"))?;

    // Resolve to full path
    let full_path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        home_dir.join(path)
    };

    // Canonicalize to resolve any symlinks and normalize
    let normalized = full_path.canonicalize()
        .or_else(|_| {
            // If path doesn't exist yet, validate parent directory
            if let Some(parent) = full_path.parent() {
                parent.canonicalize().map(|p| p.join(full_path.file_name().unwrap()))
            } else {
                Err(std::io::Error::new(std::io::ErrorKind::NotFound, "Invalid local path"))
            }
        })
        .map_err(|e| anyhow!("Failed to validate local path: {}", e))?;

    // Verify path is within user's home directory
    if !normalized.starts_with(&home_dir) {
        tracing::warn!(
            normalized_path = %normalized.display(),
            home_dir = %home_dir.display(),
            "Access denied: local path outside home directory"
        );
        return Err(anyhow!(
            "Access denied: local path must be within your home directory ({})",
            home_dir.display()
        ));
    }

    tracing::debug!(
        original_path = local_path,
        normalized_path = %normalized.display(),
        "Local path validated successfully"
    );

    Ok(normalized)
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

    // Try multiple authentication methods and accumulate errors for better diagnostics
    let mut auth_errors = Vec::new();

    // Try SSH agent authentication first (most common for GCP)
    if let Err(e) = sess.userauth_agent(username) {
        let error_msg = format!("SSH agent: {}", e);
        tracing::warn!(error = %error_msg, "SSH agent authentication failed");
        auth_errors.push(error_msg);

        // Try default SSH key as fallback
        let home = dirs::home_dir()
            .ok_or_else(|| anyhow!("Could not determine home directory"))?;
        let key_path = home.join(".ssh").join("id_rsa");

        if !key_path.exists() {
            let error_msg = format!(
                "SSH key file not found at: {}. Set up SSH keys or start ssh-agent.",
                key_path.display()
            );
            auth_errors.push(error_msg.clone());

            return Err(anyhow!(
                "All SSH authentication methods failed:\n  • {}\n\n\
                Please either:\n\
                  1. Start ssh-agent and add your key: ssh-add ~/.ssh/id_rsa\n\
                  2. Create an SSH key pair: ssh-keygen -t rsa\n\
                  3. Ensure your public key is in the remote server's ~/.ssh/authorized_keys",
                auth_errors.join("\n  • ")
            ));
        }

        if let Err(e) = sess.userauth_pubkey_file(username, None, &key_path, None) {
            let error_msg = format!("SSH key file ({}): {}", key_path.display(), e);
            auth_errors.push(error_msg);

            return Err(anyhow!(
                "All SSH authentication methods failed:\n  • {}\n\n\
                Troubleshooting:\n\
                  • Check that your public key is in ~/.ssh/authorized_keys on the remote server\n\
                  • Verify key permissions: chmod 600 ~/.ssh/id_rsa\n\
                  • Try: ssh-add ~/.ssh/id_rsa",
                auth_errors.join("\n  • ")
            ));
        }
    }

    if !sess.authenticated() {
        auth_errors.push("Final authentication check failed".to_string());
        return Err(anyhow!(
            "SSH authentication failed despite successful auth call:\n  • {}",
            auth_errors.join("\n  • ")
        ));
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
    // Security: Validate and normalize path to prevent traversal attacks
    let validated_path = validate_and_normalize_path(&remote_path, &username)?;

    tracing::info!(
        remote_path = %validated_path.display(),
        "Listing SFTP directory"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    let entries = sftp.readdir(&validated_path)
        .map_err(|e| anyhow!("Failed to read directory '{}': {}", validated_path.display(), e))?;

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
    // Security: Validate and normalize remote path to prevent traversal attacks
    let validated_remote_path = validate_and_normalize_path(&remote_path, &username)?;

    // Security: Validate local path to prevent writing to arbitrary locations
    let validated_local_path = validate_local_path(&local_path)?;

    tracing::info!(
        remote_path = %validated_remote_path.display(),
        local_path = %validated_local_path.display(),
        "Downloading file via SFTP"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    // Open remote file
    let mut remote_file = sftp.open(&validated_remote_path)
        .map_err(|e| anyhow!("Failed to open remote file '{}': {}", validated_remote_path.display(), e))?;

    // Create local file
    let mut local_file = std::fs::File::create(&validated_local_path)
        .map_err(|e| anyhow!("Failed to create local file '{}': {}", validated_local_path.display(), e))?;

    // Copy data with size limit to prevent DoS
    let bytes_copied = copy_with_limit(&mut remote_file, &mut local_file, MAX_FILE_SIZE)?;

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
    // Security: Validate local path to prevent reading from arbitrary locations
    let validated_local_path = validate_local_path(&local_path)?;

    // Security: Validate and normalize remote path to prevent traversal attacks
    let validated_remote_path = validate_and_normalize_path(&remote_path, &username)?;

    tracing::info!(
        local_path = %validated_local_path.display(),
        remote_path = %validated_remote_path.display(),
        "Uploading file via SFTP"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    // Open local file
    let mut local_file = std::fs::File::open(&validated_local_path)
        .map_err(|e| anyhow!("Failed to open local file '{}': {}", validated_local_path.display(), e))?;

    // Create remote file
    let mut remote_file = sftp.create(&validated_remote_path)
        .map_err(|e| anyhow!("Failed to create remote file '{}': {}", validated_remote_path.display(), e))?;

    // Copy data with size limit to prevent DoS
    let bytes_copied = copy_with_limit(&mut local_file, &mut remote_file, MAX_FILE_SIZE)?;

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
    // Security: Validate and normalize path to prevent traversal attacks
    let validated_path = validate_and_normalize_path(&remote_path, &username)?;

    tracing::info!(remote_path = %validated_path.display(), "Creating remote directory");

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    sftp.mkdir(&validated_path, 0o755)
        .map_err(|e| anyhow!("Failed to create directory '{}': {}", validated_path.display(), e))?;

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
    // Security: Validate and normalize path to prevent traversal attacks
    let validated_path = validate_and_normalize_path(&remote_path, &username)?;

    tracing::info!(
        remote_path = %validated_path.display(),
        is_directory = is_directory,
        "Deleting remote path"
    );

    let sess = create_ssh_session(&host, port, &username)?;
    let sftp = sess.sftp()
        .map_err(|e| anyhow!("Failed to create SFTP session: {}", e))?;

    if is_directory {
        sftp.rmdir(&validated_path)
            .map_err(|e| anyhow!("Failed to delete directory '{}': {}", validated_path.display(), e))?;
    } else {
        sftp.unlink(&validated_path)
            .map_err(|e| anyhow!("Failed to delete file '{}': {}", validated_path.display(), e))?;
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
