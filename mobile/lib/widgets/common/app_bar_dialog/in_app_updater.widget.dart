import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class NativeUpdater {
  static const _channel = MethodChannel('online.isosmart.photos/native');

  static Future<bool> canInstall() async {
    try {
      final res = await _channel.invokeMethod<bool>('canInstall');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  static Future<void> installApk(String path, [String? sha256]) async {
    await _channel.invokeMethod('installApk', {'path': path, 'sha256': sha256});
  }
}

class InAppUpdaterDialog extends StatefulWidget {
  const InAppUpdaterDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const InAppUpdaterDialog(),
    );
  }

  @override
  State<InAppUpdaterDialog> createState() => _InAppUpdaterDialogState();
}

class _InAppUpdaterDialogState extends State<InAppUpdaterDialog> {
  bool _loading = true;
  bool _hasUpdate = false;
  bool _downloading = false;
  double _progress = 0.0;
  String? _newVersionName;
  String? _apkDownloadUrl;
  String? _errorMessage;
  String _statusMessage = 'Checking for updates...';

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final res = await http.get(
        Uri.parse('https://api.github.com/repos/prithvirz/isosmart-photos/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _errorMessage = 'Could not reach update server (${res.statusCode})';
        });
        return;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      final assets = (data['assets'] as List<dynamic>? ?? []);

      String? apkUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (apkUrl == null) {
        setState(() {
          _loading = false;
          _statusMessage = 'You are using the latest version ($currentVersion).';
        });
        return;
      }

      final isNewer = tagName != currentVersion;
      setState(() {
        _loading = false;
        _hasUpdate = isNewer;
        _newVersionName = tagName;
        _apkDownloadUrl = apkUrl;
        _statusMessage = isNewer
            ? 'New version available: $tagName\n(Current: $currentVersion)'
            : 'You are using the latest version ($currentVersion).';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Check failed: $e';
      });
    }
  }

  Future<void> _startDownloadAndInstall() async {
    if (_apkDownloadUrl == null) return;

    if (!await NativeUpdater.canInstall()) {
      await NativeUpdater.openInstallSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please allow installing apps from Isosmart Photos and tap Update again.')),
      );
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0.0;
      _statusMessage = 'Downloading update...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}/updates');
      if (!updateDir.existsSync()) {
        updateDir.createSync(recursive: true);
      }

      final apkFile = File('${updateDir.path}/isosmart-photos-update.apk');
      if (apkFile.existsSync()) {
        apkFile.deleteSync();
      }

      final request = http.Request('GET', Uri.parse(_apkDownloadUrl!));
      final response = await http.Client().send(request);
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = apkFile.openWrite();
      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          setState(() {
            _progress = receivedBytes / totalBytes;
          });
        }
      }).asFuture();

      await sink.close();

      setState(() {
        _statusMessage = 'Starting installation...';
      });

      await NativeUpdater.installApk(apkFile.path);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _downloading = false;
        _errorMessage = 'Download error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.system_update_rounded, size: 24),
          SizedBox(width: 8),
          Text('App Update', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: const [
                  SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 16),
                  Text('Checking releases...'),
                ],
              ),
            )
          else if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))
          else
            Text(_statusMessage, style: const TextStyle(fontSize: 14)),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 6),
            Text('${(_progress * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_hasUpdate && !_downloading)
          FilledButton.icon(
            onPressed: _startDownloadAndInstall,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Install Update'),
          ),
      ],
    );
  }
}
