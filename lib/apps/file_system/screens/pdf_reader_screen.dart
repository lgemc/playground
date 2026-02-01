import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../services/share_content.dart';
import '../../../services/share_service.dart';

class PdfReaderScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PdfReaderScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  String? _selectedText;

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  void _handleTextSelection(PdfTextSelectionChangedDetails details) {
    setState(() {
      _selectedText = details.selectedText;
    });

    if (details.selectedText != null && details.selectedText!.isNotEmpty) {
      _showSelectionMenu(details.selectedText!);
    }
  }

  void _showSelectionMenu(String selectedText) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share'),
            onTap: () async {
              Navigator.pop(context);
              await _shareText(selectedText);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(context);
              // Copy to clipboard
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _shareText(String text) async {
    final content = ShareContent.text(
      sourceAppId: 'file_system',
      text: text,
    );

    final success = await ShareService.instance.share(context, content);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text shared successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_selectedText != null && _selectedText!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareText(_selectedText!),
            ),
        ],
      ),
      body: _buildPdfViewer(),
    );
  }

  Widget _buildPdfViewer() {
    // Syncfusion PDF viewer has issues on Linux - show a simple fallback
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'PDF: ${widget.fileName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Path: ${widget.filePath}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              'PDF viewer not yet supported on desktop',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                // Open with system default PDF viewer
                Process.run('xdg-open', [widget.filePath]);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open with system viewer'),
            ),
          ],
        ),
      );
    }

    // Use Syncfusion PDF viewer on mobile platforms
    return SfPdfViewer.file(
      File(widget.filePath),
      controller: _pdfViewerController,
      enableTextSelection: true,
      onTextSelectionChanged: _handleTextSelection,
    );
  }
}