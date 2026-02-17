import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/src/rust/api/error.dart';

class ImportIdentityScreen extends ConsumerStatefulWidget {
  const ImportIdentityScreen({super.key});

  @override
  ConsumerState<ImportIdentityScreen> createState() =>
      _ImportIdentityScreenState();
}

class _ImportIdentityScreenState extends ConsumerState<ImportIdentityScreen> {
  final _nsecController = TextEditingController();
  bool _isImporting = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _nsecController.dispose();
    super.dispose();
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _nsecController.text = result;
      // Show confirmation before importing
      final confirmed = await _showImportConfirmation(result);
      if (confirmed && mounted) {
        _import();
      }
    }
  }

  Future<bool> _showImportConfirmation(String scannedKey) async {
    // Truncate the key for display: show first 12 and last 8 chars
    final display = scannedKey.length > 24
        ? '${scannedKey.substring(0, 12)}…${scannedKey.substring(scannedKey.length - 8)}'
        : scannedKey;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded,
              color: theme.colorScheme.error, size: 32),
          title: const Text('Import Identity?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to import the following key:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  display,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This will replace your current identity. '
                'Make sure you have a backup of your existing key.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _import() async {
    final key = _nsecController.text.trim();
    if (key.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await ref.read(authProvider.notifier).importIdentity(key);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        final msg = e is BurrowError ? e.message : e.toString();
        final label = msg.contains('InvalidSecretKey')
            ? 'Invalid key format. Please enter a valid nsec or hex private key.'
            : 'Login failed: $msg';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(label)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import Identity')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.key, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Enter your secret key',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Paste your nsec or hex private key. It stays on your device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nsecController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: 'nsec1...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanQrCode,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isImporting ? null : _import,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isImporting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Import & Login'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your private key is never sent to any server. '
                    'It is stored only on this device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen QR code scanner for reading nsec / hex private keys.
class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasPopped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasPopped) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      // Accept nsec1... (bech32) or 64-char hex
      final trimmed = value.trim();
      if (trimmed.startsWith('nsec1') ||
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
        _hasPopped = true;
        Navigator.of(context).pop(trimmed);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Secret Key'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, state, __) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
              ),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(220),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Point the camera at a QR code containing your nsec or hex private key.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
