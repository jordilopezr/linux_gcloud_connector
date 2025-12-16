import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/bridge/api.dart';
import 'src/bridge/frb_generated.dart';
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
    
    ref.listen(activeConnectionProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${next.error}"), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux Cloud Connector'),
        actions: [
          statusAsync.when(
            data: (status) => status['authenticated'] == true 
                ? IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Logout',
                    onPressed: () async {
                       final confirm = await showDialog<bool>(
                         context: context,
                         builder: (ctx) => AlertDialog(
                           title: const Text("Logout"),
                           content: const Text("This will revoke your Google Cloud credentials from this machine. Are you sure?"),
                           actions: [
                             TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                             TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Logout", style: TextStyle(color: Colors.red))),
                           ],
                         )
                       );
                       
                       if (confirm == true) {
                         try {
                           await gcloudLogout();
                           ref.invalidate(gcloudStatusProvider);
                           // ignore: use_build_context_synchronously
                           ref.read(activeConnectionProvider.notifier).disconnect();
                         } catch (e) {
                           if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Logout Error: $e")));
                           }
                         }
                       }
                    },
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => _showAboutDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusSection(context, ref, statusAsync),
            const Divider(height: 30),
            
            statusAsync.when(
              data: (status) => status['authenticated'] == true 
                  ? const ProjectSelector() 
                  : const SizedBox.shrink(),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text("Error checking status"),
            ),
            
            const SizedBox(height: 20),
            
             const Expanded(child: InstanceList()),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Linux Cloud Connector',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 Jordi Lopez Reyes',
      applicationIcon: const Icon(Icons.cloud_circle, size: 48, color: Colors.blueAccent),
      children: [
        const SizedBox(height: 20),
        const Text("A native tool to simplify Google Cloud IAP connections on Linux."),
        const SizedBox(height: 20),
        const Text("Key Features:", style: TextStyle(fontWeight: FontWeight.bold)),
        const Text("• Auto-Discovery (Projects & VMs)"),
        const Text("• Secure IAP Tunneling"),
        const Text("• Smart RDP Launch (Remmina)"),
        const Text("• Native SSH Terminal Support"),
        const Divider(height: 30),
        const Text("Developer: Jordi Lopez Reyes"),
        const SelectableText("Email: aim@jordilopezr.com", style: TextStyle(color: Colors.blue)),
        const SizedBox(height: 10),
        const Text("Source Code:"),
        const SelectableText(
          "https://github.com/jordilopezr/linux_gcloud_connector", 
          style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)
        ),
      ],
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Login Failed: $e")));
                    }
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
      backgroundColor: active ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
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
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.computer, color: isRunning ? Colors.green : Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(instance.name, style: Theme.of(context).textTheme.titleMedium),
                              Text("${instance.zone} • ${instance.status}", style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (isConnectingToThis)
                           const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    if (isConnectedToThis)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "Tunnel Active: localhost:${connectionState.port}",
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    
                    if (isRunning) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          // SSH Button
                          OutlinedButton.icon(
                            icon: const Icon(Icons.terminal, size: 18),
                            label: const Text("SSH"),
                            onPressed: isBusy ? null : () async {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(content: Text("Launching SSH for ${instance.name}...")),
                               );
                               try {
                                 await launchSsh(projectId: selectedProject, zone: instance.zone, instanceName: instance.name);
                               } catch (e) {
                                 if (context.mounted) {
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red),
                                   );
                                 }
                               }
                            },
                          ),
                          // RDP Button (Auto-connects)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.desktop_windows, size: 18),
                            label: const Text("RDP"),
                            onPressed: isBusy ? null : () {
                               ref.read(activeConnectionProvider.notifier).launchRDP(
                                 selectedProject, instance.zone, instance.name
                               );
                            },
                          ),
                          // Manual Connect/Disconnect
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isConnectedToThis ? Colors.red.withValues(alpha: 0.1) : null,
                              foregroundColor: isConnectedToThis ? Colors.red : null,
                            ),
                            onPressed: isBusy ? null : () {
                              if (isConnectedToThis) {
                                ref.read(activeConnectionProvider.notifier).disconnect();
                              } else {
                                ref.read(activeConnectionProvider.notifier).connect(selectedProject, instance.zone, instance.name);
                              }
                            },
                            child: Text(isConnectedToThis ? "Disconnect" : "Create Tunnel"),
                          ),
                        ],
                      )
                    ]
                  ],
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