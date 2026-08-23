const fs = require('fs');
const path = require('path');
const { createWorker } = require('tesseract.js');

async function extractTicketsFromImage(imagePath) {
    if (!fs.existsSync(imagePath)) {
        console.error(JSON.stringify({ error: `File not found: ${imagePath}` }));
        process.exit(1);
    }

    try {
        const worker = await createWorker('eng');
        const ret = await worker.recognize(imagePath);
        await worker.terminate();

        const rawText = ret.data.text || '';
        const lines = rawText.split(/\r?\n/);
        const items = [];
        let currentSeries = '12';

        for (const line of lines) {
            const l = line.trim();
            if (!l) continue;

            // 1. Header Series check e.g. "24 Series", "100"
            const headerMatch = l.match(/^(?:SERIES|SR|SER)?\s*(\d{2,3}[A-Za-z]?)\b/i);
            if (headerMatch && !l.match(/\b\d{5}\b/)) {
                currentSeries = headerMatch[1].replace(/\D/g, '') || currentSeries;
                continue;
            }

            // 2. Trailing series: 45385*24 or 45385=24 or 45385 24
            const trailingMatches = [...l.matchAll(/(\d{5})\s*[-:,\/=\s.*xX#@+]+\s*(\d{2,3}[A-Za-z]?)/g)];
            if (trailingMatches.length > 0) {
                for (const m of trailingMatches) {
                    const tNo = m[1];
                    const s = m[2].replace(/\D/g, '') || currentSeries;
                    items.push({ series: s, ticketNo: tNo, amount: 0.0 });
                }
                continue;
            }

            // 3. Leading series: 24*45385 or 24=45385 or 24 45385
            const leadingMatches = [...l.matchAll(/(\d{2,3}[A-Za-z]?)\s*[-:,\/=\s.*xX#@+]+\s*(\d{5})/g)];
            if (leadingMatches.length > 0) {
                for (const m of leadingMatches) {
                    const s = m[1].replace(/\D/g, '') || currentSeries;
                    const tNo = m[2];
                    items.push({ series: s, ticketNo: tNo, amount: 0.0 });
                }
                continue;
            }

            // 4. Standalone 5-digit numbers
            const all5s = [...l.matchAll(/\b\d{5}\b/g)];
            if (all5s.length > 0) {
                for (const m of all5s) {
                    items.push({ series: currentSeries, ticketNo: m[0], amount: 0.0 });
                }
            }
        }

        console.log(JSON.stringify(items));
    } catch (err) {
        console.error(JSON.stringify({ error: err.message }));
        process.exit(1);
    }
}

const targetImage = process.argv[2];
if (!targetImage) {
    console.error(JSON.stringify({ error: "Usage: node ocr_offline.js <image_path>" }));
    process.exit(1);
}

extractTicketsFromImage(targetImage);
