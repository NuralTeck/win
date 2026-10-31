const fs = require('fs');
const path = require('path');

let pdfModule;
try {
  pdfModule = require('pdf-parse');
} catch (e) {
  try {
    pdfModule = require(path.join(__dirname, 'node_modules', 'pdf-parse'));
  } catch (err) {
    pdfModule = null;
  }
}

async function extractRawPdfText(dataBuffer) {
  if (pdfModule && pdfModule.PDFParse) {
    try {
      const parser = new pdfModule.PDFParse({ data: dataBuffer });
      const result = await parser.getText();
      await parser.destroy();
      if (typeof result === 'string') return result;
      if (result && Array.isArray(result.pages)) {
        return result.pages.map(p => p.text || '').join('\n');
      }
      if (result && result.text) return result.text;
    } catch (e) {
      // fallback
    }
  }

  if (typeof pdfModule === 'function') {
    try {
      const data = await pdfModule(dataBuffer);
      return data.text || '';
    } catch (e) {
      // fallback
    }
  }

  return '';
}

function stripMiddleAdvertisement(text) {
  const m4 = text.match(/4th[ \t]*(?:Prize|Amount)?/i);
  const m5 = text.match(/5th[ \t]*(?:Prize|Amount)?/i);
  if (m4 && m5 && m5.index > m4.index) {
    const after4 = m4.index + m4[0].length;
    const before5 = m5.index;
    const between = text.substring(after4, before5);
    const cleanBetween = between
      .replace(/(?:₹|Rs\.?|INR)?[ \t]*\b\d+(?:,\d+)?[ \t]*\/\-/gi, ' ')
      .replace(/for[ \t]+Seller[ \t]*(?:₹|Rs\.?)?[ \t]*\d+(?:\/\-)?/gi, ' ');
    const fourDigitMatches = [...cleanBetween.matchAll(/\b[0-9]{4}\b/g)];
    if (fourDigitMatches.length >= 10) {
      const tenthNum = fourDigitMatches[9][0];
      const idxTenth = between.indexOf(tenthNum, fourDigitMatches[9].index);
      if (idxTenth !== -1) {
        const cutPoint = after4 + idxTenth + tenthNum.length;
        return text.substring(0, cutPoint) + '\n\n' + text.substring(before5);
      }
    }
  }
  return text;
}

function cleanNoiseTokens(tokens) {
  // Only keep valid 4-digit tokens - do NOT filter out genuine lottery numbers (e.g. 2024, 2025, 2026, 1000, 0120)!
  return tokens.filter(t => /^\d{4}$/.test(t));
}

async function parseLotteryPdf(pdfPath) {
  const dataBuffer = fs.readFileSync(pdfPath);
  let text = await extractRawPdfText(dataBuffer);
  if (text) {
    text = stripMiddleAdvertisement(text);
  }

  if (!text || text.trim().length === 0) {
    return {
      success: false,
      error: 'No text found in PDF (may be scanned image). Use "Bulk Paste" to enter result text directly.',
      firstPrize: '',
      consolationPrize: '',
      secondPrizeNumbers: [],
      thirdPrizeNumbers: [],
      fourthPrizeNumbers: [],
      fifthPrizeNumbers: [],
    };
  }

  // Detect Date strictly as Indian standard DD/MM/YYYY (Day first, Month second, Year third)
  let detectedDateStr = '';
  // Check for explicit "held on DD/MM/YYYY" or "Date: DD/MM/YYYY" first
  const explicitDateMatch = text.match(/(?:held\s*on|date[:\s]*)\s*([0-3]?\d)[\/\-\.]([0-1]?\d)[\/\-\.](20\d{2}|\d{2})\b/i);
  const generalDateMatch = text.match(/\b([0-3]?\d)[\/\-\.]([0-1]?\d)[\/\-\.](20\d{2}|\d{2})\b/);
  const isoDateMatch = text.match(/\b(20\d{2})[\/\-\.]([0-1]?\d)[\/\-\.]([0-3]?\d)\b/);

  if (explicitDateMatch) {
    const day = explicitDateMatch[1].padStart(2, '0');
    const month = explicitDateMatch[2].padStart(2, '0');
    let year = explicitDateMatch[3];
    if (year.length === 2) year = '20' + year;
    detectedDateStr = `${day}/${month}/${year}`;
  } else if (generalDateMatch) {
    const day = generalDateMatch[1].padStart(2, '0');
    const month = generalDateMatch[2].padStart(2, '0');
    let year = generalDateMatch[3];
    if (year.length === 2) year = '20' + year;
    detectedDateStr = `${day}/${month}/${year}`;
  } else if (isoDateMatch) {
    const year = isoDateMatch[1];
    const month = isoDateMatch[2].padStart(2, '0');
    const day = isoDateMatch[3].padStart(2, '0');
    detectedDateStr = `${day}/${month}/${year}`;
  }

  // Backup: If date not found in PDF text, check filename (e.g. lottery-sambad-8pm-21-06-2026.pdf)
  if (!detectedDateStr && pdfPath) {
    const baseName = path.basename(pdfPath);
    const fileDateMatch = baseName.match(/\b([0-3]?\d)[\/\-\.]([0-1]?\d)[\/\-\.](20\d{2}|\d{2})\b/);
    if (fileDateMatch) {
      const day = fileDateMatch[1].padStart(2, '0');
      const month = fileDateMatch[2].padStart(2, '0');
      let year = fileDateMatch[3];
      if (year.length === 2) year = '20' + year;
      detectedDateStr = `${day}/${month}/${year}`;
    }
  }

  // Detect Shift from PDF text (1 PM / 6 PM / 8 PM)
  let detectedShift = '';
  const lowerText = text.toLowerCase();
  if (/\b(1[:\.]?00\s*pm|1\s*pm|morning)\b/i.test(lowerText)) {
    detectedShift = '1 PM';
  } else if (/\b(6[:\.]?00\s*pm|6\s*pm|\bday\b)/i.test(lowerText)) {
    detectedShift = '6 PM';
  } else if (/\b(8[:\.]?00\s*pm|8\s*pm|night|evening)/i.test(lowerText)) {
    detectedShift = '8 PM';
  }

  // Backup: If shift not found in PDF text, check filename
  if (!detectedShift && pdfPath) {
    const baseName = path.basename(pdfPath).toLowerCase();
    if (/\b(1[:\.]?00\s*pm|1\s*pm|morning)\b/i.test(baseName)) {
      detectedShift = '1 PM';
    } else if (/\b(6[:\.]?00\s*pm|6\s*pm|\bday\b)/i.test(baseName)) {
      detectedShift = '6 PM';
    } else if (/\b(8[:\.]?00\s*pm|8\s*pm|night|evening)/i.test(baseName)) {
      detectedShift = '8 PM';
    }
  }

  // Separate glued 4-digit / 5-digit numbers
  text = text.replace(/(?<=\d{4})(?=\d{4})/g, ' ');
  text = text.replace(/(?<=\d{5})(?=\d{5})/g, ' ');

  // Strip dates, currency amounts, seller prizes, bumper advertisement noise, and draw headers so prize numbers are clean
  const textWithoutDates = text
    .replace(/(?:DEAR[ \t]+)?(?:BUMPER|PUJA|DIWALI|NEW[ \t]*YEAR|HOLI|SUMMER|WINTER|MONSOON|BAISAKHI|SUPER)[^\n]*(?:LOTTERY|20\d{2})?/gi, ' ')
    .replace(/\bDRAW[ \t]+ON[ \t]+[^\n]+/gi, ' ')
    .replace(/\b[0-3]?\d[\/\-\.][0-1]?\d[\/\-\.](?:20\d{2}|\d{2})\b/g, ' ')
    .replace(/(?:₹|Rs\.?|INR)?[ \t]*\b(?:1,000|9,000|1000|9000|500|450|250|120|0450|0250|0120)[ \t]*(?:\/\-|\b(?:[ \t]*to[ \t]*seller|[ \t]*each|[ \t]*for[ \t]*seller))/gi, ' ')
    .replace(/\b(?:Draw|Result|Page|TDS)[ \t]*(?:No\.?)?[ \t]*\d+/gi, ' ')
    .replace(/\b(?:Winner|Prize|Seller)[ \t]*Amount[ \t]*(?:₹|Rs\.?)?[ \t]*\d+/gi, ' ')
    .replace(/\bfor[ \t]*Seller[ \t]*(?:₹|Rs\.?)?[ \t]*\d+/gi, ' ')
    .replace(/\b\d{2}:\d{2}(?::\d{2})?\b/g, ' ')
    // Strip year only when connected to date/banner keywords, preserving genuine 4-digit lottery numbers
    .replace(/\b(?:DATE|DRAW|ON|YEAR|BUMPER|LOTTERY|SAMBAD)[^\n]*?(?:202[0-9]|203[0-9])\b/gi, ' ');

  // 1. First Prize (Pattern: 2 Digits + 1 Letter + Space + 5 Digits e.g. 74K 33607, 44A 36813, 93J 99831)
  const firstMatches = [...textWithoutDates.matchAll(/\b([0-9]{1,3}[A-Z]|[A-Z]{1,2})[\s\-_]*([0-9]{5})\b/gi)];
  let firstPrize = '';
  let consolation = '';

  if (firstMatches.length > 0) {
    firstPrize = `${firstMatches[0][1].toUpperCase()} ${firstMatches[0][2]}`;
    consolation = firstMatches[0][2];
  } else {
    // Look for first 5-digit number
    const first5 = textWithoutDates.match(/\b[0-9]{5}\b/);
    if (first5) {
      firstPrize = first5[0];
      consolation = first5[0];
    }
  }

  // 2. Second Prize (10 5-digit numbers)
  const all5s = textWithoutDates.match(/\b[0-9]{5}\b/g) || [];
  const seen5 = new Set();
  const secondPrize = [];
  for (const n of all5s) {
    if (n !== consolation && !seen5.has(n)) {
      seen5.add(n);
      secondPrize.push(n);
    }
  }
  const secondPrizeSlice = secondPrize.slice(0, 10);

  // 3. 4-Digit Numbers: Disambiguate 3rd (10), 4th (10), and 5th (100)
  // In Nagaland Lottery Sambad PDFs:
  // - 100 numbers of 5th Prize appear BEFORE 2nd Prize (5-digit block)
  // - 10 numbers of 3rd Prize appear RIGHT AFTER 2nd Prize
  // - 10 numbers of 4th Prize appear after 3rd Prize (after TDS note)
  let secondPrizeIndex = -1;
  const match2nd = textWithoutDates.match(/\b\d{5}\s+\d{5}\s+\d{5}\b/);
  if (match2nd) {
    secondPrizeIndex = match2nd.index;
  } else if (all5s.length > 0) {
    secondPrizeIndex = textWithoutDates.indexOf(all5s[0]);
  }

  let thirdPrize = [];
  let fourthPrize = [];
  let fifthPrize = [];

  if (secondPrizeIndex !== -1) {
    const textBefore2nd = textWithoutDates.substring(0, secondPrizeIndex);
    const textAfter2nd = textWithoutDates.substring(secondPrizeIndex);

    const raw4sBefore = cleanNoiseTokens(textBefore2nd.match(/\b[0-9]{4}\b/g) || []);
    const raw4sAfter = cleanNoiseTokens(textAfter2nd.match(/\b[0-9]{4}\b/g) || []);

    if (raw4sBefore.length >= 80 && raw4sAfter.length >= 10) {
      fifthPrize = raw4sBefore.slice(0, 100);
      thirdPrize = raw4sAfter.slice(0, 10);
      fourthPrize = raw4sAfter.slice(10, 20);
    } else if (raw4sAfter.length >= 80 && raw4sBefore.length >= 10) {
      thirdPrize = raw4sBefore.slice(0, 10);
      fourthPrize = raw4sBefore.slice(10, 20);
      fifthPrize = raw4sAfter.slice(0, 100);
    } else {
      const allClean4s = cleanNoiseTokens(textWithoutDates.match(/\b[0-9]{4}\b/g) || []);
      if (allClean4s.length >= 110) {
        fifthPrize = allClean4s.slice(0, 100);
        thirdPrize = allClean4s.slice(100, 110);
        fourthPrize = allClean4s.slice(110, 120);
      } else {
        thirdPrize = allClean4s.slice(0, 10);
        fourthPrize = allClean4s.slice(10, 20);
        fifthPrize = allClean4s.slice(20, 120);
      }
    }
  } else {
    const allClean4s = cleanNoiseTokens(textWithoutDates.match(/\b[0-9]{4}\b/g) || []);
    if (allClean4s.length >= 110) {
      fifthPrize = allClean4s.slice(0, 100);
      thirdPrize = allClean4s.slice(100, 110);
      fourthPrize = allClean4s.slice(110, 120);
    } else {
      thirdPrize = allClean4s.slice(0, 10);
      fourthPrize = allClean4s.slice(10, 20);
      fifthPrize = allClean4s.slice(20, 120);
    }
  }

  // 🛡️ Filter prize amounts / noise tokens, but allow genuine lottery numbers (2024, 2025, 2026, etc.)
  fourthPrize = fourthPrize.filter(n => n !== '0250' && n !== '0500' && n !== '0120' && n !== '1000');

  fifthPrize.sort();

  return {
    success: firstPrize.length > 0 || secondPrizeSlice.length > 0 || fifthPrize.length > 0,
    drawDateStr: detectedDateStr,
    drawShift: detectedShift,
    firstPrize,
    consolationPrize: consolation,
    secondPrizeNumbers: secondPrizeSlice,
    thirdPrizeNumbers: thirdPrize,
    fourthPrizeNumbers: fourthPrize,
    fifthPrizeNumbers: fifthPrize,
    stats: {
      secondCount: secondPrizeSlice.length,
      thirdCount: thirdPrize.length,
      fourthCount: fourthPrize.length,
      fifthCount: fifthPrize.length,
    }
  };
}

if (require.main === module) {
  let filePath = process.argv[2];
  if (filePath) {
    filePath = filePath.trim().replace(/^["']|["']$/g, '');
  }
  if (!filePath || !fs.existsSync(filePath)) {
    console.error(JSON.stringify({ error: 'File not found or not specified' }));
    process.exit(1);
  }

  parseLotteryPdf(filePath)
    .then(res => {
      console.log(JSON.stringify(res));
    })
    .catch(err => {
      console.error(JSON.stringify({ error: err.message }));
      process.exit(1);
    });
}

module.exports = { parseLotteryPdf };
