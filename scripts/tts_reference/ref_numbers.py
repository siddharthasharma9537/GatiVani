"""Dump the model's own Telugu normaliser output for numbers and a few texts, to compare with the Dart port."""
import json
import sys

sys.path.insert(0, sys.argv[2])  # folder holding indic_tiny_tts/ (the downloaded model code)
from indic_tiny_tts.textnorm.core import normalize_for_chars

nums = list(range(0, 1200)) + [1500, 1999, 2000, 2026, 9999, 10000, 12345, 99999, 100000, 100001, 130650, 1000000, 1234567, 10000000, 12345678, 99999999, 100000000, 999999999]
cases = [str(n) for n in nums] + ["1,30,650", "1,234", "1,23,45,678", "007", "1234567890", "1,2", "12,34",
    "140ఏళ్ల", "15శాతం", "ఇది 140 ఏళ్ల చరిత్ర", "స్మార్ట్‌ఫోన్ (smart phone) వాడకం", "హలో [noise] ప్రపంచం", "ఎందరో  మహానుభావులు\n\tఅందరికీ",
    "వాడు" + "ై"]
out = {c: normalize_for_chars(c, "te").text for c in cases}
json.dump(out, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
print(len(out), "entries")
