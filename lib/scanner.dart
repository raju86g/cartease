import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR Scanner')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && Navigator.canPop(context)) {
            // We pop with the first detected barcode value.
            // The ?? provides a fallback if rawValue is null.
            Navigator.pop<String>(context, barcode.rawValue ?? 'No data in QR');
          }
        },
      ),
    );
  }
}
