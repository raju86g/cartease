import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

typedef BarcodeScannedCallback = void Function(String barcode);

class ScannerPage extends StatefulWidget {
  final BarcodeScannedCallback? onScanned;

  const ScannerPage({super.key, this.onScanned});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Scanner')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_isProcessing) return;
          _isProcessing = true;

          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && Navigator.canPop(context)) {
            final value = barcode.rawValue ?? 'No data in QR';
            Navigator.pop<String>(context, value);
          }
        },
      ),
    );
  }
}
