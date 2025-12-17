import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/api.dart';
import '../bridge/gcloud.dart';
import '../bridge/remmina.dart';

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
  
  try {
    return await listProjects();
  } catch (e) {
    debugPrint("Error listing projects: $e");
    return [];
  }
});

// Provider para el proyecto seleccionado
final selectedProjectProvider = NotifierProvider<SelectedProjectNotifier, String?>(SelectedProjectNotifier.new);

class SelectedProjectNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? projectId) {
    state = projectId;
  }
}

// Provider para la lista de instancias
final instancesProvider = FutureProvider<List<GcpInstance>>((ref) async {
  final projectId = ref.watch(selectedProjectProvider);
  if (projectId == null) return [];
  
  try {
    return await listInstances(projectId: projectId);
  } catch (e) {
    debugPrint("Error listing instances for $projectId: $e");
    return [];
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
  final int? port;
  final String? error;

  const TunnelState({this.status = 'disconnected', this.port, this.error});
}

// Mapa: InstanceName -> TunnelState
final activeConnectionsProvider = NotifierProvider<ConnectionsNotifier, Map<String, TunnelState>>(ConnectionsNotifier.new);

class ConnectionsNotifier extends Notifier<Map<String, TunnelState>> {
  @override
  Map<String, TunnelState> build() => {};

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
      state = {
        ...state,
        instanceName: TunnelState(status: 'connected', port: port)
      };
    } catch (e) {
      // Error solo en esta instancia
      state = {
        ...state,
        instanceName: TunnelState(status: 'error', error: e.toString())
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
               error: "Launch Failed: $e" // Show transient error
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