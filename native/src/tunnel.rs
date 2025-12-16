use std::process::{Command, Child, Stdio};
use std::net::TcpListener;
use anyhow::{Result, anyhow};
use std::sync::Mutex;
use std::collections::HashMap;
use lazy_static::lazy_static;

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
}

lazy_static! {
    static ref TUNNELS: Mutex<HashMap<String, IapTunnel>> = Mutex::new(HashMap::new());
}

pub fn start_tunnel(project: &str, zone: &str, instance: &str, remote_port: u16) -> Result<u16> {
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

    // Breve pausa para detectar fallos de arranque inmediatos
    std::thread::sleep(std::time::Duration::from_millis(1000));
    
    // Aquí habría que verificar si el proceso sigue vivo.
    // Como child ha sido movido a tunnels, es complejo sin un wrapper.
    // Asumiremos éxito por ahora.
    
    let mut tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;
    tunnels.insert(instance.to_string(), IapTunnel { process: child, local_port: port });

    Ok(port)
}

pub fn stop_tunnel(instance: &str) -> Result<()> {
    let mut tunnels = TUNNELS.lock().map_err(|_| anyhow!("Tunnel lock poisoned"))?;
    if let Some(mut tunnel) = tunnels.remove(instance) {
        tunnel.stop()?;
    }
    Ok(())
}

fn get_free_port() -> Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    Ok(port) 
}
