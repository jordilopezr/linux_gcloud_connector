import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
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
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Directory Listing ═══');
      debugPrint('Operation: List directory');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('Remote Path: $dirPath');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('═════════════════════════════════════');

      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load directory "$dirPath": $e\n\nCheck permissions and network connectivity.',
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

  /// Sanitize filename to prevent command injection and path traversal
  String _sanitizeFilename(String filename) {
    return filename
        // Remove path separators
        .replaceAll(RegExp(r'[/\\\0]'), '_')
        // Remove shell metacharacters that could enable command injection
        .replaceAll(RegExp(r'[;&|`$()]'), '_')
        // Remove other potentially dangerous characters
        .replaceAll(RegExp(r'[<>"]'), '_')
        // Collapse multiple underscores
        .replaceAll(RegExp(r'_+'), '_')
        // Trim leading/trailing underscores and whitespace
        .trim()
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> uploadFile() async {
    String? fileName;
    String? localPath;
    String? remotePath;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        localPath = result.files.single.path!;
        // Sanitize filename to prevent injection attacks
        fileName = _sanitizeFilename(path.basename(localPath));
        remotePath = path.join(state.currentPath, fileName);

        state = state.copyWith(operationInProgress: 'Uploading $fileName...');

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
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Upload File ═══');
      debugPrint('Operation: Upload file');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('File Name: ${fileName ?? "unknown"}');
      debugPrint('Local Path: ${localPath ?? "unknown"}');
      debugPrint('Remote Path: ${remotePath ?? "unknown"}');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to upload "${fileName ?? "file"}": $e\n\nCheck file permissions and disk space.',
      );
    }
  }

  Future<void> downloadFile(RemoteFileEntry file) async {
    String? localPath;

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        localPath = path.join(selectedDirectory, file.name);
        state = state.copyWith(operationInProgress: 'Downloading ${file.name}...');

        await sftpDownload(
          host: host,
          port: port,
          username: username,
          remotePath: file.path,
          localPath: localPath,
        );

        state = state.copyWith(operationInProgress: null);
      }
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Download File ═══');
      debugPrint('Operation: Download file');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('File Name: ${file.name}');
      debugPrint('File Size: ${file.size} bytes');
      debugPrint('Remote Path: ${file.path}');
      debugPrint('Local Path: ${localPath ?? "unknown"}');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('══════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to download "${file.name}": $e\n\nCheck local disk space and permissions.',
      );
    }
  }

  Future<void> createDirectory(String dirName) async {
    String? remotePath;

    // Input validation: Prevent directory name injection attacks
    final trimmedName = dirName.trim();

    if (trimmedName.isEmpty) {
      state = state.copyWith(
        error: 'Directory name cannot be empty.',
      );
      return;
    }

    if (trimmedName.contains('/') || trimmedName.contains('\\')) {
      state = state.copyWith(
        error: 'Directory name cannot contain path separators (/ or \\).',
      );
      return;
    }

    if (trimmedName.contains('..')) {
      state = state.copyWith(
        error: 'Directory name cannot contain ".." (parent directory references).',
      );
      return;
    }

    if (trimmedName.length > 255) {
      state = state.copyWith(
        error: 'Directory name too long (max 255 characters).',
      );
      return;
    }

    // Note: We allow names starting with '.' for hidden directories (Unix convention)
    // If you want to prevent hidden directories, uncomment:
    // if (trimmedName.startsWith('.')) {
    //   state = state.copyWith(
    //     error: 'Directory name cannot start with "." (hidden directories not allowed).',
    //   );
    //   return;
    // }

    try {
      remotePath = path.join(state.currentPath, trimmedName);
      state = state.copyWith(operationInProgress: 'Creating directory...');

      await sftpMkdir(
        host: host,
        port: port,
        username: username,
        remotePath: remotePath,
      );

      state = state.copyWith(operationInProgress: null);
      await refresh();
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Create Directory ═══');
      debugPrint('Operation: Create directory');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('Directory Name: $dirName');
      debugPrint('Parent Path: ${state.currentPath}');
      debugPrint('Full Path: ${remotePath ?? "unknown"}');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('═════════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to create directory "$dirName": $e\n\nCheck remote permissions.',
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
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Delete Entry ═══');
      debugPrint('Operation: Delete ${file.isDirectory ? "directory" : "file"}');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('Entry Name: ${file.name}');
      debugPrint('Entry Path: ${file.path}');
      debugPrint('Is Directory: ${file.isDirectory}');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('═════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to delete "${file.name}": $e\n\nCheck remote permissions and ensure it\'s not in use.',
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
                  // Parent Directory Navigation Button
                  IconButton(
                    onPressed: (state.isLoading || state.currentPath == '/home/${widget.username}')
                        ? null
                        : () {
                            final parentPath = path.dirname(state.currentPath);
                            ref.read(provider.notifier).navigateTo(parentPath);
                          },
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Go to parent directory',
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
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
    ).then((_) => controller.dispose()); // Dispose controller when dialog closes
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
    // Use toDouble() to avoid overflow for very large files
    final double b = bytes.toDouble();

    if (b < 1024) {
      return '${bytes.toInt()} B';  // Safe: small values
    }
    if (b < 1024 * 1024) {
      return '${(b / 1024).toStringAsFixed(1)} KB';
    }
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
