import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gcloud_provider.dart';
import '../bridge/api.dart/gcloud.dart';
import '../bridge/api.dart/api.dart';
import '../bridge/api.dart/gcloud_client_poc.dart';

// Import for Compute Engine types
export '../bridge/api.dart/gcloud_client_poc.dart' show GcpInstanceClientLib;

/// Enhanced Development/Testing screen for Google Cloud Client Libraries
///
/// Features:
/// 1. Tab-based organization (API Testing, Lifecycle Ops, Performance Stats)
/// 2. Side-by-side comparisons of CLI vs Client Libraries
/// 3. "Run All Tests" button for comprehensive validation
/// 4. Real-time performance metrics and speedup calculations
class ClientLibTestScreen extends ConsumerStatefulWidget {
  const ClientLibTestScreen({super.key});

  @override
  ConsumerState<ClientLibTestScreen> createState() => _ClientLibTestScreenState();
}

class _ClientLibTestScreenState extends ConsumerState<ClientLibTestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Libraries Testing'),
        backgroundColor: Colors.blueGrey[800],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.api), text: 'API Testing'),
            Tab(icon: Icon(Icons.settings_applications), text: 'Lifecycle Ops'),
            Tab(icon: Icon(Icons.analytics), text: 'Performance'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle),
            tooltip: 'Run All Tests',
            onPressed: _runAllTests,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildApiTestingTab(),
          _buildLifecycleTab(),
          _buildPerformanceTab(),
        ],
      ),
    );
  }

  void _runAllTests() {
    // Invalidate all test providers to trigger re-run
    ref.invalidate(clientLibAuthTestProvider);
    ref.invalidate(projectsProvider);
    ref.invalidate(projectsClientLibProvider);
    ref.invalidate(benchmarkProvider);
    ref.invalidate(instancesProvider);

    final selectedProject = ref.read(selectedProjectProvider);
    if (selectedProject != null) {
      ref.invalidate(instancesClientLibProvider(selectedProject));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(width: 16),
            Text('Running all tests...'),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ==========================================
  // TAB 1: API TESTING
  // ==========================================

  Widget _buildApiTestingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildAuthTestCard(),
          const SizedBox(height: 16),
          _buildProjectsComparisonCard(),
          const SizedBox(height: 16),
          _buildBenchmarkCard(),
          const SizedBox(height: 16),
          _buildComputeEngineCard(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.blue[700], size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Google Cloud Client Libraries Integration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Test and compare the new Client Libraries integration with traditional gcloud CLI. '
              'Client Libraries use direct REST API calls for better performance.',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthTestCard() {
    final authTest = ref.watch(clientLibAuthTestProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  'Authentication Test',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            authTest.when(
              data: (message) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Error: $error',
                        style: const TextStyle(
                          color: Colors.red,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(clientLibAuthTestProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Authentication'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsComparisonCard() {
    final projectsCli = ref.watch(projectsProvider);
    final projectsClientLib = ref.watch(projectsClientLibProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text(
                  'Projects Listing Comparison',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'gcloud CLI',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      projectsCli.when(
                        data: (projects) => _buildProjectsList(projects, Colors.blue),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.api, size: 16, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'Client Libraries',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      projectsClientLib.when(
                        data: (projects) => _buildClientLibProjectsList(projects, Colors.green),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(projectsProvider);
                ref.invalidate(projectsClientLibProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Both'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsList(List<GcpProject> projects, Color color) {
    if (projects.isEmpty) {
      return const Text('No projects found', style: TextStyle(fontSize: 12));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Found ${projects.length} projects',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...projects.take(2).map((project) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${project.projectId}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          )),
          if (projects.length > 2)
            Text(
              '... and ${projects.length - 2} more',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClientLibProjectsList(List<GcpProjectClientLib> projects, Color color) {
    if (projects.isEmpty) {
      return const Text('No projects found', style: TextStyle(fontSize: 12));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Found ${projects.length} projects',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...projects.take(2).map((project) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${project.projectId}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          )),
          if (projects.length > 2)
            Text(
              '... and ${projects.length - 2} more',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard() {
    final benchmark = ref.watch(benchmarkProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: Colors.purple[700]),
                const SizedBox(width: 8),
                const Text(
                  'Performance Benchmark',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'Measures the time to list all projects using both methods.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            benchmark.when(
              data: (result) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple[200]!),
                ),
                child: Text(
                  result,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Running benchmark...'),
                    ],
                  ),
                ),
              ),
              error: (error, stack) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  'Error: $error',
                  style: const TextStyle(
                    color: Colors.red,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(benchmarkProvider),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Benchmark'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComputeEngineCard() {
    final selectedProject = ref.watch(selectedProjectProvider);

    if (selectedProject == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.computer, color: Colors.teal[700]),
                  const SizedBox(width: 8),
                  const Text(
                    'Compute Engine Instances',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text('Please select a project from the main dashboard to test instance listing.'),
            ],
          ),
        ),
      );
    }

    final instancesCli = ref.watch(instancesProvider);
    final instancesClientLib = ref.watch(instancesClientLibProvider(selectedProject));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.computer, color: Colors.teal[700]),
                const SizedBox(width: 8),
                const Text(
                  'Compute Engine Instances',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'gcloud CLI',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      instancesCli.when(
                        data: (instances) => _buildInstancesList(instances, Colors.blue),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.api, size: 16, color: Colors.teal[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'Client Libraries',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      instancesClientLib.when(
                        data: (instances) => _buildClientLibInstancesList(instances, Colors.teal),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(instancesProvider);
                ref.invalidate(instancesClientLibProvider(selectedProject));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Both'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstancesList(List<GcpInstance> instances, Color color) {
    if (instances.isEmpty) {
      return const Text('No instances found', style: TextStyle(fontSize: 12));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Found ${instances.length} instances',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...instances.take(2).map((instance) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${instance.name} (${instance.status})',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          )),
          if (instances.length > 2)
            Text(
              '... and ${instances.length - 2} more',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClientLibInstancesList(List<GcpInstanceClientLib> instances, Color color) {
    if (instances.isEmpty) {
      return const Text('No instances found', style: TextStyle(fontSize: 12));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Found ${instances.length} instances',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...instances.take(2).map((instance) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${instance.name} (${instance.status})',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          )),
          if (instances.length > 2)
            Text(
              '... and ${instances.length - 2} more',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
                fontSize: 11),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: LIFECYCLE OPERATIONS
  // ==========================================

  Widget _buildLifecycleTab() {
    final selectedProject = ref.watch(selectedProjectProvider);
    final selectedInstance = ref.watch(selectedInstanceProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.orange[50],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_applications, color: Colors.orange[700], size: 32),
                      const SizedBox(width: 12),
                      const Text(
                        'Lifecycle Operations Testing',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Test VM lifecycle operations (start/stop/reset) using both CLI and Client Libraries. '
                    'Select an instance from the main dashboard to begin testing.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (selectedProject == null || selectedInstance == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Please select a project and instance from the main dashboard',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            _buildLifecycleTestCard(selectedProject, selectedInstance),
        ],
      ),
    );
  }

  Widget _buildLifecycleTestCard(String projectId, GcpInstance instance) {
    final apiMethod = ref.watch(apiMethodProvider);
    final isRunning = instance.status == "RUNNING";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.computer, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Status: ${instance.status} • Zone: ${instance.zone}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),

            // API Method indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: apiMethod == GcpApiMethod.clientLibrary
                    ? Colors.green[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: apiMethod == GcpApiMethod.clientLibrary
                      ? Colors.green[300]!
                      : Colors.blue[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    apiMethod == GcpApiMethod.clientLibrary ? Icons.api : Icons.terminal,
                    color: apiMethod == GcpApiMethod.clientLibrary
                        ? Colors.green[700]
                        : Colors.blue[700],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Currently testing with: ${apiMethod == GcpApiMethod.clientLibrary ? "Client Libraries (REST API)" : "gcloud CLI (Process)"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: apiMethod == GcpApiMethod.clientLibrary
                          ? Colors.green[900]
                          : Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Lifecycle operation buttons
            const Text(
              'Test Operations:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning ? null : () async {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting instance...')),
                      );
                      await ref.read(activeConnectionsProvider.notifier).startInstanceWithMethod(
                        projectId,
                        instance.zone,
                        instance.name,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Instance started successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Instance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                ),

                ElevatedButton.icon(
                  onPressed: !isRunning ? null : () async {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stopping instance...')),
                      );
                      await ref.read(activeConnectionsProvider.notifier).stopInstanceWithMethod(
                        projectId,
                        instance.zone,
                        instance.name,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Instance stopped successfully!'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Instance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    foregroundColor: Colors.white,
                  ),
                ),

                ElevatedButton.icon(
                  onPressed: !isRunning ? null : () async {
                    try {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Resetting instance...')),
                      );
                      await ref.read(activeConnectionsProvider.notifier).resetInstanceWithMethod(
                        projectId,
                        instance.zone,
                        instance.name,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Instance reset successfully!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset Instance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Testing Tips',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Switch the API method in the main dashboard AppBar to test both implementations\n'
                    '• Operations take 30-120 seconds to complete\n'
                    '• Watch the console for detailed timing information\n'
                    '• Client Libraries should be slightly faster due to direct API calls',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: PERFORMANCE STATISTICS
  // ==========================================

  Widget _buildPerformanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.purple[50],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.purple[700], size: 32),
                      const SizedBox(width: 12),
                      const Text(
                        'Performance Statistics',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aggregate performance data comparing gcloud CLI and Client Libraries. '
                    'Run benchmarks from the API Testing tab to populate statistics.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildPerformanceSummaryCard(),
          const SizedBox(height: 16),
          _buildExpectedGainsCard(),
        ],
      ),
    );
  }

  Widget _buildPerformanceSummaryCard() {
    final benchmark = ref.watch(benchmarkProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Benchmark Results Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),

            benchmark.when(
              data: (result) {
                // Try to parse speedup from result
                final speedupMatch = RegExp(r'Client Libraries are (\d+\.?\d*)x faster').firstMatch(result);
                final speedup = speedupMatch != null
                    ? double.tryParse(speedupMatch.group(1) ?? '') ?? 0.0
                    : 0.0;

                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricCard(
                          'Speedup',
                          '${speedup.toStringAsFixed(2)}x',
                          Icons.speed,
                          Colors.purple,
                        ),
                        _buildMetricCard(
                          'Improvement',
                          '${((speedup - 1) * 100).toStringAsFixed(0)}%',
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        result,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Running benchmark...'),
                    ],
                  ),
                ),
              ),
              error: (error, stack) => Center(
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('Run benchmark from API Testing tab to see results'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpectedGainsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expected Performance Gains',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),

            _buildExpectedGainRow('List Projects', '1.2-1.4x', 'Faster API calls, no process overhead'),
            const SizedBox(height: 12),
            _buildExpectedGainRow('List Instances', '1.3-1.5x', 'Direct REST API vs CLI JSON parsing'),
            const SizedBox(height: 12),
            _buildExpectedGainRow('Start/Stop Instance', '1.1-1.3x', 'Reduced latency from direct API'),
            const SizedBox(height: 12),
            _buildExpectedGainRow('Reset Instance', '1.1-1.2x', 'Minimal overhead difference'),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Client Libraries excel in high-frequency operations. The more API calls, '
                      'the larger the cumulative time savings.',
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpectedGainRow(String operation, String speedup, String reason) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            operation,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              speedup,
              style: TextStyle(
                color: Colors.green[900],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            reason,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}
