import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/bridge/api.dart';
import 'src/bridge/gcloud.dart';
import 'src/bridge/remmina.dart';
import 'src/bridge/frb_generated.dart';
import 'src/features/gcloud_provider.dart';
import 'src/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
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

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Linux Cloud Connector',
      applicationVersion: '1.2.1',
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
                final isConnected = connections[instance.name]?.status == 'connected';
                
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                  leading: Icon(
                    Icons.computer, 
                    size: 18, 
                    color: isConnected ? Colors.green : (instance.status == "RUNNING" ? Colors.blueGrey : Colors.grey)
                  ),
                  title: Text(instance.name),
                  subtitle: Text(instance.status, style: const TextStyle(fontSize: 10)),
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

    final myConnection = connections[selectedInstance.name];
    final isConnected = myConnection?.status == 'connected';
    final isConnecting = myConnection?.status == 'connecting';
    final errorMessage = myConnection?.error;
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
                  Text("${selectedInstance.zone}  •  ${selectedInstance.status}", style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          if (errorMessage != null)
             Container(
               padding: const EdgeInsets.all(8),
               color: Colors.red.shade100,
               child: Row(children: [const Icon(Icons.error, color: Colors.red), const SizedBox(width: 8), Expanded(child: SelectableText(errorMessage))]),
             ),

          if (isConnected) ...[
             const SizedBox(height: 16),
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: Colors.green.shade50,
                 border: Border.all(color: Colors.green.shade200),
                 borderRadius: BorderRadius.circular(8),
               ),
               child: Row(
                 children: [
                   const Icon(Icons.check_circle, color: Colors.green),
                   const SizedBox(width: 12),
                   Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       const Text("Tunnel Active", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                       Text("Listening on localhost:${myConnection!.port}", style: const TextStyle(color: Colors.black87)),
                     ],
                   )
                 ],
               ),
             )
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
                icon: isConnected ? Icons.link_off : Icons.link,
                label: isConnected ? "Disconnect Tunnel" : "Create Tunnel",
                backgroundColor: isConnected ? Colors.red.shade50 : null,
                foregroundColor: isConnected ? Colors.red : null,
                onPressed: (isConnecting) ? null : () {
                   if (isConnected) {
                     ref.read(activeConnectionsProvider.notifier).disconnect(selectedInstance.name);
                   } else {
                     ref.read(activeConnectionsProvider.notifier).connect(selectedProject, selectedInstance.zone, selectedInstance.name);
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
                "${p.name ?? p.projectId}", 
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
