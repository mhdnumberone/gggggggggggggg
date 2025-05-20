import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io'; // Only for mobile
// Conditional import for web download functionality
import 'package:universal_html/html.dart' as html show AnchorElement, Blob, Url;

class FileSaver {
  static Future<String> saveFile({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    if (kIsWeb) {
      // Web implementation: Trigger browser download
      try {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        // The anchor element is created and clicked in one line to avoid unused variable warning.
        html.AnchorElement(href: url)
          ..setAttribute("download", suggestedFileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        return 'تم بدء تنزيل الملف "$suggestedFileName" في المتصفح.';
      } catch (e) {
        print("Web File Save Error: $e");
        throw Exception('فشل حفظ الملف على الويب: ${e.toString()}');
      }
    } else {
      // Mobile implementation: Save to downloads directory
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          throw Exception('لا يمكن الوصول إلى مجلد التنزيلات.');
        }
        final outputPath = path.join(downloadsDir.path, suggestedFileName);
        final outputFile = File(outputPath);
        await outputFile.writeAsBytes(bytes);
        return 'تم حفظ الملف بنجاح في: $outputPath';
      } catch (e) {
        print("Mobile File Save Error: $e");
        throw Exception('فشل حفظ الملف على الجهاز: ${e.toString()}');
      }
    }
  }
}

