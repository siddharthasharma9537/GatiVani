"""Audio duration of the model's own Python synthesis for sentences_te.json (both voices), to compare with the Dart pipeline.
Durations do not depend on the random noise, so they must match the Dart pipeline's to the sample.

usage: python -I ref_durations.py <out.json> <folder holding indic_tiny_tts/ and onnx/>
Run with the network off. The Dart side: tool/tts_probe (it prints the same list under "sentences_te").
"""
import json
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, sys.argv[2])
from indic_tiny_tts.export.onnx_infer import TinyTTSOnnx

sentences = json.load(open(os.path.join(here, "sentences_te.json"), encoding="utf-8"))
tts = TinyTTSOnnx.from_pretrained(sys.argv[2], threads=2)
out = {}
for voice in ("female", "male"):
    out[voice] = [len(tts.synthesize(s, voice=voice, seed=1)) / tts.sample_rate for s in sentences]
json.dump(out, open(sys.argv[1], "w"))
print(out)
