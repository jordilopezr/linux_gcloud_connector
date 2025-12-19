import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/api.dart/api.dart';
import '../bridge/api.dart/gcloud.dart';
import '../bridge/api.dart/remmina.dart';
import '../services/storage_service.dart';

/// Helper function to create composite tunnel key: "instanceName:port"
/// This allows multiple tunnels per instance (e.g., "test-vm:3389", "test-vm:5432")
String makeTunnelKey(String instanceName, int remotePort) {
  return '$instanceName:$remotePort';
}

/// Parse tunnel key back to instance and port
/// Returns (instanceName, remotePort) or null if invalid format
(String, int)? parseTunnelKey(String key) {
  final parts = key.split(':');
  if (parts.length != 2) return null;

  final port = int.tryParse(parts[1]);
  if (port == null) return null;

  return (parts[0], port);
}

// Estado para la instalación/auth
final gcloudStatusProvider = FutureProvider<Map<String, bool>>((ref) async {
  final installed = await checkGcloudInstalled();
  if (!installed) return {'installed': false, 'authenticated': false};
  
  final authenticated = await checkGcloudAuth();
  return {'installed': true, 'authenticated': authenticated};
});

// Provider para la lista de proyectos
final projectsProvider = FutureProvider<List<GcpProject>>((ref) async {
  final status = await ref.watch(gcloudStatusProvider.future);
  if (status['authenticated'] != true) return [];
  
  // Directly rethrow the error so the UI can catch and display it
  return await listProjects();
});

// Provider para el proyecto seleccionado
final selectedProjectProvider = NotifierProvider<SelectedProjectNotifier, String?>(SelectedProjectNotifier.new);

class SelectedProjectNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Attempt to load last selected project from storage
    return StorageService().getLastProject();
  }

  void select(String? projectId) {
    state = projectId;
    if (projectId != null) {
      StorageService().saveLastProject(projectId);
    }
  }
}

// Provider para la lista de instancias
final instancesProvider = FutureProvider<List<GcpInstance>>((ref) async {
  final projectId = ref.watch(selectedProjectProvider);
  if (projectId == null) return [];
  
  // Directly rethrow the error so the UI can catch and display it
  return await listInstances(projectId: projectId);
});

// UI Selection State
final selectedInstanceProvider = NotifierProvider<SelectedInstanceNotifier, GcpInstance?>(SelectedInstanceNotifier.new);

class SelectedInstanceNotifier extends Notifier<GcpInstance?> {
  @override
  GcpInstance? build() => null;

  void select(GcpInstance? instance) {
    state = instance;
  }
}

// Gestión de Conexiones (Tunneling) - Soporte Múltiple
class TunnelState {
  final String status; // 'disconnected', 'connecting', 'connected', 'error'
  final int? port; // Local port where tunnel listens (e.g., 40759)
  final int? remotePort; // Remote port being forwarded (e.g., 3389 for RDP, 22 for SSH)
  final String? error;
  final DateTime? createdAt; // When the tunnel was established
  final DateTime? lastHealthCheck; // Last health verification timestamp

  const TunnelState({
    this.status = 'disconnected',
    this.port,
    this.remotePort,
    this.error,
    this.createdAt,
    this.lastHealthCheck,
  });

  /// Calculate tunnel uptime in a human-readable format
  String get uptime {
    if (createdAt == null) return 'N/A';
    final duration = DateTime.now().difference(createdAt!);

    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  /// Get last health check as relative time
  String get lastCheckRelative {
    if (lastHealthCheck == null) return 'Never';
    final duration = DateTime.now().difference(lastHealthCheck!);

    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ago';
    } else {
      return '${duration.inSeconds}s ago';
    }
  }
}

// Mapa: InstanceName -> TunnelState
final activeConnectionsProvider = NotifierProvider<ConnectionsNotifier, Map<String, TunnelState>>(ConnectionsNotifier.new);

class ConnectionsNotifier extends Notifier<Map<String, TunnelState>> {
  Timer? _healthCheckTimer;

  @override
  Map<String, TunnelState> build() {
    // Start health check timer: check every 30 seconds
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      _checkAllTunnels,
    );

    // Cancel timer when notifier is disposed
    ref.onDispose(() {
      _healthCheckTimer?.cancel();
    });

    return {};
  }

  /// Periodic health check for all active tunnels
  Future<void> _checkAllTunnels(Timer timer) async {
    final currentConnections = {...state};

    for (var entry in currentConnections.entries) {
      final instanceName = entry.key;
      final tunnelState = entry.value;

      // Only check tunnels marked as 'connected'
      if (tunnelState.status == 'connected' && tunnelState.remotePort != null) {
        try {
          final isHealthy = await checkConnectionHealth(
            instanceName: instanceName,
            remotePort: tunnelState.remotePort!, // Use the stored remote port
          );

          if (!isHealthy) {
            // Tunnel died! Update state to error
            debugPrint('⚠️ HEALTH CHECK FAILED: Tunnel for $instanceName is unhealthy (process dead or port not listening)');

            state = {
              ...state,
              instanceName: TunnelState(
                status: 'error',
                port: tunnelState.port,
                remotePort: tunnelState.remotePort, // Preserve remote port
                error: 'Tunnel became unhealthy (process died or port stopped listening)',
                createdAt: tunnelState.createdAt, // Preserve creation time
                lastHealthCheck: DateTime.now(), // Update check time
              ),
            };
          } else {
            // Tunnel is healthy - update last health check time
            state = {
              ...state,
              instanceName: TunnelState(
                status: 'connected',
                port: tunnelState.port,
                remotePort: tunnelState.remotePort, // Preserve remote port
                error: tunnelState.error != null ? null : tunnelState.error, // Clear error if it existed
                createdAt: tunnelState.createdAt, // Preserve creation time
                lastHealthCheck: DateTime.now(), // Update check time
              ),
            };
          }
        } catch (e) {
          // Health check itself failed (e.g., tunnel doesn't exist)
          debugPrint('Health check error for $instanceName: $e');

          // Mark as error if it was connected
          state = {
            ...state,
            instanceName: TunnelState(
              status: 'error',
              port: tunnelState.port,
              remotePort: tunnelState.remotePort, // Preserve remote port
              error: 'Health check failed: ${e.toString()}',
              createdAt: tunnelState.createdAt, // Preserve creation time
              lastHealthCheck: DateTime.now(), // Update check time
            ),
          };
        }
      }
    }
  }

  Future<void> connect(
    String projectId,
    String zone,
    String instanceName, {
    int remotePort = 3389, // Default to RDP port, configurable via Custom Tunnel dialog
  }) async {
    // Use composite key to support multiple tunnels per instance
    final tunnelKey = makeTunnelKey(instanceName, remotePort);

    // Actualizar estado de ESTE túnel específico a 'connecting'
    state = {
      ...state,
      tunnelKey: const TunnelState(status: 'connecting')
    };

    try {
      final port = await startConnection(
        projectId: projectId,
        zone: zone,
        instanceName: instanceName,
        remotePort: remotePort,
      );

      // Actualizar a 'connected'
      final now = DateTime.now();
      state = {
        ...state,
        tunnelKey: TunnelState(
          status: 'connected',
          port: port,
          remotePort: remotePort, // Store the remote port
          createdAt: now, // Set creation time
          lastHealthCheck: now, // Initial health check time
        )
      };
    } catch (e) {
      // Error solo en este túnel específico
      state = {
        ...state,
        tunnelKey: TunnelState(
          status: 'error',
          remotePort: remotePort,
          error: e.toString(),
        )
      };
      // No hacemos rethrow para no romper la UI general, el estado refleja el error
    }
  }

  Future<void> disconnect(String instanceName, int remotePort) async {
    final tunnelKey = makeTunnelKey(instanceName, remotePort);

    try {
      await stopConnection(
        instanceName: instanceName,
        remotePort: remotePort,
      );
    } catch (e) {
      debugPrint("Error stopping tunnel $tunnelKey: $e");
    }

    // Remove from map - keeps the map clean
    final newState = Map<String, TunnelState>.from(state);
    newState.remove(tunnelKey);
    state = newState;
  }

  /// Disconnect ALL tunnels for a given instance (all ports)
  Future<void> disconnectAllForInstance(String instanceName) async {
    final tunnelsToRemove = state.entries
        .where((entry) => entry.key.startsWith('$instanceName:'))
        .toList();

    for (final entry in tunnelsToRemove) {
      final parsed = parseTunnelKey(entry.key);
      if (parsed != null) {
        await disconnect(parsed.$1, parsed.$2);
      }
    }
  }

  Future<void> launchRDP(String projectId, String zone, String instanceName, {RdpSettings? settings}) async {
    const rdpPort = 3389;
    final tunnelKey = makeTunnelKey(instanceName, rdpPort);
    final currentTunnel = state[tunnelKey];
    bool alreadyConnected = currentTunnel?.status == 'connected' && currentTunnel?.port != null;

    try {
      if (!alreadyConnected) {
        // Auto-connect RDP tunnel (port 3389)
        await connect(projectId, zone, instanceName, remotePort: rdpPort);
        // Check if connection succeeded
        final newTunnel = state[tunnelKey];
        if (newTunnel?.status != 'connected') {
           return; // Failed to connect, stop here.
        }
      }

      // Launch Remmina
      final activeTunnel = state[tunnelKey];
      if (activeTunnel?.port != null) {
        try {
          await launchRdp(
            port: activeTunnel!.port!,
            instanceName: instanceName,
            settings: settings ?? const RdpSettings(fullscreen: false)
          );
        } catch (e) {
           // Connection is still good, just launch failed
           state = {
             ...state,
             tunnelKey: TunnelState(
               status: 'connected',
               port: activeTunnel?.port,
               remotePort: rdpPort,
               error: "Launch Failed: $e", // Show transient error
               createdAt: activeTunnel?.createdAt, // Preserve creation time
               lastHealthCheck: activeTunnel?.lastHealthCheck, // Preserve last check
             )
           };
        }
      }
    } catch (e) {
       state = {
         ...state,
         tunnelKey: TunnelState(status: 'error', remotePort: rdpPort, error: "Auto-connect failed: $e")
       };
    }
  }
}