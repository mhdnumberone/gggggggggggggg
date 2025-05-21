// lib/core/control/file_system_service.dart - Mejorado
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final List<FileNode> children;

  FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.children = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'type': isDirectory ? 'directory' : 'file',
      'size': isDirectory ? null : size,
      'modified': modified.toIso8601String(),
      'children':
          isDirectory ? children.map((child) => child.toJson()).toList() : null,
    };
  }
}

class FileSystemService {
  Future<String> getAppDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<FileNode> getDirectoryTree(String directoryPath,
      {int maxDepth = 3, int currentDepth = 0}) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw Exception("Directory does not exist: $directoryPath");
      }

      final dirStat = await directory.stat();
      final dirName = path.basename(directoryPath);

      // Crear nodo base del directorio
      final node = FileNode(
        name: dirName,
        path: directoryPath,
        isDirectory: true,
        size: 0, // Los directorios no tienen tamaño directo
        modified: dirStat.modified,
        children: [],
      );

      // Si alcanzamos la profundidad máxima, no seguimos recursivamente
      if (currentDepth >= maxDepth) {
        return node;
      }

      // Obtener el contenido del directorio
      final entities = await directory.list().toList();

      // Procesar cada entidad recursivamente
      for (final entity in entities) {
        try {
          if (entity is Directory) {
            final childNode = await getDirectoryTree(entity.path,
                maxDepth: maxDepth, currentDepth: currentDepth + 1);
            node.children.add(childNode);
          } else if (entity is File) {
            final fileStat = await entity.stat();
            node.children.add(FileNode(
              name: path.basename(entity.path),
              path: entity.path,
              isDirectory: false,
              size: fileStat.size,
              modified: fileStat.modified,
            ));
          }
        } catch (e) {
          debugPrint("Error processing entity ${entity.path}: $e");
          // Continuamos con el siguiente elemento
        }
      }

      // Ordenar: primero directorios, luego archivos, ambos alfabéticamente
      node.children.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });

      return node;
    } catch (e) {
      debugPrint("Error getting directory tree: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        return {
          "error": "Directory does not exist: $path",
        };
      }

      final tree = await getDirectoryTree(path, maxDepth: 1);
      return {
        "path": path,
        "tree": tree.toJson(),
      };
    } catch (e) {
      debugPrint("FileSystemService: Error listing files: $e");
      return {
        "error": e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> searchFiles(
      String rootPath, String query) async {
    try {
      final results = <FileNode>[];
      await _searchRecursive(rootPath, query.toLowerCase(), results);

      return {
        "query": query,
        "results": results.map((node) => node.toJson()).toList(),
      };
    } catch (e) {
      debugPrint("FileSystemService: Error searching files: $e");
      return {
        "error": e.toString(),
      };
    }
  }

  Future<void> _searchRecursive(
      String dirPath, String query, List<FileNode> results) async {
    try {
      final dir = Directory(dirPath);
      final entities = await dir.list().toList();

      for (var entity in entities) {
        final name = path.basename(entity.path);

        if (name.toLowerCase().contains(query)) {
          final stat = await entity.stat();
          results.add(FileNode(
            name: name,
            path: entity.path,
            isDirectory: entity is Directory,
            size: entity is File ? stat.size : 0,
            modified: stat.modified,
          ));
        }

        if (entity is Directory) {
          await _searchRecursive(entity.path, query, results);
        }
      }
    } catch (e) {
      debugPrint("Error during file search in $dirPath: $e");
    }
  }

  Future<String?> saveTextFile(String content, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);
      debugPrint("FileSystemService: Text file saved: ${file.path}");
      return file.path;
    } catch (e) {
      debugPrint("FileSystemService: Error saving text file: $e");
      return null;
    }
  }

  Future<String?> readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return content;
      } else {
        debugPrint("FileSystemService: File does not exist: $filePath");
        return null;
      }
    } catch (e) {
      debugPrint("FileSystemService: Error reading text file: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> executeShellCommand(
    String command,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(command, args);
      return {
        "stdout": result.stdout.toString(),
        "stderr": result.stderr.toString(),
        "exitCode": result.exitCode,
      };
    } catch (e) {
      debugPrint("FileSystemService: Error executing shell command: $e");
      return {
        "error": e.toString(),
      };
    }
  }
}
