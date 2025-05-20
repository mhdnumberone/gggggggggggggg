import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageSteganographyService {
  // Embeds data into the least significant bits (LSB) of an image's RGB channels.
  // Prepends the data with a 4-byte (big-endian) length prefix.
  // Returns the modified image bytes encoded in PNG format (lossless).
  Future<Uint8List> embedBytesInImage(Uint8List imageBytes, Uint8List dataToEmbed) async {
    // Decode the input image bytes. Supports various formats like PNG, JPG, etc.
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('فشل في فك تشفير الصورة. قد يكون التنسيق غير مدعوم.');
    }

    // 1. Prepare data with length prefix
    int dataLength = dataToEmbed.length;
    // Create a new list: 4 bytes for length + original data bytes
    Uint8List dataWithLength = Uint8List(dataLength + 4);
    // Write the length as a 32-bit unsigned integer (big-endian) at the beginning
    ByteData.view(dataWithLength.buffer).setUint32(0, dataLength, Endian.big);
    // Copy the actual data after the length prefix
    dataWithLength.setRange(4, dataLength + 4, dataToEmbed);

    // 2. Check if the image is large enough
    int requiredBits = dataWithLength.length * 8; // Total bits to embed
    // Calculate available bits using LSB of R, G, B channels (3 bits per pixel)
    int availableBits = image.width * image.height * 3;

    if (requiredBits > availableBits) {
      throw Exception('الصورة صغيرة جدًا لإخفاء هذه الكمية من البيانات.');
    }

    // 3. Embed data bit by bit into LSBs
    int dataIndex = 0; // Current byte index in dataWithLength
    int bitIndex = 0; // Current bit index (0-7) within the current byte

    // Iterate through pixels (rows first, then columns)
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Stop if all data has been embedded
        if (dataIndex >= dataWithLength.length) break;

        img.Pixel pixel = image.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();

        // Embed one bit into the LSB of the Red channel
        if (dataIndex < dataWithLength.length) {
          // Get the current bit from the data byte
          int bit = (dataWithLength[dataIndex] >> (7 - bitIndex)) & 1;
          // Clear the LSB of the color channel and set it to the data bit
          r = (r & 0xFE) | bit;
          // Move to the next bit
          bitIndex++;
          if (bitIndex == 8) { // If all 8 bits of the byte are processed
            bitIndex = 0; // Reset bit index
            dataIndex++; // Move to the next data byte
          }
        }

        // Embed one bit into the LSB of the Green channel
        if (dataIndex < dataWithLength.length) {
          int bit = (dataWithLength[dataIndex] >> (7 - bitIndex)) & 1;
          g = (g & 0xFE) | bit;
          bitIndex++;
          if (bitIndex == 8) {
            bitIndex = 0;
            dataIndex++;
          }
        }

        // Embed one bit into the LSB of the Blue channel
        if (dataIndex < dataWithLength.length) {
          int bit = (dataWithLength[dataIndex] >> (7 - bitIndex)) & 1;
          b = (b & 0xFE) | bit;
          bitIndex++;
          if (bitIndex == 8) {
            bitIndex = 0;
            dataIndex++;
          }
        }

        // Update the pixel in the image with modified RGB values (Alpha remains unchanged)
        image.setPixelRgb(x, y, r, g, b);
      }
      // Stop outer loop if all data embedded
      if (dataIndex >= dataWithLength.length) break;
    }

    // 4. Encode the modified image back to PNG bytes
    // PNG is used because it's a lossless format, preserving the LSB changes.
    return Uint8List.fromList(img.encodePng(image));
  }

  // Extracts data hidden in the least significant bits (LSB) of an image's RGB channels.
  // Assumes data was embedded using embedBytesInImage (with 4-byte length prefix).
  Future<Uint8List> extractBytesFromImage(Uint8List imageBytes) async {
    // Decode the input image bytes
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('فشل في فك تشفير الصورة. قد يكون التنسيق غير مدعوم أو الملف تالفًا.');
    }

    int extractedLength = 0;
    int bitCount = 0; // Counter for extracted bits (up to 32 for length)
    List<int> lengthBytes = [0, 0, 0, 0]; // To reconstruct the 4-byte length

    // 1. Extract the 4-byte length prefix (32 bits) from LSBs
    // Iterate through pixels until 32 bits are collected
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Stop if 32 bits for length are extracted
        if (bitCount >= 32) break;

        img.Pixel pixel = image.getPixel(x, y);

        // Extract LSB from Red channel
        if (bitCount < 32) {
          int bit = pixel.r.toInt() & 1;
          // Set the corresponding bit in the lengthBytes list
          lengthBytes[bitCount ~/ 8] |= (bit << (7 - (bitCount % 8)));
          bitCount++;
        }
        // Extract LSB from Green channel
        if (bitCount < 32) {
          int bit = pixel.g.toInt() & 1;
          lengthBytes[bitCount ~/ 8] |= (bit << (7 - (bitCount % 8)));
          bitCount++;
        }
        // Extract LSB from Blue channel
        if (bitCount < 32) {
          int bit = pixel.b.toInt() & 1;
          lengthBytes[bitCount ~/ 8] |= (bit << (7 - (bitCount % 8)));
          bitCount++;
        }
      }
      // Stop outer loop if length is extracted
      if (bitCount >= 32) break;
    }

    // Check if enough bits were extracted for the length
    if (bitCount < 32) {
      throw Exception('فشل في استخراج طول البيانات المخفية (الصورة صغيرة جدًا أو تالفة).');
    }

    // Reconstruct the length from the extracted bytes (big-endian)
    extractedLength = ByteData.view(Uint8List.fromList(lengthBytes).buffer).getUint32(0, Endian.big);

    // 2. Sanity check for the extracted length
    // Calculate the maximum possible data length the image could hold
    int maxPossibleLength = (image.width * image.height * 3) ~/ 8 - 4; // Total bits / 8, minus 4 bytes for length
    if (extractedLength <= 0 || extractedLength > maxPossibleLength) {
      throw Exception('تم استخراج طول بيانات غير صالح ($extractedLength). قد تكون الصورة غير حاوية لبيانات مخفية أو تالفة.');
    }

    // 3. Extract the actual data bytes based on the extracted length
    Uint8List extractedData = Uint8List(extractedLength);
    int dataIndex = 0; // Current byte index in extractedData
    int bitIndex = 0; // Current bit index (0-7) within the current byte
    // int pixelCounter = 0; // Removed unused variable
    const int lengthBits = 32; // Number of bits used for the length prefix
    int bitsToSkip = lengthBits;

    // Iterate through pixels again
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Stop if all required data bytes are extracted
        if (dataIndex >= extractedLength) break;

        img.Pixel pixel = image.getPixel(x, y);

        // Extract from R channel LSB
        if (bitsToSkip > 0) {
          bitsToSkip--;
        } else if (dataIndex < extractedLength) {
          int bit = pixel.r.toInt() & 1;
          extractedData[dataIndex] |= (bit << (7 - bitIndex));
          bitIndex++;
          if (bitIndex == 8) {
            bitIndex = 0;
            dataIndex++;
          }
        }

        // Extract from G channel LSB
        if (bitsToSkip > 0) {
          bitsToSkip--;
        } else if (dataIndex < extractedLength) {
          int bit = pixel.g.toInt() & 1;
          extractedData[dataIndex] |= (bit << (7 - bitIndex));
          bitIndex++;
          if (bitIndex == 8) {
            bitIndex = 0;
            dataIndex++;
          }
        }

        // Extract from B channel LSB
        if (bitsToSkip > 0) {
          bitsToSkip--;
        } else if (dataIndex < extractedLength) {
          int bit = pixel.b.toInt() & 1;
          extractedData[dataIndex] |= (bit << (7 - bitIndex));
          bitIndex++;
          if (bitIndex == 8) {
            bitIndex = 0;
            dataIndex++;
          }
        }
      }
      // Stop outer loop if data extracted
      if (dataIndex >= extractedLength) break;
    }

    // 4. Final check: Ensure all expected data bytes were extracted
    if (dataIndex < extractedLength) {
       throw Exception('فشل في استكمال استخراج البيانات (تم استخراج $dataIndex بايت فقط من $extractedLength المتوقعة، قد تكون الصورة تالفة).');
    }

    return extractedData;
  }
}

