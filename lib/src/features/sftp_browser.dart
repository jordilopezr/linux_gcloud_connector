import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../bridge/api.dart/api.dart';
import '../bridge/api.dart/sftp.dart';

// SFTP Browser State
class SftpBrowserState {
  final String currentPath;
  final List<RemoteFileEntry> files;
  final bool isLoading;
  final String? error;
  final String? operationInProgress;

  const SftpBrowserState({
    this.currentPath = '/home',
    this.files = const [],
    this.isLoading = false,
    this.error,
    this.operationInProgress,
  });

  SftpBrowserState copyWith({
    String? currentPath,
    List<RemoteFileEntry>? files,
    bool? isLoading,
    String? error,
    String? operationInProgress,
  }) {
    return SftpBrowserState(
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      operationInProgress: operationInProgress,
    );
  }
}

// SFTP Browser Notifier Parameters
class SftpBrowserParams {
  final String host;
  final int port;
  final String username;

  const SftpBrowserParams({
    required this.host,
    required this.port,
    required this.username,
  });
}

// SFTP Browser Notifier
class SftpBrowserNotifier extends Notifier<SftpBrowserState> {
  late String host;
  late int port;
  late String username;

  @override
  SftpBrowserState build() {
    // Parameters will be set before build is called
    return const SftpBrowserState();
  }

  void initialize(String h, int p, String u) {
    host = h;
    port = p;
    username = u;
    // Load initial directory after initialization
    _loadDirectory('/home/$username');
  }

  Future<void> _loadDirectory(String dirPath) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final files = await sftpListDir(
        host: host,
        port: port,
        username: username,
        remotePath: dirPath,
      );

      state = state.copyWith(
        currentPath: dirPath,
        files: files,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load directory: $e',
      );
    }
  }

  Future<void> navigateTo(String dirPath) async {
    await _loadDirectory(dirPath);
  }

  Future<void> refresh() async {
    await _loadDirectory(state.currentPath);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        state = state.copyWith(operationInProgress: 'Uploading ${result.files.single.name}...');

        final localPath = result.files.single.path!;
        final fileName = path.basename(localPath);
        final remotePath = path.join(state.currentPath, fileName);

        await sftpUpload(
          host: host,
          port: port,
          username: username,
          localPath: localPath,
          remotePath: remotePath,
        );

        state = state.copyWith(operationInProgress: null);
        await refresh();
      }
    } catch (e) {
      state = state.copyWith(
        operationInProgress: null,
        error: 'Upload failed: $e',
      );
    }
  }

  Future<void> downloadFile(RemoteFileEntry file) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        state = state.copyWith(operationInProgress: 'Downloading ${file.name}...');

        final localPath = path.join(selectedDirectory, file.name);

        await sftpDownload(
          host: host,
          port: port,
          username: username,
          remotePath: file.path,
          localPath: localPath,
        );

        state = state.copyWith(operationInProgress: null);
      }
    } catch (e) {
      state = state.copyWith(
        operationInProgress: null,
        error: 'Download failed: $e',
      );
    }
  }

  Future<void> createDirectory(String dirName) async {
    try {
      state = state.copyWith(operationInProgress: 'Creating directory...');

      final remotePath = path.join(state.currentPath, dirName);

      await sftpMkdir(
        host: host,
        port: port,
        username: username,
        remotePath: remotePath,
      );

      state = state.copyWith(operationInProgress: null);
      await refresh();
    } catch (e) {
      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to create directory: $e',
      );
    }
  }

  Future<void> deleteEntry(RemoteFileEntry file) async {
    try {
      state = state.copyWith(operationInProgress: 'Deleting ${file.name}...');

      await sftpDelete(
        host: host,
        port: port,
        username: username,
        remotePath: file.path,
        isDirectory: file.isDirectory,
      );

      state = state.copyWith(operationInProgress: null);
      await refresh();
    } catch (e) {
      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to delete: $e',
      );
    }
  }
}

// Create a unique provider for each SFTP session
NotifierProvider<SftpBrowserNotifier, SftpBrowserState> createSftpBrowserProvider() {
  return NotifierProvider<SftpBrowserNotifier, SftpBrowserState>(SftpBrowserNotifier.new);
}

// SFTP Browser Dialog Widget
class SftpBrowserDialog extends ConsumerStatefulWidget {
  final String host;
  final int port;
  final String username;
  final String instanceName;

  const SftpBrowserDialog({
    super.key,
    required this.host,
    required this.port,
    required this.username,
    required this.instanceName,
  });

  @override
  ConsumerState<SftpBrowserDialog> createState() => _SftpBrowserDialogState();
}

class _SftpBrowserDialogState extends ConsumerState<SftpBrowserDialog> {
  late final NotifierProvider<SftpBrowserNotifier, SftpBrowserState> provider;

  @override
  void initState() {
    super.initState();
    provider = createSftpBrowserProvider();
    // Initialize the notifier with connection parameters after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(provider.notifier).initialize(
        widget.host,
        widget.port,
        widget.username,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(provider);

    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.folder_open, size: 28, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File Browser - ${widget.instanceName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        state.currentPath,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),

            // Toolbar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: state.isLoading ? null : () => ref.read(provider.notifier).uploadFile(),
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('Upload'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: state.isLoading ? null : () => _showCreateDirectoryDialog(),
                    icon: const Icon(Icons.create_new_folder, size: 18),
                    label: const Text('New Folder'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: state.isLoading ? null : () => ref.read(provider.notifier).refresh(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                  const Spacer(),
                  if (state.operationInProgress != null)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(state.operationInProgress!),
                      ],
                    ),
                ],
              ),
            ),

            // Error display
            if (state.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => ref.read(provider.notifier).clearError(),
                    ),
                  ],
                ),
              ),

            // File list
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: state.files.length,
                      itemBuilder: (context, index) {
                        final file = state.files[index];
                        return _FileListTile(
                          file: file,
                          onTap: () {
                            if (file.isDirectory) {
                              ref.read(provider.notifier).navigateTo(file.path);
                            }
                          },
                          onDownload: file.isDirectory ? null : () {
                            ref.read(provider.notifier).downloadFile(file);
                          },
                          onDelete: file.name == '..' ? null : () {
                            _showDeleteConfirmation(file);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDirectoryDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'my-folder',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(provider.notifier).createDirectory(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(RemoteFileEntry file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(provider.notifier).deleteEntry(file);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// File List Tile Widget
class _FileListTile extends StatelessWidget {
  final RemoteFileEntry file;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _FileListTile({
    required this.file,
    required this.onTap,
    this.onDownload,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        file.isDirectory ? Icons.folder : _getFileIcon(file.name),
        color: file.isDirectory ? Colors.blue.shade400 : Colors.grey.shade600,
        size: 28,
      ),
      title: Text(file.name),
      subtitle: file.isDirectory
          ? const Text('Folder')
          : Text(_formatFileSize(file.size)),
      trailing: file.name == '..'
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onDownload != null)
                  IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    onPressed: onDownload,
                    tooltip: 'Download',
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                  ),
              ],
            ),
      onTap: onTap,
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    switch (ext) {
      case '.txt':
      case '.md':
        return Icons.description;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return Icons.image;
      case '.zip':
      case '.tar':
      case '.gz':
        return Icons.archive;
      case '.sh':
      case '.py':
      case '.js':
      case '.dart':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
