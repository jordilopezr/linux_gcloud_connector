import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/api.dart';
import '../bridge/gcloud.dart';
import '../bridge/remmina.dart';
import '../services/storage_service.dart';

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
  final int? port;
  final String? error;
  final DateTime? createdAt; // When the tunnel was established
  final DateTime? lastHealthCheck; // Last health verification timestamp

  const TunnelState({
    this.status = 'disconnected',
    this.port,
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
      if (tunnelState.status == 'connected') {
        try {
          final isHealthy = await checkConnectionHealth(
            instanceName: instanceName,
          );

          if (!isHealthy) {
            // Tunnel died! Update state to error
            debugPrint('⚠️ HEALTH CHECK FAILED: Tunnel for $instanceName is unhealthy (process dead or port not listening)');

            state = {
              ...state,
              instanceName: TunnelState(
                status: 'error',
                port: tunnelState.port,
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
              error: 'Health check failed: ${e.toString()}',
              createdAt: tunnelState.createdAt, // Preserve creation time
              lastHealthCheck: DateTime.now(), // Update check time
            ),
          };
        }
      }
    }
  }

  Future<void> connect(String projectId, String zone, String instanceName) async {
    // Actualizar estado de ESTA instancia a 'connecting'
    state = {
      ...state,
      instanceName: const TunnelState(status: 'connecting')
    };

    try {
      final port = await startConnection(
        projectId: projectId, 
        zone: zone, 
        instanceName: instanceName, 
        remotePort: 3389 
      );
      
      // Actualizar a 'connected'
      final now = DateTime.now();
      state = {
        ...state,
        instanceName: TunnelState(
          status: 'connected',
          port: port,
          createdAt: now, // Set creation time
          lastHealthCheck: now, // Initial health check time
        )
      };
    } catch (e) {
      // Error solo en esta instancia
      state = {
        ...state,
        instanceName: TunnelState(
          status: 'error',
          error: e.toString(),
        )
      };
      // No hacemos rethrow para no romper la UI general, el estado refleja el error
    }
  }

  Future<void> disconnect(String instanceName) async {
    // Optimistic update or keep current while processing? Let's just try to stop.
    try {
      await stopConnection(instanceName: instanceName);
    } catch (e) {
      debugPrint("Error stopping tunnel for $instanceName: $e");
    }
    
    // Remove from map or set to disconnected. 
    // Removing keeps the map clean.
    final newState = Map<String, TunnelState>.from(state);
    newState.remove(instanceName);
    state = newState;
  }

  Future<void> launchRDP(String projectId, String zone, String instanceName, {RdpSettings? settings}) async {
    final currentTunnel = state[instanceName];
    bool alreadyConnected = currentTunnel?.status == 'connected' && currentTunnel?.port != null;

    try {
      if (!alreadyConnected) {
        // Auto-connect specific instance
        await connect(projectId, zone, instanceName);
        // Check if connection succeeded
        final newTunnel = state[instanceName];
        if (newTunnel?.status != 'connected') {
           return; // Failed to connect, stop here.
        }
      }

      // Launch Remmina
      final activeTunnel = state[instanceName];
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
             instanceName: TunnelState(
               status: 'connected',
               port: activeTunnel?.port,
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
         instanceName: TunnelState(status: 'error', error: "Auto-connect failed: $e")
       };
    }
  }
}