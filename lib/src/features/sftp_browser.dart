import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import '../bridge/api.dart/api.dart';
import '../bridge/api.dart/sftp.dart';

// SFTP Browser State
class SftpBrowserState {
  final String currentPath;
  final List<RemoteFileEntry> files;
  final bool isLoading;
  final String? error;
  final String? operationInProgress;
  final String searchQuery;

  const SftpBrowserState({
    this.currentPath = '/home',
    this.files = const [],
    this.isLoading = false,
    this.error,
    this.operationInProgress,
    this.searchQuery = '',
  });

  SftpBrowserState copyWith({
    String? currentPath,
    List<RemoteFileEntry>? files,
    bool? isLoading,
    String? error,
    String? operationInProgress,
    String? searchQuery,
  }) {
    return SftpBrowserState(
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      operationInProgress: operationInProgress,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  /// Get filtered files based on search query
  List<RemoteFileEntry> get filteredFiles {
    if (searchQuery.isEmpty) return files;
    final query = searchQuery.toLowerCase();
    return files.where((file) {
      return file.name.toLowerCase().contains(query);
    }).toList();
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

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void clearSearch() {
    state = state.copyWith(searchQuery: '');
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

  /// Upload multiple files from drag & drop
  Future<void> uploadFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    try {
      final totalFiles = files.length;
      int uploadedCount = 0;

      for (final file in files) {
        uploadedCount++;
        final fileName = _sanitizeFilename(path.basename(file.path));
        final remotePath = path.join(state.currentPath, fileName);

        state = state.copyWith(
          operationInProgress: 'Uploading $uploadedCount/$totalFiles: $fileName...',
        );

        await sftpUpload(
          host: host,
          port: port,
          username: username,
          localPath: file.path,
          remotePath: remotePath,
        );
      }

      state = state.copyWith(operationInProgress: null);
      await refresh();
    } catch (e, stackTrace) {
      // Structured logging for debugging
      debugPrint('═══ SFTP ERROR: Batch Upload ═══');
      debugPrint('Operation: Upload multiple files');
      debugPrint('Host: $host:$port');
      debugPrint('Username: $username');
      debugPrint('Total Files: ${files.length}');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('Error Message: $e');
      debugPrint('Stack Trace:\n$stackTrace');
      debugPrint('═════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to upload files: $e\n\nSome files may have been uploaded successfully.',
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

  /// Download file to temp directory for preview
  Future<String?> downloadForPreview(RemoteFileEntry file) async {
    try {
      state = state.copyWith(operationInProgress: 'Loading preview...');

      // Create temp directory
      final tempDir = await Directory.systemTemp.createTemp('sftp_preview_');
      final localPath = path.join(tempDir.path, file.name);

      await sftpDownload(
        host: host,
        port: port,
        username: username,
        remotePath: file.path,
        localPath: localPath,
      );

      state = state.copyWith(operationInProgress: null);
      return localPath;
    } catch (e, stackTrace) {
      debugPrint('═══ SFTP ERROR: Preview Download ═══');
      debugPrint('File: ${file.name}');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('═════════════════════════════════════');

      state = state.copyWith(
        operationInProgress: null,
        error: 'Failed to load preview: $e',
      );
      return null;
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
  bool _isDragging = false;

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

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search files and folders...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: state.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => ref.read(provider.notifier).clearSearch(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onChanged: (value) => ref.read(provider.notifier).updateSearchQuery(value),
              ),
            ),

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

            // File list with drag & drop support
            Expanded(
              child: DropTarget(
                onDragEntered: (details) {
                  setState(() => _isDragging = true);
                },
                onDragExited: (details) {
                  setState(() => _isDragging = false);
                },
                onDragDone: (details) async {
                  setState(() => _isDragging = false);
                  await ref.read(provider.notifier).uploadFiles(details.files);
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isDragging ? Colors.blue : Colors.transparent,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _isDragging ? Colors.blue.withValues(alpha: 0.05) : null,
                  ),
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.filteredFiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isDragging
                                        ? Icons.file_upload
                                        : (state.searchQuery.isEmpty ? Icons.folder_open : Icons.search_off),
                                    size: 64,
                                    color: _isDragging ? Colors.blue : Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _isDragging
                                        ? 'Drop files here to upload'
                                        : (state.searchQuery.isEmpty
                                            ? 'This folder is empty\n\nDrag & drop files here to upload'
                                            : 'No files match "${state.searchQuery}"'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isDragging ? Colors.blue : Colors.grey.shade600,
                                      fontSize: 16,
                                      fontWeight: _isDragging ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Stack(
                              children: [
                                ListView.builder(
                                  itemCount: state.filteredFiles.length,
                                  itemBuilder: (context, index) {
                                    final file = state.filteredFiles[index];
                                    return _FileListTile(
                                      file: file,
                                      searchQuery: state.searchQuery,
                                      onTap: () {
                                        if (file.isDirectory) {
                                          ref.read(provider.notifier).navigateTo(file.path);
                                        }
                                      },
                                      onPreview: _canPreview(file) && !file.isDirectory
                                          ? () => _showPreview(file)
                                          : null,
                                      onDownload: file.isDirectory ? null : () {
                                        ref.read(provider.notifier).downloadFile(file);
                                      },
                                      onDelete: file.name == '..' ? null : () {
                                        _showDeleteConfirmation(file);
                                      },
                                    );
                                  },
                                ),
                                // Drag overlay
                                if (_isDragging)
                                  Container(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.file_upload,
                                            size: 80,
                                            color: Colors.blue.shade700,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Drop files here to upload',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                ),
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

  /// Check if file can be previewed
  bool _canPreview(RemoteFileEntry file) {
    if (file.isDirectory || file.name == '..') return false;

    final ext = path.extension(file.name).toLowerCase();
    const textExtensions = ['.txt', '.md', '.log', '.json', '.xml', '.yaml', '.yml', '.conf', '.ini', '.sh', '.py', '.js', '.dart', '.html', '.css', '.sql'];
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

    return textExtensions.contains(ext) || imageExtensions.contains(ext);
  }

  /// Show file preview dialog
  Future<void> _showPreview(RemoteFileEntry file) async {
    final localPath = await ref.read(provider.notifier).downloadForPreview(file);
    if (localPath == null || !mounted) return;

    final ext = path.extension(file.name).toLowerCase();
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 800,
          height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    imageExtensions.contains(ext) ? Icons.image : Icons.description,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      // Clean up temp file
                      try {
                        File(localPath).deleteSync();
                      } catch (_) {}
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              const Divider(),
              // Content
              Expanded(
                child: imageExtensions.contains(ext)
                    ? _ImagePreview(filePath: localPath)
                    : _TextPreview(filePath: localPath),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // Clean up temp file after dialog closes
      try {
        File(localPath).deleteSync();
      } catch (_) {}
    });
  }
}

// File List Tile Widget
class _FileListTile extends StatelessWidget {
  final RemoteFileEntry file;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback? onPreview;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _FileListTile({
    required this.file,
    required this.searchQuery,
    required this.onTap,
    this.onPreview,
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
      title: _buildHighlightedText(file.name, searchQuery),
      subtitle: file.isDirectory
          ? const Text('Folder')
          : Text(_formatFileSize(file.size)),
      trailing: file.name == '..'
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onPreview != null)
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 20),
                    onPressed: onPreview,
                    tooltip: 'Preview',
                    color: Colors.blue.shade600,
                  ),
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

  /// Build text with search query highlighted
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matches = <TextSpan>[];
    int currentIndex = 0;

    while (currentIndex < text.length) {
      final matchIndex = lowerText.indexOf(lowerQuery, currentIndex);

      if (matchIndex == -1) {
        // No more matches, add remaining text
        if (currentIndex < text.length) {
          matches.add(TextSpan(text: text.substring(currentIndex)));
        }
        break;
      }

      // Add text before match
      if (matchIndex > currentIndex) {
        matches.add(TextSpan(text: text.substring(currentIndex, matchIndex)));
      }

      // Add highlighted match
      matches.add(
        TextSpan(
          text: text.substring(matchIndex, matchIndex + query.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      );

      currentIndex = matchIndex + query.length;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        children: matches,
      ),
    );
  }
}

// Text File Preview Widget
class _TextPreview extends StatefulWidget {
  final String filePath;

  const _TextPreview({required this.filePath});

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  String? _content;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      final content = await file.readAsString();
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load file: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _content ?? '',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// Image File Preview Widget
class _ImagePreview extends StatelessWidget {
  final String filePath;

  const _ImagePreview({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.1,
        maxScale: 5.0,
        child: Image.file(
          File(filePath),
          errorBuilder: (context, error, stackTrace) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
