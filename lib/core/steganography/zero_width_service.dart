import 'dart:convert';

class ZeroWidthService {
  // Encodes a string into zero-width characters (U+200B and U+200C).
  String encode(String input) {
    if (input.isEmpty) return '';
    final bytes = utf8.encode(input);
    StringBuffer sb = StringBuffer();
    for (var byte in bytes) {
      for (int i = 7; i >= 0; i--) {
        // Use U+200C (ZWNJ) for 1 and U+200B (ZWSP) for 0
        sb.write(((byte >> i) & 1) == 1 ? '\u200C' : '\u200B');
      }
    }
    return sb.toString();
  }

  // Decodes a string containing zero-width characters back to the original string.
  // Returns the decoded string or throws an exception if decoding fails.
  String decode(String input) {
    // Filter only the relevant zero-width characters
    final zeroWidthRunes = input.runes.where((r) => r == 0x200B || r == 0x200C).toList();

    // Check if the number of bits is a multiple of 8
    if (zeroWidthRunes.isEmpty || zeroWidthRunes.length % 8 != 0) {
      throw Exception('No hidden message found or data is corrupted (invalid length).');
    }

    List<int> bytes = [];
    try {
      for (int i = 0; i < zeroWidthRunes.length; i += 8) {
        int currentByte = 0;
        for (int j = 0; j < 8; j++) {
          if (zeroWidthRunes[i + j] == 0x200C) { // 1 is ZWNJ
            currentByte |= (1 << (7 - j));
          }
          // No need for else, ZWSP (0) doesn't change the byte
        }
        bytes.add(currentByte);
      }
      // Attempt to decode the byte list as UTF-8
      return utf8.decode(bytes, allowMalformed: false); // Strict decoding
    } on FormatException catch (e) {
      print('Zero-width decoding error (Format): $e');
      throw Exception('Failed to decode hidden message: Invalid character sequence.');
    } catch (e) {
      print('Zero-width decoding error: $e');
      throw Exception('Failed to decode hidden message: ${e.toString()}');
    }
  }

  // Hides a secret message (already encoded with zero-width chars) within a cover message.
  // Simple strategy: append to the end.
  // More sophisticated strategies could intersperse characters.
  String hideInCoverText(String coverText, String zeroWidthMessage) {
    // Basic implementation: just append the zero-width message
    // Ensure there's maybe a space or ZWSP if cover text doesn't end with one?
    // For now, simple append is likely sufficient as they are invisible.
    return '$coverText$zeroWidthMessage';
  }

  // Extracts the zero-width message potentially hidden in a combined text.
  // This relies on the decode function filtering non-zero-width characters.
  String extractFromText(String combinedText) {
    // The decode function inherently extracts by filtering.
    return decode(combinedText);
  }
}

