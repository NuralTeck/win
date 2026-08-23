const fs = require('fs');
const pdf = require('pdf-parse');

function cleanNoiseTokens(tokens) {
  const noiseSet = new Set(['1000', '9000', '0450', '0250', '0120', '2020', '2021', '2022', '2023', '2024', '2025', '2026', '2027', '2028', '2029', '2030']);
  return tokens.filter(t => {
    if (noiseSet.has(t)) return false;
    if (/^\d{4}$/.test(t) && parseInt(t, 10) >= 2020 && parseInt(t, 10) <= 2035) {
      return false;
    }
    return true;
  });
}

async function parseLotteryPdf(pdfPath) {
  const dataBuffer = fs.readFileSync(pdfPath);
  const data = await pdf(dataBuffer);
  let text = data.text || '';

  if (!text || text.trim().length === 0) {
    return {
      success: false,
      error: 'No text found in PDF (scanned/image PDF). Use "Bulk Paste" to enter result text directly.',
      firstPrize: '',
      consolationPrize: '',
      secondPrizeNumbers: [],
      thirdPrizeNumbers: [],
      fourthPrizeNumbers: [],
      fifthPrizeNumbers: [],
    };
  }

  // Separate glued 4-digit / 5-digit numbers
  text = text.replace(/(?<=\d{4})(?=\d{4})/g, ' ');
  text = text.replace(/(?<=\d{5})(?=\d{5})/g, ' ');

  // Strip dates
  const textWithoutDates = text.replace(/\b\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}\b/g, ' ');

  // 1. First Prize (Pattern: 2 Digits + 1 Letter + Space + 5 Digits e.g. 44A 36813 or 93J 99831)
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

  // 3. 4-Digit Numbers: 3rd (10), 4th (10), 5th (100)
  const all4s = textWithoutDates.match(/\b[0-9]{4}\b/g) || [];
  const clean4s = cleanNoiseTokens(all4s);
  const seen4 = new Set();
  const orderedUnique4s = [];
  for (const n of clean4s) {
    if (!seen4.has(n)) {
      seen4.add(n);
      orderedUnique4s.push(n);
    }
  }

  const thirdPrize = orderedUnique4s.slice(0, 10);
  const fourthPrize = orderedUnique4s.slice(10, 20);
  const fifthPrize = orderedUnique4s.slice(20, 120);
  fifthPrize.sort();

  return {
    success: firstPrize.length > 0 || secondPrizeSlice.length > 0,
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
  const filePath = process.argv[2];
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
