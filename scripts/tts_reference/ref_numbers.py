"""Dump the model's own Telugu normaliser output for every case in cases_te.json, to compare with the Dart port.

usage: python -I ref_numbers.py <out.json> <folder holding indic_tiny_tts/> [cases_te.json]
Output: {group: {case: model_text}}. Run with the network off (sandbox-exec ... (deny network*)).
"""
import json
import os
import sys

sys.path.insert(0, sys.argv[2])  # the downloaded model code
from indic_tiny_tts.textnorm.core import normalize_for_chars

cases_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases_te.json")
groups = json.load(open(cases_path, encoding="utf-8"))
out = {g: {c: normalize_for_chars(c, "te").text for c in cs} for g, cs in groups.items()}
json.dump(out, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
print(sum(len(v) for v in out.values()), "entries in", len(out), "groups")
