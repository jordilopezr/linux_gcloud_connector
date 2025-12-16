use std::fs::{self, File};
use std::io::Write;
use std::process::{Command, Stdio};
use anyhow::{Result, anyhow};

pub fn launch_remmina(port: u16, instance_name: &str) -> Result<()> {
    println!("RUST: Preparing to launch Remmina for {} on port {}", instance_name, port);
    
    let mut config_path_opt = None;

    // Try to create config file
    if let Some(mut config_dir) = dirs::cache_dir() {
        config_dir.push("linux_cloud_connector");
        if !config_dir.exists() {
            let _ = fs::create_dir_all(&config_dir);
        }
        
        let mut file_path = config_dir.clone();
        file_path.push(format!("iap_{}.remmina", instance_name));
        
        let content = format!(r#"
[remmina]
name={} (IAP)
protocol=RDP
server=127.0.0.1:{}
ignore-certificate=1
window_maximize=1
enable-autostart=1
"#, instance_name, port);

        if let Ok(mut file) = File::create(&file_path)
            && file.write_all(content.as_bytes()).is_ok() {
                config_path_opt = Some(file_path);
            }
    }

    // 1. Try Native
    if let Some(ref path) = config_path_opt {
        println!("RUST: Attempting Native Remmina with file...");
        let native = Command::new("remmina")
            .arg("-c")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();

        if native.is_ok() {
            println!("RUST: Native Remmina launched.");
            return Ok(());
        }
    }

    // 2. Try Flatpak with File Forwarding
    if let Some(ref path) = config_path_opt {
        println!("RUST: Attempting Flatpak Remmina with File Forwarding...");
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
            println!("RUST: Flatpak launched (File mode). Check logs above if UI doesn't appear.");
            // We return Ok here because spawn succeeded, but Remmina might fail later.
            // If it fails immediately, the logs will show it.
            // But let's add a tiny fallback: if spawn is ok, we assume success. 
            // The user will report if it crashes.
            return Ok(()); 
        } else {
             println!("RUST: Flatpak File launch error: {:?}", flatpak.err());
        }
    }

    // 3. Fallback: Flatpak URI (Bypasses file permission issues entirely)
    println!("RUST: Fallback to Flatpak URI mode...");
    let uri = format!("rdp://127.0.0.1:{}", port);
    
    let flatpak_uri = Command::new("flatpak")
        .args(["run", "org.remmina.Remmina", "-c", &uri])
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn();

    match flatpak_uri {
        Ok(_) => {
            println!("RUST: Flatpak launched (URI mode).");
            Ok(())
        },
        Err(e) => Err(anyhow!("All launch attempts failed. Error: {}", e))
    }
}
