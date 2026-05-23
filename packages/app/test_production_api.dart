import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// Tell the Dart engine to accept our development SSL cert context
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Automatically trust our custom server domain layer
        return host == "gativani.sohum.cloud";
      };
  }
}

void main() async {
  // Activate our custom SSL bypass handler globally
  HttpOverrides.global = MyHttpOverrides();

  final String backendUrl = 'https://gativani.sohum.cloud/api/documents/process';
  
  final testFile = File('test-mobile-upload.txt');
  await testFile.writeAsString('సమయం మూడు గంటలు - Sent directly from our Flutter Client Network Logic.');

  print('📡 [Integration Test] Initializing live HTTP Multipart Request to: $backendUrl');

  try {
    final request = http.MultipartRequest('POST', Uri.parse(backendUrl));

    request.headers.addAll({
      'X-Subscription-Tier': 'premium',
    });

    request.files.add(
      await http.MultipartFile.fromPath(
        'document',
        testFile.path,
        filename: 'test-mobile-upload.txt',
      ),
    );

    print('🚀 Sending multipart payload across the internet (SSL Bypass Active)...');
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('📡 Server Response Code: ${response.statusCode}');
    print('📦 Server Response Body:');
    print(response.body);

    await testFile.delete();

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['ok'] == true) {
        print('\n🏆 SUCCESS! Your core client network engine is fully operational!');
        print('📝 Received Telugu Summary: ${data['summary']}');
      }
    }
  } catch (e) {
    print('❌ Connection Error: $e');
  }
}
