import { env } from "../config/env.js";
import { generateTeluguAudioDataUrl } from "./azure-tts-service.js";

const { GoogleGenerativeAI } = await import("@google/generative-ai");
const genAI = new GoogleGenerativeAI(env.geminiApiKey);

/**
 * Stage 3: Post-Processing & Verification
 * - Text quality verification
 * - Image quality verification
 * - TTS audio generation
 * - Final quality scoring
 */

export async function verifyTextQuality(text) {
  console.log("[Stage3] Verifying text quality...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });

  const verificationPrompt = `Analyze this Telugu/Hindi newspaper text for quality issues:
1. **Completeness**: Is it a complete article (has intro, body, possibly conclusion)?
2. **Readability**: Easy to understand? Any garbled sections?
3. **OCR Artifacts**: Remaining OCR errors or weird characters?
4. **Structure**: Well-formatted paragraphs? Missing line breaks?
5. **Content Integrity**: Does the text make sense? No obvious missing words?

Respond in JSON:
{
  "isComplete": boolean,
  "completenessScore": 0-100,
  "readabilityScore": 0-100,
  "hasOCRArtifacts": boolean,
  "structureScore": 0-100,
  "hasContentGaps": boolean,
  "issues": ["string"],
  "overallQualityScore": 0-100,
  "verdict": "pass|review|fail"
}`;

  try {
    const response = await model.generateContent(verificationPrompt + "\n\nTEXT:\n" + text.slice(0, 3000));
    let analysisText = response.response.text();
    const jsonMatch = analysisText.match(/\{[\s\S]*\}/);
    const verification = JSON.parse(jsonMatch[0]);

    console.log("[Stage3] Text verification:", verification);

    return {
      success: true,
      verification,
    };
  } catch (error) {
    console.error("[Stage3] Text verification failed:", error.message);
    return {
      success: false,
      error: error.message,
      verification: {
        overallQualityScore: 0,
        verdict: "fail",
        issues: [error.message],
      },
    };
  }
}

export async function verifyImageQuality(imageBuffer) {
  console.log("[Stage3] Verifying image quality...");

  const model = genAI.getGenerativeModel({ model: env.geminiModel });
  const base64Data = imageBuffer.toString("base64");

  const verificationPrompt = `Verify this article image for quality:
1. **File Size**: Is it acceptable for mobile (<100KB ideal)?
2. **Resolution**: Wide enough for mobile display (>300px)?
3. **Blur Check**: Is image sharp and readable?
4. **Contrast**: Good contrast for reading?
5. **Color Profile**: Any unusual color issues?

Respond in JSON:
{
  "sizeBytes": number,
  "sizeOK": boolean,
  "resolution": "low|medium|high",
  "resolutionOK": boolean,
  "isSharp": boolean,
  "contrast": "poor|fair|good",
  "colorProfile": "normal|unusual",
  "issues": ["string"],
  "overallScore": 0-100,
  "verdict": "pass|review|fail"
}`;

  try {
    const response = await model.generateContent([
      {
        inlineData: {
          data: base64Data,
          mimeType: "image/jpeg",
        },
      },
      { text: verificationPrompt },
    ]);

    let analysisText = response.response.text();
    const jsonMatch = analysisText.match(/\{[\s\S]*\}/);
    const verification = JSON.parse(jsonMatch[0]);
    verification.sizeBytes = imageBuffer.length;

    console.log("[Stage3] Image verification:", verification);

    return {
      success: true,
      verification,
    };
  } catch (error) {
    console.error("[Stage3] Image verification failed:", error.message);
    return {
      success: false,
      error: error.message,
      verification: {
        sizeBytes: imageBuffer.length,
        overallScore: 0,
        verdict: "fail",
        issues: [error.message],
      },
    };
  }
}

export async function generateArticleAudio(text, language = "te-IN") {
  console.log(`[Stage3] Generating audio (${language})...`);

  try {
    // Use Azure TTS to generate natural audio
    const audioUrl = await generateTeluguAudioDataUrl(text, language);

    console.log("[Stage3] Audio generated successfully");

    return {
      success: true,
      audioUrl,
      language,
      sizeBytes: audioUrl.length, // Approximate size of data URL
    };
  } catch (error) {
    console.error("[Stage3] Audio generation failed:", error.message);
    return {
      success: false,
      error: error.message,
      audioUrl: "",
    };
  }
}

export async function calculateFinalQualityScore(textVerification, imageVerification, audioSuccess) {
  console.log("[Stage3] Calculating final quality score...");

  const textScore = textVerification?.overallQualityScore || 0;
  const imageScore = imageVerification?.overallScore || 0;
  const audioScore = audioSuccess ? 100 : 0;

  // Weighted average: text 50%, image 30%, audio 20%
  const finalScore = textScore * 0.5 + imageScore * 0.3 + audioScore * 0.2;

  const verdict =
    finalScore >= 80 ? "pass" : finalScore >= 60 ? "review" : "fail";

  return {
    textScore,
    imageScore,
    audioScore,
    finalScore: Math.round(finalScore),
    verdict,
    readyForUser: finalScore >= 60,
  };
}

export async function stage3ProcessComplete(stage2Result) {
  console.log("[Stage3] Starting post-processing...");

  try {
    const { stage2 } = stage2Result;
    const imageBuffer = stage2?.image?.buffer;
    const enhancedText = stage2?.text?.enhanced || stage2?.text?.cleaned || "";

    // Verify text quality
    const textVerification = await verifyTextQuality(enhancedText);

    // Verify image quality
    const imageVerification = imageBuffer
      ? await verifyImageQuality(imageBuffer)
      : { success: false, verification: { verdict: "fail" } };

    // Generate audio
    const audioGeneration = enhancedText.length > 0
      ? await generateArticleAudio(enhancedText, "te-IN")
      : { success: false, error: "No text for audio generation" };

    // Calculate final score
    const qualityScore = await calculateFinalQualityScore(
      textVerification.verification,
      imageVerification.verification,
      audioGeneration.success
    );

    console.log("[Stage3] Final quality score:", qualityScore);

    return {
      success:
        textVerification.success &&
        imageVerification.success &&
        audioGeneration.success,
      stage3: {
        textVerification: textVerification.verification,
        imageVerification: imageVerification.verification,
        audio: {
          success: audioGeneration.success,
          audioUrl: audioGeneration.audioUrl,
          language: audioGeneration.language,
          error: audioGeneration.error,
        },
        qualityScore,
      },
      ready: qualityScore.readyForUser,
    };
  } catch (error) {
    console.error("[Stage3] Post-processing failed:", error.message);
    return {
      success: false,
      error: error.message,
      stage3: {},
      ready: false,
    };
  }
}

export async function finalizeArticleOutput(stage1Result, stage2Result, stage3Result, metadata = {}) {
  console.log("[Stage3] Finalizing article output...");

  return {
    ok: true,
    stage1: {
      analysis: stage1Result?.analysis || {},
      metadata: stage1Result?.metadata || {},
    },
    stage2: {
      image: stage2Result?.stage2?.image,
      text: stage2Result?.stage2?.text,
      quality: stage2Result?.stage2?.quality,
    },
    stage3: {
      textVerification: stage3Result?.stage3?.textVerification,
      imageVerification: stage3Result?.stage3?.imageVerification,
      audio: stage3Result?.stage3?.audio,
      qualityScore: stage3Result?.stage3?.qualityScore,
    },
    final: {
      readyForUser: stage3Result?.ready || false,
      overallQuality: stage3Result?.stage3?.qualityScore?.finalScore || 0,
      audioUrl: stage3Result?.stage3?.audio?.audioUrl || "",
      articleText: stage2Result?.stage2?.text?.enhanced || "",
      metadata,
    },
  };
}
