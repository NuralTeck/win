/**
 * ==============================================================================
 * HIGH-THROUGHPUT WHATSAPP ENTRY LOGGING ENGINE
 * Built with Node.js, Express, Baileys & Supabase Batch Ingestion
 * ==============================================================================
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  makeCacheableSignalKeyStore,
  DisconnectReason,
  Browsers,
  fetchLatestBaileysVersion,
  downloadMediaMessage,
} = require('@whiskeysockets/baileys');
const { createClient } = require('@supabase/supabase-js');
const pino = require('pino');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { DatabaseSync } = require('node:sqlite');

// --- 1. CONFIGURATION & STATE ---
const PORT = process.env.PORT || 4000;
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_KEY || '';
const FLUSH_INTERVAL_MS = parseInt(process.env.BUFFER_FLUSH_INTERVAL_MS || '2000', 10);
const MAX_BUFFER_SIZE = parseInt(process.env.BUFFER_MAX_SIZE || '100', 10);

// Initialize Local SQLite Database
let localDb = null;
try {
  const baseDocsDir = path.join(os.homedir(), 'Documents');
  if (!fs.existsSync(baseDocsDir)) {
    fs.mkdirSync(baseDocsDir, { recursive: true });
  }
  const dbPath = path.join(baseDocsDir, 'opscore_pro.db');
  localDb = new DatabaseSync(dbPath);
  localDb.exec('PRAGMA journal_mode=WAL;');
  localDb.exec('PRAGMA busy_timeout=10000;');
  localDb.exec('PRAGMA synchronous=NORMAL;');
  localDb.exec(`
    CREATE TABLE IF NOT EXISTS ai_settings (
      key TEXT PRIMARY KEY,
      value TEXT,
      updatedAt TEXT
    );
    CREATE TABLE IF NOT EXISTS pending_photo_bookings (
      id TEXT PRIMARY KEY,
      senderPhone TEXT NOT NULL,
      buyerName TEXT NOT NULL,
      drawShift TEXT NOT NULL,
      drawDate TEXT NOT NULL,
      imageBase64 TEXT,
      extractedText TEXT NOT NULL,
      parsedTicketsJson TEXT NOT NULL,
      status TEXT NOT NULL,
      createdAt TEXT NOT NULL
    );
  `);
  console.log('✅ [LOCAL SQLITE] Connected to opscore_pro.db at:', dbPath);
} catch (sqliteErr) {
  console.log('⚠️ [LOCAL SQLITE] Note: Could not open local SQLite db:', sqliteErr.message);
}

// Initialize Supabase Client
let supabase = null;
if (SUPABASE_URL && SUPABASE_KEY) {
  supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false },
  });
}

// Ignore EPIPE errors on stdout and stderr (occurs when Flutter parent process closes pipe during hot restart)
process.stdout?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});
process.stderr?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});

// --- GLOBAL ERROR & TIMEOUT GUARDS (Prevents Node.js Baileys crash on socket timeout) ---
process.on('uncaughtException', (err) => {
  if (err?.code === 'EPIPE' || err?.message?.includes('EPIPE')) return;
  try {
    appendLog('warn', `🛡️ [CRASH GUARD] Caught Exception: ${err?.message || err}`);
  } catch (_) {}
});
process.on('unhandledRejection', (reason) => {
  try {
    appendLog('warn', `🛡️ [CRASH GUARD] Caught Rejection: ${reason?.message || reason}`);
  } catch (_) {}
});

// Sender Session Memory Map
// Remembers active Date, Shift, Customer Name, and Last Series for each sender across separate messages!
const senderSessions = new Map();

// Duplicate Prevention Cache (Key: drawDate_shiftName_sender_series_ticketNo)
const bookedKeysCache = new Set();

/**
 * Get YYYY-MM-DD in local system timezone (never shifts date backwards due to UTC conversion)
 */
function getLocalYmd(d) {
  if (!d) return '';
  const dateObj = typeof d === 'string' ? new Date(d) : d;
  if (isNaN(dateObj.getTime())) return '';
  const year = dateObj.getFullYear();
  const month = String(dateObj.getMonth() + 1).padStart(2, '0');
  const day = String(dateObj.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
/**
 * Get ISO formatted string for UTC storage and accurate IST display
 */
function getLocalIsoString(d, isDrawDate = false) {
  if (!d) return new Date().toISOString();
  const dateObj = typeof d === 'string' ? new Date(d) : d;
  if (isNaN(dateObj.getTime())) return new Date().toISOString();
  if (isDrawDate) {
    const year = dateObj.getFullYear();
    const month = String(dateObj.getMonth() + 1).padStart(2, '0');
    const day = String(dateObj.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}T00:00:00.000Z`;
  }
  return dateObj.toISOString();
}

async function syncRecentBookingsForDuplicateGuard() {
  if (!localDb) return;
  try {
    const todayIso = getLocalYmd(new Date());
    const rows = localDb
      .prepare('SELECT buyerPhone, drawName, drawDate, ticketSeries, ticketNumber FROM ticket_sales WHERE drawDate >= ? LIMIT 5000')
      .all(todayIso);
    if (rows && rows.length > 0) {
      for (const s of rows) {
        const dDate = getLocalYmd(s.drawDate || '');
        const shift = (s.drawName || '').trim().toLowerCase();
        const sender = s.buyerPhone || '';
        const series = s.ticketSeries || '';
        const parts = (s.ticketNumber || '').trim().split(' ');
        const tNo = parts.length > 1 ? parts[parts.length - 1] : (s.ticketNumber || '');
        if (dDate && sender && series && tNo) {
          bookedKeysCache.add(`${dDate}_${shift}_${sender}_${series}_${tNo}`);
        }
      }
    }
  } catch (_) {}
}

// Dynamic Learned Patterns Cache
let learnedPatterns = [];

async function refreshLearnedPatterns() {
  if (!supabase) return;
  try {
    const { data, error } = await supabase.from('learned_patterns').select('*').order('created_at', { ascending: false });
    if (!error && data) {
      learnedPatterns = data;
    }
  } catch (err) {
    appendLog('warn', `Learned patterns fetch note: ${err.message}`);
  }
}

// Dynamic Series Pricing Cache
let seriesPricesCache = [];

async function refreshSeriesPrices() {
  // Load from local SQLite DB (instant offline read from UI System Config)
  try {
    if (localDb) {
      const rows = localDb.prepare('SELECT seriesName as series_name, ticketPrice as ticket_price, isActive as is_active FROM series_prices WHERE isActive = 1').all();
      if (rows && rows.length > 0) {
        seriesPricesCache = rows;
      }
    }
  } catch (dbErr) {
    appendLog('warn', `Local SQLite series prices read note: ${dbErr.message}`);
  }
}

/**
 * Calculate dynamic price for ticket series based on System Configuration:
 * 1. Check exact match in series_prices table
 * 2. Or derive unit rate from Series 100 price (seriesNum * perSeriesRate)
 * 3. Or fallback to seriesDigits (e.g. Series 24 = ₹24, Series 6 = ₹6)
 */
function calculateSeriesPrice(seriesName) {
  const cleanName = String(seriesName || '').trim().toUpperCase();

  // 1. Exact match in configured series prices
  const exact = seriesPricesCache.find(
    (s) => String(s.series_name || s.seriesName || '').trim().toUpperCase() === cleanName && (s.is_active ?? s.isActive ?? true)
  );
  if (exact && Number(exact.ticket_price || exact.ticketPrice) > 0) {
    return Number(exact.ticket_price || exact.ticketPrice);
  }

  // 2. Derive unit rate from Series 100
  const s100 = seriesPricesCache.find(
    (s) => String(s.series_name || s.seriesName || '').trim() === '100' && (s.is_active ?? s.isActive ?? true)
  );
  const s100Price = s100 ? Number(s100.ticket_price || s100.ticketPrice) : 600.0;
  const perSeriesRate = s100Price >= 100 ? (s100Price / 100.0) : (s100Price > 0 ? s100Price : 6.0);

  const digits = cleanName.replace(/\D/g, '');
  const multiplier = parseFloat(digits);
  if (!isNaN(multiplier) && multiplier > 0) {
    return multiplier * perSeriesRate;
  }
  return 600.0;
}

// Refresh dynamic caches every 30 seconds
setInterval(() => {
  refreshLearnedPatterns();
  refreshSeriesPrices();
  syncRecentBookingsForDuplicateGuard();
}, 30000);

// Initial cache load
refreshLearnedPatterns();
refreshSeriesPrices();
syncRecentBookingsForDuplicateGuard();

// Global Engine State
let sock = null;
let connectionStatus = 'disconnected'; // 'disconnected' | 'connecting' | 'qr_ready' | 'connected'
let currentQrRaw = null;
let currentQrDataUrl = null;
let processedTotalCount = 0;
let lastFlushTimestamp = null;
const recentLogs = [];

// High-speed In-Memory Queue Buffer
let messageBuffer = [];
let isFlushing = false;

// Silence internal Baileys logging to prevent stdout bottlenecks at 1000+ msgs/min
const baileysLogger = pino({ level: 'silent' });

function appendLog(level, message, data = null) {
  const logItem = {
    time: new Date().toLocaleTimeString(),
    level,
    message,
    data,
  };
  recentLogs.push(logItem);
  if (recentLogs.length > 100) recentLogs.shift();
  try {
    console.log(`[${logItem.time}] [${level.toUpperCase()}] ${message}`);
  } catch (_) {}
}

/**
 * 👁️ GEMINI VISION AI OCR ENGINE
 * Extracts 5-digit ticket numbers & series from image buffer (photos, slips, handwritten parchas)
 */
async function extractTicketsFromImageViaGemini(imageBuffer, mimeType = 'image/jpeg') {
  let apiKey = process.env.GEMINI_API_KEY || '';
  if (!apiKey && localDb) {
    try {
      const row = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'gemini_api_key' LIMIT 1").get();
      if (row && row.value) apiKey = row.value;
    } catch (_) {}
  }

  if (!apiKey) {
    appendLog('warn', '⚠️ [GEMINI VISION AI] GEMINI_API_KEY is not set. Please set GEMINI_API_KEY in .env or Settings to scan photos!');
    return '';
  }

  const base64Data = imageBuffer.toString('base64');
  const prompt = `You are a high-accuracy OCR for handwritten Indian lottery slips (parchas).
Analyze this lottery parcha/slip image carefully and extract ALL 5-digit lottery ticket numbers and series.

CRITICAL RULES:
1. Multi-Column Structure: The slip is organized into vertical columns from left to right.
   You MUST read strictly COLUMN-BY-COLUMN from TOP TO BOTTOM:
   - Read Column 1 (leftmost column) completely from top to bottom.
   - Then read Column 2 completely from top to bottom.
   - Then read Column 3 completely from top to bottom.
   - Then read Column 4 completely from top to bottom.
   - Then read Column 5 completely from top to bottom.
   DO NOT read across rows horizontally. DO NOT skip or rearrange lines.

2. Series Header: If a series is written at the top of the slip (e.g. "24 सीरीज", "24", "12 Series", "36"), apply that series to all tickets unless a column has a different series.

3. Ticket Numbers: Every ticket is a 5-digit number (e.g. 45385, 55385, 65385).

4. Output Format: Return each ticket line by line in standard notation:
   <series>=<ticketNo>
   or
   <ticketNo>*<series>

Example:
24=45385
24=55385
24=65385

Output ONLY the ticket lines in exact physical sequence. No commentary, no codeblocks.`;

  const candidateModels = [
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
    'gemini-flash-latest',
  ];

  for (const modelName of candidateModels) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`;
        const response = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [
              {
                parts: [
                  { text: prompt },
                  {
                    inlineData: {
                      mimeType: mimeType || 'image/jpeg',
                      data: base64Data,
                    },
                  },
                ],
              },
            ],
            generationConfig: {
              temperature: 0.1,
              maxOutputTokens: 4096,
            },
          }),
        });

        if (!response.ok) {
          const errText = await response.text();
          if ((response.status === 503 || response.status === 429) && attempt === 1) {
            appendLog('warn', `⚠️ [GEMINI VISION AI] Model ${modelName} returned HTTP ${response.status} (High Demand). Retrying in 1.5s...`);
            await new Promise((r) => setTimeout(r, 1500));
            continue;
          }
          appendLog('warn', `⚠️ [GEMINI VISION AI] Model ${modelName} returned HTTP ${response.status}. Trying next model...`);
          break;
        }

        const data = await response.json();
        const extractedText = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
        appendLog('success', `📸 [GEMINI VISION AI (${modelName})] Scanned photo successfully! Extracted:\n${extractedText.trim()}`);
        return extractedText.trim();
      } catch (err) {
        appendLog('warn', `⚠️ [GEMINI VISION AI] Exception with ${modelName}: ${err.message}`);
        break;
      }
    }
  }

  appendLog('error', '❌ [GEMINI VISION AI] All candidate models failed to scan image.');
  return '';
}

/**
 * Intelligent WhatsApp message text parser for lottery tickets.
 * Handles single lines, bulk headers, ranges (e.g. 65491-95-5), and multipliers.
 */
/**
 * Extract pure numeric digits for Series (strips any letters, e.g. "12c" -> "12", "12s" -> "12", "12se" -> "12", "83L" -> "83", "SR-36" -> "36")
 * If no series digits exist, returns fallback ('') - ZERO DEFAULT 12 ASSUMPTIONS!
 */
function cleanSeriesNumber(rawSeries, fallback = '') {
  if (!rawSeries) return fallback;
  const str = String(rawSeries).trim();
  const digits = str.replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 4) {
    return digits;
  }
  return fallback;
}

/**
 * TOP PRIORITY #1 LOTTERY TICKET PARSER - SUPREME MASTER RULE
 * Rule 1: Fixed 5 Digits (e.g. 15204, 62393, 00123) -> ALWAYS 5-DIGIT TICKET NUMBER
 * Rule 2: 1 to 3 Digits with ANY suffix (c, s, se, ser, serial, l) or prefix (sr, s, c) -> ALWAYS PURE NUMERIC SERIES (e.g. 12c -> 12)
 * Rule 3: Series can be AAGE (before ticket) or PEECHE (after ticket) or STANDALONE HEADER
 * Rule 4: If no series is provided, sets series as '?' (NO SILENT DEFAULT) for UI highlight!
 */
function parseIncomingTicketText(text, defaultSeries = '') {
  // 1. Strip real dates (e.g. 13=8=2026, 14/08/2026, 14/08)
  const cleanedText = text
    .replace(/\b\d{1,2}[=\/\.-]\d{1,2}[=\/\.-]\d{2,4}(?:=[0-9A-Za-z]+)?\b/g, ' ')
    .replace(/\b\d{1,2}\/\d{1,2}\b/g, ' ');

  const items = [];
  const lines = cleanedText.split(/\r?\n/);
  let currentSeries = cleanSeriesNumber(defaultSeries, '');

  for (const line of lines) {
    let l = line.trim();
    if (!l) {
      currentSeries = '';
      continue;
    }

    // Ignore pure time tags and standalone noise lines
    if (/^(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)$/i.test(l) || /^(?:kal|tomorrow|aaj|today)$/i.test(l)) {
      continue;
    }
    // Skip booking header lines like "Rustam g booking", "Ram Kumar booking", "Rajiv booking"
    if (/^[A-Za-z][A-Za-z\s]{1,30}\s+(?:boakg|booking|bokg|bok|bkg)\s*$/i.test(l)) {
      continue;
    }
    // Skip forwarded message header lines
    if (/^(?:Forwarded|\u203A\u203A\s*Forwarded|fwd|forward)/i.test(l)) {
      continue;
    }

    // --- CASE A: Standalone Series Header e.g. "30", "12=", "12-", "12:", "12....", "12c", "12s", "12se", "12 serial", "(40c)", "40", "SERIES 24", "12" ---
    const headerMatch = l.match(/^(?:SERIES|SR|SER|SERI)?\s*[\(\[\{]?\s*([0-9]{1,3}\s*[A-Za-z]{0,8}|[A-Za-z]{1,4}\s*[0-9]{1,3})\s*[\)\]\}]?\s*[-:,\/=\s._~|*xX#@+]*$/i);
    if (
      headerMatch &&
      l.length <= 15 &&
      !/\d{5}/.test(l) &&
      !['qty', 'pcs', 'pm', 'am', 'dear', 'ok', 'hi', 'hello', 'thanks'].includes(l.toLowerCase())
    ) {
      const extracted = cleanSeriesNumber(headerMatch[1], '');
      if (extracted) {
        currentSeries = extracted;
        // 🔄 RETROACTIVE BACKFILL: If preceding items in the block were missing series ('?'), backfill them with this bottom series!
        for (let i = items.length - 1; i >= 0; i--) {
          if (!items[i].isSeriesLocked) {
            items[i].series = extracted;
            items[i].isSeriesLocked = true;
          } else {
            break;
          }
        }
        continue;
      }
    }

    const lineForTickets = l.replace(/(?:=|\b)(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)\b/gi, ' ').trim();

    // =========================================================================
    // MASTER RULE ENGINE:
    // Rule 1: 5-Digit (\d{5}) is ALWAYS the Ticket Number
    // Rule 2: 1, 2, or 3 digits (e.g. 12, 12), 12-, 12=, 12/, 12c, 36, 100) is ALWAYS the Series
    // Rule 3: '12) 12345-5' -> 5 consecutive tickets (12345 to 12349) with Series 12
    // Rule 4: '12 12345-12348' -> 4 tickets (12345 to 12348) with Series 12
    // =========================================================================

    // --- PATTERN 1: Range or Consecutive Count with optional Leading Series ---
    // Matches: '(24) 12345-5', '12) 12345-5', '12- 12345-12348', '12 12345-48', '12345-5'
    const rangeRegex = /(?:[\(\[\{]?\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[\)\]\}:,\/=\s._~|*xX#@+-]+\s*)?(\d{5})\s*(?:[-~to]+|\s+to\s+)\s*(\d{1,5})(?:\s*[-*=xX,\s._~|#@+]\s*(\d+))?/gi;
    let rMatch;
    let matchedRange = false;
    while ((rMatch = rangeRegex.exec(lineForTickets)) !== null) {
      if (rMatch[1] && /\d{5}/.test(rMatch[1])) continue;
      const s = rMatch[1] ? cleanSeriesNumber(rMatch[1], currentSeries) : currentSeries;
      const startNum = parseInt(rMatch[2], 10);
      const endPart = rMatch[3];

      if (!isNaN(startNum)) {
        let generatedTickets = [];

        // Case A: Full 5-Digit End Number e.g. 12345-12348 -> 12345 to 12348 (4 tickets)
        if (endPart.length === 5) {
          const endNum = parseInt(endPart, 10);
          if (endNum >= startNum && endNum - startNum <= 200) {
            for (let num = startNum; num <= endNum; num++) {
              generatedTickets.push(String(num).padStart(5, '0'));
            }
          }
        }
        // Case B: Explicit Count or Range
        else if (endPart.length >= 1 && endPart.length <= 3) {
          const countOrEnd = parseInt(endPart, 10);
          const last2Start = startNum % 100;
          const tens = Math.floor(last2Start / 10);
          const lastDigit = startNum % 10;

          // If endPart is a 2-digit number greater than last2Start (e.g. 12345-48 -> range to 48)
          if (endPart.length === 2 && countOrEnd > last2Start && countOrEnd - last2Start <= 50) {
            const prefix = Math.floor(startNum / 100);
            for (let last = last2Start; last <= countOrEnd; last++) {
              generatedTickets.push(`${prefix}${String(last).padStart(2, '0')}`);
            }
          }
          // If endPart is 1 digit ending digit greater than last digit (e.g. 12345-9 -> 12345..12349)
          else if (endPart.length === 1 && countOrEnd > lastDigit) {
            const prefix = Math.floor(startNum / 100);
            const endLast2 = tens * 10 + countOrEnd;
            for (let last = last2Start; last <= endLast2; last++) {
              generatedTickets.push(`${prefix}${String(last).padStart(2, '0')}`);
            }
          }
          // Otherwise, treat as consecutive ticket count (e.g. 12345-5 means 5 tickets starting at 12345)
          else if (countOrEnd > 0 && countOrEnd <= 100) {
            for (let c = 0; c < countOrEnd; c++) {
              generatedTickets.push(String(startNum + c).padStart(5, '0'));
            }
          }
        }

        if (generatedTickets.length > 0) {
          for (const tNo of generatedTickets) {
            items.push({
              series: s || '?',
              isSeriesLocked: Boolean(s),
              ticketNo: tNo,
              quantity: 1,
            });
          }
          currentSeries = s || currentSeries;
          matchedRange = true;
        }
      }
    }
    if (matchedRange) continue;

    // --- PATTERN 2: Series AAGE with optional brackets + Single 5-Digit Ticket: e.g. '(24)57655', '(24) 57655', '24) 57655', '[24]57655', '36 49151' ---
    const leadingRegex = /(?:^|[\s,;])(?:[\(\[\{]?\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[\)\]\}:,\/=\s._~|*xX#@+-]+|\((?:[0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\))\s*(\d{5})(?=[\s,;]|$)/gi;
    let lMatch;
    let matchedLeading = false;
    while ((lMatch = leadingRegex.exec(lineForTickets)) !== null) {
      if (!/\d{5}/.test(lMatch[1])) {
        const s = cleanSeriesNumber(lMatch[1], currentSeries);
        const tNo = lMatch[2];
        items.push({
          series: s || '?',
          isSeriesLocked: Boolean(s),
          ticketNo: tNo,
          quantity: 1,
        });
        currentSeries = s || currentSeries;
        matchedLeading = true;
      }
    }
    if (matchedLeading) continue;

    // --- PATTERN 3: Single 5-Digit Ticket + Series PEECHE with optional brackets: e.g. '57655(24)', '57655 (24)', '85638-6', '85638 = 6' ---
    const trailingRegex = /(?:^|[\s,;])(\d{5})\s*(?:[\)\]\}:,\/=\s._~|*xX#@+-]+|[\(\[\{])\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[\)\]\}]?(?=[\s,;]|$)/gi;
    let tMatch;
    let matchedTrailing = false;
    while ((tMatch = trailingRegex.exec(lineForTickets)) !== null) {
      if (!/\d{5}/.test(tMatch[2])) {
        const tNo = tMatch[1];
        const s = cleanSeriesNumber(tMatch[2], currentSeries);
        items.push({
          series: s || '?',
          isSeriesLocked: Boolean(s),
          ticketNo: tNo,
          quantity: 1,
        });
        currentSeries = s || currentSeries;
        matchedTrailing = true;
      }
    }
    if (matchedTrailing) continue;

    // --- PATTERN 4: Standalone 5-Digit tickets on the line: e.g. '12345', '12345 67890 54321' ---
    const all5s = lineForTickets.match(/\b\d{5}\b/g);
    if (all5s && all5s.length > 0) {
      for (const tNo of all5s) {
        items.push({
          series: currentSeries || '?',
          isSeriesLocked: Boolean(currentSeries),
          ticketNo: tNo,
          quantity: 1,
        });
      }
      continue;
    }
  }

  // --- DYNAMIC AI LEARNED PATTERNS PIPELINE ---
  if (items.length === 0 && learnedPatterns.length > 0) {
    for (const pattern of learnedPatterns) {
      try {
        const regex = new RegExp(pattern.regex_pattern, 'i');
        for (const line of lines) {
          const l = line.trim();
          if (!l) continue;
          const match = l.match(regex);
          if (match) {
            let s = defaultSeries;
            if (pattern.series_group_index > 0 && match[pattern.series_group_index]) {
              s = cleanSeriesNumber(match[pattern.series_group_index], defaultSeries);
            }
            let tNo = '';
            if (pattern.ticket_group_index > 0 && match[pattern.ticket_group_index]) {
              tNo = match[pattern.ticket_group_index];
            }
            let qty = 1;
            if (pattern.qty_group_index > 0 && match[pattern.qty_group_index]) {
              qty = parseInt(match[pattern.qty_group_index], 10) || 1;
            }
            if (tNo.length === 5) {
              items.push({
                series: s,
                ticketNo: tNo,
                quantity: qty > 0 ? qty : 1,
              });
            }
          }
        }
        if (items.length > 0) break;
      } catch (e) {
        // Skip malformed regex
      }
    }
  }

  return items;
}

/**
 * Extract explicit Shift, Date, Customer Name, and Greetings from message text
 * Strict Rules:
 *   - Greetings: 'hi', 'hello', 'namaste', 'gm', 'pranam', 'radhe radhe', 'ok', etc. -> ignored cleanly
 *   - Shifts: STRICTLY 'Dear 1 PM', 'Dear 6 PM', 'Dear 8 PM'
 *   - Dates: '14/08/2026', '14-08-2026', '14.08', '14/08', '15/08', 'kal', 'tomorrow', 'aaj', 'today'
 *   - Customer Names: 'Ramesh', 'Sonu', 'Customer: Ramesh', 'Party: Suresh', 'Ramesh booking'
 */
function extractExplicitShiftAndDate(text) {
  let explicitShift = null;
  let explicitDrawDate = null;
  let explicitBuyerName = null;
  let isGreeting = false;

  const cleanTrimmed = text.trim();
  const lower = cleanTrimmed.toLowerCase();

  // 1. Check for pure greetings / casual words
  const greetingRegex = /^\s*(?:hi+|he+l+o+|hlo+|hey+|namaste+|namaskar+|pranam+|radhe\s*radhe+|ram\s*ram+|jai\s*shree\s*ram+|good\s*morning|good\s*evening|gm|gn|kaise\s*ho|bhai|sir|boss|ok+|haan+|theek\s*hai|ha|haa|yes|no|thanks|thx|kya\s*haal|hello\s*bhai)\s*$/i;
  if (greetingRegex.test(cleanTrimmed)) {
    return {
      explicitShift: null,
      explicitDrawDate: null,
      explicitBuyerName: null,
      isGreeting: true,
    };
  }

  const nonCustomerWords = new Set([
    'hi', 'hello', 'ok', 'end', 'done', 'khatam', 'finish', 'close', 'stop', 'clear', 'samapt', 'khtm',
    'dear', 'today', 'tomorrow', 'kal', 'aaj', 'thanks', 'test', 'help', 'status', 'yes', 'no', 'pls', 'please',
    '1pm', '6pm', '8pm', '1 pm', '6 pm', '8 pm', '1baje', '6baje', '8baje', '1:00pm', '6:00pm', '8:00pm',
    'morning', 'day', 'evening', 'night', 'series', 'serial', 'nagaland', 'ticket', 'booking', 'bkg', 'bokg',
    'all', 'shift', 'shifts', 'qty', 'pcs', 'pic', 'amount', 'total', 'price', 'cash', 'upi', 'gpay', 'paytm'
  ]);

  // 2. Check Shift Tags (STRICTLY 1pm, 6pm, 8pm)
  if (/(?:=|\b)(?:dear\s*)?1(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?1(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*morning\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 1 PM';
  } else if (/(?:=|\b)(?:dear\s*)?6(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?6(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*day\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 6 PM';
  } else if (/(?:=|\b)(?:dear\s*)?8(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?8(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*(?:night|evening)\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 8 PM';
  }

  // 3. Check Date Tags (e.g. "13/08/2026", "13=8=2026", "13-08-2026", "13/08", "14.08")
  const fullDateMatch = text.match(/\b(\d{1,2})[=\/\.-](\d{1,2})[=\/\.-](\d{2,4})\b/);
  const slashDateMatch = text.match(/\b(\d{1,2})[=\/\.-](\d{1,2})\b/);
  const dateMatch = fullDateMatch || slashDateMatch;

  if (dateMatch) {
    const day = parseInt(dateMatch[1], 10);
    const month = parseInt(dateMatch[2], 10) - 1;
    let year = dateMatch[3] ? parseInt(dateMatch[3], 10) : new Date().getFullYear();
    if (year < 100) year += 2000;
    if (day >= 1 && day <= 31 && month >= 0 && month <= 11) {
      explicitDrawDate = new Date(year, month, day);
    }
  } else if (/\b(?:kal|tomorrow)\b/i.test(text)) {
    const tmrw = new Date();
    tmrw.setDate(tmrw.getDate() + 1);
    explicitDrawDate = new Date(tmrw.getFullYear(), tmrw.getMonth(), tmrw.getDate());
  } else if (/\b(?:aaj|today)\b/i.test(text)) {
    const today = new Date();
    explicitDrawDate = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  }

  // 4. Check for Customer / Party Name line by line (e.g. "mithu", "Sanni ji", "Ck booking", "Raman ji booking", "Customer: Sonu")
  const msgLines = cleanTrimmed.split(/\r?\n/);
  for (const rawL of msgLines) {
    const l = rawL.trim();
    if (!l) continue;

    // Pattern A: "Customer: Sonu", "Party: Ramesh", "Name: Sonu"
    const prefixMatch = l.match(/^\s*(?:customer|cust|client|name|naam|nam|party|party\s*name|start)\s*[:=-]?\s*([A-Za-z0-9\s]{2,25})\b/i);
    if (prefixMatch) {
      const cand = prefixMatch[1].trim();
      if (!nonCustomerWords.has(cand.toLowerCase()) && !/^\d+$/.test(cand)) {
        explicitBuyerName = cand;
        break;
      }
    }

    // Pattern B: "Sonu booking", "Sonu boakg", "Sonu bkg", "Sonu party"
    const suffixMatch = l.match(/^(?:name:?\s*)?([A-Za-z0-9\s]{2,25})\s+(?:boakg|booking|bokg|bok|bkg|party)\s*$/i);
    if (suffixMatch) {
      const cand = suffixMatch[1].trim();
      if (!nonCustomerWords.has(cand.toLowerCase()) && !/^\d+$/.test(cand)) {
        explicitBuyerName = cand;
        break;
      }
    }

    // Pattern C: Standalone pure name line e.g. "mithu", "Sanni ji", "Ck", "Raman ji", "Rustam g"
    if (
      /^[A-Za-z][A-Za-z0-9\s.]{1,25}$/i.test(l) &&
      !nonCustomerWords.has(l.toLowerCase()) &&
      !/^(?:date|time|[0-9\/\.=-]+)$/i.test(l) &&
      !/(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)/i.test(l) &&
      !/^\d{1,4}[csl]?$/i.test(l) &&
      !/\b\d{5}\b/.test(l)
    ) {
      explicitBuyerName = l;
      break;
    }
  }

  return {
    explicitShift,
    explicitDrawDate,
    explicitBuyerName,
    isGreeting: false,
  };
}

/**
 * Clean & resolve Seller/Customer Name and Agent Code from database or session
 * Ensures NO phone numbers, brackets, or "WA:" tags are attached to the name!
 */
function resolveSellerInfo(senderPhone, rawName) {
  let cleanName = (rawName || '').trim();
  let agentCode = 'AG-WA';

  if (cleanName.includes('(')) {
    cleanName = cleanName.replace(/\(.*?\)/g, '').trim();
  }
  if (cleanName.startsWith('WA:')) {
    cleanName = cleanName.replace(/^WA:\s*/i, '').trim();
  }
  // Strip trailing words like 'booking', 'boakg', 'bkg', 'party'
  cleanName = cleanName.replace(/\s+(?:boakg|booking|bokg|bok|bkg|party)\s*$/i, '').trim();

  if (localDb) {
    try {
      const cleanDigits = String(senderPhone || '').replace(/\D/g, '');
      const last10 = cleanDigits.length >= 10 ? cleanDigits.slice(-10) : cleanDigits;

      // 1. Search by exact name / accessKey in registered database
      if (cleanName && cleanName.toLowerCase() !== 'walk-in customer') {
        const rowByName = localDb.prepare(`
          SELECT name, accessKey FROM seller_customers 
          WHERE LOWER(name) = LOWER(?) OR LOWER(accessKey) = LOWER(?)
          LIMIT 1
        `).get(cleanName, cleanName);

        if (rowByName) {
          return { cleanName: rowByName.name, agentCode: rowByName.accessKey || 'AG-WA' };
        }
      }

      // 2. Search by Phone Number ONLY IF no explicit customer name was provided!
      if (!cleanName && last10) {
        const rowByPhone = localDb.prepare(`
          SELECT name, accessKey FROM seller_customers 
          WHERE phone LIKE ? OR phone = ?
          LIMIT 1
        `).get(`%${last10}%`, senderPhone);

        if (rowByPhone) {
          return { cleanName: rowByPhone.name, agentCode: rowByPhone.accessKey || 'AG-WA' };
        }
      }
    } catch (_) {}
  }

  if (!cleanName || cleanName.toLowerCase() === 'unknown' || cleanName.toLowerCase() === 'user') {
    cleanName = 'Walk-in Customer';
  }

  return { cleanName, agentCode };
}

/**
 * Nagaland Lottery Draw Shift & Date Window Calculator
 * Cycle Rules (Used when no explicit shift/date is given):
 *   - 06:00 AM to 12:55 PM  -> "Dear 1 PM", Draw Date = Today
 *   - 12:56 PM to 05:55 PM  -> "Dear 6 PM", Draw Date = Today
 *   - 05:56 PM to 07:55 PM  -> "Dear 8 PM", Draw Date = Today
 *   - 07:56 PM to 11:59 PM  -> "Dear 1 PM", Draw Date = Next Day (Tomorrow)
 *   - 12:00 AM to 05:59 AM  -> "Dear 1 PM", Draw Date = Today
 */
function getLotteryDrawShiftAndDate(timestamp) {
  let ts = timestamp;
  if (ts && ts < 10000000000) {
    ts = ts * 1000;
  }
  const d = ts ? new Date(ts) : new Date();
  const totalMins = d.getHours() * 60 + d.getMinutes();

  let drawName = 'Dear 1 PM';
  let drawCode = 'DEAR-1-PM';
  let targetDate = new Date(d);

  if (totalMins >= 360 && totalMins <= 775) {
    // 06:00 AM to 12:55 PM (360 - 775 mins)
    drawName = 'Dear 1 PM';
    drawCode = 'DEAR-1-PM';
  } else if (totalMins > 775 && totalMins <= 1075) {
    // 12:56 PM to 05:55 PM (776 - 1075 mins)
    drawName = 'Dear 6 PM';
    drawCode = 'DEAR-6-PM';
  } else if (totalMins > 1075 && totalMins <= 1195) {
    // 05:56 PM to 07:55 PM (1076 - 1195 mins)
    drawName = 'Dear 8 PM';
    drawCode = 'DEAR-8-PM';
  } else if (totalMins > 1195) {
    // 07:56 PM to 11:59 PM -> Next Day Dear 1 PM
    drawName = 'Dear 1 PM';
    drawCode = 'DEAR-1-PM';
    targetDate.setDate(targetDate.getDate() + 1);
  } else {
    // 12:00 AM to 05:59 AM -> Today Dear 1 PM
    drawName = 'Dear 1 PM';
    drawCode = 'DEAR-1-PM';
  }

  const drawDate = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate());

  return {
    drawName,
    drawCode,
    drawDate,
    saleDate: d,
  };
}

// --- 2. BATCH BUFFERING & SUPABASE BULK INGESTION ---
async function flushBufferToSupabase() {
  if (isFlushing || messageBuffer.length === 0 || !supabase) {
    return;
  }

  isFlushing = true;
  // Atomically splice batch out of memory buffer (swaps reference instantly)
  const batchToInsert = messageBuffer.splice(0, MAX_BUFFER_SIZE);

  try {
    const startTime = Date.now();
    


    // 2. Parse tickets and Auto-Book directly into ticket_sales table
    const ticketSalesBatch = [];
    for (const raw of batchToInsert) {
      const parsedTickets = parseIncomingTicketText(raw.message_text);

      if (parsedTickets.length === 0) {
        // Log clear warning for Invalid/Unrecognized format with sample valid format
        appendLog(
          'warn',
          `⚠️ [WRONG FORMAT] From: ${raw.sender} (${raw.sender_name || 'User'}) | Received: "${raw.message_text}" | ✅ Working Format: "12- 15204", "36 65491-95-5", or "12- 78476 = 10"`
        );
      } else {
        const preview = parsedTickets
          .slice(0, 3)
          .map((p) => `${p.series} #${p.ticketNo}${p.quantity > 1 ? ` (x${p.quantity})` : ''}`)
          .join(', ');
        
        // Resolve Target Shift & Date:
        // If message was queued with a locked session (_session* fields), use those directly.
        // Otherwise: Explicit Tag -> Sender Active Session -> Current Auto-Cycle
        const autoCycle = getLotteryDrawShiftAndDate(raw.message_timestamp);
        const explicit = extractExplicitShiftAndDate(raw.message_text);
        const session = senderSessions.get(raw.sender) || {};

        let targetShiftName, targetDrawDate, rawBuyerName;

        if (raw._sessionBuyerName || raw._sessionDrawShift || raw._sessionDrawDate) {
          // 🔒 LOCKED SESSION ENTRY: use session values strictly, allow explicit shift timing update
          targetShiftName = explicit.explicitShift || raw._sessionDrawShift || session.drawShift || autoCycle.drawName;
          targetDrawDate = raw._sessionDrawDate ? new Date(raw._sessionDrawDate) : (session.drawDate || autoCycle.drawDate);
          rawBuyerName = raw._sessionBuyerName || session.buyerName || raw.sender_name || '';
        } else {
          // Normal: Active session Party Name and Date CANNOT be overwritten by message content without 'end'
          const activeSessionDate  = session.drawDate  || null;
          const activeSessionShift = session.drawShift || null;
          const activeSessionBuyer = session.buyerName || null;
          
          // Timing/Shift can change dynamically inside session
          targetShiftName = explicit.explicitShift || activeSessionShift || autoCycle.drawName;
          // Date is locked to active session date
          targetDrawDate  = activeSessionDate || explicit.explicitDrawDate || autoCycle.drawDate;
          // Party Name is locked to active session buyer
          rawBuyerName    = activeSessionBuyer || explicit.explicitBuyerName || raw.sender_name || '';
        }

        const targetDrawCode = targetShiftName.replace(/\s+/g, '-').toUpperCase();
        const now = new Date();
        const targetSaleDate = new Date(
          targetDrawDate.getFullYear(), targetDrawDate.getMonth(), targetDrawDate.getDate(),
          now.getHours(), now.getMinutes(), now.getSeconds()
        );

        const isCustomTagged = !!(raw._sessionBuyerName || raw._sessionDrawShift || session.drawShift || session.drawDate);
        appendLog(
          'info',
          `📥 [PARSED -> ${targetShiftName} (${getLocalYmd(targetDrawDate)})${isCustomTagged ? ' *LOCKED*' : ''}] ${parsedTickets.length} ticket(s) from ${raw.sender}: ${preview}${parsedTickets.length > 3 ? ` (+${parsedTickets.length - 3} more)` : ''}`
        );

        const { cleanName: resolvedSellerName, agentCode: resolvedAgentCode } = resolveSellerInfo(raw.sender, rawBuyerName);

        let ticketIndex = 0;
        for (const t of parsedTickets) {
          ticketIndex++;
          const pricePerTicket = calculateSeriesPrice(t.series);
          // Pure rule: Each individual 5-digit ticket is strictly Quantity = 1
          const finalQty = 1;
          const totalAmount = pricePerTicket * finalQty;
          const uniqueSalt = Math.random().toString(36).substring(2, 8);

          ticketSalesBatch.push({
            id: `tkt_wa_${Date.now()}_${uniqueSalt}_${t.series}_${t.ticketNo}_${ticketIndex}`,
            receiptNumber: `REC-${t.series}-${t.ticketNo}`,
            buyerName: resolvedSellerName,
            buyerPhone: raw.sender,
            agentCode: resolvedAgentCode,
            agentName: resolvedSellerName,
            drawCode: targetDrawCode,
            drawName: targetShiftName,
            ticketSeries: t.series,
            ticketNumber: `${t.series} ${t.ticketNo}`,
            quantity: finalQty,
            pricePerTicket,
            totalAmount,
            commissionAmount: totalAmount * 0.05,
            status: 'sold',
            paymentMode: 'cash',
            saleDate: getLocalIsoString(targetSaleDate),
            drawDate: getLocalIsoString(targetDrawDate, true),
          });
        }
      }
    }

    if (ticketSalesBatch.length > 0) {
      // 1. Direct Local SQLite Fast Insert (Zero UI Lag / Instant Local Access)
      if (localDb) {
        try {
          const insertStmt = localDb.prepare(`
            INSERT OR REPLACE INTO ticket_sales (
              id, receiptNumber, buyerName, buyerPhone, agentCode, agentName,
              drawCode, drawName, ticketSeries, ticketNumber, quantity,
              pricePerTicket, totalAmount, commissionAmount, status, paymentMode,
              saleDate, drawDate
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `);

          localDb.exec('BEGIN TRANSACTION');
          for (const t of ticketSalesBatch) {
            insertStmt.run(
              t.id,
              t.receiptNumber,
              t.buyerName,
              t.buyerPhone,
              t.agentCode,
              t.agentName,
              t.drawCode,
              t.drawName,
              t.ticketSeries,
              t.ticketNumber,
              t.quantity,
              t.pricePerTicket,
              t.totalAmount,
              t.commissionAmount,
              t.status,
              t.paymentMode,
              t.saleDate,
              t.drawDate
            );
          }
          localDb.exec('COMMIT');
          appendLog('success', `💾 [LOCAL SQLITE] Saved ${ticketSalesBatch.length} ticket(s) directly to opscore_pro.db!`);
        } catch (localSqliteErr) {
          try { localDb.exec('ROLLBACK'); } catch (_) {}
          appendLog('warn', `⚠️ [LOCAL SQLITE ERROR] ${localSqliteErr.message}`);
        }
      }
    }

    const durationMs = Date.now() - startTime;
    processedTotalCount += ticketSalesBatch.length;
    lastFlushTimestamp = new Date().toISOString();
    if (ticketSalesBatch.length > 0) {
      appendLog(
        'success',
        `🚀 Booked ${ticketSalesBatch.length} ticket(s) in ${durationMs}ms (Total Booked: ${processedTotalCount})`
      );
    }
  } catch (err) {
    appendLog('error', `Flush exception: ${err.message}`);
    messageBuffer.unshift(...batchToInsert);
  } finally {
    isFlushing = false;
  }
}

// Periodic Ingestion Timer (Every 2000ms)
setInterval(() => {
  if (messageBuffer.length > 0) {
    flushBufferToSupabase();
  }
}, FLUSH_INTERVAL_MS);

// Safe writable session directory on Windows to prevent EPERM errors when installed in Program Files
function getAuthDir() {
  const baseDir = process.env.APPDATA || process.env.LOCALAPPDATA || process.env.USERPROFILE || 'C:\\Lottery_Reports';
  const targetDir = path.join(baseDir, 'OpsCore_Pro', 'whatsapp_session');
  try {
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
    }
    return targetDir;
  } catch (err) {
    try {
      const fallbackDir = path.join(process.cwd(), 'app_session');
      if (!fs.existsSync(fallbackDir)) {
        fs.mkdirSync(fallbackDir, { recursive: true });
      }
      return fallbackDir;
    } catch (_) {
      const cReportsDir = 'C:\\Lottery_Reports\\whatsapp_session';
      if (!fs.existsSync(cReportsDir)) {
        fs.mkdirSync(cReportsDir, { recursive: true });
      }
      return cReportsDir;
    }
  }
}

// --- 3. WHATSAPP BAILEYS CONNECTION MANAGEMENT ---
let isIntentionallyStopped = false;
let consecutiveDisconnects = 0;

async function startWhatsAppSocket() {
  if (sock && (connectionStatus === 'connected' || connectionStatus === 'connecting')) {
    appendLog('info', 'WhatsApp socket is already active or connecting.');
    return;
  }

  isIntentionallyStopped = false;
  connectionStatus = 'connecting';
  currentQrRaw = null;
  currentQrDataUrl = null;
  appendLog('info', 'Initializing WhatsApp socket session...');

  try {
    const authDir = getAuthDir();
    appendLog('info', `Using WhatsApp session storage: ${authDir}`);

    const { state, saveCreds } = await useMultiFileAuthState(authDir);
    let version = [2, 3000, 1043857760];
    try {
      const v = await fetchLatestBaileysVersion();
      if (v && v.version) {
        version = v.version;
      }
    } catch (_) {}

    sock = makeWASocket({
      version,
      logger: baileysLogger,
      printQRInTerminal: false,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, baileysLogger),
      },
      browser: Browsers.windows('Desktop'),
      syncFullHistory: false,
      markOnlineOnConnect: true,
      generateHighQualityLinkPreview: false,
      getMessage: async (key) => {
        return { conversation: '' };
      },
    });

    sock.ev.on('creds.update', async () => {
      try {
        if (!fs.existsSync(authDir)) {
          fs.mkdirSync(authDir, { recursive: true });
        }
        await saveCreds();
      } catch (err) {
        appendLog('error', `Error saving session credentials: ${err.message}`);
      }
    });

    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        currentQrRaw = qr;
        currentQrDataUrl = await QRCode.toDataURL(qr);
        connectionStatus = 'qr_ready';
        appendLog('info', 'QR Code generated! Scan via WhatsApp Mobile app.');
      }

      if (connection === 'close') {
        const statusCode = lastDisconnect?.error?.output?.statusCode;
        const isLoggedOut = statusCode === DisconnectReason.loggedOut;
        connectionStatus = 'disconnected';
        currentQrRaw = null;
        currentQrDataUrl = null;

        if (isIntentionallyStopped) {
          appendLog('info', '🛑 WhatsApp bot stopped by operator. (Auto-reconnect inactive)');
          return;
        }

        consecutiveDisconnects++;
        appendLog('warn', `Connection closed (Status: ${statusCode}, Failures: ${consecutiveDisconnects}). Logged Out: ${isLoggedOut}`);

        // If explicitly logged out, unauthorized, or repeated reconnection failures with invalid creds -> Purge session & show Fresh QR!
        if (isLoggedOut || statusCode === 401 || statusCode === 403 || statusCode === 411 || consecutiveDisconnects >= 2) {
          appendLog('warn', '🗑️ Session invalid or unlinked. Purging session storage for instant fresh QR...');
          try {
            if (fs.existsSync(authDir)) {
              fs.rmSync(authDir, { recursive: true, force: true });
            }
          } catch (delErr) {
            appendLog('error', `Could not delete session directory: ${delErr.message}`);
          }
          consecutiveDisconnects = 0;
          // Re-trigger start for fresh QR scan
          setTimeout(() => {
            if (!isIntentionallyStopped) startWhatsAppSocket();
          }, 1500);
        } else {
          // Temporary drop / restart required -> Auto-reconnect
          const delay = statusCode === DisconnectReason.restartRequired ? 1000 : 2500;
          appendLog('info', `🔄 Auto-reconnecting in ${delay}ms...`);
          setTimeout(() => {
            if (!isIntentionallyStopped) startWhatsAppSocket();
          }, delay);
        }
      } else if (connection === 'open') {
        consecutiveDisconnects = 0;
        connectionStatus = 'connected';
        currentQrRaw = null;
        currentQrDataUrl = null;
        appendLog('success', '✅ WhatsApp Connected Successfully & Ready for High-Traffic Stream!');
      }
    });

    // High-Speed Message Ingestion Hook
    sock.ev.on('messages.upsert', async (m) => {
      if (!m.messages || m.messages.length === 0) return;

      for (const msg of m.messages) {
        // Skip status broadcast stories only
        if (msg.key.remoteJid === 'status@broadcast') continue;

        const isFromMe = Boolean(msg.key.fromMe);
        const rawJid = msg.key.remoteJid || 'unknown';
        const sender = rawJid.replace(/@.+/, '').replace(/:.+/, '');
        const pushName = msg.pushName || (isFromMe ? 'Owner' : 'Customer');

        // Detect if the message contains an Image / Photo (direct photo or document image)
        const isImage = Boolean(
          msg.message?.imageMessage ||
          msg.message?.extendedTextMessage?.contextInfo?.quotedMessage?.imageMessage ||
          (msg.message?.documentMessage && msg.message?.documentMessage?.mimetype?.startsWith('image/'))
        );

        // Extract message text across all possible WhatsApp message payload structures
        let messageText =
          msg.message?.conversation ||
          msg.message?.extendedTextMessage?.text ||
          msg.message?.extendedTextMessage?.contextInfo?.quotedMessage?.conversation ||
          msg.message?.extendedTextMessage?.contextInfo?.quotedMessage?.extendedTextMessage?.text ||
          msg.message?.imageMessage?.caption ||
          msg.message?.videoMessage?.caption ||
          msg.message?.documentMessage?.caption ||
          msg.message?.listMessage?.description ||
          msg.message?.buttonsResponseMessage?.selectedDisplayText ||
          msg.message?.templateButtonReplyMessage?.selectedId ||
          msg.message?.interactiveResponseMessage?.body?.text ||
          msg.message?.viewOnceMessage?.message?.conversation ||
          msg.message?.viewOnceMessage?.message?.extendedTextMessage?.text ||
          msg.message?.viewOnceMessage?.message?.imageMessage?.caption ||
          msg.message?.viewOnceMessageV2?.message?.conversation ||
          msg.message?.viewOnceMessageV2?.message?.extendedTextMessage?.text ||
          msg.message?.viewOnceMessageV2?.message?.imageMessage?.caption ||
          msg.message?.documentWithCaptionMessage?.message?.documentMessage?.caption ||
          msg.message?.ephemeralMessage?.message?.conversation ||
          msg.message?.ephemeralMessage?.message?.extendedTextMessage?.text ||
          msg.message?.ephemeralMessage?.message?.imageMessage?.caption ||
          msg.message?.editedMessage?.message?.protocolMessage?.editedMessage?.conversation ||
          msg.message?.editedMessage?.message?.protocolMessage?.editedMessage?.extendedTextMessage?.text ||
          '';

        // 📸 Scan photo via Gemini Vision AI if image detected -> Queue for Operator Approval
        if (isImage) {
          appendLog('info', `📸 [IMAGE DETECTED] Downloading photo from ${sender}...`);
          try {
            const buffer = await downloadMediaMessage(
              msg,
              'buffer',
              {},
              {
                logger: baileysLogger,
                reuploadRequest: sock.updateMediaMessage,
              }
            );

            if (buffer && buffer.length > 0) {
              imageBase64Data = buffer.toString('base64');
              const mime = msg.message?.imageMessage?.mimetype || 'image/jpeg';
              const aiExtracted = await extractTicketsFromImageViaGemini(buffer, mime);
              if (aiExtracted && aiExtracted.trim().length > 0) {
                const rawParsed = parseIncomingTicketText(aiExtracted, '');
                const parsedTickets = rawParsed.map((t) => ({
                  series: t.series || '?',
                  ticketNo: t.ticketNo,
                  quantity: t.quantity || 1,
                  amount: calculateSeriesPrice(t.series || '?'),
                }));
                const session = senderSessions.get(sender) || {};
                const autoCycle = getLotteryDrawShiftAndDate(new Date());
                const targetShift = session.drawShift || autoCycle.drawName || 'Dear 1 PM';
                const targetDate = session.drawDate ? getLocalYmd(session.drawDate) : getLocalYmd(autoCycle.drawDate);
                const targetCustomer = session.buyerName || pushName || 'Walk-in Customer';
                const photoId = `photo_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

                if (localDb) {
                  try {
                    localDb.prepare(`
                      INSERT INTO pending_photo_bookings (
                        id, senderPhone, buyerName, drawShift, drawDate,
                        imageBase64, extractedText, parsedTicketsJson, status, createdAt
                      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
                    `).run(
                      photoId,
                      sender,
                      targetCustomer,
                      targetShift,
                      targetDate,
                      imageBase64Data,
                      aiExtracted,
                      JSON.stringify(parsedTickets),
                      new Date().toISOString()
                    );
                  } catch (dbErr) {
                    appendLog('error', `❌ [PENDING PHOTO DB ERROR] ${dbErr.message}`);
                  }
                }

                appendLog(
                  'success',
                  `📸 [PHOTO HELD FOR OPERATOR APPROVAL] ${parsedTickets.length} ticket(s) extracted for "${targetCustomer}" (${targetShift}). Queued for Operator confirmation on desktop!`
                );
              }
            }
          } catch (mediaErr) {
            appendLog('error', `❌ [IMAGE DOWNLOAD ERROR] ${mediaErr.message}`);
          }
          // Photos MUST NEVER auto-book directly! Skip further processing.
          continue;
        }

        if (!messageText || messageText.trim().length === 0) continue;

        // 0. Check for End / Close Customer & Date Session command (e.g. "End", "Done", "Khatam", "Finish", "Close", "Stop")
        const isEndCommand = /^\s*(?:end|finish|done|khatam|close|stop|completed|ok\s*end|clear|samapt|khtm)\s*(?:booking|session|customer|party|date)?\s*$/i.test(messageText.trim());
        if (isEndCommand) {
          const session = senderSessions.get(sender) || {};
          const prevName = session.buyerName || 'Active Customer';
          const prevDate = session.drawDate ? getLocalYmd(session.drawDate) : 'Today';
          senderSessions.delete(sender);
          appendLog(
            'success',
            `🛑 [SESSION CLOSED] Closed booking session for "${prevName}" (Date: ${prevDate}) (${sender}). Ready for next session!`
          );
          continue;
        }

        // ─── UNIVERSAL SMART MESSAGE & TICKET PARSER ───────────────────────────
        const existingSession = senderSessions.get(sender) || {};
        const explicit = extractExplicitShiftAndDate(messageText);

        // 1. Ignore casual greetings & chatter cleanly
        if (explicit.isGreeting) {
          appendLog(
            'info',
            `👋 [GREETING] ${sender} (${pushName || 'User'}): "${messageText.trim()}" (Ignored)`
          );
          continue;
        }

        // 2. Active Session Management (Strict Party & Date Locking Rules)
        let sessionUpdated = false;

        // Dynamic Shift / Timing CAN CHANGE at any time during session
        if (explicit.explicitShift) {
          if (existingSession.drawShift !== explicit.explicitShift) {
            existingSession.drawShift = explicit.explicitShift;
            sessionUpdated = true;
          }
        }

        // Draw Date: Strictly LOCKED once set! Cannot change without 'end' message
        if (explicit.explicitDrawDate) {
          if (!existingSession.drawDate) {
            existingSession.drawDate = explicit.explicitDrawDate;
            sessionUpdated = true;
          }
        }

        // Customer / Party Name: Strictly LOCKED once set! Cannot change without 'end' message
        if (explicit.explicitBuyerName) {
          if (!existingSession.buyerName) {
            existingSession.buyerName = explicit.explicitBuyerName;
            sessionUpdated = true;
          }
        }

        if (sessionUpdated) {
          existingSession.lastUpdated = Date.now();
          senderSessions.set(sender, existingSession);
        }

        // 3. Attempt parsing ticket numbers from message
        const parsedTickets = parseIncomingTicketText(messageText, existingSession.lastSeries || '12');

        if (parsedTickets.length > 0) {
          // Resolve target Shift, Date, and Customer from locked session
          const autoCycle = getLotteryDrawShiftAndDate(new Date());
          const targetShift = existingSession.drawShift || autoCycle.drawName || 'Dear 1 PM';
          const targetDate = existingSession.drawDate || autoCycle.drawDate || new Date();
          const targetBuyer = existingSession.buyerName || pushName || (`Party ${sender.slice(-4)}`);

          const preview = parsedTickets.slice(0, 3).map((p) => `${p.series} #${p.ticketNo}`).join(', ');
          appendLog(
            'info',
            `📥 [TICKETS BOOKED -> ${targetShift} (${getLocalYmd(targetDate)}) | Party: ${targetBuyer}] ${parsedTickets.length} ticket(s) from ${sender}: ${preview}${parsedTickets.length > 3 ? ` (+${parsedTickets.length - 3} more)` : ''}`
          );

          const ticketEntry = {
            sender,
            sender_name: targetBuyer,
            message_text: messageText.trim(),
            message_timestamp: Number(msg.messageTimestamp || Date.now()),
            status: 'pending',
            _sessionBuyerName: targetBuyer,
            _sessionDrawShift: targetShift,
            _sessionDrawDate: getLocalIsoString(targetDate, true),
          };

          existingSession.lastSeries = parsedTickets[parsedTickets.length - 1].series;
          senderSessions.set(sender, existingSession);

          messageBuffer.push(ticketEntry);
          if (messageBuffer.length >= MAX_BUFFER_SIZE) {
            flushBufferToSupabase();
          }
          continue;
        }

        // If NO tickets were found:
        // Case A: Message was configuring Shift, Date, or Customer Name -> confirm and log
        if (sessionUpdated) {
          appendLog(
            'success',
            `⚙️ [SESSION ACTIVE] ${sender} -> Party: "${existingSession.buyerName || 'Auto'}" | Shift: "${existingSession.drawShift || 'Auto'}" | Date: "${existingSession.drawDate ? getLocalYmd(existingSession.drawDate) : 'Today'}"`
          );
          continue;
        }

        // Case 2: Unknown 5-Digit Ticket format -> Save to Resolver for Operator Training
        if (/\b\d{5}\b/.test(messageText)) {
          if (supabase) {
            supabase
              .from('unparsed_messages')
              .insert({
                raw_text: messageText.trim(),
                sender_phone: sender,
                sender_name: pushName || null,
                status: 'pending',
              })
              .then(() => {});
          }
          appendLog(
            'warn',
            `⚠️ [SAVED TO RESOLVER] Unknown ticket format from ${sender} (${pushName || 'User'}): "${messageText.trim()}" -> Added to Resolver Queue`
          );
        } else {
          // Case 3: Regular chat / text message
          appendLog(
            'info',
            `💬 [CHAT] ${sender} (${pushName || 'User'}): "${messageText.trim().substring(0, 50)}"`
          );
        }

        // Remember last used series in session for seamless subsequent single tickets
        if (parsedTickets.length > 0) {
          session.lastSeries = parsedTickets[parsedTickets.length - 1].series;
          senderSessions.set(sender, session);
        }

        // 📸 IF MESSAGE WAS AN IMAGE/PHOTO: Queue into pending_photo_bookings for OPERATOR REVIEW (Human-in-the-Loop)!
        if (isImage && imageBase64Data && parsedTickets.length > 0) {
          const photoId = `photo_${Date.now()}_${sender.slice(-6)}`;
          const buyer = session.buyerName || pushName || 'Walk-in Customer';
          const shift = session.drawShift || 'Dear 1 PM';
          const dateStr = session.drawDate ? getLocalYmd(session.drawDate) : getLocalYmd(new Date());

          if (localDb) {
            try {
              localDb.prepare(`
                INSERT INTO pending_photo_bookings (id, senderPhone, buyerName, drawShift, drawDate, imageBase64, extractedText, parsedTicketsJson, status, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
              `).run(
                photoId,
                sender,
                buyer,
                shift,
                dateStr,
                imageBase64Data,
                messageText.trim(),
                JSON.stringify(parsedTickets),
                new Date().toISOString()
              );
              appendLog(
                'warn',
                `📸 [PHOTO HELD FOR OPERATOR APPROVAL] ${parsedTickets.length} ticket(s) scanned from "${buyer}" (${sender}). Queued in Ticket Booking Counter for operator confirmation!`
              );
            } catch (pErr) {
              appendLog('error', `Could not save pending photo: ${pErr.message}`);
            }
          }
          continue; // Skip automatic instant direct entry for photos! Wait for operator review!
        }

        // Push ONLY valid ticket booking entries into In-Memory Buffer
        const entry = {
          sender,
          sender_name: pushName,
          message_text: messageText.trim(),
          message_timestamp: Number(msg.messageTimestamp || Date.now()),
          status: 'pending',
        };

        messageBuffer.push(entry);

        // Immediate flush trigger if buffer hits threshold capacity (e.g. 100 msgs)
        if (messageBuffer.length >= MAX_BUFFER_SIZE) {
          flushBufferToSupabase();
        }
      }
    });
  } catch (err) {
    connectionStatus = 'disconnected';
    appendLog('error', `Failed to initialize WhatsApp socket: ${err.message}`);
  }
}

async function stopWhatsAppSocket() {
  isIntentionallyStopped = true;
  if (!sock) {
    connectionStatus = 'disconnected';
    return;
  }
  try {
    appendLog('info', 'Stopping WhatsApp socket gracefully...');
    // Flush remaining buffer before stopping
    if (messageBuffer.length > 0) {
      await flushBufferToSupabase();
    }
    sock.end(undefined);
    sock = null;
    connectionStatus = 'disconnected';
    currentQrRaw = null;
    currentQrDataUrl = null;
    appendLog('info', 'WhatsApp socket stopped.');
  } catch (err) {
    appendLog('error', `Error stopping socket: ${err.message}`);
  }
}

// --- 4. EXPRESS REST API SERVER ---
const app = express();
app.use(cors());
app.use(express.json());

// Endpoint: Health & System Status
app.get('/status', (req, res) => {
  res.json({
    online: true,
    connectionStatus,
    isConnected: connectionStatus === 'connected',
    hasQr: Boolean(currentQrDataUrl),
    qrDataUrl: currentQrDataUrl,
    processedTotalCount,
    currentBufferSize: messageBuffer.length,
    lastFlushTimestamp,
    supabaseConfigured: Boolean(supabase),
    uptimeSeconds: Math.floor(process.uptime()),
  });
});

// Endpoint: Get Live QR Code
app.get('/qr', (req, res) => {
  res.json({
    connectionStatus,
    qrRaw: currentQrRaw,
    qrDataUrl: currentQrDataUrl,
  });
});

// Endpoint: Start WhatsApp Bot
app.post('/start', async (req, res) => {
  // Allow passing SUPABASE_URL / SUPABASE_KEY dynamically from Flutter GUI if provided
  if (req.body?.supabaseUrl && req.body?.supabaseKey) {
    supabase = createClient(req.body.supabaseUrl, req.body.supabaseKey, {
      auth: { persistSession: false },
    });
    appendLog('info', 'Supabase credentials updated dynamically from GUI.');
  }

  startWhatsAppSocket();
  res.json({ success: true, message: 'WhatsApp engine starting...', status: connectionStatus });
});

// Endpoint: Stop WhatsApp Bot
app.post('/stop', async (req, res) => {
  await stopWhatsAppSocket();
  processedTotalCount = 0;
  messageBuffer.length = 0;
  res.json({ success: true, message: 'WhatsApp engine stopped.', status: connectionStatus });
});

// Endpoint: Get Recent Logs for Flutter Terminal UI
app.get('/logs', (req, res) => {
  res.json({
    logs: recentLogs,
    bufferCount: messageBuffer.length,
    processedTotalCount,
  });
});

// Endpoint: Clear Logs from Terminal UI
app.post('/clear-logs', (req, res) => {
  recentLogs.length = 0;
  res.json({ success: true, message: 'Logs cleared.' });
});

// Endpoint: Reset Booked Tickets Counter
app.post('/reset-count', (req, res) => {
  processedTotalCount = 0;
  appendLog('info', '🔄 Booked tickets counter reset to 0 by operator.');
  res.json({ success: true, message: 'Counter reset to 0.', processedTotalCount });
});

// Endpoint: Disconnect & Switch WhatsApp Account (Purges session for fresh QR)
app.post('/unlink', async (req, res) => {
  try {
    appendLog('warn', '🔄 Unlinking active WhatsApp account and purging session...');
    consecutiveDisconnects = 0;
    if (sock) {
      try {
        await sock.logout();
      } catch (_) {
        try { sock.end(undefined); } catch (__) {}
      }
      sock = null;
    }
    connectionStatus = 'disconnected';
    currentQrRaw = null;
    currentQrDataUrl = null;
    recentLogs.length = 0;
    messageBuffer.length = 0;

    const authDir = getAuthDir();
    if (fs.existsSync(authDir)) {
      fs.rmSync(authDir, { recursive: true, force: true });
    }
    appendLog('info', '✅ Session purged. Generating new QR code for new WhatsApp account...');
    // Re-trigger start for fresh QR scan
    setTimeout(() => startWhatsAppSocket(), 1000);
    res.json({ success: true, message: 'Account unlinked. New QR code generating...' });
  } catch (err) {
    appendLog('error', `Error unlinking account: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// Endpoint: Get Gemini AI Configuration
app.get('/api/settings/ai', (req, res) => {
  let apiKey = process.env.GEMINI_API_KEY || '';
  if (!apiKey && localDb) {
    try {
      const row = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'gemini_api_key' LIMIT 1").get();
      if (row && row.value) apiKey = row.value;
    } catch (_) {}
  }
  const isConfigured = Boolean(apiKey && apiKey.length > 10);
  const maskedKey = isConfigured ? `${apiKey.slice(0, 6)}...${apiKey.slice(-4)}` : '';
  res.json({ success: true, isConfigured, maskedKey });
});

// Endpoint: Update Gemini AI Configuration
app.post('/api/settings/ai', (req, res) => {
  const { apiKey } = req.body || {};
  nm
  if (!apiKey || typeof apiKey !== 'string') {
    return res.status(400).json({ error: 'Valid Gemini API key is required' });
  }
  process.env.GEMINI_API_KEY = apiKey.trim();
  if (localDb) {
    try {
      localDb.prepare(`
        INSERT INTO ai_settings (key, value, updatedAt)
        VALUES ('gemini_api_key', ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
      `).run(apiKey.trim(), new Date().toISOString());
    } catch (dbErr) {
      appendLog('error', `Could not save AI setting to SQLite: ${dbErr.message}`);
    }
  }
  appendLog('success', '🔑 [GEMINI VISION AI] Gemini API Key updated successfully!');
  res.json({ success: true, message: 'Gemini Vision AI key saved successfully!' });
});

// Endpoint: Get all Pending Photo Bookings
app.get('/api/pending-photos', (req, res) => {
  if (!localDb) {
    return res.json({ success: true, photos: [] });
  }
  try {
    const rows = localDb.prepare(`
      SELECT id, senderPhone, buyerName, drawShift, drawDate, imageBase64, extractedText, parsedTicketsJson, status, createdAt
      FROM pending_photo_bookings
      WHERE status = 'pending'
      ORDER BY createdAt DESC
    `).all();
    res.json({ success: true, photos: rows || [] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Endpoint: Mark Pending Photo as Approved or Rejected
app.post('/api/pending-photos/:id/status', (req, res) => {
  const { id } = req.params;
  const { status } = req.body || {};
  if (!['approved', 'rejected'].includes(status)) {
    return res.status(400).json({ error: 'Status must be approved or rejected' });
  }
  if (!localDb) {
    return res.json({ success: true });
  }
  try {
    localDb.prepare('UPDATE pending_photo_bookings SET status = ? WHERE id = ?').run(status, id);
    res.json({ success: true, id, status });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Endpoint: Parse Lottery Result PDF natively
app.post('/api/parse-pdf', async (req, res) => {
  const { filePath } = req.body || {};
  if (!filePath || !fs.existsSync(filePath)) {
    return res.status(400).json({ error: 'File path invalid or not found' });
  }
  try {
    const { parseLotteryPdf } = require('./parse_pdf');
    const parsed = await parseLotteryPdf(filePath);
    res.json({ success: true, ...parsed });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Start Express Server & Auto-Start Socket
app.listen(PORT, '127.0.0.1', () => {
  appendLog('info', `⚡ WhatsApp Engine REST API listening on http://127.0.0.1:${PORT}`);
  // Immediately initialize WhatsApp socket on startup for instant QR / connection
  startWhatsAppSocket();
});
