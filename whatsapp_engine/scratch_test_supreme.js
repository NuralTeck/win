const assert = require('assert');

function cleanSeriesNumber(rawSeries, fallback = '12') {
  if (!rawSeries) return fallback;
  const str = String(rawSeries).trim();
  const digits = str.replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 4) {
    return digits;
  }
  return digits.length > 0 ? digits.slice(0, 3) : fallback;
}

function parseIncomingTicketText(text, defaultSeries = '12') {
  // 1. Strip real dates (e.g. 13=8=2026, 14/08/2026, 14/08)
  const cleanedText = text
    .replace(/\b\d{1,2}[=\/\.-]\d{1,2}[=\/\.-]\d{2,4}(?:=[0-9A-Za-z]+)?\b/g, ' ')
    .replace(/\b\d{1,2}\/\d{1,2}\b/g, ' ');

  const items = [];
  const lines = cleanedText.split(/[\r\n]+/);
  let currentSeries = cleanSeriesNumber(defaultSeries, '12');

  for (const line of lines) {
    let l = line.trim();
    if (!l) continue;

    // Ignore pure time tags and standalone noise lines
    if (/^(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)$/i.test(l) || /^(?:kal|tomorrow|aaj|today)$/i.test(l)) {
      continue;
    }
    if (/^[A-Za-z]{3,20}\s*(?:boakg|booking|bokg|bok|bkg)$/i.test(l)) {
      continue;
    }

    // --- CASE A: Standalone Series Header e.g. "12c", "12s", "12se", "12 serial", "(40c)", "40", "SERIES 24" ---
    const headerMatch = l.match(/^(?:SERIES|SR|SER|SERI)?\s*[\(\[]?\s*([0-9]{1,3}\s*[A-Za-z]{0,8}|[A-Za-z]{1,4}\s*[0-9]{1,3})\s*[\)\]]?\s*$/i);
    if (
      headerMatch &&
      l.length <= 15 &&
      !l.includes('-') &&
      !/\d{5}/.test(l) &&
      !['qty', 'pcs', 'pm', 'am', 'dear', 'ok', 'hi', 'hello', 'thanks'].includes(l.toLowerCase())
    ) {
      currentSeries = cleanSeriesNumber(headerMatch[1], currentSeries);
      continue;
    }

    // Strip inline shift tags (e.g. "8pm", "1pm", "6pm", "8gm") from line containing tickets
    const lineForTickets = l.replace(/(?:=|\b)(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)\b/gi, ' ').trim();

    // --- CASE B: Series (with c/s/se) AAGE + 5-Digit Range e.g. "12c 15204-09-5", "(40s)=15204-09=10" ---
    const inlineSeriesRange = lineForTickets.match(
      /(?:^|[\s,;])[\(\[]?\s*([0-9]{1,3}\s*[A-Za-z]{0,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})\s*[\)\]]?\s*[-:,\/=\s]\s*(\d{3})(\d{2})\s*[-~to]+\s*(\d{2}|\d{5})(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (inlineSeriesRange && !/\d{5}/.test(inlineSeriesRange[1])) {
      const s = cleanSeriesNumber(inlineSeriesRange[1], currentSeries);
      const prefix = inlineSeriesRange[2];
      const startLast2 = parseInt(inlineSeriesRange[3], 10);
      const endStr = inlineSeriesRange[4];
      const endLast2 = endStr.length === 5 ? parseInt(endStr.slice(-2), 10) : parseInt(endStr, 10);
      const qty = inlineSeriesRange[5] ? parseInt(inlineSeriesRange[5], 10) : 1;

      if (!isNaN(startLast2) && !isNaN(endLast2) && endLast2 >= startLast2 && endLast2 - startLast2 <= 200) {
        for (let i = startLast2; i <= endLast2; i++) {
          const tNo = `${prefix}${String(i).padStart(2, '0')}`;
          if (tNo.length === 5) {
            items.push({
              series: s,
              ticketNo: tNo,
              quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
            });
          }
        }
        currentSeries = s;
        continue;
      }
    }

    // --- CASE C: Inverted Range with Series PEECHE e.g. "15204-09=12c*5", "15204-09 (40s)*5" ---
    const invertedRangeMatch = lineForTickets.match(
      /(?:^|[\s,;])(\d{3})(\d{2})\s*[-~to]+\s*(\d{2}|\d{5})\s*[-:,\/=\s]*[\(\[]?\s*([0-9]{1,3}\s*[A-Za-z]{0,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})\s*[\)\]]?(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (invertedRangeMatch && !/\d{5}/.test(invertedRangeMatch[4])) {
      const prefix = invertedRangeMatch[1];
      const startLast2 = parseInt(invertedRangeMatch[2], 10);
      const endStr = invertedRangeMatch[3];
      const endLast2 = endStr.length === 5 ? parseInt(endStr.slice(-2), 10) : parseInt(endStr, 10);
      const s = cleanSeriesNumber(invertedRangeMatch[4], currentSeries);
      const qty = invertedRangeMatch[5] ? parseInt(invertedRangeMatch[5], 10) : 1;

      if (!isNaN(startLast2) && !isNaN(endLast2) && endLast2 >= startLast2 && endLast2 - startLast2 <= 200) {
        for (let i = startLast2; i <= endLast2; i++) {
          const tNo = `${prefix}${String(i).padStart(2, '0')}`;
          if (tNo.length === 5) {
            items.push({
              series: s,
              ticketNo: tNo,
              quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
            });
          }
        }
        currentSeries = s;
        continue;
      }
    }

    // --- CASE D: Standalone 5-Digit Range under Active Series e.g. "15204-09-5", "65491-95=10" ---
    const trailingRange = lineForTickets.match(
      /(?:^|[\s,;])(\d{3})(\d{2})\s*[-~to]+\s*(\d{2}|\d{5})(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (trailingRange) {
      const prefix = trailingRange[1];
      const startLast2 = parseInt(trailingRange[2], 10);
      const endStr = trailingRange[3];
      const endLast2 = endStr.length === 5 ? parseInt(endStr.slice(-2), 10) : parseInt(endStr, 10);
      const qty = trailingRange[4] ? parseInt(trailingRange[4], 10) : 1;

      if (!isNaN(startLast2) && !isNaN(endLast2) && endLast2 >= startLast2 && endLast2 - startLast2 <= 200) {
        for (let i = startLast2; i <= endLast2; i++) {
          const tNo = `${prefix}${String(i).padStart(2, '0')}`;
          if (tNo.length === 5) {
            items.push({
              series: currentSeries,
              ticketNo: tNo,
              quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
            });
          }
        }
        continue;
      }
    }

    // --- CASE E: Bracket Series (with c/s/se) + 5-Digit Ticket (e.g. "(12c) 62393", "(40s)=12543*5", "[36se] 65491") ---
    const bracketSeriesMatch = lineForTickets.match(
      /(?:^|[\s,;])[\(\[]\s*([0-9]{1,3}\s*[A-Za-z]{0,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})\s*[\)\]]\s*[-:,\/=\s]*(\d{5})(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (bracketSeriesMatch) {
      const s = cleanSeriesNumber(bracketSeriesMatch[1], currentSeries);
      const tNo = bracketSeriesMatch[2];
      const qty = bracketSeriesMatch[3] ? parseInt(bracketSeriesMatch[3], 10) : 1;
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE F: Inverted Multiplier First + Series PEECHE (e.g. "62393*5=12c", "12543*5=(40s)", "62393*5=12") ---
    const invertedMultiplierFirst = lineForTickets.match(
      /(?:^|[\s,;])(\d{5})\s*[*xX]\s*(\d+)\s*[-:,\/=\s]*[\(\[]?\s*([0-9]{1,3}\s*[A-Za-z]{0,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})\s*[\)\]]?/i
    );
    if (invertedMultiplierFirst) {
      const tNo = invertedMultiplierFirst[1];
      const qty = parseInt(invertedMultiplierFirst[2], 10);
      const s = cleanSeriesNumber(invertedMultiplierFirst[3], currentSeries);
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE G: Inverted 5-Digit Ticket + Explicit Series PEECHE (e.g. "62393=12s", "62393 12c", "62393-12se", "12543 (40c)") ---
    const invertedMatch = lineForTickets.match(
      /(?:^|[\s,;])(\d{5})\s*[-:,\/=\s]*([\(\[][0-9]{1,3}[A-Za-z]?[\)\]]|[0-9]{1,3}\s*[A-Za-z]{1,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (invertedMatch) {
      const tNo = invertedMatch[1];
      const s = cleanSeriesNumber(invertedMatch[2], currentSeries);
      const qty = invertedMatch[3] ? parseInt(invertedMatch[3], 10) : 1;
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE H: Universal Series AAGE + 5-Digit Ticket (e.g. "12c- 62393", "12s=62393", "12se:62393*10", "83L- 15204", "12- 62393") ---
    const universalMatch = lineForTickets.match(
      /(?:^|[\s,;])([0-9]{1,3}\s*[A-Za-z]{0,6}|[A-Za-z]{1,3}\s*[0-9]{1,3})\s*[-:,\/=\s]\s*(\d{5})(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i
    );
    if (universalMatch && !/\d{5}/.test(universalMatch[1])) {
      const s = cleanSeriesNumber(universalMatch[1], currentSeries);
      const tNo = universalMatch[2];
      const qty = universalMatch[3] ? parseInt(universalMatch[3], 10) : 1;
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE I: Standalone 5-Digit Ticket under Active Series with optional multiplier (e.g. "62393", "54474=5", "62393*10") ---
    const standaloneTicket = lineForTickets.match(/\b(\d{5})\b(?:\s*[-*=xX]\s*(\d+)(?:pic|pcs|qty)?)?/i);
    if (standaloneTicket) {
      const tNo = standaloneTicket[1];
      const qty = standaloneTicket[2] ? parseInt(standaloneTicket[2], 10) : 1;
      items.push({
        series: currentSeries,
        ticketNo: tNo,
        quantity: isNaN(qty) || qty <= 0 ? 1 : qty,
      });
      continue;
    }
  }

  return items;
}

// REAL WORLD TEST CASES
const testCases = [
  { text: "8pm 62393=12s", expected: [{ series: "12", ticketNo: "62393", quantity: 1 }] },
  { text: "62393=12s 8pm", expected: [{ series: "12", ticketNo: "62393", quantity: 1 }] },
  { text: "Wakil 62393=12s ok", expected: [{ series: "12", ticketNo: "62393", quantity: 1 }] },
  { text: "bhai 62393=12s*5 kar do 8pm", expected: [{ series: "12", ticketNo: "62393", quantity: 5 }] },
  { text: "dear 1pm 12c 62393 please", expected: [{ series: "12", ticketNo: "62393", quantity: 1 }] },
  { text: "Ramesh booking 8pm\n62393=12s\n15204=12s*5\n54474=12s\ntotal 7 piece ok", expected: [
    { series: "12", ticketNo: "62393", quantity: 1 },
    { series: "12", ticketNo: "15204", quantity: 5 },
    { series: "12", ticketNo: "54474", quantity: 1 }
  ]}
];

let allPassed = true;
for (const tc of testCases) {
  const result = parseIncomingTicketText(tc.text);
  try {
    assert.deepStrictEqual(result, tc.expected);
    console.log(`✅ PASSED: "${tc.text.replace(/\n/g, ' ')}" ->`, JSON.stringify(result));
  } catch (e) {
    console.error(`❌ FAILED for "${tc.text}":`, JSON.stringify(result), 'Expected:', JSON.stringify(tc.expected));
    allPassed = false;
  }
}

module.exports = { parseIncomingTicketText, cleanSeriesNumber };
