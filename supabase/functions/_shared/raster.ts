// Render one PDF page to a downscaled JPEG, before it is sent to Gemini.
//
// Why: the structuring pipeline currently hands Gemini the raw single-page PDF
// (up to 15 MB of base64). Gemini bills image input by pixel area — 258 tokens
// per 768×768 tile — and rasterises the PDF itself at a resolution we do not
// control. A newspaper scan at ~3000×4000 is ~24 tiles ≈ 6.2k tokens; the same
// page at 1600 px tall is ~12 tiles ≈ 3.1k. Roughly half the input cost per
// page, on the single most-called model path in the app.
//
// ── Status: OFF by default, and deliberately so ─────────────────────────────
// Enable with RASTER_PAGES=true.
//
// Two things are unverified until this runs on real infrastructure:
//   1. Whether pdfium's WASM build initialises inside the Supabase Edge
//      runtime at all. It is a large binary and the runtime is not plain Deno.
//   2. Whether the saving is real. That is now measurable rather than
//      arguable: `model_calls.input_tokens` records tokens per page, so
//      process one edition with the flag off, one with it on, and compare
//      `edition_cost`. Do that before making it the default — the ledger
//      exists precisely so this decision stops being a guess.
//
// The import is dynamic and every failure path returns null, so with the flag
// off this module costs nothing, and with it on a failure degrades to today's
// behaviour (send the PDF) rather than breaking ingestion. Shrinking an image
// is an optimisation, and an optimisation may never be why a page fails.

/** True when the function is configured to rasterise pages before Gemini. */
export function rasterEnabled(): boolean {
  return (Deno.env.get("RASTER_PAGES") ?? "").toLowerCase() === "true";
}

/** Longest edge of the rendered image, in pixels. */
const TARGET_HEIGHT = 1600;
const JPEG_QUALITY = 82;

export interface Raster {
  bytes: Uint8Array;
  mimeType: string;
  width: number;
  height: number;
}

/**
 * Render page 1 of a single-page PDF to a JPEG no taller than TARGET_HEIGHT.
 *
 * Returns null if rasterising is disabled, unavailable, or fails for any
 * reason. Callers must fall back to sending the original PDF bytes.
 */
export async function rasterFirstPage(pdfBytes: Uint8Array): Promise<Raster | null> {
  if (!rasterEnabled()) return null;
  try {
    const { PDFiumLibrary } = await import("npm:@hyzyla/pdfium@2.1.5");
    const library = await PDFiumLibrary.init();
    try {
      const doc = await library.loadDocument(pdfBytes);
      const page = doc.getPage(0);

      // pdfium renders at 72 dpi by default; scale so the output lands near
      // TARGET_HEIGHT rather than at whatever the page's natural size is.
      const scale = Math.min(4, Math.max(1, TARGET_HEIGHT / page.getSize().height));
      const rendered = await page.render({ scale, render: "bitmap" });

      // pdfium hands back BGRA; jpegts reads the buffer as RGBA. Swap the two
      // outer channels in place, or every rendered page comes out with red and
      // blue exchanged.
      const data = rendered.data;
      for (let i = 0; i < data.length; i += 4) {
        const b = data[i];
        data[i] = data[i + 2];
        data[i + 2] = b;
      }

      const { encode, Image } = await import("https://deno.land/x/jpegts@1.1/mod.ts");
      const image = new Image();
      image.width = rendered.width;
      image.height = rendered.height;
      image.data = data;
      const jpeg = encode(image, JPEG_QUALITY);

      doc.destroy();
      return {
        bytes: jpeg.data,
        mimeType: "image/jpeg",
        width: rendered.width,
        height: rendered.height,
      };
    } finally {
      library.destroy();
    }
  } catch (e) {
    console.warn("[raster] falling back to PDF:", (e as Error).message);
    return null;
  }
}
