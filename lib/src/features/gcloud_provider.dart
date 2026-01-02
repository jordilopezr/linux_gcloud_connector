import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/api.dart/api.dart';
import '../bridge/api.dart/gcloud.dart';
import '../bridge/api.dart/gcloud_client_poc.dart';
import '../bridge/api.dart/remmina.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'settings_provider.dart';

// ==========================================
// GOOGLE CLOUD CLIENT LIBRARIES PROVIDERS
// ==========================================

// Temporary workaround: Use GcpProjectClientLib as GcpProject until FRB generates both types
typedef GcpProject = GcpProjectClientLib;

// ==========================================
// API METHOD SELECTION (CLI vs Client Libraries)
// ==========================================

enum GcpApiMethod {
  cli,           // Traditional gcloud CLI (spawns processes)
  clientLibrary  // Google Cloud Client Libraries (REST API)
}

/// Provider to toggle between CLI and Client Libraries
final apiMethodProvider = NotifierProvider<ApiMethodNotifier, GcpApiMethod>(ApiMethodNotifier.new);

class ApiMethodNotifier extends Notifier<GcpApiMethod> {
  @override
  GcpApiMethod build() {
    // Load last selected method from storage
    final lastMethod = StorageService().getLastApiMethod();
    return lastMethod == 'clientLibrary'
        ? GcpApiMethod.clientLibrary
        : GcpApiMethod.cli;
  }

  void setMethod(GcpApiMethod method) {
    state = method;
    // Persist selection
    final methodString = method == GcpApiMethod.clientLibrary
        ? 'clientLibrary'
        : 'cli';
    StorageService().saveApiMethod(methodString);
  }
}

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

  // Use selected API method (CLI or Client Libraries)
  final apiMethod = ref.watch(apiMethodProvider);

  if (apiMethod == GcpApiMethod.clientLibrary) {
    // Use Client Libraries (faster)
    final clientLibInstances = await listInstancesClientLib(projectId: projectId);
    // Convert GcpInstanceClientLib to GcpInstance for UI compatibility
    return clientLibInstances.map((inst) => GcpInstance(
      name: inst.name,
      status: inst.status,
      zone: inst.zone,
      machineType: inst.machineType,
      cpuCount: inst.cpuCount,
      memoryMb: inst.memoryMb,
      diskGb: inst.diskGb,
    )).toList();
  } else {
    // Use gcloud CLI (traditional)
    return await listInstances(projectId: projectId);
  }
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

            // Send notification about tunnel failure
            final parsed = parseTunnelKey(instanceName);
            if (parsed != null) {
              final selectedProject = ref.read(selectedProjectProvider);
              NotificationService().notifyTunnelFailed(
                instanceName: parsed.$1,
                remotePort: parsed.$2,
                project: selectedProject ?? 'unknown',
                zone: 'unknown', // We don't have zone info here, but we can improve this later
              );
            }

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

  Future<int?> connect(
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
      return port;
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
      return null;
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
            settings: settings ?? const RdpSettings(fullscreen: false, ignoreCertificate: false)
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

  /// Refresh instances list after lifecycle operations
  Future<void> refreshInstances(String projectId) async {
    // Invalidate the instances provider to force a refresh
    ref.invalidate(instancesProvider);
  }

  /// Start instance using selected API method (CLI or Client Libraries)
  Future<void> startInstanceWithMethod(String projectId, String zone, String instanceName) async {
    final method = ref.read(apiMethodProvider);

    debugPrint('Starting instance using ${method == GcpApiMethod.cli ? "CLI" : "Client Libraries"}');

    try {
      if (method == GcpApiMethod.clientLibrary) {
        await startInstanceClientLib(projectId: projectId, zone: zone, instanceName: instanceName);
      } else {
        await startInstance(projectId: projectId, zone: zone, instanceName: instanceName);
      }
      await refreshInstances(projectId);

      // Send success notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Start',
        success: true,
        project: projectId,
        zone: zone,
      );
    } catch (e) {
      debugPrint('Error starting instance: $e');

      // Send failure notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Start',
        success: false,
        project: projectId,
        zone: zone,
        errorMessage: e.toString(),
      );

      rethrow;
    }
  }

  /// Stop instance using selected API method (CLI or Client Libraries)
  Future<void> stopInstanceWithMethod(String projectId, String zone, String instanceName) async {
    final method = ref.read(apiMethodProvider);

    debugPrint('Stopping instance using ${method == GcpApiMethod.cli ? "CLI" : "Client Libraries"}');

    try {
      if (method == GcpApiMethod.clientLibrary) {
        await stopInstanceClientLib(projectId: projectId, zone: zone, instanceName: instanceName);
      } else {
        await stopInstance(projectId: projectId, zone: zone, instanceName: instanceName);
      }
      await refreshInstances(projectId);

      // Send success notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Stop',
        success: true,
        project: projectId,
        zone: zone,
      );
    } catch (e) {
      debugPrint('Error stopping instance: $e');

      // Send failure notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Stop',
        success: false,
        project: projectId,
        zone: zone,
        errorMessage: e.toString(),
      );

      rethrow;
    }
  }

  /// Reset instance using selected API method (CLI or Client Libraries)
  Future<void> resetInstanceWithMethod(String projectId, String zone, String instanceName) async {
    final method = ref.read(apiMethodProvider);

    debugPrint('Resetting instance using ${method == GcpApiMethod.cli ? "CLI" : "Client Libraries"}');

    try {
      if (method == GcpApiMethod.clientLibrary) {
        await resetInstanceClientLib(projectId: projectId, zone: zone, instanceName: instanceName);
      } else {
        await resetInstance(projectId: projectId, zone: zone, instanceName: instanceName);
      }
      await refreshInstances(projectId);

      // Send success notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Reset',
        success: true,
        project: projectId,
        zone: zone,
      );
    } catch (e) {
      debugPrint('Error resetting instance: $e');

      // Send failure notification
      NotificationService().notifyLifecycleOperation(
        instanceName: instanceName,
        operation: 'Reset',
        success: false,
        project: projectId,
        zone: zone,
        errorMessage: e.toString(),
      );

      rethrow;
    }
  }
}

// ==========================================
// AUTO-REFRESH - SMART INSTANCE MONITORING
// ==========================================

/// Auto-refresh state
class AutoRefreshState {
  final bool enabled;
  final Duration interval;
  final Map<String, String> lastKnownStates; // instanceName -> status

  const AutoRefreshState({
    this.enabled = false,
    this.interval = const Duration(seconds: 30),
    this.lastKnownStates = const {},
  });

  AutoRefreshState copyWith({
    bool? enabled,
    Duration? interval,
    Map<String, String>? lastKnownStates,
  }) {
    return AutoRefreshState(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      lastKnownStates: lastKnownStates ?? this.lastKnownStates,
    );
  }
}

/// Provider for auto-refresh functionality
final autoRefreshProvider = NotifierProvider<AutoRefreshNotifier, AutoRefreshState>(AutoRefreshNotifier.new);

class AutoRefreshNotifier extends Notifier<AutoRefreshState> {
  Timer? _refreshTimer;

  @override
  AutoRefreshState build() {
    // Cancel timer when notifier is disposed
    ref.onDispose(() {
      _refreshTimer?.cancel();
    });

    return const AutoRefreshState();
  }

  void toggle() {
    if (state.enabled) {
      disable();
    } else {
      enable();
    }
  }

  void enable() {
    state = state.copyWith(enabled: true);
    _startRefreshTimer();
    debugPrint('🔄 Auto-refresh enabled (${state.interval.inSeconds}s interval)');
  }

  void disable() {
    state = state.copyWith(enabled: false);
    _stopRefreshTimer();
    debugPrint('⏸️  Auto-refresh disabled');
  }

  void setInterval(Duration interval) {
    state = state.copyWith(interval: interval);
    if (state.enabled) {
      // Restart timer with new interval
      _stopRefreshTimer();
      _startRefreshTimer();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(state.interval, (_) {
      _refreshInstances();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refreshInstances() async {
    final selectedProject = ref.read(selectedProjectProvider);
    if (selectedProject == null) return;

    debugPrint('🔄 Auto-refresh: Refreshing instances for project $selectedProject');

    // Capture current states before refresh
    final previousStates = Map<String, String>.from(state.lastKnownStates);

    // Invalidate to trigger refresh
    ref.invalidate(instancesProvider);

    // Wait a bit for the provider to update
    await Future.delayed(const Duration(milliseconds: 500));

    // Get new states
    final instances = await ref.read(instancesProvider.future).catchError((e) {
      debugPrint('Error refreshing instances: $e');
      return <GcpInstance>[];
    });

    // Build new states map
    final newStates = <String, String>{};
    for (final instance in instances) {
      newStates[instance.name] = instance.status;
    }

    // Detect changes and send notifications
    for (final instance in instances) {
      final previousStatus = previousStates[instance.name];
      final currentStatus = instance.status;

      if (previousStatus != null && previousStatus != currentStatus) {
        debugPrint('🔔 State change detected: ${instance.name} $previousStatus → $currentStatus');

        // Send notification
        NotificationService().notifyVmStateChange(
          instanceName: instance.name,
          oldState: previousStatus,
          newState: currentStatus,
          project: selectedProject,
          zone: instance.zone,
        );
      }
    }

    // Update last known states
    state = state.copyWith(lastKnownStates: newStates);
  }

  /// Get state changes since last refresh
  Map<String, StateChange> getStateChanges(List<GcpInstance> currentInstances) {
    final changes = <String, StateChange>{};

    for (final instance in currentInstances) {
      final previousStatus = state.lastKnownStates[instance.name];
      if (previousStatus != null && previousStatus != instance.status) {
        changes[instance.name] = StateChange(
          instanceName: instance.name,
          from: previousStatus,
          to: instance.status,
        );
      }
    }

    return changes;
  }
}

/// Represents a state change for an instance
class StateChange {
  final String instanceName;
  final String from;
  final String to;

  const StateChange({
    required this.instanceName,
    required this.from,
    required this.to,
  });

  @override
  String toString() => '$instanceName: $from → $to';
}

// ==========================================
// GOOGLE CLOUD CLIENT LIBRARIES - NEW APPROACH
// ==========================================

/// Provider for testing Client Libraries authentication
/// This uses Application Default Credentials (ADC) from gcloud
final clientLibAuthTestProvider = FutureProvider<String>((ref) async {
  return await testGcpAuthentication();
});

/// Provider for listing projects using Client Libraries (REST API)
/// This is significantly faster than gcloud CLI (5-20ms vs 60-250ms)
final projectsClientLibProvider = FutureProvider<List<GcpProjectClientLib>>((ref) async {
  final status = await ref.watch(gcloudStatusProvider.future);
  if (status['authenticated'] != true) return [];

  return await listProjectsClientLib();
});

/// Provider for benchmark comparison: Client Libraries vs gcloud CLI
/// Returns formatted string with performance comparison
final benchmarkProvider = FutureProvider<String>((ref) async {
  final status = await ref.watch(gcloudStatusProvider.future);
  if (status['authenticated'] != true) {
    return 'Please authenticate with gcloud first';
  }

  return await benchmarkProjectsListing();
});

// ==========================================
// COMPUTE ENGINE CLIENT LIBRARIES PROVIDERS
// ==========================================

/// Provider for listing instances using Client Libraries (REST API)
/// This is significantly faster than gcloud CLI for listing instances
final instancesClientLibProvider = FutureProvider.family<List<GcpInstanceClientLib>, String>((ref, projectId) async {
  if (projectId.isEmpty) return [];

  return await listInstancesClientLib(projectId: projectId);
});