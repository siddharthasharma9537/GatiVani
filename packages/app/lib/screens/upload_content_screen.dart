import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../design/app_theme.dart';
import '../services/document_service.dart';
import 'review_screen.dart';

class UploadContentScreen extends StatefulWidget {
  const UploadContentScreen({Key? key}) : super(key: key);

  @override
  State<UploadContentScreen> createState() => _UploadContentScreenState();
}

class _UploadContentScreenState extends State<UploadContentScreen> {
  late final DocumentService _uploadService;
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String _processingStep = '';

  @override
  void initState() {
    super.initState();
    _uploadService = DocumentService();
  }

  Future<bool> _requestPermission(Permission permission) async {
    if (kIsWeb) return true;
    final status = await permission.request();
    return status.isGranted;
  }

  Future<void> _processImage(XFile image, String source) async {
    try {
      setState(() {
        _isProcessing = true;
        _processingStep = 'uploading';
      });
      _showProcessingDialog();

      final bytes = await image.readAsBytes();
      final extension = image.name.split('.').last;
      final cleanExtension = extension.length <= 4 ? extension : 'jpg';
      final filename =
          'document_${DateTime.now().millisecondsSinceEpoch}.$cleanExtension';

      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _processingStep = 'extracting');

      final article = await _uploadService.processUploadedContent(
        filePath: image.path,
        source: source,
        filename: filename,
        fileBytes: bytes,
      );

      if (mounted) {
        setState(() => _processingStep = 'complete');
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context); // dismiss dialog
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReviewScreen(article: article)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError('Processing failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStep = '';
        });
      }
    }
  }

  Future<void> _uploadFromCamera() async {
    final hasPermission = await _requestPermission(Permission.camera);
    if (!hasPermission) return _showError('Camera permission denied');
    final photo = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (photo != null) await _processImage(photo, 'camera');
  }

  Future<void> _uploadFromGallery() async {
    if (!kIsWeb) {
      final hasPermission = await _requestPermission(Permission.photos);
      if (!hasPermission) {
        final storage = await _requestPermission(Permission.storage);
        if (!storage) return _showError('Storage permission denied');
      }
    }
    final image = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (image != null) await _processImage(image, 'gallery');
  }

  // TODO: replace with real file_picker for PDFs
  Future<void> _uploadPDF() async => await _uploadFromGallery();

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: GVColors.danger(context),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GVRadius.md)),
      ),
    );
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProcessingDialog(step: _processingStep),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add document'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a source',
                style: GVTypography.heading(context),
              ),
              const SizedBox(height: 6),
              Text(
                'Capture or import your document to convert it to audio.',
                style: GVTypography.bodySecondary(context),
              ),
              const SizedBox(height: 24),
              _SourceCard(
                icon: Icons.camera_alt_outlined,
                title: 'Camera scan',
                subtitle: 'Photograph a physical page',
                enabled: !_isProcessing,
                onTap: _uploadFromCamera,
              ),
              const SizedBox(height: 10),
              _SourceCard(
                icon: Icons.photo_library_outlined,
                title: 'Device gallery',
                subtitle: 'Choose an existing image',
                enabled: !_isProcessing,
                onTap: _uploadFromGallery,
              ),
              const SizedBox(height: 10),
              _SourceCard(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Import PDF',
                subtitle: 'Upload a PDF document',
                enabled: !_isProcessing,
                onTap: _uploadPDF,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Source picker card ────────────────────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(GVRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GVColors.bgPrimary(context),
            borderRadius: BorderRadius.circular(GVRadius.lg),
            border: Border.all(
              color: GVColors.borderTertiary(context),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GVColors.bgTertiary(context),
                  borderRadius: BorderRadius.circular(GVRadius.md),
                ),
                child: Icon(icon,
                    size: 20, color: GVColors.textSecondary(context)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GVTypography.body(context)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: GVTypography.small(context)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: GVColors.textTertiary(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Processing dialog ─────────────────────────────────────────────────────────

class _ProcessingDialog extends StatelessWidget {
  final String step;
  const _ProcessingDialog({required this.step});

  String get _title {
    switch (step) {
      case 'uploading':
        return 'Uploading document';
      case 'extracting':
        return 'Extracting text';
      case 'complete':
        return 'Done';
      default:
        return 'Processing';
    }
  }

  String get _subtitle {
    switch (step) {
      case 'uploading':
        return 'Sending file to Gemini...';
      case 'extracting':
        return 'AI is reading your document...';
      case 'complete':
        return 'Preparing your review...';
      default:
        return 'Please wait';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GVColors.bgPrimary(context),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GVRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: GVColors.accent(context),
              ),
            ),
            const SizedBox(height: 20),
            Text(_title, style: GVTypography.heading(context)),
            const SizedBox(height: 6),
            Text(_subtitle,
                style: GVTypography.bodySecondary(context),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
