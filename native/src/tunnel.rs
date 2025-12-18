use std::process::{Command, Child, Stdio};
use std::net::{TcpListener, TcpStream};
use anyhow::{Result, anyhow};
use std::sync::Mutex;
use std::collections::HashMap;
use std::time::Duration;
use lazy_static::lazy_static;
use tracing;
use crate::validation::{validate_project_id, validate_zone, validate_instance_name};

pub struct IapTunnel {
    process: Child,
    pub local_port: u16,
}

impl IapTunnel {
    pub fn stop(&mut self) -> Result<()> {
        // Enviar SIGTERM o SIGKILL. kill() es SIGKILL.
        let _ = self.process.kill();
        let _ = self.process.wait();
        Ok(())
    }

    /// Check if the tunnel process is still running
    pub fn is_process_alive(&mut self) -> bool {
        match self.process.try_wait() {
            Ok(Some(_)) => false, // Process has exited
            Ok(None) => true,     // Process is still running
            Err(_) => false,      // Error checking status, assume dead
        }
    }

    /// Check if the local port is actually listening
    pub fn is_port_listening(&self) -> bool {
        let addr = format!("127.0.0.1:{}", self.local_port);
        // Try to connect to the port
        TcpStream::connect_timeout(
            &addr.parse().unwrap(),
            Duration::from_millis(500)
        ).is_ok()
    }

    /// Comprehensive health check
    pub fn is_healthy(&mut self) -> bool {
        self.is_process_alive() && self.is_port_listening()
    }
}

lazy_static! {
    static ref TUNNELS: Mutex<HashMap<String, IapTunnel>> = Mutex::new(HashMap::new());
}

pub fn start_tunnel(project: &str, zone: &str, instance: &str, remote_port: u16) -> Result<u16> {
    // SECURITY: Validate all inputs before passing to gcloud command
    validate_project_id(project)?;
    validate_zone(zone)?;
    validate_instance_name(instance)?;

    // Scope para el lock
    {
        let tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;
        if let Some(tunnel) = tunnels.get(instance) {
            return Ok(tunnel.local_port);
        }
    }

    let port = get_free_port()?;
    
    let child = Command::new("gcloud")
        .args([
            "compute", 
            "start-iap-tunnel", 
            instance, 
            &remote_port.to_string(),
            &format!("--local-host-port=localhost:{}", port),
            "--zone", zone,
            "--project", project
        ])
        .stdout(Stdio::null()) // Ignorar stdout por ahora
        .stderr(Stdio::piped()) // Capturar stderr para logs si fuera necesario (no implementado lectura async aun)
        .spawn()
        .map_err(|e| anyhow!("Failed to spawn gcloud tunnel: {}", e))?;

    // Store the tunnel immediately so we can check its health
    let mut tunnel = IapTunnel { process: child, local_port: port };

    // Wait briefly for tunnel to initialize
    std::thread::sleep(std::time::Duration::from_millis(1000));

    // IMPROVEMENT: Verify tunnel health before declaring success
    if !tunnel.is_process_alive() {
        return Err(anyhow!("Tunnel process died immediately after startup"));
    }

    // Wait up to 10 seconds for port to start listening (increased from 5s)
    let mut port_ready = false;
    tracing::info!(
        instance = instance,
        port = port,
        "Waiting for tunnel port to start listening (max 10 seconds)..."
    );

    for attempt in 0..20 {
        if tunnel.is_port_listening() {
            port_ready = true;
            tracing::info!(
                instance = instance,
                port = port,
                attempt = attempt + 1,
                elapsed_ms = (attempt + 1) * 500,
                "Port is now listening"
            );
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(500));
    }

    if !port_ready {
        // Kill the process since it's not working
        let _ = tunnel.stop();
        tracing::error!(
            instance = instance,
            port = port,
            "Tunnel port failed to listen after 10 seconds"
        );
        return Err(anyhow!(
            "Tunnel process started but port {} is not listening after 10 seconds. \
             Possible causes: IAP not enabled, firewall blocking, or slow network. \
             Check logs and try SSH first to verify IAP works.",
            port
        ));
    }

    tracing::info!(
        instance = instance,
        port = port,
        "Tunnel health check passed - process alive and port listening"
    );

    let mut tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;
    tunnels.insert(instance.to_string(), tunnel);

    Ok(port)
}

pub fn stop_tunnel(instance: &str) -> Result<()> {
    let mut tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;
    if let Some(mut tunnel) = tunnels.remove(instance) {
        tunnel.stop()?;
    }
    Ok(())
}

/// Check if a tunnel is healthy (process alive + port listening)
/// Returns true if healthy, false if dead/unhealthy, error if tunnel doesn't exist
pub fn check_tunnel_health(instance: &str) -> Result<bool> {
    let mut tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;

    if let Some(tunnel) = tunnels.get_mut(instance) {
        let is_healthy = tunnel.is_healthy();

        // If unhealthy, automatically clean up the dead tunnel
        if !is_healthy {
            tracing::warn!(
                instance = instance,
                "Tunnel is unhealthy - process died or port stopped listening"
            );
            // We can't remove while holding the reference, so we'll mark it for removal
            // by dropping the tunnel. The caller should call stop_tunnel to clean up.
        }

        Ok(is_healthy)
    } else {
        Err(anyhow!("No tunnel exists for instance '{}'", instance))
    }
}

fn get_free_port() -> Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    Ok(port)
}
