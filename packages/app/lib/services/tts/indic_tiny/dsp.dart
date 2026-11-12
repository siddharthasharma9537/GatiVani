import 'dart:math' as math;
import 'dart:typed_data';

/// The signal-processing steps of the Indic Tiny TTS ONNX pipeline that are not inside the ONNX graphs. Ported from
/// `indic_tiny_tts/export/onnx_infer.py` (sulabhkatiyar/indic-tiny-tts-telugu, MIT); the maths is the same.

/// float32 `torch.linspace` (two-sided formula, so values match torch).
Float32List torchLinspace(double start, double end, int steps) {
  if (steps == 1) return Float32List.fromList([start]);
  final step = (end - start) / (steps - 1);
  final out = Float32List(steps);
  final half = steps ~/ 2;
  for (var i = 0; i < steps; i++) {
    out[i] = i < half ? start + step * i : end - step * (steps - 1 - i);
  }
  return out;
}

class Durations {
  Durations(this.wCeil, this.yLen, this.yPad);
  final Float32List wCeil; // frames per token
  final int yLen; // mel frames
  final int yPad; // mel frames, padded to a multiple of frameMultiple
}

/// `w_ceil = ceil(exp(logw)) * lengthScale`, `yLen = max(sum, 1)` truncated, `yPad` rounded up to [frameMultiple].
Durations durations(Float32List logw, double lengthScale, int frameMultiple) {
  final w = Float32List(logw.length);
  var sum = 0.0;
  for (var i = 0; i < logw.length; i++) {
    w[i] = (math.exp(logw[i]).ceilToDouble()) * lengthScale;
    sum += w[i];
  }
  final yLen = math.max(sum, 1.0).toInt();
  final yPad = ((yLen + frameMultiple - 1) ~/ frameMultiple) * frameMultiple;
  return Durations(w, yLen, yPad);
}

class Regulated {
  Regulated(this.muY, this.yMask);
  final Float32List muY; // [C, yPad] row-major
  final Float32List yMask; // [yPad]
}

/// Expand token features [muX] ([C, tx] row-major) to frames: frame j copies token i iff cum[i-1] <= j < cum[i].
Regulated lengthRegulate(Float32List muX, int channels, int tx, Float32List wCeil, int yLen, int yPad) {
  final cum = Float64List(tx);
  var run = 0.0;
  for (var i = 0; i < tx; i++) {
    run += wCeil[i];
    cum[i] = run;
  }
  final muY = Float32List(channels * yPad);
  final mask = Float32List(yPad);
  var tok = 0;
  for (var j = 0; j < yPad; j++) {
    while (tok < tx && cum[tok] <= j) {
      tok++; // first i with cum[i] > j
    }
    if (tok < tx && j < yLen) {
      mask[j] = 1.0;
      for (var c = 0; c < channels; c++) {
        muY[c * yPad + j] = muX[c * tx + tok];
      }
    }
  }
  return Regulated(muY, mask);
}

/// In-place iterative radix-2 FFT over [re]/[im] (length a power of two). [inverse] gives the unscaled inverse transform.
void _fft(Float64List re, Float64List im, bool inverse) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = 2 * math.pi / len * (inverse ? 1 : -1);
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = i + k + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

/// `numpy.fft.irfft` of one frame: [bins] = nFft/2+1 complex values -> nFft real values. numpy ignores the imaginary parts of
/// the DC and Nyquist bins, so this does too.
Float64List irfftFrame(Float64List re, Float64List im, int nFft) {
  final fr = Float64List(nFft), fi = Float64List(nFft);
  final bins = nFft ~/ 2 + 1;
  for (var k = 0; k < bins; k++) {
    fr[k] = re[k];
    fi[k] = (k == 0 || k == nFft ~/ 2) ? 0.0 : im[k];
  }
  for (var k = 1; k < nFft ~/ 2; k++) {
    fr[nFft - k] = re[k];
    fi[nFft - k] = -im[k];
  }
  _fft(fr, fi, true);
  for (var i = 0; i < nFft; i++) {
    fr[i] /= nFft;
  }
  return fr;
}

/// Spectrum [bins, t] (row-major `real`/`imag`) -> waveform: periodic Hann window, overlap-add, window-envelope normalisation,
/// like `torch.istft(center=True)` (Vocos 'center' padding) or Vocos' 'same' padding.
Float32List istft(Float32List real, Float32List imag, int bins, int t, int nFft, int hop, {String padding = 'center'}) {
  final window = Float64List(nFft);
  for (var i = 0; i < nFft; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / nFft);
  }
  final total = nFft + hop * (t - 1);
  final y = Float64List(total), env = Float64List(total);
  final re = Float64List(bins), im = Float64List(bins);
  for (var f = 0; f < t; f++) {
    for (var k = 0; k < bins; k++) {
      re[k] = real[k * t + f];
      im[k] = imag[k * t + f];
    }
    final frame = irfftFrame(re, im, nFft);
    final off = f * hop;
    for (var i = 0; i < nFft; i++) {
      y[off + i] += frame[i] * window[i];
      env[off + i] += window[i] * window[i];
    }
  }
  if (padding != 'center' && padding != 'same') throw ArgumentError(padding);
  final pad = padding == 'center' ? nFft ~/ 2 : (nFft - hop) ~/ 2;
  final n = total - 2 * pad;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final e = env[pad + i];
    if (e < 1e-11) throw StateError('istft: window overlap-add is ~0 (NOLA violated)');
    out[i] = y[pad + i] / e;
  }
  return out;
}
