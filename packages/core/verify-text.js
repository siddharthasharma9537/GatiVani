import fs from 'fs';
import path from 'path';
import { extractPdfTextByPageCap } from './src/lib/pdfExtract.js';

async function verifyPdfText(fileName) {
  try {
    const filePath = path.resolve(fileName);
    if (!fs.existsSync(filePath)) {
      console.error(`❌ Error: File not found at ${filePath}`);
      return;
    }

    console.log(`\n================================================================`);
    console.log(`🔍 Inspecting PDF Layout Matrix for: ${fileName}`);
    console.log(`================================================================\n`);

    const fileBuffer = fs.readFileSync(filePath);
    
    // Extract up to 500 pages for maximum premium test coverage
    const extracted = await extractPdfTextByPageCap(fileBuffer, 500);

    console.log(`📊 PDF Metadata Properties:`);
    console.log(`   - Total Document Pages Found: ${extracted.totalPages}`);
    console.log(`   - Total Document Pages Processed: ${extracted.processedPages}\n`);
    console.log(`========================= EXTRACTED TEXT =========================\n`);

    if (!extracted.text || extracted.text.trim().length === 0) {
      console.log("⚠️  [EMPTY TEXT MATRIX]");
      console.log("   This document does not contain a digital Unicode layer.");
      console.log("   It will automatically trigger the GatiVani Multimodal Vision Fallback in production.");
    } else {
      // Print the clean, formatted text string array directly to the terminal screen
      console.log(extracted.text);
    }

    console.log(`\n========================= END OF OUTPUT =========================\n`);

  } catch (error) {
    console.error('❌ Ingestion Inspection Transaction Failed:', error);
  }
}

// Run the verification layer against your local test file
verifyPdfText('telugu_test.pdf');
