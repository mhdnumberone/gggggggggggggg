// lib/presentation/file_encryption_tab/file_encryption_screen.dart
// import 'dart:io'; // إزالة إذا لم تستخدمه مباشرة هنا (Web لا يدعمه)
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
// import 'package:path_provider/path_provider.dart'; // إزالة إذا لم تستخدمه
import 'package:path/path.dart' as path; // لا يزال مستخدمًا

import '../../core/encryption/aes_gcm_service.dart'; //  <<< تأكد من المسار
import '../../core/logging/logger_provider.dart'; //  <<< لاستخدام appLoggerProvider
import '../../core/logging/logger_service.dart';
import '../../core/utils/file_saver.dart';
// لا حاجة لاستيراد ../encryption_tab/encryption_tab.dart

enum FileOperationMode { encrypt, decrypt }

class FileEncryptionState {
  final PlatformFile? inputFile;
  final String passwordInput;
  final String outputMessage;
  final bool isLoading;
  final double progress;
  final bool isPasswordVisible;
  final FileOperationMode operationMode;

  FileEncryptionState({
    this.inputFile,
    this.passwordInput = '',
    this.outputMessage = '',
    this.isLoading = false,
    this.progress = 0.0,
    this.isPasswordVisible = false,
    this.operationMode = FileOperationMode.encrypt,
  });

  FileEncryptionState copyWith({
    PlatformFile? inputFile,
    String? passwordInput,
    String? outputMessage,
    bool? isLoading,
    double? progress,
    bool? isPasswordVisible,
    FileOperationMode? operationMode,
    bool clearInputFile = false,
  }) {
    return FileEncryptionState(
      inputFile: clearInputFile ? null : inputFile ?? this.inputFile,
      passwordInput: passwordInput ?? this.passwordInput,
      outputMessage: outputMessage ?? this.outputMessage,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      isPasswordVisible: isPasswordVisible ?? this.isPasswordVisible,
      operationMode: operationMode ?? this.operationMode,
    );
  }
}

class FileEncryptionNotifier extends StateNotifier<FileEncryptionState> {
  final AesGcmService _aesService;
  final LoggerService _logger; // إضافة logger

  FileEncryptionNotifier(this._aesService, this._logger)
      : super(FileEncryptionState());

  void setOperationMode(FileOperationMode mode) => state = state.copyWith(
      operationMode: mode, outputMessage: '', inputFile: null, progress: 0.0);
  void updatePasswordInput(String value) =>
      state = state.copyWith(passwordInput: value);
  void togglePasswordVisibility() =>
      state = state.copyWith(isPasswordVisible: !state.isPasswordVisible);

  void resetState() {
    state = state.copyWith(
      clearInputFile: true, // سيقوم بتعيين inputFile إلى null
      // passwordInput: '', // قد يرغب المستخدم في الاحتفاظ بكلمة المرور
      outputMessage: '',
      isLoading: false,
      progress: 0.0,
    );
  }

  Future<void> pickFile() async {
    try {
      _logger.info("pickFile", "Attempting to pick file.");
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        _logger.info("pickFile", "File picked: ${result.files.first.name}");
        state = state.copyWith(
          inputFile: result.files.first,
          outputMessage: '',
          progress: 0.0,
        );
      } else {
        _logger.info("pickFile", "File picking cancelled by user.");
        state = state.copyWith(
            outputMessage: 'لم يتم اختيار أي ملف.'); // رسالة أوضح
      }
    } catch (e, stackTrace) {
      _logger.error("pickFile", "Error during file picking", e, stackTrace);
      state = state.copyWith(
          outputMessage: '❌ خطأ أثناء اختيار الملف: ${e.toString()}');
    }
  }

  Future<void> performFileOperation() async {
    if (state.inputFile == null) {
      state = state.copyWith(outputMessage: '❌ يرجى اختيار ملف أولاً.');
      return;
    }
    if (state.passwordInput.isEmpty) {
      state = state.copyWith(outputMessage: '❌ يرجى إدخال كلمة مرور.');
      return;
    }
    state = state.copyWith(
        isLoading: true, outputMessage: 'جاري التهيئة...', progress: 0.0);
    _logger.info("performFileOperation",
        "Starting file operation. Mode: ${state.operationMode}, File: ${state.inputFile!.name}");

    try {
      final inputFile = state.inputFile!;
      final inputFileName = inputFile.name; // اسم الملف الأصلي
      final fileBytes = inputFile.bytes;

      if (fileBytes == null) {
        _logger.error("performFileOperation",
            "File bytes are null for ${inputFile.name}.");
        throw Exception(
            "لا يمكن قراءة بيانات الملف المختار. قد يكون الملف كبيرًا جدًا للقراءة المباشرة في الذاكرة على هذه المنصة.");
      }
      _logger.debug(
          "performFileOperation", "File bytes length: ${fileBytes.length}");

      final password = state.passwordInput;
      final isEncrypting = state.operationMode == FileOperationMode.encrypt;

      state = state.copyWith(
          outputMessage:
              isEncrypting ? 'جاري التشفير...' : 'جاري فك التشفير...',
          progress: 0.2);

      Uint8List resultBytes;
      if (isEncrypting) {
        resultBytes =
            await _aesService.encryptBytesWithPassword(fileBytes, password);
      } else {
        resultBytes =
            await _aesService.decryptBytesWithPassword(fileBytes, password);
      }
      _logger.info("performFileOperation",
          "Encryption/Decryption complete. Result bytes length: ${resultBytes.length}");

      state =
          state.copyWith(outputMessage: 'تجهيز الملف للحفظ...', progress: 0.7);
      final outputFileName = isEncrypting
          ? '${path.basenameWithoutExtension(inputFileName)}.conduit_enc' // امتداد مميز
          : (inputFileName.endsWith('.conduit_enc')
              ? inputFileName.substring(
                  0, inputFileName.length - '.conduit_enc'.length)
              : 'decrypted_$inputFileName');
      _logger.info("performFileOperation", "Output file name: $outputFileName");

      state = state.copyWith(outputMessage: 'جاري حفظ الملف...', progress: 0.9);
      // FileSaver.saveFile هو للويب. ستحتاج إلى طريقة حفظ مختلفة للموبايل
      // هنا يجب عليك تحديد منصة التشغيل
      if (kIsWeb) {
        await FileSaver.saveFile(
            bytes: resultBytes, suggestedFileName: outputFileName);
      } else {
        //   // منطق حفظ الملف للموبايل (يتطلب أذونات ومسارات)
        //   // ... هذا الجزء يحتاج تنفيذ خاص للموبايل ...
        _logger.warn("performFileOperation",
            "Mobile file saving not yet implemented. Data is in memory.");
        throw Exception(
            "حفظ الملفات على الهاتف غير مدعوم حاليًا في هذه النسخة التجريبية.");
      }
      await FileSaver.saveFile(
          bytes: resultBytes,
          suggestedFileName: outputFileName); // افتراض أنه يعمل للويب حاليًا

      state = state.copyWith(
          isLoading: false,
          outputMessage: '✅ تمت معالجة وحفظ الملف بنجاح باسم: $outputFileName',
          progress: 1.0);
      _logger.info("performFileOperation",
          "File operation successful. Saved as: $outputFileName");
    } on SecretBoxAuthenticationError {
      _logger.warn("performFileOperation",
          "Authentication failed (wrong password or data tampered)");
      state = state.copyWith(
        isLoading: false,
        outputMessage:
            '❌ خطأ: فشل فك تشفير الملف. كلمة المرور خاطئة أو الملف تالف.',
        progress: 0.0,
      );
      // لا حاجة لـ throw هنا
    } catch (e, stackTrace) {
      _logger.error(
          "performFileOperation", "Error during file operation", e, stackTrace);
      final errorMessage = e.toString().replaceFirst("Exception: ", "");
      state = state.copyWith(
        isLoading: false,
        outputMessage: '❌ خطأ: $errorMessage',
        progress: 0.0,
      );
      // لا حاجة لـ throw هنا
    }
  }
}

final fileEncryptionScreenProvider = // تم تغيير الاسم
    StateNotifierProvider<FileEncryptionNotifier, FileEncryptionState>((ref) {
  return FileEncryptionNotifier(
    ref.watch(aesGcmServiceProvider),
    ref.watch(appLoggerProvider), // تمرير الـ logger
  );
});

// تم تغيير اسم الكلاس
class FileEncryptionScreen extends ConsumerWidget {
  const FileEncryptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileEncryptionScreenProvider);
    final notifier = ref.read(fileEncryptionScreenProvider.notifier);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFileOperationModeSelector(context, state, notifier),
              const SizedBox(height: 20),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.attach_file_rounded,
                            color: Colors.white.withOpacity(0.9)),
                        label: Text('اختر ملفًا للمعالجة',
                            style: GoogleFonts.cairo(
                                fontSize: 16, fontWeight: FontWeight.w500)),
                        onPressed: state.isLoading ? null : notifier.pickFile,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (state.inputFile != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: theme.primaryColor.withOpacity(0.3))),
                          child: Row(
                            children: [
                              Icon(Icons.insert_drive_file_rounded,
                                  color: theme.primaryColor, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.inputFile!.name,
                                      style: GoogleFonts.cairo(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (state.inputFile!.size > 0)
                                      Text(
                                        'الحجم: ${(state.inputFile!.size / 1024).toStringAsFixed(2)} KB',
                                        style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close_rounded,
                                    size: 20, color: Colors.grey[700]),
                                onPressed: state.isLoading
                                    ? null
                                    : notifier.resetState,
                                tooltip: 'إلغاء اختيار الملف',
                              )
                            ],
                          ),
                        )
                      else
                        Text('لم يتم اختيار أي ملف بعد.',
                            style: GoogleFonts.cairo(
                                textStyle: TextStyle(
                                    color: Colors.grey[600], fontSize: 14))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: TextEditingController(text: state.passwordInput)
                      ..selection = TextSelection.fromPosition(
                          TextPosition(offset: state.passwordInput.length)),
                    onChanged: notifier.updatePasswordInput,
                    obscureText: !state.isPasswordVisible,
                    style: GoogleFonts.cairo(fontSize: 16, letterSpacing: 1),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      labelStyle: GoogleFonts.cairo(),
                      hintText: 'مطلوبة لتشفير وفك تشفير الملفات...',
                      hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.password_rounded,
                          color: theme.iconTheme.color?.withOpacity(0.7)),
                      suffixIcon: IconButton(
                        icon: Icon(
                            state.isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: theme.iconTheme.color?.withOpacity(0.7)),
                        onPressed: notifier.togglePasswordVisibility,
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : Icon(state.operationMode == FileOperationMode.encrypt
                        ? Icons.enhanced_encryption_rounded
                        : Icons.lock_open_rounded),
                label: Text(
                    state.isLoading
                        ? 'جاري المعالجة...'
                        : (state.operationMode == FileOperationMode.encrypt
                            ? 'تشفير الملف المختار'
                            : 'فك تشفير الملف المختار'),
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: (state.isLoading ||
                        state.inputFile == null ||
                        state.passwordInput.isEmpty)
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus(); // إخفاء لوحة المفاتيح
                        try {
                          await notifier.performFileOperation();
                          if (context.mounted &&
                              !state.isLoading &&
                              (ref
                                      .read(fileEncryptionScreenProvider)
                                      .outputMessage
                                      .isNotEmpty &&
                                  !ref
                                      .read(fileEncryptionScreenProvider)
                                      .outputMessage
                                      .startsWith('❌'))) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      ref
                                          .read(fileEncryptionScreenProvider)
                                          .outputMessage,
                                      style: GoogleFonts.cairo()),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.green[700],
                                  duration: const Duration(seconds: 4)),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('حدث خطأ في العملية',
                                    style: GoogleFonts.cairo()),
                                content: Text(
                                    e
                                        .toString()
                                        .replaceFirst("Exception: ", ""),
                                    style: GoogleFonts.cairo()),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: Text('حسنًا',
                                          style: GoogleFonts.cairo(
                                              color: theme.primaryColor)))
                                ],
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 3,
                ),
              ),
              const SizedBox(height: 20),
              if (state.isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.progress,
                        backgroundColor: theme.primaryColor.withOpacity(0.2),
                        color: theme.primaryColor,
                        minHeight: 6,
                      ),
                      const SizedBox(height: 8),
                      Text(state.outputMessage,
                          style: GoogleFonts.cairo(
                              textStyle: TextStyle(
                                  color: theme.primaryColor, fontSize: 14))),
                    ],
                  ),
                )
              else if (state.outputMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    state.outputMessage,
                    style: GoogleFonts.cairo(
                        textStyle: TextStyle(
                            color: state.outputMessage.startsWith('❌')
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileOperationModeSelector(BuildContext context,
      FileEncryptionState state, FileEncryptionNotifier notifier) {
    final theme = Theme.of(context);
    return SegmentedButton<FileOperationMode>(
      segments: <ButtonSegment<FileOperationMode>>[
        ButtonSegment<FileOperationMode>(
          value: FileOperationMode.encrypt,
          label: Text('تشفير ملف',
              style: GoogleFonts.cairo(
                  fontWeight: state.operationMode == FileOperationMode.encrypt
                      ? FontWeight.w600
                      : FontWeight.normal)),
          icon: const Icon(Icons.enhanced_encryption_outlined, size: 20),
        ),
        ButtonSegment<FileOperationMode>(
          value: FileOperationMode.decrypt,
          label: Text('فك تشفير ملف',
              style: GoogleFonts.cairo(
                  fontWeight: state.operationMode == FileOperationMode.decrypt
                      ? FontWeight.w600
                      : FontWeight.normal)),
          icon: const Icon(Icons.lock_open_outlined, size: 20),
        ),
      ],
      selected: {state.operationMode},
      onSelectionChanged: (Set<FileOperationMode> newSelection) {
        notifier.setOperationMode(newSelection.first);
      },
      style: SegmentedButton.styleFrom(
        backgroundColor:
            theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        selectedBackgroundColor: theme.primaryColor.withOpacity(0.9),
        selectedForegroundColor: Colors.white,
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        textStyle: GoogleFonts.cairo(fontSize: 13),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      showSelectedIcon: false, // لإخفاء أيقونة الاختيار الافتراضية
    );
  }
}
