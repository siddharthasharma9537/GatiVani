"""Write cases_te.json: the inputs for the Telugu normaliser reference comparison (ref_numbers.py on the model's Python,
telugu_normalizer_test.dart on the Dart port). Run: python3 make_cases.py"""
import json
import os
import random

random.seed(7)
g = {}
g["integers"] = [str(n) for n in list(range(0, 1200)) + [1500, 1999, 2000, 2026, 9999, 10000, 12345, 99999, 100000, 100001, 130650, 999999,
                 1000000, 1234567, 10000000, 12345678, 99999999, 100000000, 999999999, 1000000000, 2147483648]] + [
    str(random.randint(1, 10**9 - 1)) for _ in range(300)]
g["grouped"] = ["1,30,650", "1,234", "12,345", "1,23,456", "12,34,567", "1,23,45,678", "1,00,000", "10,00,000", "1,000", "999,999",
                "1,234,567", "12,34", "1,2", "1,23", "12,3", "123,45", "1,2345", "1,234,56"]
g["leading_zero_and_long"] = ["007", "00", "0", "000123", "0123", "1234567890", "12345678901", "9876543210", "9876543210123"]
g["phone_like"] = ["9876543210", "98765 43210", "040-23456789", "+91 98765 43210", "1800-123-4567"]
g["years_and_ranges"] = ["2026", "1999", "5-6", "5–6", "10-12", "2024-25", "2024-2025", "1947", "12/13", "3/4"]
g["negatives_signs"] = ["-5", "+5", "-140", "−12", "5-", "-"]
g["lists"] = ["1,2,3", "1, 2, 3", "1 2 3", "1,2,3,4,5", "10,20,30", "5, 6", "1;2", "1:2"]
g["glued_suffix"] = ["15శాతం", "140ఏళ్ల", "15శాతమున్న", "5వ", "12వ తేదీ", "3లో", "21న", "100మంది", "2026లో", "7గురు", "3,4లో", "1,30,650లో"]
g["in_prose"] = ["ఇది 140 ఏళ్ల చరిత్ర", "సుమారు 15 శాతం మంది", "మొత్తం 1,30,650 మంది హాజరయ్యారు", "వారు 3, 4 రోజులు ఉన్నారు",
                 "రాష్ట్రంలో 12 జిల్లాలు, 5 నగరాలు", "ఏప్రిల్ 12న", "12 మంది, 13 మంది, 14 మంది"]
g["clean"] = ["ఎందరో  మహానుభావులు\n\tఅందరికీ", "హలో [noise] ప్రపంచం", "స్మార్ట్‌ఫోన్ (smart phone) వాడకం", "కా​ల‍ం", "కిి",
              "వాడై", "(music) పాట", "[laugh]"]
# Readings beyond the model's own normaliser (it leaves these unread): the test only checks that no ASCII digit is left.
g["ext_decimals"] = ["3.5", "0.25", "10.75", "1.2.3", "12.", "3.14159", "100.0"]
g["ext_percent"] = ["15%", "2.5%", "100%", "15 %", "1,234%"]
g["ext_rupees"] = ["₹500", "₹1,30,650", "రూ. 10 వేలు", "రూ.40 వేల కోట్లు", "రూ 15 కోట్లు", "₹2.5 లక్షలు", "రూ. 1,000"]
g["ext_dates_times"] = ["12-11-2026", "12/11/2026", "12.11.2026", "1/3/2025", "31.12.1999", "5-13-2026", "10:30", "5:00", "23:59", "10:61"]
g["ext_units"] = ["5km", "10 kg", "3.5 m", "2GB", "BJP", "ISRO", "5వ", "1వ", "20వ"]
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases_te.json")
json.dump(g, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print({k: len(v) for k, v in g.items()}, sum(len(v) for v in g.values()))
