// lib/presentation/control_tab/file_tree_widget.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class FileTreeWidget extends ConsumerStatefulWidget {
  final String initialPath;
  final Function(String path, bool isDirectory)? onItemSelected;

  const FileTreeWidget({
    super.key,
    this.initialPath = '',
    this.onItemSelected,
  });

  @override
  ConsumerState<FileTreeWidget> createState() => _FileTreeWidgetState();
}

class _FileTreeWidgetState extends ConsumerState<FileTreeWidget> {
  String _currentPath = '';
  List<FileSystemItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('https://ws.sosa-qav.es/api/directory?path=$path'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _currentPath = data['path'];
            _items = (data['items'] as List)
                .map((item) => FileSystemItem.fromJson(item))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'حدث خطأ غير معروف';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'فشل في تحميل محتويات المجلد: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء الاتصال بالخادم: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createDirectory(String parentPath) async {
    final name = await _showCreateDirectoryDialog();
    if (name == null || name.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('https://ws.sosa-qav.es/api/directory/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'path': parentPath,
          'name': name,
        }),
      );

      if (response.statusCode == 201) {
        // Reload the current directory to show the new folder
        _loadDirectory(_currentPath);
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'فشل في إنشاء المجلد')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء إنشاء المجلد: $e')),
      );
    }
  }

  Future<String?> _showCreateDirectoryDialog() async {
    final textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء مجلد جديد'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: 'اسم المجلد',
            hintText: 'أدخل اسم المجلد الجديد',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Breadcrumb navigation
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Text('المسار: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildBreadcrumbs(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _currentPath.isNotEmpty
                    ? () {
                        final parentPath = _currentPath.contains('/')
                            ? _currentPath.substring(
                                0, _currentPath.lastIndexOf('/'))
                            : '';
                        _loadDirectory(parentPath);
                      }
                    : null,
                icon: const Icon(Icons.arrow_upward),
                label: const Text('المستوى الأعلى'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _createDirectory(_currentPath),
                icon: const Icon(Icons.create_new_folder),
                label: const Text('إنشاء مجلد'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _loadDirectory(_currentPath),
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث'),
              ),
            ],
          ),
        ),

        const Divider(),

        // Directory content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _loadDirectory(_currentPath),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? const Center(child: Text('المجلد فارغ'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              leading: Icon(
                                item.isDirectory
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                                color: item.isDirectory
                                    ? Colors.amber
                                    : Colors.blueGrey,
                              ),
                              title: Text(item.name),
                              subtitle: item.isDirectory
                                  ? const Text('مجلد')
                                  : Text(
                                      '${_formatFileSize(item.size ?? 0)} - ${_formatDate(item.modified)}',
                                    ),
                              onTap: () {
                                if (item.isDirectory) {
                                  _loadDirectory(item.path);
                                }
                                if (widget.onItemSelected != null) {
                                  widget.onItemSelected!(
                                    item.path,
                                    item.isDirectory,
                                  );
                                }
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }

  List<Widget> _buildBreadcrumbs() {
    if (_currentPath.isEmpty) {
      return [
        TextButton(
          onPressed: () => _loadDirectory(''),
          child: const Text('الجذر'),
        ),
      ];
    }

    final parts = _currentPath.split('/');
    final widgets = <Widget>[];

    // Add root
    widgets.add(
      TextButton(
        onPressed: () => _loadDirectory(''),
        child: const Text('الجذر'),
      ),
    );

    // Add separator
    widgets.add(const Text(' / '));

    // Add path parts
    String currentPath = '';
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;

      currentPath += (currentPath.isEmpty ? '' : '/') + parts[i];

      widgets.add(
        TextButton(
          onPressed: () => _loadDirectory(currentPath),
          child: Text(parts[i]),
        ),
      );

      if (i < parts.length - 1) {
        widgets.add(const Text(' / '));
      }
    }

    return widgets;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }
}

class FileSystemItem {
  final String name;
  final String type;
  final String path;
  final int? size;
  final String? modified;

  FileSystemItem({
    required this.name,
    required this.type,
    required this.path,
    this.size,
    this.modified,
  });

  bool get isDirectory => type == 'directory';

  factory FileSystemItem.fromJson(Map<String, dynamic> json) {
    return FileSystemItem(
      name: json['name'] as String,
      type: json['type'] as String,
      path: json['path'] as String,
      size: json['size'] as int?,
      modified: json['modified'] as String?,
    );
  }
}
