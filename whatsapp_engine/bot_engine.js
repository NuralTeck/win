/**
 * ==============================================================================
 * HIGH-THROUGHPUT WHATSAPP ENTRY LOGGING ENGINE (STRICT LOCK VERIFIED)
 * Built with Node.js, Express, Baileys & Local SQLite
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
const pino = require('pino');
const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { DatabaseSync } = require('node:sqlite');

// --- 1. CONFIGURATION & STATE ---
const PORT = process.env.PORT || 4000;
const FLUSH_INTERVAL_MS = parseInt(process.env.BUFFER_FLUSH_INTERVAL_MS || '2000', 10);
const MAX_BUFFER_SIZE = parseInt(process.env.BUFFER_MAX_SIZE || '100', 10);

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
    CREATE TABLE IF NOT EXISTS ticket_sales (
      id TEXT PRIMARY KEY,
      receiptNumber TEXT,
      buyerName TEXT,
      buyerPhone TEXT,
      agentCode TEXT,
      agentName TEXT,
      drawCode TEXT,
      drawName TEXT,
      ticketSeries TEXT,
      ticketNumber TEXT,
      quantity INTEGER,
      pricePerTicket REAL,
      totalAmount REAL,
      commissionAmount REAL,
      status TEXT,
      paymentMode TEXT,
      saleDate TEXT,
      drawDate TEXT
    );
    CREATE TABLE IF NOT EXISTS unparsed_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sender TEXT NOT NULL,
      sender_name TEXT,
      raw_message TEXT NOT NULL,
      status TEXT DEFAULT 'pending',
      received_at TEXT NOT NULL,
      resolved_at TEXT
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
  console.log('⚠️ [LOCAL SQLITE] Could not open local SQLite db:', sqliteErr.message);
}

process.stdout?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});
process.stderr?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});

process.on('uncaughtException', (err) => {
  if (err?.code === 'EPIPE' || err?.message?.includes('EPIPE')) return;
  try { appendLog('warn', `🛡️ [CRASH GUARD] Exception: ${err?.message || err}`); } catch (_) { }
});
process.on('unhandledRejection', (reason) => {
  try { appendLog('warn', `🛡️ [CRASH GUARD] Rejection: ${reason?.message || reason}`); } catch (_) { }
});

// 🔒 GLOBAL STRICT TARGET LOCK
let globalTargetConfig = {
  lockedShift: 'Dear 8 PM',
  lockedDate: '2026-09-02',
  lockedBuyerName: '',
  strictLockEnabled: true,
};

function readLiveTargetLock() {
  if (!localDb) return;
  try {
    const rowShift = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'bot_locked_shift' LIMIT 1").get();
    if (rowShift && rowShift.value && rowShift.value.trim().length > 0) {
      globalTargetConfig.lockedShift = rowShift.value.trim();
    }

    const rowDate = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'bot_locked_date' LIMIT 1").get();
    if (rowDate && rowDate.value && rowDate.value.trim().length >= 8) {
      globalTargetConfig.lockedDate = rowDate.value.trim();
    }

    const rowBuyer = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'bot_locked_buyer' LIMIT 1").get();
    if (rowBuyer && rowBuyer.value !== undefined) {
      globalTargetConfig.lockedBuyerName = rowBuyer.value.trim();
    }

    const rowStrict = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'bot_strict_lock' LIMIT 1").get();
    if (rowStrict && rowStrict.value) {
      globalTargetConfig.strictLockEnabled = (rowStrict.value === '1' || rowStrict.value === 'true');
    }
  } catch (_) { }
}

function getEffectiveTarget(senderPhone) {
  readLiveTargetLock();

  // 1. Shift (GUI Lock strictly takes precedence)
  let shift = 'Dear 8 PM';
  if (globalTargetConfig.lockedShift && globalTargetConfig.lockedShift !== 'auto' && globalTargetConfig.lockedShift.trim().length > 0) {
    shift = globalTargetConfig.lockedShift.trim();
  }

  // 2. Date (GUI Lock strictly takes precedence)
  let date = new Date();
  if (globalTargetConfig.lockedDate && globalTargetConfig.lockedDate !== 'auto' && globalTargetConfig.lockedDate.trim().length >= 8) {
    const p = globalTargetConfig.lockedDate.trim().split('-');
    if (p.length === 3) {
      date = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
    }
  }

  // 3. Party Name (GUI Lock strictly takes precedence if set)
  let buyer = globalTargetConfig.lockedBuyerName ? globalTargetConfig.lockedBuyerName.trim() : '';
  if (!buyer || buyer.toLowerCase() === 'auto') {
    if (localDb) {
      try {
        const cleanDigits = String(senderPhone || '').replace(/\D/g, '');
        const last10 = cleanDigits.length >= 10 ? cleanDigits.slice(-10) : cleanDigits;
        if (last10) {
          const row = localDb.prepare(`
            SELECT name FROM seller_customers 
            WHERE phone LIKE ? OR phone = ? OR REPLACE(REPLACE(phone, ' ', ''), '+', '') LIKE ?
            LIMIT 1
          `).get(`%${last10}%`, senderPhone, `%${last10}%`);
          if (row && row.name && row.name.trim().length > 0) {
            buyer = row.name.trim();
          }
        }
      } catch (_) { }
    }
    if (!buyer) {
      buyer = `Party ${String(senderPhone).slice(-4)}`;
    }
  }

  return { targetShift: shift, targetDate: date, targetBuyer: buyer };
}

function getLocalYmd(d) {
  if (!d) return '';
  const dateObj = typeof d === 'string' ? new Date(d) : d;
  if (isNaN(dateObj.getTime())) return '';
  const year = dateObj.getFullYear();
  const month = String(dateObj.getMonth() + 1).padStart(2, '0');
  const day = String(dateObj.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

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

let seriesPricesCache = [];
async function refreshSeriesPrices() {
  try {
    if (localDb) {
      const rows = localDb.prepare('SELECT seriesName as series_name, ticketPrice as ticket_price, isActive as is_active FROM series_prices WHERE isActive = 1').all();
      if (rows && rows.length > 0) seriesPricesCache = rows;
    }
  } catch (_) { }
}

function calculateSeriesPrice(seriesName) {
  const cleanName = String(seriesName || '').trim().toUpperCase();
  const exact = seriesPricesCache.find(
    (s) => String(s.series_name || '').trim().toUpperCase() === cleanName
  );
  if (exact && Number(exact.ticket_price) > 0) {
    return Number(exact.ticket_price);
  }
  const digits = cleanName.replace(/\D/g, '');
  const mult = parseFloat(digits);
  if (!isNaN(mult) && mult > 0) {
    return mult * 2.25;
  }
  return 27.0; // Standard 12 series price (12 * 2.25 = ₹27)
}

setInterval(() => {
  readLiveTargetLock();
  refreshSeriesPrices();
}, 15000);

readLiveTargetLock();
refreshSeriesPrices();

let sock = null;
let connectionStatus = 'disconnected';
let currentQrRaw = null;
let currentQrDataUrl = null;
let processedTotalCount = 0;
let lastFlushTimestamp = null;
const recentLogs = [];

let messageBuffer = [];
let isFlushing = false;
const baileysLogger = pino({ level: 'silent' });

function appendLog(level, message) {
  const logItem = {
    time: new Date().toLocaleTimeString(),
    level,
    message,
  };
  recentLogs.push(logItem);
  if (recentLogs.length > 120) recentLogs.shift();
  try {
    console.log(`[${logItem.time}] [${level.toUpperCase()}] ${message}`);
  } catch (_) { }
}

let _botGeminiKeyIndex = 0;

/**
 * 👁️ GEMINI VISION AI OCR ENGINE FOR LOTTERY SLIPS / PHOTOS
 * Supports Multi-Key Load Balancing (Round-Robin) & Instant Failover
 */
async function extractTicketsFromImageViaGemini(imageBuffer, mimeType = 'image/jpeg') {
  let apiKeys = [];
  if (process.env.GEMINI_API_KEY) {
    apiKeys.push(process.env.GEMINI_API_KEY.trim());
  }
  if (localDb) {
    try {
      const row = localDb.prepare("SELECT value FROM ai_settings WHERE key = 'gemini_api_key' LIMIT 1").get();
      if (row && row.value) {
        const parsed = row.value.split(/[\r\n,;]+/).map(k => k.trim()).filter(k => k && !k.startsWith('#'));
        if (parsed.length > 0) apiKeys = parsed;
      }
    } catch (_) { }
  }

  if (apiKeys.length === 0) {
    appendLog('warn', '⚠️ [GEMINI VISION AI] GEMINI_API_KEY is not configured in Settings. Cannot scan photo!');
    return '';
  }

  // Round-Robin key rotation across requests
  const startIdx = _botGeminiKeyIndex % apiKeys.length;
  _botGeminiKeyIndex = (_botGeminiKeyIndex + 1) % apiKeys.length;
  const keyPool = [];
  for (let i = 0; i < apiKeys.length; i++) {
    keyPool.push(apiKeys[(startIdx + i) % apiKeys.length]);
  }

  const base64Data = imageBuffer.toString('base64');
  const prompt = `You are a high-accuracy OCR engine for Indian lottery parchas, handwritten slips, and printed ticket lists.
Analyze this lottery parcha/slip image carefully and extract ALL 5-digit lottery ticket numbers and their series.

CRITICAL READING RULES:
1. Column-by-Column: The slip is organized into vertical columns from left to right.
   Read strictly from TOP to BOTTOM in Column 1, then Column 2, etc.
2. 5-Digit Ticket Numbers: Every ticket is a 5-digit number (e.g. 12345, 84252, 90124).
3. Series: If series is written (e.g. "24", "12", "60", "24 Series"), output as <series>=<ticketNo> or <ticketNo> <series>.
4. Format: Output each ticket line by line. Nothing else. No commentary, no codeblocks.

Example:
24=45385
24=55385
12345 60`;

  const candidateModels = [
    'gemini-3.8-flash',
    'gemini-3.5-flash',
    'gemini-3.7-flash',
    'gemini-flash-latest',
  ];

  for (let kIdx = 0; kIdx < keyPool.length; kIdx++) {
    const currentKey = keyPool[kIdx];
    const keyShort = currentKey.length > 8 ? currentKey.substring(0, 8) + '...' : currentKey;

    for (const modelName of candidateModels) {
      for (let attempt = 1; attempt <= 2; attempt++) {
        try {
          const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${currentKey}`;
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
                temperature: 0.0,
                maxOutputTokens: 8192,
              },
            }),
          });

          if (!response.ok) {
            if ((response.status === 503 || response.status === 429) && kIdx < keyPool.length - 1) {
              appendLog('warn', `⚠️ [LOAD BALANCER] Key ${keyShort} hit HTTP ${response.status}. Auto-switching to next key...`);
              break; // Switch to next API Key in keyPool
            }
            if ((response.status === 503 || response.status === 429) && attempt === 1) {
              await new Promise((r) => setTimeout(r, 1000));
              continue;
            }
            break;
          }

          const data = await response.json();
          const extracted = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
          if (extracted && extracted.trim().length > 0) {
            appendLog('success', `📸 [GEMINI AI (${modelName} with Key ${keyShort})] Scanned image successfully! Extracted:\n${extracted.trim().substring(0, 100)}...`);
            return extracted.trim();
          }
        } catch (err) {
          appendLog('warn', `⚠️ [GEMINI AI] Key ${keyShort} on ${modelName} error: ${err.message}`);
          if (kIdx < keyPool.length - 1) break; // Switch to next key
          break;
        }
      }
    }
  }
  return '';
}

function cleanSeriesNumber(rawSeries, fallback = '12') {
  if (!rawSeries) return fallback;
  const digits = String(rawSeries).replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 4) {
    return digits;
  }
  return fallback;
}

function isDateOrTimeOrHeaderLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return true;

  // 🛑 Any line containing a 5-digit number is NOT a pure header!
  // It must go through strict pattern matching or be sent to unparsed queue.
  if (/\b\d{5}\b/.test(trimmed)) return false;

  // 1. WhatsApp forwarded / encryption / deleted / media noise
  if (/^(?:Messages and calls are end-to-end encrypted|This message was deleted|You deleted this message|<Media omitted>|You pinned a message)/i.test(trimmed)) return true;
  if (/^(?:Forwarded|\u203A\u203A\s*Forwarded|fwd|forward|\*forwarded\*)/i.test(trimmed)) return true;

  // 2. Chat greetings / casual chatter
  if (/^\s*(?:hi+|hello+|hlo+|hey+|ok+|haan+|ha+|namaste+|thanks|thx|bye|bhai|sir|boss|yes|no)\s*$/i.test(trimmed)) return true;

  // 3. Shift headers (e.g. "Start 8pm", "1:pm booking ab jayega", "Dear 1 PM", "8PM", "6PM", "1PM")
  if (/^(?:(?:dear\s*)?[168]\s*(?::\s*00)?\s*(?:pm|am|qm|gm|p|baje)|dear\s+[168])$/i.test(trimmed)) return true;
  if (/^(?:start\s+[168]|updated\s+[168]|[168]:?pm\s+booking|booking\s+ab\s+jayega)/i.test(trimmed)) return true;
  if (/^\b(?:morning|day|night|evening)\b$/i.test(trimmed)) return true;

  // 4. Booking meta lines (e.g. "S.k.booking", "Rustam g booking", "Laddu", "Updated 10/6/2026=1pm", "Ck booking")
  if (/^[A-Za-z0-9\s\.\/\-=]+\s+(?:boakg|booking|bookin|bokg|bok|bkg)\b/i.test(trimmed)) return true;
  if (/^(?:date\s*[:=\/\.-]?\s*\d{1,2}[\/\.-]\d{1,2}|time\s*[:=\/\.-]?\s*[168]\s*(?:pm|am|qm|gm|p|baje)?)/i.test(trimmed)) return true;


  // 4b. Mixed date and/or time and/or initials header (e.g. "8/6/26. Sk. 1:00 pm", "8/6/26 1pm", "1:00 pm Sk")
  if (/\b\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?\b/.test(trimmed) ||
      /\b(?:[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|p|baje)|dear\s+[168])\b/i.test(trimmed)) {
    const withoutDateAndTime = trimmed
      .replace(/\b\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?\b/g, '')
      .replace(/\b(?:\d{1,2}:\d{2}|[168](?::00|\.00|\.)?\s*(?:pm|am|qm|gm|p|baje)|dear\s+[168])\b/gi, '')
      .trim();
    if (!/\d{3,}/.test(withoutDateAndTime)) {
      return true;
    }
  }

  // 5. Divider lines / Punctuation noise
  if (/^[-=_*#]{3,}$/.test(trimmed)) return true;
  if (/^[.,;]+$/.test(trimmed)) return true;
  if (/^(?:shiv|radhe|om|jai)\b/i.test(trimmed)) return true;

  return false;
}

function isPureSeriesLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return false;

  // 1. MUST NOT contain any date pattern (e.g. 8/6/26, 08/06/2026, 8.6.26, 8-6-26)
  if (/\b\d{1,2}[\/\.-]\d{1,2}(?:[\/\.-]\d{2,4})?\b/.test(trimmed)) return false;

  // 2. MUST NOT contain any time pattern (e.g. 1pm, 6pm, 8pm, 1:00, 1 baje, 1qm, 6qm, am)
  if (/\b(?:\d{1,2}:\d{2}|[168]\s*(?::\s*00)?\s*(?:pm|am|qm|gm|p|baje)|dear\s+[168])\b/i.test(trimmed)) return false;

  // 3. MUST NOT contain 5 or more continuous digits (that's a ticket, not a series!)
  if (/\d{5}/.test(trimmed)) return false;

  // 4. Strict standalone series regex:
  // ONLY allowed:
  // "6", "12", "24", "40", "60", "100"
  // "(12)", "[24]"
  // "12c", "6c", "24c"
  // "Series 12", "Series: 24", "12 series", "60sirij"
  // ABSOLUTELY NO other words/letters allowed!
  const match = trimmed.match(/^(?:(?:\(|\[)\s*([0-9]{1,3})\s*(?:\)|\])|(?:series\s*[:=-]?\s*)?([0-9]{1,3})\s*(?:c|sirij|series)?)$/i);
  if (!match) return false;

  const digits = match[1] || match[2];
  if (!digits) return false;
  const val = parseInt(digits, 10);
  return val > 0 && val <= 120;
}

/**
 * Universal Strict Ticket Parser:
 * - 100% Pattern Match: Every valid line must fit 100% strictly into the defined patterns.
 * - Any stray letter, mixed word, or unrecognized line is pushed to unparsedLines.
 * - Standalone series lines strictly have NO letters, NO dates, NO times.
 * - Standalone ticket lines strictly have pure 5-digit numbers.
 */
function parseIncomingTicketText(text, defaultSeries = null) {
  const items = [];
  const unparsedLines = [];

  // Strip WhatsApp message metadata headers e.g. "9/3/26, 12:41 PM - Mama2: "
  const rawLines = text.split(/\r?\n/).map(l => {
    let s = l.trim();
    if (!s) return '';
    const waHeader = s.match(/^(?:\[\d{1,2}:\d{2}(?::\d{2})?\s*(?:[aApP][mM])?,\s*\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}\]|\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4},?\s+[\d:]+\s*(?:AM|PM|am|pm)?\s*[-~])\s*[^:]+:\s*(.*)$/);
    if (waHeader) {
      s = waHeader[1].trim();
    }
    return s;
  }).filter(l => l.length > 0);

  // NO SILENT ASSUMPTION: If the message does not have an explicit series header or inline series,
  // standalone tickets will NOT guess 12, they will safely go to unparsedLines.
  let currentSeries = defaultSeries ? cleanSeriesNumber(defaultSeries, null) : null;
  let hasExplicitSeriesAbove = Boolean(defaultSeries);

  // Look-ahead check: agar shuruat me koi series nahi hai aur aakhiri line series ho (reverse series lock)
  let bottomSeries = null;
  for (let idx = rawLines.length - 1; idx >= 0; idx--) {
    const cand = rawLines[idx].trim();
    if (/^(?:dear\s*)?[168]\s*(?::\s*00)?\s*(?:pm|am|qm|gm|p|baje)$/i.test(cand) ||
        /^(?:[168]\s*(?::\s*00)?\s*(?:pm|am|qm|gm|p)|dear\s+[168])/i.test(cand) ||
        isDateOrTimeOrHeaderLine(cand)) {
      continue;
    }
    if (isPureSeriesLine(cand)) {
      bottomSeries = cleanSeriesNumber(cand, null);
      if (!currentSeries) {
        currentSeries = bottomSeries;
      }
    }
    break;
  }

  for (let i = 0; i < rawLines.length; i++) {
    const line = rawLines[i].trim();
    if (!line) continue;

    // Check if line is a recognized non-ticket line (Header, Date, Shift, Greeting, Divider)
    if (isDateOrTimeOrHeaderLine(line)) {
      continue;
    }

    // Check if line is strict standalone series
    if (isPureSeriesLine(line)) {
      const extracted = cleanSeriesNumber(line, null);
      if (extracted) {
        currentSeries = extracted;
        hasExplicitSeriesAbove = true;
        for (let j = items.length - 1; j >= 0; j--) {
          if (!items[j].isSeriesLocked) {
            items[j].series = extracted;
            items[j].isSeriesLocked = true;
          } else break;
        }
        continue;
      }
    }

    // STRICT PATTERN 0: Comma range or double dot range e.g. 40350,,59,,10go,, 6c or 70480,,89,,12c,, 10go or 40350..59
    const commaRangeMatch = line.match(/^(\d{5})\s*(?:,,+|\.\.+|___+)\s*(\d{1,3})(?:\s*(?:,,+|\.\.+|___+).*?(?:([0-9]{1,3})[cs]|(?:[cs])\s*([0-9]{1,3})))?(?:\s*(?:pcs?|go|p))?\s*$/i);
    if (commaRangeMatch) {
      const startTktStr = commaRangeMatch[1];
      const endPartStr = commaRangeMatch[2];
      const serStr = commaRangeMatch[3] || commaRangeMatch[4];
      const s = serStr ? cleanSeriesNumber(serStr, currentSeries) : currentSeries;
      if (!s) {
        unparsedLines.push(line);
        continue;
      }
      const startNum = parseInt(startTktStr, 10);
      const prefix = startTktStr.slice(0, 5 - endPartStr.length);
      const endNum = parseInt(prefix + endPartStr, 10);

      if (!isNaN(startNum) && !isNaN(endNum) && endNum >= startNum && endNum - startNum <= 100) {
        for (let n = startNum; n <= endNum; n++) {
          items.push({
            series: s,
            isSeriesLocked: true,
            ticketNo: String(n).padStart(5, '0'),
          });
        }
        currentSeries = s;
        continue;
      }
    }

    // STRICT PATTERN 1: Triplet Range e.g. 62759-83-25 or 40280-289-10 or 43300-309=10 pcs
    const tripletMatch = line.match(/^(?:([0-9]{1,3}[A-Za-z]?)\s*[:=/]\s*)?(\d{5})\s*[-~to]+\s*(\d{1,5})\s*[-=x*,\s]+\s*(\d+)(?:\s*(?:pcs?|go|p))?\s*$/i);
    if (tripletMatch) {
      const s = tripletMatch[1] ? cleanSeriesNumber(tripletMatch[1], currentSeries) : currentSeries;
      if (!s) {
        unparsedLines.push(line);
        continue;
      }
      const startNum = parseInt(tripletMatch[2], 10);
      const count = parseInt(tripletMatch[4], 10);
      if (!isNaN(startNum) && count > 0 && count <= 150) {
        for (let k = 0; k < count; k++) {
          items.push({
            series: s,
            isSeriesLocked: true,
            ticketNo: String(startNum + k).padStart(5, '0'),
          });
        }
        currentSeries = s;
        continue;
      }
    }

    // STRICT PATTERN 2: Hyphen range e.g. 50170-189 or 24: 50170 to 50189 or 68150-159
    const hyphenMatch = line.match(/^(?:([0-9]{1,3}[A-Za-z]?)\s*[:=/]\s*)?(\d{5})\s*[-~/\s]*(?:to|se|-|\/)\s*(\d{1,5})$/i);
    if (hyphenMatch) {
      const s = hyphenMatch[1] ? cleanSeriesNumber(hyphenMatch[1], currentSeries) : currentSeries;
      if (!s) {
        unparsedLines.push(line);
        continue;
      }
      const startNum = parseInt(hyphenMatch[2], 10);
      const endPart = hyphenMatch[3];
      const prefix = String(startNum).slice(0, 5 - endPart.length);
      const fullEndNum = parseInt(prefix + endPart, 10);
      const isKnownSeries = ['6', '12', '18', '20', '24', '30', '36', '40', '48', '50', '60', '100'].includes(endPart.trim());
      const hasExplicitRange = line.includes('to') || line.includes('se') || String(startNum).endsWith('0');

      if (endPart.length >= 1 && (!isKnownSeries || hasExplicitRange) && !isNaN(startNum) && !isNaN(fullEndNum) && fullEndNum >= startNum && fullEndNum - startNum <= 150) {
        for (let n = startNum; n <= fullEndNum; n++) {
          items.push({
            series: s,
            isSeriesLocked: true,
            ticketNo: String(n).padStart(5, '0'),
          });
        }
        currentSeries = s;
        continue;
      }
    }

    // STRICT PATTERN 3: Prefix Series (Series MUST be clean digits, e.g. 6=83453, 24=43239, 12-42614, 24/81192, (24)79159, 12..44189, 36"61163)
    // 🛑 Strictly NO 1pm, 6pm, 8pm or words allowed!
    if (!/(?:pm|am|qm|gm|baje)\b/i.test(line)) {
      const prefixMatch = line.match(/^(?:[\(\[]\s*([0-9]{1,3}[cs]?)\s*[\)\]]|([0-9]{1,3}[cs]?)\s*(?:[:=/\-._~*#@+"\s]+))\s*(\d{5})$/i);
      if (prefixMatch) {
        const rawS = prefixMatch[1] || prefixMatch[2] || currentSeries;
        const s = cleanSeriesNumber(rawS, currentSeries);
        if (!s) {
          unparsedLines.push(line);
          continue;
        }
        const tNo = prefixMatch[3];
        items.push({
          series: s,
          isSeriesLocked: true,
          ticketNo: tNo,
        });
        continue;
      }
    }

    // STRICT PATTERN 4: Suffix Series (Series MUST strictly be digits or c/s, e.g. 09243=12, 43283=6, 36963 -40, 76371-12, 18886..12c, 54256..24, 12454....40, 81684,,20)
    // 🛑 Strictly NO 1pm, 6pm, 8pm, MSM or extra letters/words allowed! If letters are present, goes to unparsed!
    if (!/(?:pm|am|qm|gm|baje)\b/i.test(line)) {
      const suffixMatch = line.match(/^(\d{5})\s*([=:\-\/._~*#@+]|\s+)+\s*([0-9]{1,3}[cs]?|[\(\[][0-9]{1,3}[\)\]])$/i);
      if (suffixMatch) {
        const tNo = suffixMatch[1];
        const s = cleanSeriesNumber(suffixMatch[3], currentSeries);
        if (!s) {
          unparsedLines.push(line);
          continue;
        }
        items.push({
          series: s,
          isSeriesLocked: true,
          ticketNo: tNo,
        });
        continue;
      }
    }

    // STRICT PATTERN 5: Pure 5-digit number(s) on a line (ABSOLUTELY NO letters or extra words allowed!)
    // e.g. "84252" or "84252, 14252, 64252"
    if (/^\d{5}(?:[,\s\t]+\d{5})*$/.test(line)) {
      if (!currentSeries) {
        // 🛑 NO SERIES DECLARED in this message! Do NOT assume 12! Send to unparsed review queue!
        unparsedLines.push(line);
        continue;
      }
      const ticketsOnLine = line.match(/\b\d{5}\b/g);
      if (ticketsOnLine && ticketsOnLine.length > 0) {
        for (const tNo of ticketsOnLine) {
          items.push({
            series: currentSeries,
            isSeriesLocked: hasExplicitSeriesAbove || Boolean(bottomSeries),
            ticketNo: tNo,
          });
        }
        continue;
      }
    }

    // 🛑 100% STRICT FIT GUARD:
    // If the line did NOT match any of the above standard patterns 100%,
    // or contains stray letters/noise -> SEND TO UNPARSED!
    unparsedLines.push(line);
  }

  items.unparsedLines = unparsedLines;
  return items;
}

// --- 2. BATCH BUFFERING & DATABASE STORAGE ---
async function flushBufferToLocalDb() {
  if (isFlushing || messageBuffer.length === 0) return;

  isFlushing = true;
  const batchToInsert = messageBuffer.splice(0, MAX_BUFFER_SIZE);

  try {
    const startTime = Date.now();
    const ticketSalesBatch = [];

    for (const raw of batchToInsert) {
      // PRE-PARSED TICKETS SEEDHE USE HONGE (NO RE-PARSING)
      const parsedTickets = raw._parsedTickets || [];

      if (parsedTickets.length > 0) {
        const targetShiftName = raw._sessionDrawShift;
        const targetDrawDate = new Date(raw._sessionDrawDate);
        const resolvedSellerName = raw._sessionBuyerName;
        const targetDrawCode = targetShiftName.replace(/\s+/g, '-').toUpperCase();

        let ticketIndex = 0;
        for (const t of parsedTickets) {
          ticketIndex++;
          const finalSeries = (t.series && t.series !== '?') ? t.series : '12';
          const pricePerTicket = calculateSeriesPrice(finalSeries);
          const finalQty = 1;
          const totalAmount = pricePerTicket * finalQty;
          const uniqueSalt = Math.random().toString(36).substring(2, 8);

          ticketSalesBatch.push({
            id: `tkt_wa_${Date.now()}_${uniqueSalt}_${finalSeries}_${t.ticketNo}_${ticketIndex}`,
            receiptNumber: `REC-${finalSeries}-${t.ticketNo}`,
            buyerName: resolvedSellerName,
            buyerPhone: raw.sender,
            agentCode: 'AG-WA',
            agentName: resolvedSellerName,
            drawCode: targetDrawCode,
            drawName: targetShiftName,
            ticketSeries: finalSeries,
            ticketNumber: `${finalSeries} ${t.ticketNo}`,
            quantity: finalQty,
            pricePerTicket,
            totalAmount,
            commissionAmount: totalAmount * 0.05,
            status: 'sold',
            paymentMode: 'cash',
            saleDate: getLocalIsoString(new Date()),
            drawDate: getLocalIsoString(targetDrawDate, true),
          });
        }
      }
    }

    if (ticketSalesBatch.length > 0 && localDb) {
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
            t.id, t.receiptNumber, t.buyerName, t.buyerPhone, t.agentCode, t.agentName,
            t.drawCode, t.drawName, t.ticketSeries, t.ticketNumber, t.quantity,
            t.pricePerTicket, t.totalAmount, t.commissionAmount, t.status, t.paymentMode,
            t.saleDate, t.drawDate
          );
        }
        localDb.exec('COMMIT');

        appendLog(
          'success',
          `💾 [SAVED] ${ticketSalesBatch.length} ticket(s) under [${ticketSalesBatch[0].drawName}] (${ticketSalesBatch[0].drawDate.slice(0, 10)}) for Party: "${ticketSalesBatch[0].buyerName}"!`
        );
      } catch (localSqliteErr) {
        try { localDb.exec('ROLLBACK'); } catch (_) { }
        appendLog('warn', `⚠️ [SQLITE ERROR] ${localSqliteErr.message}`);
      }
    }

    processedTotalCount += ticketSalesBatch.length;
    lastFlushTimestamp = new Date().toISOString();
  } catch (err) {
    appendLog('error', `Flush exception: ${err.message}`);
  } finally {
    isFlushing = false;
  }
}

setInterval(() => {
  if (messageBuffer.length > 0) flushBufferToLocalDb();
}, FLUSH_INTERVAL_MS);

function getAuthDir() {
  const baseDir = process.env.APPDATA || process.env.LOCALAPPDATA || process.env.USERPROFILE || 'C:\\Lottery_Reports';
  const targetDir = path.join(baseDir, 'OpsCore_Pro', 'whatsapp_session');
  try {
    if (!fs.existsSync(targetDir)) fs.mkdirSync(targetDir, { recursive: true });
    return targetDir;
  } catch (_) {
    return path.join(process.cwd(), 'app_session');
  }
}

let isIntentionallyStopped = false;

async function startWhatsAppSocket() {
  if (sock) {
    if (connectionStatus === 'connected') return;
    try {
      sock.ev.removeAllListeners();
      sock.end(undefined);
    } catch (_) { }
    sock = null;
  }

  isIntentionallyStopped = false;
  connectionStatus = 'connecting';
  currentQrRaw = null;
  currentQrDataUrl = null;

  try {
    const authDir = getAuthDir();
    const { state, saveCreds } = await useMultiFileAuthState(authDir);

    if (state?.creds?.me?.id) {
      state.creds.registered = true;
      try { await saveCreds(); } catch (_) { }
    }

    let version = [2, 3000, 1043857760];
    try {
      const v = await fetchLatestBaileysVersion();
      if (v?.version) version = v.version;
    } catch (_) { }

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
      getMessage: async () => ({ conversation: '' }),
    });

    sock.ev.on('creds.update', async () => {
      try { await saveCreds(); } catch (_) { }
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
        connectionStatus = 'disconnected';
        currentQrRaw = null;
        currentQrDataUrl = null;
        appendLog('warn', `⚠️ [WHATSAPP DISCONNECTED] (Code: ${statusCode || 'unknown'}). Reconnecting...`);

        if (isIntentionallyStopped) return;

        const isRestartRequired = statusCode === DisconnectReason.restartRequired || statusCode === 515;
        const delay = isRestartRequired ? 800 : 2500;
        setTimeout(() => {
          if (!isIntentionallyStopped) startWhatsAppSocket();
        }, delay);
      } else if (connection === 'open') {
        connectionStatus = 'connected';
        currentQrRaw = null;
        currentQrDataUrl = null;
        appendLog('success', '✅ WhatsApp Connected Successfully & Ready for Stream!');
      }
    });

    // MESSAGE INGESTION HOOK
    sock.ev.on('messages.upsert', async (m) => {
      if (!m.messages || m.messages.length === 0) return;

      for (const msg of m.messages) {
        if (msg.key.remoteJid === 'status@broadcast') continue;

        const rawJid = msg.key.remoteJid || 'unknown';
        const sender = rawJid.replace(/@.+/, '').replace(/:.+/, '');

        // Unwrap nested containers: ephemeral, viewOnce, document caption, etc.
        let actualMessage = msg.message;
        if (actualMessage?.ephemeralMessage?.message) {
          actualMessage = actualMessage.ephemeralMessage.message;
        }
        if (actualMessage?.viewOnceMessage?.message) {
          actualMessage = actualMessage.viewOnceMessage.message;
        }
        if (actualMessage?.viewOnceMessageV2?.message) {
          actualMessage = actualMessage.viewOnceMessageV2.message;
        }
        if (actualMessage?.documentWithCaptionMessage?.message) {
          actualMessage = actualMessage.documentWithCaptionMessage.message;
        }

        let messageText =
          actualMessage?.conversation ||
          actualMessage?.extendedTextMessage?.text ||
          actualMessage?.imageMessage?.caption ||
          actualMessage?.documentMessage?.caption ||
          '';

        if (messageText && messageText.trim().length > 0) {
          appendLog('info', `📩 [INCOMING] From ${sender}: "${messageText.trim().replace(/\s+/g, ' ').substring(0, 60)}"`);
        }

        // 📸 IMAGE MESSAGE DETECTION & GEMINI SCANNING
        const isImage = Boolean(
          actualMessage?.imageMessage ||
          (actualMessage?.documentMessage?.mimetype && actualMessage.documentMessage.mimetype.startsWith('image/'))
        );

        if (isImage) {
          appendLog('info', `📸 [IMAGE DETECTED] Downloading photo from ${sender}...`);
          let buffer = null;
          for (let attempt = 1; attempt <= 2; attempt++) {
            try {
              buffer = await downloadMediaMessage(
                msg,
                'buffer',
                {},
                {
                  logger: baileysLogger,
                  reuploadRequest: sock.updateMediaMessage,
                }
              );
              if (buffer && buffer.length > 0) break;
            } catch (mediaErr) {
              if (attempt === 2) {
                appendLog('error', `❌ [IMAGE DOWNLOAD ERROR] ${mediaErr.message}`);
              } else {
                await new Promise((r) => setTimeout(r, 1000));
              }
            }
          }

          if (buffer && buffer.length > 0) {
            const mime = msg.message?.imageMessage?.mimetype || 'image/jpeg';
            appendLog('info', `🔍 [GEMINI OCR SCANNING] Scanning photo with Gemini Vision AI...`);
            const aiText = await extractTicketsFromImageViaGemini(buffer, mime);

            // 🔒 STRICT TARGET LOCK LIVE ENFORCEMENT
            const effective = getEffectiveTarget(sender);
            const targetShift = effective.targetShift;
            const targetDate = effective.targetDate;
            const targetBuyer = effective.targetBuyer;

            const imageBase64Data = buffer.toString('base64');
            const photoId = `photo_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
            const parsedTickets = (aiText && aiText.trim().length > 0)
              ? parseIncomingTicketText(aiText, null)
              : [];

            const parsedItems = parsedTickets.map((t) => ({
              series: t.series || '12',
              ticketNo: t.ticketNo,
              quantity: t.quantity || 1,
              amount: calculateSeriesPrice(t.series || '12'),
              sellerName: targetBuyer,
            }));

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
                  targetBuyer,
                  targetShift,
                  getLocalYmd(targetDate),
                  imageBase64Data,
                  aiText || '',
                  JSON.stringify(parsedItems),
                  new Date().toISOString()
                );
                appendLog(
                  'success',
                  `📸 [QUEUED FOR VERIFICATION] ${parsedItems.length} ticket(s) from ${sender} (${targetBuyer}) sent to Desktop Verification Screen!`
                );
              } catch (dbErr) {
                appendLog('error', `❌ [PENDING PHOTO DB ERROR] ${dbErr.message}`);
              }
            }
          }
          continue; // 🛑 CRITICAL: Photos MUST NEVER auto-book directly! Always queue for operator verification!
        }

        if (!messageText || messageText.trim().length === 0) continue;

        // 🔒 STRICT TARGET LOCK LIVE ENFORCEMENT
        const effective = getEffectiveTarget(sender);

        // Parse tickets (Strict: NO silent fallback to 12. If no series is provided in the message, tickets go to unparsed review queue)
        const parsedTickets = parseIncomingTicketText(messageText, null);

        // 🔒 STRICT UNPARSED QUEUE DISPATCH:
        // If the message has ANY unparsed lines or unrecognized tickets:
        // 1. Save the FULL incoming message content into unparsed_messages as a single item!
        // 2. DO NOT auto-book! Operator will manually verify the full message in Pattern Resolver.
        if (parsedTickets.unparsedLines && parsedTickets.unparsedLines.length > 0) {
          if (localDb) {
            const targetBuyer = effective.targetBuyer;
            const nowIso = new Date().toISOString();
            try {
              localDb.prepare(`
                INSERT INTO unparsed_messages (sender, sender_name, raw_message, status, received_at)
                VALUES (?, ?, ?, 'pending', ?)
              `).run(sender, targetBuyer, messageText.trim(), nowIso);

              appendLog(
                'warn',
                `⚠️ [FULL MESSAGE -> REVIEW QUEUE] From ${sender} (${targetBuyer}): Sent entire message to Pattern Resolver for manual verification.`
              );
            } catch (err) {
              appendLog('warn', `⚠️ [UNPARSED DB ERROR] ${err.message}`);
            }
          }
          continue; // 🛑 CRITICAL: Do NOT auto-book contaminated/partial messages! Operator must manually verify!
        }

        if (parsedTickets.length > 0) {
          const targetShift = effective.targetShift;
          const targetDate = effective.targetDate;
          const targetBuyer = effective.targetBuyer;

          const preview = parsedTickets.slice(0, 3).map((p) => `${p.series} #${p.ticketNo}`).join(', ');
          appendLog(
            'info',
            `📥 [LOCKED: ${targetShift} (${getLocalYmd(targetDate)}) | Party: ${targetBuyer}] ${parsedTickets.length} ticket(s) from ${sender}: ${preview}`
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
            _parsedTickets: parsedTickets, // Direct locked pre-parsed list
          };

          messageBuffer.push(ticketEntry);
          if (messageBuffer.length >= MAX_BUFFER_SIZE) {
            flushBufferToLocalDb();
          }
        } else if (!parsedTickets.unparsedLines || parsedTickets.unparsedLines.length === 0) {
          // Check if it's pure casual greeting / chatter
          const isCasual = /^\s*(?:hi+|hello+|hlo+|hey+|ok+|haan+|ha+|namaste+|thanks|thx|bye|bhai|sir|boss)\s*$/i.test(messageText.trim());

          if (!isCasual && localDb) {
            try {
              localDb.prepare(`
                INSERT INTO unparsed_messages (sender, sender_name, raw_message, status, received_at)
                VALUES (?, ?, ?, 'pending', ?)
              `).run(sender, effective.targetBuyer, messageText.trim(), new Date().toISOString());
            } catch (err) {
              appendLog('warn', `⚠️ [UNPARSED DB ERROR] ${err.message}`);
            }
          }

          if (isCasual) {
            appendLog('info', `💬 [GREETING/CHAT] ${sender} (${effective.targetBuyer}): "${messageText.trim()}" (Ignored)`);
          } else {
            appendLog(
              'warn',
              `⚠️ [UNPARSED -> REVIEW QUEUE] From ${sender} (${effective.targetBuyer}): "${messageText.trim().substring(0, 70)}" (Ticket entry nahi hui, review section me add kar diya)`
            );
          }
        }
      }
    });
  } catch (err) {
    connectionStatus = 'disconnected';
    appendLog('error', `Socket error: ${err.message}`);
  }
}

async function stopWhatsAppSocket() {
  isIntentionallyStopped = true;
  connectionStatus = 'disconnected';
  if (!sock) return;
  try {
    if (messageBuffer.length > 0) await flushBufferToLocalDb();
    sock.ev.removeAllListeners();
    sock.end(undefined);
    sock = null;
  } catch (_) { }
}

// --- 4. EXPRESS REST API SERVER ---
const app = express();
app.use(cors());
app.use(express.json());

app.get('/status', (req, res) => {
  const isConn = connectionStatus === 'connected';
  res.json({
    online: true,
    connectionStatus,
    isConnected: isConn,
    hasQr: !isConn && Boolean(currentQrDataUrl),
    qrDataUrl: isConn ? null : currentQrDataUrl,
    processedTotalCount,
    currentBufferSize: messageBuffer.length,
    lastFlushTimestamp,
    storageType: 'local_sqlite',
    uptimeSeconds: Math.floor(process.uptime()),
  });
});

app.get('/qr', (req, res) => {
  res.json({ connectionStatus, qrRaw: currentQrRaw, qrDataUrl: currentQrDataUrl });
});

app.post('/start', async (req, res) => {
  startWhatsAppSocket();
  res.json({ success: true, message: 'WhatsApp engine starting...', status: connectionStatus });
});

app.post('/stop', async (req, res) => {
  await stopWhatsAppSocket();
  res.json({ success: true, message: 'WhatsApp engine stopped.', status: connectionStatus });
});

app.post('/restart-server', async (req, res) => {
  res.json({ success: true, message: 'WhatsApp Engine restarting...' });
  setTimeout(() => {
    process.exit(0);
  }, 400);
});

app.get('/logs', (req, res) => {
  res.json({ logs: recentLogs, bufferCount: messageBuffer.length, processedTotalCount });
});

app.post('/clear-logs', (req, res) => {
  recentLogs.length = 0;
  res.json({ success: true, message: 'Logs cleared.' });
});

app.post('/reset-count', (req, res) => {
  processedTotalCount = 0;
  res.json({ success: true, message: 'Counter reset to 0.', processedTotalCount });
});

app.get('/api/bot/target-lock', (req, res) => {
  readLiveTargetLock();
  res.json({ success: true, targetConfig: globalTargetConfig });
});

app.post('/api/bot/target-lock', (req, res) => {
  const { lockedShift, lockedDate, lockedBuyerName, strictLockEnabled } = req.body || {};
  if (lockedShift !== undefined) globalTargetConfig.lockedShift = String(lockedShift || '').trim();
  if (lockedDate !== undefined) globalTargetConfig.lockedDate = String(lockedDate || '').trim();
  if (lockedBuyerName !== undefined) globalTargetConfig.lockedBuyerName = String(lockedBuyerName || '').trim();
  if (strictLockEnabled !== undefined) globalTargetConfig.strictLockEnabled = Boolean(strictLockEnabled);

  if (localDb) {
    try {
      const now = new Date().toISOString();
      const insertOrUpdate = localDb.prepare(`
        INSERT INTO ai_settings (key, value, updatedAt)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
      `);
      insertOrUpdate.run('bot_locked_shift', globalTargetConfig.lockedShift, now);
      insertOrUpdate.run('bot_locked_date', globalTargetConfig.lockedDate, now);
      insertOrUpdate.run('bot_locked_buyer', globalTargetConfig.lockedBuyerName, now);
      insertOrUpdate.run('bot_strict_lock', globalTargetConfig.strictLockEnabled ? '1' : '0', now);
    } catch (dbErr) {
      appendLog('error', `Target lock save error: ${dbErr.message}`);
    }
  }

  appendLog(
    'success',
    `🔒 [TARGET LOCK ACTIVE] Shift: "${globalTargetConfig.lockedShift}" | Date: "${globalTargetConfig.lockedDate}" | Party: "${globalTargetConfig.lockedBuyerName}"`
  );

  res.json({ success: true, message: 'Target Lock saved successfully!', targetConfig: globalTargetConfig });
});

app.post('/api/parse-pdf', async (req, res) => {
  try {
    let { filePath } = req.body || {};
    if (filePath) filePath = filePath.trim().replace(/^["']|["']$/g, '');
    if (!filePath || !fs.existsSync(filePath)) {
      return res.status(400).json({ success: false, error: 'File path invalid or not found' });
    }
    const { parseLotteryPdf } = require('./parse_pdf.js');
    const result = await parseLotteryPdf(filePath);
    res.json(result);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.listen(PORT, '127.0.0.1', () => {
  appendLog('info', `⚡ WhatsApp Engine REST API listening on http://127.0.0.1:${PORT}`);
});