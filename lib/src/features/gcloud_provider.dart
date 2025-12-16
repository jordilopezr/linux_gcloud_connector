import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/api.dart';
import '../bridge/gcloud.dart';

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
    print("Error listing projects: $e");
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
    print("Error listing instances for $projectId: $e");
    return [];
  }
});

// Gestión de Conexiones (Tunneling)
class ConnectionState {
  final String status; // 'disconnected', 'connecting', 'connected'
  final String? instanceName;
  final int? port;
  final String? error;

  ConnectionState({this.status = 'disconnected', this.instanceName, this.port, this.error});
}

final activeConnectionProvider = NotifierProvider<ConnectionNotifier, ConnectionState>(ConnectionNotifier.new);

class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => ConnectionState();

  Future<void> connect(String projectId, String zone, String instanceName) async {
    state = ConnectionState(status: 'connecting', instanceName: instanceName);
    try {
      final port = await startConnection(
        projectId: projectId, 
        zone: zone, 
        instanceName: instanceName, 
        remotePort: 3389 
      );
      state = ConnectionState(status: 'connected', instanceName: instanceName, port: port);
    } catch (e) {
      state = ConnectionState(status: 'disconnected', error: e.toString());
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final currentInstance = state.instanceName;
    if (currentInstance != null) {
      try {
        await stopConnection(instanceName: currentInstance);
      } catch (e) {
        print("Error stopping tunnel: $e");
      }
    }
    state = ConnectionState(status: 'disconnected');
  }

  Future<void> launchRDP() async {
    if (state.port != null && state.instanceName != null) {
      try {
        await launchRdp(port: state.port!, instanceName: state.instanceName!);
      } catch (e) {
        state = ConnectionState(
          status: state.status, 
          instanceName: state.instanceName, 
          port: state.port, 
          error: "Launch Failed: $e"
        );
      }
    }
  }
}