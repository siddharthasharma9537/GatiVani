// Backward-compat re-export. Canonical file: document_service.dart
// All new code should import document_service.dart directly.
export 'document_service.dart';

import 'document_service.dart';
// Alias so callers using UploadedContentService still compile.
typedef UploadedContentService = DocumentService;
