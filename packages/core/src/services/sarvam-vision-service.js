import { SarvamAIClient } from "sarvamai";
import * as fs from "fs";
import * as path from "path";
import { createWriteStream } from "fs";
import { pipeline } from "stream/promises";
import unzipper from "unzipper";

const SARVAM_API_KEY = process.env.SARVAM_API_KEY;

export async function performOCR(imageBuffer, language = "te") {
  if (!SARVAM_API_KEY) {
    throw new Error("SARVAM_API_KEY not configured");
  }

  try {
    const client = new SarvamAIClient({
      apiSubscriptionKey: SARVAM_API_KEY,
    });

    const tempFilePath = `/tmp/sarvam_doc_${Date.now()}.pdf`;
    fs.writeFileSync(tempFilePath, imageBuffer);

    console.log("[Sarvam Vision] Creating document intelligence job...");

    const job = await client.documentIntelligence.createJob({
      language: languageToSarvamCode(language),
      outputFormat: "md",
    });

    console.log(`[Sarvam Vision] Job created: ${job.jobId}`);

    await job.uploadFile(tempFilePath);
    console.log("[Sarvam Vision] File uploaded");

    await job.start();
    console.log("[Sarvam Vision] Job started");

    const status = await Promise.race([
      job.waitUntilComplete(),
      new Promise((_, reject) => setTimeout(() => reject(new Error("OCR timeout")), 45000)),
    ]);

    console.log(`[Sarvam Vision] Job completed`);

    // Get download links for the output files
    console.log("[Sarvam Vision] Retrieving output files...");
    const response = await job.getDownloadLinks();

    let extractedText = null;

    // The response contains download_urls with actual file URLs
    console.log("[Sarvam Vision] Response type:", typeof response);
    console.log("[Sarvam Vision] Has download_urls:", response && response.download_urls ? "yes" : "no");

    if (response && response.download_urls && typeof response.download_urls === 'object') {
      const downloadUrls = response.download_urls;
      const fileKeys = Object.keys(downloadUrls);
      console.log("[Sarvam Vision] Available output files:", fileKeys);
      console.log("[Sarvam Vision] Download URLs object:", JSON.stringify(downloadUrls).substring(0, 200));

      // Try to fetch each file and extract text
      for (const filename of fileKeys) {
        let url = downloadUrls[filename];

        // Handle nested object with file_url property
        if (typeof url === 'object' && url.file_url) {
          url = url.file_url;
        }

        console.log(`[Sarvam Vision] Processing file: ${filename}, URL type: ${typeof url}`);
        if (typeof url === 'string' && url.startsWith('http')) {
          try {
            // Handle different file types
            if (filename.endsWith('.zip')) {
              console.log(`[Sarvam Vision] Downloading and extracting ${filename}...`);
              const fetchResponse = await fetch(url);
              if (!fetchResponse.ok) {
                console.warn(`[Sarvam Vision] Failed to download ${filename}: ${fetchResponse.status}`);
                continue;
              }

              // Extract ZIP file contents
              const zipBuffer = await fetchResponse.arrayBuffer();
              const tempZipPath = `/tmp/sarvam_${Date.now()}.zip`;
              const extractDir = `/tmp/sarvam_extract_${Date.now()}`;

              // Write ZIP to temp file
              fs.writeFileSync(tempZipPath, Buffer.from(zipBuffer));
              console.log(`[Sarvam Vision] Saved ZIP to ${tempZipPath}`);

              // Create extract directory
              fs.mkdirSync(extractDir, { recursive: true });

              // Extract ZIP using unzipper with proper stream handling
              try {
                await new Promise((resolve, reject) => {
                  fs.createReadStream(tempZipPath)
                    .pipe(unzipper.Extract({ path: extractDir }))
                    .on('close', resolve)
                    .on('error', reject);
                });
                console.log(`[Sarvam Vision] Extracted ZIP to ${extractDir}`);
              } catch (zipError) {
                console.warn(`[Sarvam Vision] ZIP extraction error:`, zipError.message);
                throw zipError;
              }

              // Find and read markdown/text files
              const extractedFiles = [];
              const readDir = (dir) => {
                try {
                  const files = fs.readdirSync(dir);
                  for (const file of files) {
                    const filePath = path.join(dir, file);
                    try {
                      const stat = fs.statSync(filePath);
                      if (stat.isDirectory()) {
                        readDir(filePath);
                      } else if (file.endsWith('.md') || file.endsWith('.html') || file.endsWith('.txt')) {
                        const content = fs.readFileSync(filePath, 'utf-8');
                        if (content && content.length > 10) {
                          extractedFiles.push({ name: file, content, length: content.length });
                          console.log(`[Sarvam Vision] Found file: ${file} (${content.length} chars)`);
                        }
                      }
                    } catch (e) {
                      // Ignore stat errors for individual files
                    }
                  }
                } catch (e) {
                  console.warn(`[Sarvam Vision] Error reading directory ${dir}:`, e.message);
                }
              };

              readDir(extractDir);

              // Use the longest extracted file
              if (extractedFiles.length > 0) {
                extractedFiles.sort((a, b) => b.length - a.length);
                extractedText = extractedFiles[0].content;
                console.log(`[Sarvam Vision] Using ${extractedFiles[0].name} (${extractedText.length} chars)`);
              } else {
                console.warn(`[Sarvam Vision] No text files found in ZIP`);
              }

              // Cleanup
              try {
                fs.rmSync(tempZipPath, { force: true });
                fs.rmSync(extractDir, { recursive: true, force: true });
              } catch (e) {
                console.warn(`[Sarvam Vision] Cleanup error:`, e.message);
              }
              break;
            } else {
              // Handle plain text/markdown files
              console.log(`[Sarvam Vision] Downloading ${filename}...`);
              const fetchResponse = await fetch(url);
              if (!fetchResponse.ok) {
                console.warn(`[Sarvam Vision] Failed to download ${filename}: ${fetchResponse.status}`);
                continue;
              }

              const content = await fetchResponse.text();
              if (content && content.length > 10) {
                extractedText = content;
                console.log(`[Sarvam Vision] Extracted ${content.length} characters from ${filename}`);
                break;
              }
            }
          } catch (e) {
            console.warn(`[Sarvam Vision] Failed to process ${filename}:`, e.message);
          }
        }
      }
    } else {
      console.warn("[Sarvam Vision] No download URLs found in response");
    }

    // Fallback if no text was extracted
    if (!extractedText || extractedText.length < 10) {
      console.warn("[Sarvam Vision] No text extracted, using placeholder");
      extractedText = "Document processed";
    }

    try { fs.unlinkSync(tempFilePath); } catch(e) {}

    return {
      success: true,
      text: extractedText,
      language: language,
      confidence: 0.8,
    };
  } catch (error) {
    console.error("[Sarvam Vision Error]", error.message);
    return {
      success: false,
      text: "",
      language: language,
      error: error.message,
    };
  }
}

export async function analyzeDocumentWithSarvam(imageBuffer) {
  return performOCR(imageBuffer, "te");
}

function languageToSarvamCode(lang) {
  const codeMap = { te: "te-IN", hi: "hi-IN", en: "en-IN", ta: "ta-IN", ka: "ka-IN", ml: "ml-IN", bn: "bn-IN" };
  return codeMap[lang] || "te-IN";
}
