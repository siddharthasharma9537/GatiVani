import { env } from "../config/env.js";

/**
 * Direct PostgreSQL REST API calls to Supabase
 * Bypasses Realtime to avoid WebSocket issues on Node.js < 22
 */

/**
 * Save extracted text to Supabase database via REST API
 * Creates entries in 'extracted_texts' table with OCR metadata
 */
export async function saveExtractedText({
  filename,
  text,
  confidence,
  fileSize,
  mimeType,
  language = "te",
  source = "ocr",
}) {
  try {
    if (!env.supabaseUrl || !env.supabaseAnonKey) {
      throw new Error(
        "Supabase credentials missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env"
      );
    }

    const restUrl = env.supabaseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${restUrl}/rest/v1/extracted_texts`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: env.supabaseAnonKey,
          Authorization: `Bearer ${env.supabaseAnonKey}`,
          Prefer: "return=representation",
        },
        body: JSON.stringify({
          filename,
          text,
          confidence,
          file_size: fileSize,
          mime_type: mimeType,
          language,
          source,
          extracted_at: new Date().toISOString(),
        }),
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error("[Supabase] HTTP error:", response.status, error);
      return {
        success: false,
        error: `HTTP ${response.status}: ${error}`,
      };
    }

    const data = await response.json();
    const record = Array.isArray(data) ? data[0] : data;

    console.log(
      `[Supabase] Extracted text saved (${text.length} chars) → ID: ${record?.id}`
    );

    return {
      success: true,
      id: record?.id,
      filename,
      textLength: text.length,
    };
  } catch (error) {
    console.error("[Supabase] Failed to save extracted text:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Retrieve extracted text by ID
 */
export async function getExtractedText(id) {
  try {
    if (!env.supabaseUrl || !env.supabaseAnonKey) {
      throw new Error(
        "Supabase credentials missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env"
      );
    }

    const restUrl = env.supabaseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${restUrl}/rest/v1/extracted_texts?id=eq.${id}`,
      {
        headers: {
          apikey: env.supabaseAnonKey,
          Authorization: `Bearer ${env.supabaseAnonKey}`,
        },
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error("[Supabase] HTTP error:", response.status, error);
      return {
        success: false,
        error: `HTTP ${response.status}`,
      };
    }

    const data = await response.json();
    const record = Array.isArray(data) ? data[0] : null;

    if (!record) {
      return {
        success: false,
        error: "Not found",
      };
    }

    return {
      success: true,
      data: record,
    };
  } catch (error) {
    console.error("[Supabase] Failed to fetch extracted text:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * List recently extracted texts (with pagination)
 */
export async function listExtractedTexts(limit = 10, offset = 0) {
  try {
    if (!env.supabaseUrl || !env.supabaseAnonKey) {
      throw new Error(
        "Supabase credentials missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env"
      );
    }

    const restUrl = env.supabaseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${restUrl}/rest/v1/extracted_texts?select=id,filename,confidence,extracted_at&order=extracted_at.desc&limit=${limit}&offset=${offset}`,
      {
        headers: {
          apikey: env.supabaseAnonKey,
          Authorization: `Bearer ${env.supabaseAnonKey}`,
          Prefer: "count=exact",
        },
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error("[Supabase] HTTP error:", response.status, error);
      return {
        success: false,
        error: `HTTP ${response.status}`,
      };
    }

    const data = await response.json();
    const count = response.headers.get("content-range")
      ? parseInt(response.headers.get("content-range").split("/")[1])
      : data.length;

    return {
      success: true,
      data,
      total: count,
    };
  } catch (error) {
    console.error("[Supabase] Failed to list extracted texts:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Delete extracted text by ID
 */
export async function deleteExtractedText(id) {
  try {
    if (!env.supabaseUrl || !env.supabaseAnonKey) {
      throw new Error(
        "Supabase credentials missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env"
      );
    }

    const restUrl = env.supabaseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${restUrl}/rest/v1/extracted_texts?id=eq.${id}`,
      {
        method: "DELETE",
        headers: {
          apikey: env.supabaseAnonKey,
          Authorization: `Bearer ${env.supabaseAnonKey}`,
        },
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.error("[Supabase] HTTP error:", response.status, error);
      return {
        success: false,
        error: `HTTP ${response.status}`,
      };
    }

    console.log(`[Supabase] Extracted text deleted → ID: ${id}`);

    return {
      success: true,
    };
  } catch (error) {
    console.error("[Supabase] Failed to delete extracted text:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}

/**
 * Check if Supabase table exists and has correct schema
 */
export async function verifyExtractedTextsTable() {
  try {
    if (!env.supabaseUrl || !env.supabaseAnonKey) {
      throw new Error(
        "Supabase credentials missing. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env"
      );
    }

    const restUrl = env.supabaseUrl.replace(/\/$/, "");
    const response = await fetch(
      `${restUrl}/rest/v1/extracted_texts?select=id&limit=1`,
      {
        headers: {
          apikey: env.supabaseAnonKey,
          Authorization: `Bearer ${env.supabaseAnonKey}`,
        },
      }
    );

    if (!response.ok) {
      const error = await response.text();
      console.warn("[Supabase] Table verification failed:", error);
      return {
        success: false,
        error,
        needsSetup: response.status === 404,
      };
    }

    console.log("[Supabase] Table 'extracted_texts' verified ✓");
    return {
      success: true,
    };
  } catch (error) {
    console.error("[Supabase] Verification error:", error.message);
    return {
      success: false,
      error: error.message,
    };
  }
}
