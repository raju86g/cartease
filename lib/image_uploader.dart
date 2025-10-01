import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ImageUploader {
  // IMPORTANT: Replace with your own imgbb API key.
  // You can get one from https://api.imgbb.com/
  static const String _apiKey = '624c7f03d544ea3e3eb4e7fe29bd03a8';

  static Future<String?> uploadImage(Uint8List imageBytes) async {
    try {
      final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$_apiKey');
      var request = http.MultipartRequest('POST', uri);

      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'product_image.jpg',
      ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseBody);
        return jsonResponse['data']['url'];
      }
    } catch (e) {
      print('Image upload failed: $e');
    }
    return null;
  }
}