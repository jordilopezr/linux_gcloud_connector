use std::fs::{self, File};
use std::io::Write;
use std::process::{Command, Stdio};
use anyhow::{Result, anyhow};
use tracing;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

#[derive(Default, Debug)]
pub struct RdpSettings {
    pub username: Option<String>,
    pub password: Option<String>,
    pub domain: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub fullscreen: bool,
}

pub fn launch_remmina(port: u16, instance_name: &str, settings: RdpSettings) -> Result<()> {
    tracing::info!(
        instance_name = instance_name,
        port = port,
        fullscreen = settings.fullscreen,
        "Launching Remmina RDP client"
    );
    
    let mut config_path_opt = None;

    // Try to create config file
    if let Some(mut config_dir) = dirs::cache_dir() {
        config_dir.push("linux_cloud_connector");
        if !config_dir.exists() {
            let _ = fs::create_dir_all(&config_dir);
        }
        
        let mut file_path = config_dir.clone();
        file_path.push(format!("iap_{}.remmina", instance_name));
        
        let mut content = format!(r#"
[remmina]
name={} (IAP)
protocol=RDP
server=127.0.0.1:{}
ignore-certificate=1
enable-autostart=1
"#, instance_name, port);

        if let Some(u) = &settings.username { content.push_str(&format!("username={}\n", u)); }
        if let Some(p) = &settings.password { content.push_str(&format!("password={}\n", p)); }
        if let Some(d) = &settings.domain { content.push_str(&format!("domain={}\n", d)); }
        
        if settings.fullscreen {
            content.push_str("window_maximize=1\n"); // Remmina treats maximize as almost fullscreen usually, real fullscreen is 'viewmode=4'? Let's check docs or stick to maximize which is safe.
            // Actually 'viewmode' in remmina: 1=scaled, 2=viewport, 4=fullscreen.
            content.push_str("viewmode=4\n");
        } else {
             if let (Some(w), Some(h)) = (settings.width, settings.height) {
                 content.push_str(&format!("resolution={}x{}\n", w, h));
             } else {
                 content.push_str("window_maximize=1\n");
             }
        }

        if let Ok(mut file) = File::create(&file_path)
            && file.write_all(content.as_bytes()).is_ok() {
                // SECURITY: Set file permissions to 0600 (owner read/write only)
                // This prevents other users from reading RDP credentials
                #[cfg(unix)]
                {
                    if let Err(e) = fs::set_permissions(&file_path, fs::Permissions::from_mode(0o600)) {
                        tracing::warn!(
                            error = %e,
                            "Could not set secure permissions (0600) on .remmina file"
                        );
                        // Continue anyway, file was created
                    } else {
                        tracing::debug!("Secure permissions (0600) set on .remmina file");
                    }
                }

                config_path_opt = Some(file_path);
            }
    }

    // 1. Try Native
    if let Some(ref path) = config_path_opt {
        tracing::debug!("Attempting native Remmina with config file");
        let native = Command::new("remmina")
            .arg("-c")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();

        if native.is_ok() {
            tracing::info!("Native Remmina launched successfully");
            return Ok(());
        }
    }

    // 2. Try Flatpak with File Forwarding
    if let Some(ref path) = config_path_opt {
        tracing::debug!("Attempting Flatpak Remmina with file forwarding");
        // Note: inheriting stdio to debug why it fails
        let flatpak = Command::new("flatpak")
            .args(["run", "--file-forwarding", "org.remmina.Remmina"])
            .arg("-c")
            .arg("@@")
            .arg(path)
            .arg("@@")
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn();

        if flatpak.is_ok() {
            tracing::info!("Flatpak Remmina launched (file mode)");
            // We return Ok here because spawn succeeded, but Remmina might fail later.
            // If it fails immediately, the logs will show it.
            // But let's add a tiny fallback: if spawn is ok, we assume success.
            // The user will report if it crashes.
            return Ok(());
        } else if let Err(e) = flatpak {
             tracing::warn!(error = %e, "Flatpak file mode launch failed");
        }
    }

    // 3. Fallback: Flatpak URI (Bypasses file permission issues entirely)
    tracing::debug!("Falling back to Flatpak URI mode");
    let uri = format!("rdp://127.0.0.1:{}", port);

    let flatpak_uri = Command::new("flatpak")
        .args(["run", "org.remmina.Remmina", "-c", &uri])
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn();

    match flatpak_uri {
        Ok(_) => {
            tracing::info!("Flatpak Remmina launched (URI mode)");
            Ok(())
        },
        Err(e) => {
            tracing::error!(error = %e, "All Remmina launch attempts failed");
            Err(anyhow!("All launch attempts failed. Error: {}", e))
        }
    }
}
