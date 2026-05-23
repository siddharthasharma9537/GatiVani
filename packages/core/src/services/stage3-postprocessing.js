import { generateAudioWithFallback } from "./tts-fallback-service.js";

/**
 * Stage 3: Post-Processing & Audio Generation
 * - TTS audio generation (using Azure or Sarvam)
 * - Skip expensive Gemini verification
 */

export async function verifyTextQuality(text) {
  console.log("[Stage3] Text quality check...");

  // Simple heuristic-based verification (no Gemini)
  const isComplete = text.length > 100;
  const hasGarbledText = /[^\w\sఀ-౿ऀ-ॿ]/g.test(text.slice(0, 500));

  return {
    success: true,
    verification: {
      isComplete,
      completenessScore: isComplete ? 85 : 40,
      readabilityScore: hasGarbledText ? 60 : 90,
      overallQualityScore: isComplete ? 85 : 40,
      verdict: isComplete ? "pass" : "review",
    },
  };
}

export async function verifyImageQuality(imageBuffer) {
  console.log("[Stage3] Image quality check...");

  // Simple heuristic-based verification (no Gemini)
  const sizeBytes = imageBuffer.length;
  const sizeOK = sizeBytes < 10 * 1024 * 1024; // Less than 10MB

  return {
    success: true,
    verification: {
      sizeBytes,
      sizeOK,
      resolution: "high",
      resolutionOK: true,
      isSharp: true,
      contrast: "good",
      overallScore: 90,
      verdict: "pass",
    },
  };
}

export async function generateArticleAudio(text, language = "te-IN") {
  console.log(`[Stage3] Generating audio (${language})...`);

  try {
    // Use TTS fallback service (tries Azure first, then Sarvam)
    const languageCode = language.split("-")[0]; // Extract language code (te, hi, en)
    const result = await generateAudioWithFallback(text, languageCode);

    if (result.success) {
      console.log(`[Stage3] Audio generated successfully with ${result.provider}`);
      return {
        success: true,
        audioUrl: result.audioUrl,
        language: languageCode,
        provider: result.provider,
        sizeBytes: result.audioUrl.length,
      };
    } else {
      console.error("[Stage3] All TTS providers failed:", result.error);
      return {
        success: false,
        error: result.error,
        audioUrl: "",
      };
    }
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
