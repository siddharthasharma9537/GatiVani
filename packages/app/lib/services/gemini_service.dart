// Stub — placeholder for future Firebase-based AI categorization.
// NOTE: The actual Gemini AI processing happens server-side in gativani-core.
// This client stub is not currently used; category is returned by the backend
// in the /api/documents/process response (see document_service.dart).
class GeminiService {
  Future<String> categorizeText(String text) async {
    // Not implemented — category comes from backend DocumentService response.
    return 'News';
  }
}
