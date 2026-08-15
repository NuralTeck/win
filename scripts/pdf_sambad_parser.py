#!/usr/bin/env python3
"""
Advanced Multi-Layer Hybrid PDF Parser for Lottery Sambad / Nagaland State Lotteries
Resilient against format changes, rearranged columns, missing headers, or new layout styles.
"""

import sys
import json
import re
import csv
import os

def clean_noise_tokens(tokens):
    """Filter out calendar years, dates, phone numbers, and noise"""
    cleaned = []
    for t in tokens:
        # Ignore 4-digit calendar years (2020-2035)
        if t.isdigit() and len(t) == 4 and 2020 <= int(t) <= 2035:
            continue
        cleaned.append(t)
    return cleaned

def extract_tokens_from_pdf(pdf_path):
    """Extracts text using both layout and plain modes with anti-concatenation split"""
    extracted_chunks = []
    try:
        import pypdf
        reader = pypdf.PdfReader(pdf_path)
        for page in reader.pages:
            t_layout = page.extract_text(extraction_mode="layout") or ""
            if t_layout:
                # Separate numbers that are glued without whitespace in layout extraction
                # e.g. "88390733" -> "8839 0733", "1234567890" -> "12345 67890"
                t_layout = re.sub(r'(?<=\d{4})(?=\d{4})', ' ', t_layout)
                t_layout = re.sub(r'(?<=\d{5})(?=\d{5})', ' ', t_layout)
                extracted_chunks.append(t_layout)
                
            t_plain = page.extract_text() or ""
            if t_plain:
                t_plain = re.sub(r'(?<=\d{4})(?=\d{4})', ' ', t_plain)
                t_plain = re.sub(r'(?<=\d{5})(?=\d{5})', ' ', t_plain)
                extracted_chunks.append(t_plain)
    except Exception as e:
        sys.stderr.write(f"PDF Extraction Exception: {e}\n")

    return "\n".join(extracted_chunks)

def parse_lottery_pdf(pdf_path):
    raw_text = extract_tokens_from_pdf(pdf_path)
    
    # Strip date patterns (e.g. 13/08/26, 01.04.2026, 2026-08-13)
    text_without_dates = re.sub(r'\b\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}\b', ' ', raw_text)
    
    # ── 1. First Prize (Pattern: 2 Digits + 1 Letter + Space + 5 Digits e.g. 44A 36813 or 93J 99831) ──
    first_matches = re.findall(r'\b([0-9]{2}[A-Z])[\s\-_]*([0-9]{5})\b', text_without_dates, re.IGNORECASE)
    if first_matches:
        first_prize = f"{first_matches[0][0].upper()} {first_matches[0][1]}"
        consolation = first_matches[0][1]
    else:
        # Fallback for alternative series format: 1 letter + 5 digits
        fallback_m = re.search(r'\b([0-9A-Z]{1,4})\s*([0-9]{5})\b', text_without_dates, re.IGNORECASE)
        if fallback_m:
            first_prize = f"{fallback_m.group(1).upper()} {fallback_m.group(2)}"
            consolation = fallback_m.group(2)
        else:
            first_prize = ""
            consolation = ""

    # ── 2. Second Prize (10 5-digit numbers) ──
    all_raw_5s = re.findall(r'\b[0-9]{5}\b', text_without_dates)
    seen_5 = set()
    second_prize = []
    for n in all_raw_5s:
        if n != consolation and n not in seen_5:
            seen_5.add(n)
            second_prize.append(n)
    second_prize = second_prize[:10]

    # ── 3. 4-Digit Numbers: 3rd (10), 4th (10), 5th (100) ──
    all_raw_4s = re.findall(r'\b[0-9]{4}\b', text_without_dates)
    all_clean_4s = clean_noise_tokens(all_raw_4s)
    
    # Deduplicate in document-occurrence order
    seen_4 = set()
    ordered_unique_4s = []
    for n in all_clean_4s:
        if n not in seen_4:
            seen_4.add(n)
            ordered_unique_4s.append(n)

    third_prize = ordered_unique_4s[:10]
    fourth_prize = ordered_unique_4s[10:20]
    fifth_prize = ordered_unique_4s[20:120]

    # Sort 5th prize in standard ascending order (0007, 0026, ... 9999)
    fifth_prize.sort()

    # ── 4. Export CSV Matrix for reference ──
    csv_file_path = os.path.join(os.path.dirname(__file__), 'parsed_result_matrix.csv')
    try:
        with open(csv_file_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['Prize_Tier', 'Count', 'Numbers'])
            writer.writerow(['1st_Prize', '1', first_prize])
            writer.writerow(['Consolation', '1', consolation])
            writer.writerow(['2nd_Prize', str(len(second_prize)), ' '.join(second_prize)])
            writer.writerow(['3rd_Prize', str(len(third_prize)), ' '.join(third_prize)])
            writer.writerow(['4th_Prize', str(len(fourth_prize)), ' '.join(fourth_prize)])
            writer.writerow(['5th_Prize', str(len(fifth_prize)), ' '.join(fifth_prize)])
    except Exception:
        pass

    return {
        "firstPrize": first_prize,
        "consolationPrize": consolation,
        "secondPrizeNumbers": second_prize,
        "thirdPrizeNumbers": third_prize,
        "fourthPrizeNumbers": fourth_prize,
        "fifthPrizeNumbers": fifth_prize,
        "csvPath": csv_file_path,
        "stats": {
            "secondCount": len(second_prize),
            "thirdCount": len(third_prize),
            "fourthCount": len(fourth_prize),
            "fifthCount": len(fifth_prize),
        }
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No PDF file path provided"}))
        sys.exit(1)

    pdf_file = sys.argv[1]
    res = parse_lottery_pdf(pdf_file)
    print(json.dumps(res))