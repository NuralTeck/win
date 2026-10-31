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
    """Filter out non-4-digit tokens while keeping all genuine lottery numbers (e.g. 2024, 2025, 2026, 1000, 0120)"""
    return [t for t in tokens if len(t) == 4 and t.isdigit()]

def extract_tokens_from_pdf(pdf_path):
    """Fast, safe text extraction from PDF pages"""
    extracted_chunks = []
    try:
        import pypdf
        reader = pypdf.PdfReader(pdf_path)
        for page in reader.pages:
            t = page.extract_text() or ""
            if t:
                # Separate numbers glued together without whitespace
                t = re.sub(r'(?<=\d{4})(?=\d{4})', ' ', t)
                t = re.sub(r'(?<=\d{5})(?=\d{5})', ' ', t)
                extracted_chunks.append(t)
    except Exception as e:
        sys.stderr.write(f"PDF Extraction Exception: {e}\n")

    return "\n".join(extracted_chunks)

def strip_middle_advertisement(text: str) -> str:
    m4 = re.search(r'4th[ \t]*(?:Prize|Amount)?', text, re.IGNORECASE)
    m5 = re.search(r'5th[ \t]*(?:Prize|Amount)?', text, re.IGNORECASE)
    if m4 and m5 and m5.start() > m4.end():
        after4 = m4.end()
        before5 = m5.start()
        between = text[after4:before5]
        clean_between = re.sub(r'(?:₹|Rs\.?|INR)?[ \t]*\b\d+(?:,\d+)?[ \t]*\/\-', ' ', between, flags=re.IGNORECASE)
        clean_between = re.sub(r'for[ \t]+Seller[ \t]*(?:₹|Rs\.?)?[ \t]*\d+(?:\/\-)?', ' ', clean_between, flags=re.IGNORECASE)
        matches = list(re.finditer(r'\b[0-9]{4}\b', clean_between))
        if len(matches) >= 10:
            tenth_num = matches[9].group(0)
            idx_tenth = between.find(tenth_num, matches[9].start())
            if idx_tenth != -1:
                cut_point = after4 + idx_tenth + len(tenth_num)
                return text[:cut_point] + '\n\n' + text[before5:]
    return text

def parse_lottery_pdf(pdf_path):
    raw_text = extract_tokens_from_pdf(pdf_path)
    raw_text = strip_middle_advertisement(raw_text)
    
    # Detect Date from PDF text (e.g. 08/06/26 or 08-06-2026 or 08.06.2026)
    detected_date_str = ""
    date_m = re.search(r'\b([0-3]?\d)[\/\-\.]([0-1]?\d)[\/\-\.](20\d{2}|\d{2})\b', raw_text)
    if date_m:
        day = date_m.group(1).zfill(2)
        month = date_m.group(2).zfill(2)
        year = date_m.group(3)
        if len(year) == 2:
            year = "20" + year
        detected_date_str = f"{day}/{month}/{year}"

    # Detect Shift from PDF text (1 PM / 6 PM / 8 PM)
    detected_shift = ""
    lower = raw_text.lower()
    if re.search(r'\b(1[:\.]?00\s*pm|1\s*pm|morning)\b', lower):
        detected_shift = "1 PM"
    elif re.search(r'\b(6[:\.]?00\s*pm|6\s*pm|\bday\b)', lower):
        detected_shift = "6 PM"
    elif re.search(r'\b(8[:\.]?00\s*pm|8\s*pm|night|evening)', lower):
        detected_shift = "8 PM"

    # Strip date patterns, currency amounts, seller prizes, bumper banner noise, and draw headers
    clean_text = raw_text
    clean_text = re.sub(r'(?:DEAR[ \t]+)?(?:BUMPER|PUJA|DIWALI|NEW[ \t]*YEAR|HOLI|SUMMER|WINTER|MONSOON|BAISAKHI|SUPER)[^\n]*(?:LOTTERY|20\d{2})?', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\bDRAW[ \t]+ON[ \t]+[^\n]+', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\b[0-3]?\d[\/\-\.][0-1]?\d[\/\-\.](?:20\d{2}|\d{2})\b', ' ', clean_text)
    clean_text = re.sub(r'(?:₹|Rs\.?|INR)?[ \t]*\b(?:1,000|9,000|1000|9000|500|450|250|120|0450|0250|0120)[ \t]*(?:\/\-|\b(?:[ \t]*to[ \t]*seller|[ \t]*each|[ \t]*for[ \t]*seller))', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\b(?:Draw|Result|Page|TDS)[ \t]*(?:No\.?)?[ \t]*\d+', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\b(?:Winner|Prize|Seller)[ \t]*Amount[ \t]*(?:₹|Rs\.?)?[ \t]*\d+', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\bfor[ \t]*Seller[ \t]*(?:₹|Rs\.?)?[ \t]*\d+', ' ', clean_text, flags=re.IGNORECASE)
    clean_text = re.sub(r'\b\d{2}:\d{2}(?::\d{2})?\b', ' ', clean_text)
    # Strip year only when connected to date/banner keywords, preserving genuine 4-digit lottery numbers
    clean_text = re.sub(r'\b(?:DATE|DRAW|ON|YEAR|BUMPER|LOTTERY|SAMBAD)[^\n]*?(?:202[0-9]|203[0-9])\b', ' ', clean_text, flags=re.IGNORECASE)
    text_without_dates = clean_text
    
    # ── 1. First Prize (Pattern: 2 Digits + 1 Letter + Space + 5 Digits e.g. 74K 33607, 44A 36813 or 93J 99831) ──
    first_matches = re.findall(r'\b([0-9]{1,3}[A-Z]|[A-Z]{1,2})[\s\-_]*([0-9]{5})\b', text_without_dates, re.IGNORECASE)
    if first_matches:
        first_prize = f"{first_matches[0][0].upper()} {first_matches[0][1]}"
        consolation = first_matches[0][1]
    else:
        # Fallback for alternative format
        fallback_m = re.search(r'\b([0-9]{5})\b', text_without_dates)
        if fallback_m:
            first_prize = fallback_m.group(1)
            consolation = fallback_m.group(1)
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

    # ── 3. 4-Digit Numbers: Disambiguate 3rd (10), 4th (10), 5th (100) ──
    # In Nagaland Lottery Sambad PDFs:
    # - 100 numbers of 5th Prize appear BEFORE 2nd Prize (5-digit block)
    # - 10 numbers of 3rd Prize appear RIGHT AFTER 2nd Prize
    # - 10 numbers of 4th Prize appear after 3rd Prize (after TDS note)
    m2nd = re.search(r'\b\d{5}\s+\d{5}\s+\d{5}\b', text_without_dates)
    second_prize_index = m2nd.start() if m2nd else -1
    if second_prize_index == -1 and second_prize:
        second_prize_index = text_without_dates.find(second_prize[0])

    third_prize = []
    fourth_prize = []
    fifth_prize = []

    if second_prize_index != -1:
        text_before_2nd = text_without_dates[:second_prize_index]
        text_after_2nd = text_without_dates[second_prize_index:]

        b4 = clean_noise_tokens(re.findall(r'\b[0-9]{4}\b', text_before_2nd))
        a4 = clean_noise_tokens(re.findall(r'\b[0-9]{4}\b', text_after_2nd))

        if len(b4) >= 80 and len(a4) >= 10:
            fifth_prize = b4[:100]
            third_prize = a4[:10]
            fourth_prize = a4[10:20]
        elif len(a4) >= 80 and len(b4) >= 10:
            third_prize = b4[:10]
            fourth_prize = b4[10:20]
            fifth_prize = a4[:100]
        else:
            all_raw = clean_noise_tokens(re.findall(r'\b[0-9]{4}\b', text_without_dates))
            if len(all_raw) >= 110:
                fifth_prize = all_raw[:100]
                third_prize = all_raw[100:110]
                fourth_prize = all_raw[110:120]
            else:
                third_prize = all_raw[:10]
                fourth_prize = all_raw[10:20]
                fifth_prize = all_raw[20:120]
    else:
        all_raw = clean_noise_tokens(re.findall(r'\b[0-9]{4}\b', text_without_dates))
        if len(all_raw) >= 110:
            fifth_prize = all_raw[:100]
            third_prize = all_raw[100:110]
            fourth_prize = all_raw[110:120]
        else:
            third_prize = all_raw[:10]
            fourth_prize = all_raw[10:20]
            fifth_prize = all_raw[20:120]

    # 🛡️ Filter prize amounts / noise tokens, but allow genuine lottery numbers (2024, 2025, 2026, etc.)
    fourth_prize = [n for n in fourth_prize if n not in {'0250', '0500', '0120', '1000', '9000', '7001'}]

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
        "success": bool(first_prize or second_prize or fifth_prize),
        "drawDateStr": detected_date_str,
        "drawShift": detected_shift,
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