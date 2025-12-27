import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/bridge/api.dart/api.dart';
import 'src/bridge/api.dart/gcloud.dart';
import 'src/bridge/api.dart/remmina.dart';
import 'src/bridge/api.dart/frb_generated.dart';
import 'src/features/gcloud_provider.dart';
import 'src/features/sftp_browser.dart';
import 'src/services/storage_service.dart';

/// Helper: Get all active tunnels for a given instance
List<MapEntry<String, TunnelState>> getTunnelsForInstance(
  Map<String, TunnelState> connections,
  String instanceName,
) {
  return connections.entries
      .where((entry) => entry.key.startsWith('$instanceName:'))
      .toList();
}

/// Helper: Check if instance has any active tunnel
bool hasAnyActiveTunnel(Map<String, TunnelState> connections, String instanceName) {
  return connections.keys.any((key) =>
      key.startsWith('$instanceName:') &&
      connections[key]?.status == 'connected');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
  await RustLib.init();

  // Initialize structured logging system
  try {
    await initLoggingSystem();
    debugPrint('✓ Logging system initialized');
  } catch (e) {
    debugPrint('⚠️  Failed to initialize logging: $e');
    // Continue anyway - logging is not critical for app functionality
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linux Cloud Connector',
      debugShowCheckedModeBanner: false,
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
                           ref.invalidate(activeConnectionsProvider);
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
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Logs',
            onPressed: () => _exportLogs(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => _showAboutDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: statusAsync.when(
        data: (status) {
           if (status['installed'] != true) {
             return const Center(child: Text("Google Cloud CLI not installed."));
           }
           if (status['authenticated'] != true) {
             return Center(
               child: ElevatedButton.icon(
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
                ),
             );
           }
           
           return const Row(
             children: [
               SizedBox(
                 width: 300,
                 child: ResourceTree(),
               ),
               VerticalDivider(width: 1),
               Expanded(
                 child: InstanceDetailPane(),
               ),
             ],
           );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text("Error: $err")),
      ),
    );
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('Exporting logs...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Call Rust export function
      final exportPath = await exportLogsToFile();

      // Show success dialog with path
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Logs Exported Successfully'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All logs have been consolidated and exported to:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    exportPath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can share this file for troubleshooting.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export logs: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Linux Cloud Connector',
      applicationVersion: '1.4.0',
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
        const Text("• Credential Persistence & Secure Storage"),
        const Text("• Instance Search & Filtering"),
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
}

class ResourceTree extends ConsumerStatefulWidget {
  const ResourceTree({super.key});

  @override
  ConsumerState<ResourceTree> createState() => _ResourceTreeState();
}

class _ResourceTreeState extends ConsumerState<ResourceTree> {
  final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'All'; // 'All', 'RUNNING', 'STOPPED'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: ProjectSelector(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search instances...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              isDense: true,
            ),
            onChanged: (value) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              _buildFilterChip('All'),
              const SizedBox(width: 8),
              _buildFilterChip('RUNNING'),
              const SizedBox(width: 8),
              _buildFilterChip('STOPPED'), // Usually TERMINATED in API, but simpler for UI
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildInstanceList(context, ref),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filterStatus == label;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _filterStatus = label;
        });
      },
      checkmarkColor: Colors.white,
      selectedColor: Colors.blueAccent,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildInstanceList(BuildContext context, WidgetRef ref) {
    final instancesAsync = ref.watch(instancesProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final selectedInstance = ref.watch(selectedInstanceProvider);
    final connections = ref.watch(activeConnectionsProvider);

    if (selectedProject == null) {
      return const Center(child: Text("Select a project", style: TextStyle(color: Colors.grey)));
    }

    return instancesAsync.when(
      data: (instances) {
        if (instances.isEmpty) return const Center(child: Text("No instances found."));
        
        // Filter instances
        final query = _searchController.text.toLowerCase();
        final filteredInstances = instances.where((inst) {
          final matchesName = inst.name.toLowerCase().contains(query);
          final matchesStatus = _filterStatus == 'All' || 
                                (_filterStatus == 'RUNNING' && inst.status == 'RUNNING') ||
                                (_filterStatus == 'STOPPED' && inst.status != 'RUNNING');
          return matchesName && matchesStatus;
        }).toList();

        if (filteredInstances.isEmpty) return const Center(child: Text("No matching instances."));

        // Group instances by Zone
        final Map<String, List<GcpInstance>> byZone = {};
        for (var instance in filteredInstances) {
          byZone.putIfAbsent(instance.zone, () => []).add(instance);
        }

        return ListView(
          children: byZone.entries.map((entry) {
            final zone = entry.key;
            final zoneInstances = entry.value;
            return ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.location_on_outlined, size: 20),
              title: Text(zone, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              children: zoneInstances.map((instance) {
                final isSelected = selectedInstance?.name == instance.name;
                final isConnected = hasAnyActiveTunnel(connections, instance.name);

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                  leading: Stack(
                    children: [
                      Icon(
                        Icons.computer,
                        size: 18,
                        color: isConnected ? Colors.green : (instance.status == "RUNNING" ? Colors.blueGrey : Colors.grey)
                      ),
                      // Health indicator badge
                      if (isConnected)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(instance.name),
                  subtitle: Text(
                    isConnected 
                        ? 'RUNNING • Tunnel Active • ${instance.machineType}' 
                        : '${instance.status} • ${instance.machineType}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isConnected ? Colors.green.shade700 : null,
                      fontWeight: isConnected ? FontWeight.bold : null,
                    ),
                  ),
                  onTap: () {
                    ref.read(selectedInstanceProvider.notifier).select(instance);
                  },
                );
              }).toList(),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text("Error: $err", style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}

class InstanceDetailPane extends ConsumerWidget {
  const InstanceDetailPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedInstance = ref.watch(selectedInstanceProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final connections = ref.watch(activeConnectionsProvider);

    if (selectedInstance == null || selectedProject == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("Select an instance to view details", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Get ALL tunnels for this instance
    final activeTunnels = getTunnelsForInstance(connections, selectedInstance.name);
    final isConnected = activeTunnels.any((t) => t.value.status == 'connected');
    final isConnecting = activeTunnels.any((t) => t.value.status == 'connecting');
    // final errorTunnels = activeTunnels.where((t) => t.value.error != null).toList();
    final isRunning = selectedInstance.status == "RUNNING";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.computer, size: 48, color: Colors.blueAccent),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selectedInstance.name, style: Theme.of(context).textTheme.headlineSmall),
                  Row(
                    children: [
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                         decoration: BoxDecoration(
                           color: Colors.grey.shade200,
                           borderRadius: BorderRadius.circular(4),
                           border: Border.all(color: Colors.grey.shade400),
                         ),
                         child: Text(selectedInstance.machineType, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                       ),
                       const SizedBox(width: 8),
                       Text("${selectedInstance.zone}  •  ${selectedInstance.status}", style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Instance Resources Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Instance Resources",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ResourceChip(
                        icon: Icons.developer_board,
                        label: "CPU",
                        value: selectedInstance.cpuCount != null
                            ? "${selectedInstance.cpuCount} vCPUs"
                            : "N/A",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ResourceChip(
                        icon: Icons.memory,
                        label: "RAM",
                        value: selectedInstance.memoryMb != null
                            ? "${(selectedInstance.memoryMb! / 1024).toStringAsFixed(1)} GB"
                            : "N/A",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ResourceChip(
                        icon: Icons.storage,
                        label: "Disk",
                        value: selectedInstance.diskGb != null
                            ? "${selectedInstance.diskGb} GB"
                            : "N/A",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Show all active tunnels for this instance
          if (activeTunnels.isNotEmpty) ...[
            const Text("Active Tunnels", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...activeTunnels.map((tunnelEntry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildTunnelDashboard(
                  context,
                  tunnelEntry.value,
                  tunnelEntry.key,
                  selectedInstance.name,
                  ref,
                ),
              );
            }),
          ],

          const SizedBox(height: 32),
          const Text("Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          Wrap(
            spacing: 16.0,
            runSpacing: 16.0,
            children: [
              _ActionButton(
                icon: Icons.desktop_windows,
                label: "Connect RDP",
                onPressed: (!isRunning || isConnecting) ? null : () async {
                   final settings = await _showConnectionSettingsDialog(context, selectedInstance.name);
                   if (settings != null) {
                      ref.read(activeConnectionsProvider.notifier).launchRDP(
                        selectedProject, selectedInstance.zone, selectedInstance.name,
                        settings: settings
                      );
                   }
                },
              ),
              _ActionButton(
                icon: Icons.terminal,
                label: "Connect SSH",
                onPressed: (!isRunning || isConnecting) ? null : () async {
                   try {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Launching Terminal...")));
                     await launchSsh(projectId: selectedProject, zone: selectedInstance.zone, instanceName: selectedInstance.name);
                   } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("SSH Error: $e")));
                      }
                   }
                },
              ),
              _ActionButton(
                icon: Icons.folder_open,
                label: "Open SFTP",
                onPressed: (!isRunning || isConnecting) ? null : () async {
                  try {
                    // Check for existing SSH tunnel (port 22)
                    final activeTunnels = getTunnelsForInstance(connections, selectedInstance.name);
                    int? tunnelPort;
                    
                    // Look for a tunnel mapped to remote port 22
                    for (var t in activeTunnels) {
                       if (t.value.remotePort == 22 && t.value.status == 'connected') {
                         tunnelPort = t.value.port;
                         break;
                       }
                    }

                    if (tunnelPort == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Opening tunnel for SFTP..."))
                      );
                      // Create new tunnel to port 22
                      final newPort = await ref.read(activeConnectionsProvider.notifier).connect(
                        selectedProject,
                        selectedInstance.zone,
                        selectedInstance.name,
                        remotePort: 22,
                      );

                      if (newPort == null) {
                        // Tunnel creation failed - provide explicit error feedback
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Failed to create SSH tunnel for SFTP.\n\n"
                                "Please verify:\n"
                                "• Instance is RUNNING\n"
                                "• You have IAP tunnel permissions\n"
                                "• Network connectivity is working\n"
                                "• gcloud CLI is authenticated"
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 8),
                              action: SnackBarAction(
                                label: 'Retry',
                                textColor: Colors.white,
                                onPressed: () {
                                  // User can click to retry
                                },
                              ),
                            ),
                          );
                        }
                        return; // Exit without opening dialog
                      }

                      tunnelPort = newPort;
                    }

                    // At this point, tunnelPort is guaranteed to be non-null
                    if (context.mounted) {
                      // Get current username
                      final username = await getUsername();

                      if (context.mounted) {
                        // Open integrated SFTP browser dialog
                        showDialog(
                          context: context,
                          builder: (ctx) => SftpBrowserDialog(
                            host: 'localhost',
                            port: tunnelPort!, // Safe: checked for null above
                            username: username,
                            instanceName: selectedInstance.name,
                          ),
                        );
                      }
                    }
                  } on StateError catch (e) {
                    // State management errors (Riverpod/Provider issues)
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("State error: $e\nPlease restart the app."),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 6),
                        ),
                      );
                    }
                  } on Exception catch (e) {
                    // Expected runtime errors (network, permissions, etc.)
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Failed to open SFTP browser: $e"),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  } catch (e, stackTrace) {
                    // Unexpected errors - these are bugs that need fixing!
                    debugPrint("═══ UNEXPECTED SFTP ERROR ═══");
                    debugPrint("Error: $e");
                    debugPrint("Type: ${e.runtimeType}");
                    debugPrint("Stack: $stackTrace");
                    debugPrint("════════════════════════════");

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            "An unexpected error occurred.\n"
                            "Please check console logs and report this bug."
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    }
                  }
                },
              ),
              _ActionButton(
                icon: Icons.settings_ethernet,
                label: "Custom Tunnel",
                backgroundColor: Colors.purple.shade50,
                foregroundColor: Colors.purple.shade700,
                onPressed: (!isRunning || isConnecting) ? null : () async {
                  final selectedPort = await _showCustomTunnelDialog(context);
                  if (selectedPort != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Creating tunnel to port $selectedPort..."))
                    );
                    await ref.read(activeConnectionsProvider.notifier).connect(
                      selectedProject,
                      selectedInstance.zone,
                      selectedInstance.name,
                      remotePort: selectedPort,
                    );
                  }
                },
              ),
               _ActionButton(
                icon: isConnected ? Icons.link_off : Icons.network_check,
                label: isConnected ? "Disconnect All Tunnels" : "Test IAP Connection",
                backgroundColor: isConnected ? Colors.red.shade50 : Colors.blue.shade50,
                foregroundColor: isConnected ? Colors.red : Colors.blue.shade700,
                onPressed: (isConnecting) ? null : () async {
                   if (isConnected) {
                     await ref.read(activeConnectionsProvider.notifier).disconnectAllForInstance(selectedInstance.name);
                   } else {
                     // Test IAP connectivity
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(
                         content: Text("Testing IAP connection... This verifies if IAP is properly configured."),
                         duration: Duration(seconds: 2),
                       )
                     );
                     ref.read(activeConnectionsProvider.notifier).connect(selectedProject, selectedInstance.zone, selectedInstance.name);
                   }
                },
              ),
              // VM Lifecycle Management buttons
              _ActionButton(
                icon: Icons.play_arrow,
                label: "Start Instance",
                backgroundColor: Colors.green.shade50,
                foregroundColor: Colors.green.shade700,
                onPressed: (isRunning || isConnecting) ? null : () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Starting instance... This may take a few minutes."))
                    );
                    await startInstance(
                      projectId: selectedProject,
                      zone: selectedInstance.zone,
                      instanceName: selectedInstance.name,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Instance started successfully!"))
                      );
                      // Refresh instances list
                      await ref.read(activeConnectionsProvider.notifier).refreshInstances(selectedProject);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to start instance: $e"))
                      );
                    }
                  }
                },
              ),
              _ActionButton(
                icon: Icons.stop,
                label: "Stop Instance",
                backgroundColor: Colors.orange.shade50,
                foregroundColor: Colors.orange.shade700,
                onPressed: (!isRunning || isConnecting) ? null : () async {
                  final confirmed = await _showConfirmationDialog(
                    context,
                    title: "Stop Instance",
                    message: "Are you sure you want to stop ${selectedInstance.name}?\n\nThis will disconnect all active tunnels and shut down the instance.",
                    confirmText: "Stop",
                    isDestructive: true,
                  );
                  if (confirmed == true) {
                    try {
                      // Disconnect all tunnels first
                      await ref.read(activeConnectionsProvider.notifier).disconnectAllForInstance(selectedInstance.name);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Stopping instance... This may take a few minutes."))
                        );
                      }

                      await stopInstance(
                        projectId: selectedProject,
                        zone: selectedInstance.zone,
                        instanceName: selectedInstance.name,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Instance stopped successfully!"))
                        );
                        // Refresh instances list
                        await ref.read(activeConnectionsProvider.notifier).refreshInstances(selectedProject);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to stop instance: $e"))
                        );
                      }
                    }
                  }
                },
              ),
              _ActionButton(
                icon: Icons.restart_alt,
                label: "Reset Instance",
                backgroundColor: Colors.red.shade50,
                foregroundColor: Colors.red.shade700,
                onPressed: (!isRunning || isConnecting) ? null : () async {
                  final confirmed = await _showConfirmationDialog(
                    context,
                    title: "Reset Instance",
                    message: "Are you sure you want to reset ${selectedInstance.name}?\n\nThis will forcefully restart the instance and disconnect all active tunnels.",
                    confirmText: "Reset",
                    isDestructive: true,
                  );
                  if (confirmed == true) {
                    try {
                      // Disconnect all tunnels first
                      await ref.read(activeConnectionsProvider.notifier).disconnectAllForInstance(selectedInstance.name);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Resetting instance... This may take a few minutes."))
                        );
                      }

                      await resetInstance(
                        projectId: selectedProject,
                        zone: selectedInstance.zone,
                        instanceName: selectedInstance.name,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Instance reset successfully!"))
                        );
                        // Wait a bit before refreshing to allow GCP to update status
                        await Future.delayed(const Duration(seconds: 3));
                        await ref.read(activeConnectionsProvider.notifier).refreshInstances(selectedProject);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to reset instance: $e"))
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ),
          
          if (isConnecting)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(),
            )
        ],
      ),
    );
  }

  /// Show Custom Tunnel Dialog to select port
  Future<int?> _showCustomTunnelDialog(BuildContext context) async {
    int? selectedPort;
    final customPortController = TextEditingController();
    bool isCustomPort = false;

    // Common service presets
    final Map<String, int> servicePresets = {
      'RDP (Remote Desktop)': 3389,
      'SSH': 22,
      'PostgreSQL': 5432,
      'MySQL/MariaDB': 3306,
      'HTTP': 8080,
      'HTTPS': 443,
      'MongoDB': 27017,
      'Redis': 6379,
    };

    if (!context.mounted) return null;

    return showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings_ethernet, color: Colors.blue),
                  SizedBox(width: 8),
                  Text("Custom Tunnel Configuration"),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Select a service preset or enter a custom port:",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Service Preset Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: servicePresets.entries.map((entry) {
                        final isSelected = selectedPort == entry.value && !isCustomPort;
                        return ChoiceChip(
                          label: Text('${entry.key}\n:${entry.value}', textAlign: TextAlign.center),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                selectedPort = entry.value;
                                isCustomPort = false;
                                customPortController.clear();
                              } else {
                                selectedPort = null;
                              }
                            });
                          },
                          selectedColor: Colors.blue.shade100,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.blue.shade900 : Colors.black87,
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Custom Port Input
                    TextField(
                      controller: customPortController,
                      decoration: InputDecoration(
                        labelText: "Custom Port",
                        hintText: "Enter port (1-65535)",
                        prefixIcon: const Icon(Icons.edit),
                        border: const OutlineInputBorder(),
                        filled: isCustomPort,
                        fillColor: isCustomPort ? Colors.blue.shade50 : null,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          final port = int.tryParse(value);
                          if (port != null && port >= 1 && port <= 65535) {
                            selectedPort = port;
                            isCustomPort = true;
                          } else {
                            if (isCustomPort) selectedPort = null;
                          }
                        });
                      },
                    ),

                    if (selectedPort != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Selected port: $selectedPort',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: selectedPort == null
                      ? null
                      : () => Navigator.pop(context, selectedPort),
                  child: const Text("Connect"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<RdpSettings?> _showConnectionSettingsDialog(BuildContext context, String instanceName) async {
    final userController = TextEditingController();
    final passController = TextEditingController();
    final domainController = TextEditingController();
    bool fullscreen = false;
    bool saveCredentials = false;
    
    // Default resolution
    int width = 1920;
    int height = 1080;

    // Load saved credentials
    final saved = await StorageService().getRdpCredentials(instanceName);
    if (saved['username'] != null) {
      userController.text = saved['username']!;
      saveCredentials = true;
    }
    if (saved['password'] != null) passController.text = saved['password']!;
    if (saved['domain'] != null) domainController.text = saved['domain']!;

    if (!context.mounted) return null;

    return showDialog<RdpSettings>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Connection Settings"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(labelText: "Username"),
                    ),
                    TextField(
                      controller: passController,
                      decoration: const InputDecoration(labelText: "Password"),
                      obscureText: true,
                    ),
                    TextField(
                      controller: domainController,
                      decoration: const InputDecoration(labelText: "Domain (Optional)"),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text("Save Credentials"),
                      value: saveCredentials,
                      onChanged: (val) => setState(() => saveCredentials = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text("Fullscreen"),
                      value: fullscreen,
                      onChanged: (val) => setState(() => fullscreen = val),
                    ),
                    if (!fullscreen)
                       Row(
                         children: [
                           Expanded(child: TextFormField(
                             initialValue: width.toString(),
                             decoration: const InputDecoration(labelText: "Width"),
                             keyboardType: TextInputType.number,
                             onChanged: (v) => width = int.tryParse(v) ?? 1920,
                           )),
                           const SizedBox(width: 16),
                           Expanded(child: TextFormField(
                             initialValue: height.toString(),
                             decoration: const InputDecoration(labelText: "Height"),
                             keyboardType: TextInputType.number,
                             onChanged: (v) => height = int.tryParse(v) ?? 1080,
                           )),
                         ],
                       )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null), // Cancel
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (saveCredentials) {
                      await StorageService().saveRdpCredentials(
                        instanceName: instanceName,
                        username: userController.text,
                        password: passController.text,
                        domain: domainController.text,
                      );
                    } else {
                      await StorageService().clearRdpCredentials(instanceName);
                    }

                    if (context.mounted) {
                      Navigator.pop(context, RdpSettings(
                        username: userController.text.isNotEmpty ? userController.text : null,
                        password: passController.text.isNotEmpty ? passController.text : null,
                        domain: domainController.text.isNotEmpty ? domainController.text : null,
                        fullscreen: fullscreen,
                        width: fullscreen ? null : width,
                        height: fullscreen ? null : height,
                      ));
                    }
                  },
                  child: const Text("Connect"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Build comprehensive tunnel status dashboard with metrics
  Widget _buildTunnelDashboard(
    BuildContext context,
    TunnelState tunnel,
    String tunnelKey,
    String instanceName,
    WidgetRef ref,
  ) {
    // Determine health status color and icon
    final bool isHealthy = tunnel.status == 'connected' && tunnel.error == null;
    final bool isError = tunnel.status == 'error';
    final Color statusColor = isError ? Colors.red : (isHealthy ? Colors.green : Colors.orange);
    final Color bgColor = isError ? Colors.red.shade50 : (isHealthy ? Colors.green.shade50 : Colors.orange.shade50);
    final Color borderColor = isError ? Colors.red.shade200 : (isHealthy ? Colors.green.shade200 : Colors.orange.shade200);
    final IconData statusIcon = isError ? Icons.error : (isHealthy ? Icons.check_circle : Icons.warning);
    final String statusText = isError ? 'Unhealthy' : (isHealthy ? 'Healthy' : 'Degraded');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Tunnel → :${tunnel.remotePort ?? "?"}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: statusColor.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isHealthy ? Icons.favorite : Icons.warning_amber,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (tunnel.port != null)
                      Text(
                        'localhost:${tunnel.port}',
                        style: TextStyle(
                          fontSize: 13,
                          color: statusColor.withValues(alpha: 0.7),
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),
              // Disconnect button
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Disconnect this tunnel',
                onPressed: () async {
                  await ref.read(activeConnectionsProvider.notifier).disconnect(
                    instanceName,
                    tunnel.remotePort!,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Metrics Grid
          Row(
            children: [
              // Uptime metric
              Expanded(
                child: _MetricCard(
                  icon: Icons.schedule,
                  label: 'Uptime',
                  value: tunnel.uptime,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              // Last health check metric
              Expanded(
                child: _MetricCard(
                  icon: Icons.health_and_safety,
                  label: 'Last Check',
                  value: tunnel.lastCheckRelative,
                  color: statusColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Monitoring info
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.autorenew, size: 14, color: Colors.black.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Auto-monitoring every 30 seconds',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isDestructive ? Icons.warning : Icons.help_outline,
                color: isDestructive ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDestructive ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }
}

/// Metric card widget for tunnel dashboard
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ResourceChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _ActionButton({
    required this.icon, 
    required this.label, 
    this.onPressed, 
    this.backgroundColor, 
    this.foregroundColor
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
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
        
        // Ensure selected value exists in the list
        final validSelection = projects.any((p) => p.projectId == selectedProject) ? selectedProject : null;
        
        // If selection became invalid, update provider safely? 
        // Better to just show null in UI, provider will update when user picks.
        
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Select Project',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          ),
          isExpanded: true,
          value: validSelection,
          items: projects.map((p) {
            return DropdownMenuItem(
              value: p.projectId,
              child: Text(
                // Show both name and projectId for clarity
                p.name != null && p.name != p.projectId
                    ? "${p.name} (${p.projectId})"
                    : p.projectId,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            ref.read(selectedProjectProvider.notifier).select(value);
            ref.read(selectedInstanceProvider.notifier).select(null); // Clear selection
          },
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text("Error loading projects: $err"),
    );
  }
}
