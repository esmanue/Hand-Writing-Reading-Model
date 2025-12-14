import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handwriting Reader (Web)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const PredictWebScreen(),
    );
  }
}

class PredictWebScreen extends StatefulWidget {
  const PredictWebScreen({super.key});

  @override
  State<PredictWebScreen> createState() => _PredictWebScreenState();
}

class _PredictWebScreenState extends State<PredictWebScreen> {
  Uint8List? _imageBytes;
  String? _prediction;
  String? _error;
  bool _loading = false;

  final String baseUrl = "http://localhost:8000";

  Future<Uint8List?> _pickImageBytesWeb() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/png,image/jpeg';

    web.document.body?.append(input);
    input.click();

    try {
      await input.onChange.first.timeout(const Duration(seconds: 60));

      final file = input.files?.item(0);
      if (file == null) return null;

      final mime = (file.type).toLowerCase();
      if (mime != 'image/png' && mime != 'image/jpeg') {
        throw Exception("Lütfen PNG veya JPG/JPEG seç (HEIC/WebP desteklenmiyor).");
      }

      final reader = web.FileReader();
      final completer = Completer<Uint8List?>();

      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (result == null) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }

        // "data:image/png;base64,...."
        final dataUrl = result.toString();
        final comma = dataUrl.indexOf(',');
        if (comma < 0) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }

        final b64 = dataUrl.substring(comma + 1);
        try {
          final bytes = base64Decode(b64);
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (_) {
          if (!completer.isCompleted) {
            completer.completeError(Exception("Görsel base64 decode edilemedi."));
          }
        }
      });

      reader.readAsDataURL(file);

      // Okuma takılırsa diye timeout
      return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    } on TimeoutException {
      return null;
    } finally {
      input.remove();
    }
  }

  Future<void> pickImage() async {
    setState(() {
      _error = null;
      _prediction = null;
    });

    try {
      final bytes = await _pickImageBytesWeb();
      if (bytes == null) return;

      setState(() {
        _imageBytes = bytes;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _imageBytes = null;
      });
    }
  }

  Future<void> predict() async {
    if (_imageBytes == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _prediction = null;
    });

    try {
      final uri = Uri.parse("$baseUrl/predict-word?infer_orientation=none");
      final req = http.MultipartRequest("POST", uri);

      req.files.add(
        http.MultipartFile.fromBytes(
          "image",
          _imageBytes!,
          filename: "upload.jpg",
        ),
      );

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode != 200) {
        throw Exception("Server error: ${resp.statusCode}\n${resp.body}");
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() {
        _prediction = (data["prediction"] ?? "").toString();
      });
    } catch (e) {
      setState(() {
        _error =
            "İstek atılamadı (Failed to fetch). Muhtemelen CORS/Backend URL.\n"
            "URL: $baseUrl\n"
            "Hata: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPredict = !_loading && _imageBytes != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Handwriting Word Reader (Web)")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: _imageBytes == null
                      ? const Center(child: Text("Bir PNG/JPG görsel seç"))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : pickImage,
                        icon: const Icon(Icons.upload_file),
                        label: const Text("Görsel Seç"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canPredict ? predict : null,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_loading ? "Tahmin..." : "Tahmin Et"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_prediction != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.text_fields),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _prediction!,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 10),
                Text("Backend: $baseUrl", style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
