import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/bridge/api.dart';
import 'src/bridge/frb_generated.dart';
import 'src/bridge/gcloud.dart';
import 'src/features/gcloud_provider.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linux Cloud Connector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(gcloudStatusProvider);
    
    // Watch connection state for errors handling
    ref.listen(activeConnectionProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${next.error}"), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Linux Cloud Connector')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Section
            _buildStatusSection(context, ref, statusAsync),
            const Divider(height: 30),
            
            // Project Selector
            statusAsync.when(
              data: (status) => status['authenticated'] == true 
                  ? const ProjectSelector() 
                  : const SizedBox.shrink(),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text("Error checking status"),
            ),
            
            const SizedBox(height: 20),
            
            // Instance List
             const Expanded(child: InstanceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context, WidgetRef ref, AsyncValue<Map<String, bool>> statusAsync) {
    return statusAsync.when(
      data: (status) {
        final installed = status['installed'] ?? false;
        final authenticated = status['authenticated'] ?? false;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(label: "Gcloud Installed", active: installed),
                const SizedBox(width: 10),
                _StatusChip(label: "Authenticated", active: authenticated),
              ],
            ),
            if (installed && !authenticated) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Launching browser for login...")));
                    await gcloudLogin();
                    ref.invalidate(gcloudStatusProvider);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Login Failed: $e")));
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text("Login to Google Cloud"),
              )
            ]
          ],
        );
      },
      loading: () => const Text("Checking gcloud..."),
      error: (err, stack) => Text("Error: $err"),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  const _StatusChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.error,
        color: active ? Colors.green : Colors.red,
      ),
      label: Text(label),
      backgroundColor: active ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
    );
  }
}

class ProjectSelector extends ConsumerWidget {
  const ProjectSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final selectedProject = ref.watch(selectedProjectProvider);

    return projectsAsync.when(
      data: (projects) {
        if (projects.isEmpty) return const Text("No projects found.");
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Select Google Cloud Project',
            border: OutlineInputBorder(),
          ),
          value: selectedProject,
          items: projects.map((p) {
            return DropdownMenuItem(
              value: p.projectId,
              child: Text("${p.name ?? p.projectId} (${p.projectId})"),
            );
          }).toList(),
          onChanged: (value) {
            ref.read(selectedProjectProvider.notifier).select(value);
          },
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (err, _) => Text("Error loading projects: $err"),
    );
  }
}

class InstanceList extends ConsumerWidget {
  const InstanceList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedProject = ref.watch(selectedProjectProvider);
    if (selectedProject == null) {
      return const Center(child: Text("Select a project to view instances."));
    }

    final instancesAsync = ref.watch(instancesProvider);
    final connectionState = ref.watch(activeConnectionProvider);

    return instancesAsync.when(
      data: (instances) {
        if (instances.isEmpty) return const Center(child: Text("No instances found in this project."));
        return ListView.builder(
          itemCount: instances.length,
          itemBuilder: (context, index) {
            final instance = instances[index];
            final isRunning = instance.status == "RUNNING";
            
            final isConnectedToThis = connectionState.status == 'connected' && connectionState.instanceName == instance.name;
            final isConnectingToThis = connectionState.status == 'connecting' && connectionState.instanceName == instance.name;
            final isBusy = connectionState.status != 'disconnected' && !isConnectedToThis; 

            return Card(
              child: ListTile(
                leading: Icon(
                  Icons.computer,
                  color: isRunning ? Colors.green : Colors.grey,
                ),
                title: Text(instance.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${instance.zone} • ${instance.status}"),
                    if (isConnectedToThis) ...[
                      const SizedBox(height: 5),
                      Text(
                        "Tunnel Active: localhost:${connectionState.port}",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.desktop_windows, size: 16),
                        label: const Text("Launch Remote Desktop"),
                        onPressed: () {
                           ref.read(activeConnectionProvider.notifier).launchRDP();
                        },
                      )
                    ]
                  ],
                ),
                trailing: SizedBox(
                  width: 130,
                  child: isConnectingToThis
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnectedToThis ? Colors.red : null,
                            foregroundColor: isConnectedToThis ? Colors.white : null,
                          ),
                          onPressed: (isRunning && !isBusy) ? () {
                            if (isConnectedToThis) {
                              ref.read(activeConnectionProvider.notifier).disconnect();
                            } else {
                              ref.read(activeConnectionProvider.notifier).connect(selectedProject, instance.zone, instance.name);
                            }
                          } : null,
                          child: Text(isConnectedToThis ? "Disconnect" : "Connect"),
                        ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text("Error loading instances: $err")),
    );
  }
}
