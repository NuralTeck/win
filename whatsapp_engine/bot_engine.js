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
  DisconnectReason,
  fetchLatestBaileysVersion,
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
  const dbPath = path.join(os.homedir(), 'Documents', 'opscore_pro.db');
  localDb = new DatabaseSync(dbPath);
  localDb.exec('PRAGMA journal_mode=WAL;');
  localDb.exec('PRAGMA busy_timeout=10000;');
  localDb.exec('PRAGMA synchronous=NORMAL;');
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
  if (!supabase) return;
  try {
    const todayIso = getLocalYmd(new Date());
    const { data, error } = await supabase
      .from('ticket_sales')
      .select('buyer_phone, draw_name, draw_date, ticket_series, ticket_number')
      .gte('draw_date', todayIso)
      .limit(5000);
    if (!error && data) {
      for (const s of data) {
        const dDate = getLocalYmd(s.draw_date || s.drawDate || '');
        const shift = (s.draw_name || s.drawName || '').trim().toLowerCase();
        const sender = s.buyer_phone || s.buyerPhone || '';
        const series = s.ticket_series || s.ticketSeries || '';
        const parts = (s.ticket_number || s.ticketNumber || '').trim().split(' ');
        const tNo = parts.length > 1 ? parts[parts.length - 1] : (s.ticket_number || s.ticketNumber || '');
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
  if (!supabase) return;
  try {
    const { data, error } = await supabase.from('series_prices').select('*');
    if (!error && data) {
      seriesPricesCache = data;
    }
  } catch (err) {
    appendLog('warn', `Series prices fetch note: ${err.message}`);
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
  const s100Price = s100 ? Number(s100.ticket_price || s100.ticketPrice) : 100.0;
  const perSeriesRate = s100Price >= 100 ? (s100Price / 100.0) : (s100Price > 0 ? s100Price : 1.0);

  const digits = cleanName.replace(/\D/g, '');
  const multiplier = parseFloat(digits);
  if (!isNaN(multiplier) && multiplier > 0) {
    return multiplier * perSeriesRate;
  }
  return 100.0;
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
 * Intelligent WhatsApp message text parser for lottery tickets.
 * Handles single lines, bulk headers, ranges (e.g. 65491-95-5), and multipliers.
 */
/**
 * Extract pure numeric digits for Series (strips any letters, e.g. "12c" -> "12", "12s" -> "12", "12se" -> "12", "83L" -> "83", "SR-36" -> "36")
 */
function cleanSeriesNumber(rawSeries, fallback = '12') {
  if (!rawSeries) return fallback;
  const str = String(rawSeries).trim();
  const digits = str.replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 4) {
    return digits;
  }
  return digits.length > 0 ? digits.slice(0, 3) : fallback;
}

/**
 * TOP PRIORITY #1 LOTTERY TICKET PARSER - SUPREME MASTER RULE
 * Rule 1: Fixed 5 Digits (e.g. 15204, 62393, 00123) -> ALWAYS 5-DIGIT TICKET NUMBER
 * Rule 2: 1 to 3 Digits with ANY suffix (c, s, se, ser, serial, l) or prefix (sr, s, c) -> ALWAYS PURE NUMERIC SERIES (e.g. 12c -> 12)
 * Rule 3: Series can be AAGE (before ticket) or PEECHE (after ticket) or STANDALONE HEADER
 * Rule 4: All other non-ticket alphabets/words (e.g. greetings, chats) are safely ignored
 */
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
    // Skip booking header lines like "Rustam g booking", "Ram Kumar booking", "Rajiv booking"
    if (/^[A-Za-z][A-Za-z\s]{1,30}\s+(?:boakg|booking|bokg|bok|bkg)\s*$/i.test(l)) {
      continue;
    }
    // Skip forwarded message header lines
    if (/^(?:Forwarded|\u203A\u203A\s*Forwarded|fwd|forward)/i.test(l)) {
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

    const lineForTickets = l.replace(/(?:=|\b)(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)\b/gi, ' ').trim();

    // --- CASE 1: Range format: Series AAGE + Range e.g. '12 12345-9 5', '12- 12345-49', '12345-49 5', '12345-9' ---
    const rangeMatch = lineForTickets.match(
      /(?:^|[\s,;])(?:([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[-:,\/=\s]+)?(\d{3})(\d{2})\s*[-~to]+\s*(\d{1,5})(?:\s*[-*=xX,\s]\s*(\d+))?/i
    );
    if (rangeMatch && !/\d{5}/.test(rangeMatch[1] || '')) {
      const s = rangeMatch[1] ? cleanSeriesNumber(rangeMatch[1], currentSeries) : currentSeries;
      const prefix = rangeMatch[2];
      const startLast2 = parseInt(rangeMatch[3], 10);
      const endStr = rangeMatch[4];
      let endLast2 = parseInt(endStr, 10);
      if (endStr.length === 5) {
        endLast2 = parseInt(endStr.slice(-2), 10);
      } else if (endStr.length === 1) {
        // e.g. 12345-9 -> startLast2 is 45, endLast2 becomes 49
        const tens = Math.floor(startLast2 / 10);
        endLast2 = tens * 10 + parseInt(endStr, 10);
      }

      if (!isNaN(startLast2) && !isNaN(endLast2) && endLast2 >= startLast2 && endLast2 - startLast2 <= 200) {
        for (let i = startLast2; i <= endLast2; i++) {
          items.push({
            series: s,
            ticketNo: `${prefix}${String(i).padStart(2, '0')}`,
            quantity: 1,
          });
        }
        currentSeries = s;
        continue;
      }
    }

    // --- CASE 2: Single Ticket + Series PEECHE: e.g. '69459 = 6', '69459-6', '69459 6', '69459/6', '69459=12c', '75383 = 6' ---
    const singleWithTrailingSeries = lineForTickets.match(
      /(?:^|[\s,;])(\d{5})\s*[-:,\/=\s]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\b/i
    );
    if (singleWithTrailingSeries && !/\d{5}/.test(singleWithTrailingSeries[2])) {
      const tNo = singleWithTrailingSeries[1];
      const s = cleanSeriesNumber(singleWithTrailingSeries[2], currentSeries);
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: 1,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE 3: Series AAGE + Single Ticket: e.g. '6 = 69459', '12- 69459', '12/69459', '12c 69459', '6 69459', '24 84389' ---
    const singleWithLeadingSeries = lineForTickets.match(
      /(?:^|[\s,;])([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})\s*[-:,\/=\s]+\s*(\d{5})\b/i
    );
    if (singleWithLeadingSeries && !/\d{5}/.test(singleWithLeadingSeries[1])) {
      const s = cleanSeriesNumber(singleWithLeadingSeries[1], currentSeries);
      const tNo = singleWithLeadingSeries[2];
      items.push({
        series: s,
        ticketNo: tNo,
        quantity: 1,
      });
      currentSeries = s;
      continue;
    }

    // --- CASE 4: Standalone 5-Digit tickets on the line: e.g. '69459', '69459 75383 75384' ---
    const all5s = lineForTickets.match(/\b\d{5}\b/g);
    if (all5s && all5s.length > 0) {
      for (const tNo of all5s) {
        items.push({
          series: currentSeries,
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
 * Extract explicit Shift and Date from message text (if present)
 * Supports:
 *   - Shifts: 1pm, 6pm, 8pm, Dear 1 PM, =8pm, =1pm, =6pm
 *   - Dates: 13=8=2026, 14/08/2026, 14-08-2026, 14.08.2026, 14/08, 15/08, "kal", "tomorrow", "aaj", "today"
 */
function extractExplicitShiftAndDate(text) {
  let explicitShift = null;
  let explicitDrawDate = null;
  let explicitBuyerName = null;

  const cleanTrimmed = text.trim();

  const nonCustomerWords = new Set([
    'hi', 'hello', 'ok', 'end', 'done', 'khatam', 'finish', 'close', 'stop', 'clear', 'samapt', 'khtm',
    'dear', 'today', 'tomorrow', 'kal', 'aaj', 'thanks', 'test', 'help', 'status', 'yes', 'no', 'pls', 'please',
    '1pm', '6pm', '8pm', '1 pm', '6 pm', '8 pm', '1baje', '6baje', '8baje',
    'morning', 'day', 'evening', 'night', 'series', 'serial', 'nagaland', 'ticket', 'booking', 'bkg', 'bokg',
    'all', 'shift', 'shifts', 'qty', 'pcs', 'pic', 'amount', 'total', 'price', 'cash', 'upi', 'gpay', 'paytm'
  ]);

  // 1. Check Shift Tags (supports 8pm, 8 pm, =8pm, 8:00pm, dear 8 pm, 8 baje, morning, day, night)
  if (/(?:=|\b)(?:dear\s*)?1(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?1(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*morning\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 1 PM';
  } else if (/(?:=|\b)(?:dear\s*)?6(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?6(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*day\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 6 PM';
  } else if (/(?:=|\b)(?:dear\s*)?8(?::00)?\s*pm\b/i.test(text) || /^\s*(?:=)?\s*(?:dear\s*)?8(?::00)?\s*(?:pm|baje)?\s*$/i.test(cleanTrimmed) || /^\s*(?:night|evening)\s*$/i.test(cleanTrimmed)) {
    explicitShift = 'Dear 8 PM';
  }

  // 2. Check Date Tags (e.g. "13/08/2026", "13=8=2026", "13-08-2026", "13/08")
  const fullDateMatch = text.match(/\b(\d{1,2})[=\/\.-](\d{1,2})[=\/\.-](\d{2,4})\b/);
  const slashDateMatch = text.match(/\b(\d{1,2})\/(\d{1,2})\b/);
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

  // 3. Check for Buyer / Customer Name Tag (e.g. "Customer: Rajiv", "Rajiv booking", "Name: Rajiv", "Cust: Rajiv", "Party: Rajiv", "Start Rajiv")
  const custPrefixMatch = cleanTrimmed.match(/^\s*(?:customer|cust|client|name|naam|nam|party|start)\s*[:=-]?\s*([A-Za-z0-9\s]{2,25})\b/i);
  const custSuffixMatch = cleanTrimmed.match(/^(?:name:?\s*)?([A-Za-z0-9\s]{2,20})\s*(?:boakg|booking|bokg|bok|bkg|party)\b/i);

  if (custPrefixMatch) {
    const candidate = custPrefixMatch[1].trim();
    if (!nonCustomerWords.has(candidate.toLowerCase())) {
      explicitBuyerName = candidate;
    }
  } else if (custSuffixMatch) {
    const candidate = custSuffixMatch[1].trim();
    if (!nonCustomerWords.has(candidate.toLowerCase())) {
      explicitBuyerName = candidate;
    }
  } else {
    // Standalone name: only if message has NO reserved words, NO shift, and NO date
    const words = cleanTrimmed.toLowerCase().split(/\s+/);
    const hasReservedWord = words.some((w) => nonCustomerWords.has(w));
    if (
      /^[A-Za-z\s]{2,25}$/i.test(cleanTrimmed) &&
      !hasReservedWord &&
      !explicitShift &&
      !explicitDrawDate
    ) {
      explicitBuyerName = cleanTrimmed;
    }
  }

  return {
    explicitShift,
    explicitDrawDate,
    explicitBuyerName,
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
    
    // 1. Bulk Insert into raw stream log table (whatsapp_entries)
    const { error: rawError } = await supabase
      .from('whatsapp_entries')
      .insert(batchToInsert);

    if (rawError) {
      appendLog('error', `whatsapp_entries bulk insert failed: ${rawError.message}`);
    }

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
          // 🔒 LOCKED SESSION ENTRY: use only session values, ignore message text
          targetShiftName = raw._sessionDrawShift || session.drawShift || autoCycle.drawName;
          targetDrawDate = raw._sessionDrawDate ? new Date(raw._sessionDrawDate) : (session.drawDate || autoCycle.drawDate);
          rawBuyerName = raw._sessionBuyerName || session.buyerName || raw.sender_name || '';
        } else {
          // Normal (no lock): use message-extracted values with session fallback
          const activeSessionDate  = session.drawDate  || null;
          const activeSessionShift = session.drawShift || null;
          const activeSessionBuyer = session.buyerName || null;
          targetShiftName = explicit.explicitShift || activeSessionShift || autoCycle.drawName;
          targetDrawDate  = explicit.explicitDrawDate || activeSessionDate || autoCycle.drawDate;
          rawBuyerName    = explicit.explicitBuyerName || activeSessionBuyer || raw.sender_name || '';
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

      // 2. Cloud Supabase Sync (Upload to Cloud)
      if (supabase) {
        const { error: salesError } = await supabase
          .from('ticket_sales')
          .upsert(ticketSalesBatch);

        if (salesError) {
          appendLog('warn', `ticket_sales cloud upsert note: ${salesError.message}`);
        } else {
          appendLog('success', `☁️ [CLOUD SYNC] Synced ${ticketSalesBatch.length} ticket(s) to Supabase Cloud!`);
        }
      }
    }

    const durationMs = Date.now() - startTime;
    processedTotalCount += batchToInsert.length;
    lastFlushTimestamp = new Date().toISOString();
    appendLog(
      'success',
      `🚀 Ingested ${batchToInsert.length} messages in ${durationMs}ms (Total Processed: ${processedTotalCount})`
    );
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

// --- 3. WHATSAPP BAILEYS CONNECTION MANAGEMENT ---
async function startWhatsAppSocket() {
  if (sock && (connectionStatus === 'connected' || connectionStatus === 'connecting')) {
    appendLog('info', 'WhatsApp socket is already active or connecting.');
    return;
  }

  connectionStatus = 'connecting';
  currentQrRaw = null;
  currentQrDataUrl = null;
  appendLog('info', 'Initializing WhatsApp socket session...');

  try {
    const authDir = path.join(process.cwd(), 'app_session');
    if (!fs.existsSync(authDir)) {
      fs.mkdirSync(authDir, { recursive: true });
    }

    const { state, saveCreds } = await useMultiFileAuthState(authDir);
    const { version } = await fetchLatestBaileysVersion();

    sock = makeWASocket({
      version,
      logger: baileysLogger,
      printQRInTerminal: false,
      auth: state,
      browser: ['OpsCore WhatsApp Engine', 'Desktop', '1.0.0'],
      syncFullHistory: false,
      markOnlineOnConnect: true,
      generateHighQualityLinkPreview: false,
    });

    sock.ev.on('creds.update', async () => {
      try {
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

        appendLog('warn', `Connection closed (Status: ${statusCode}). Logged Out: ${isLoggedOut}`);

        if (isLoggedOut) {
          appendLog('warn', '🗑️ Device logged out. Purging app_session for fresh QR...');
          try {
            if (fs.existsSync(authDir)) {
              fs.rmSync(authDir, { recursive: true, force: true });
            }
          } catch (delErr) {
            appendLog('error', `Could not delete session directory: ${delErr.message}`);
          }
          // Re-trigger start for fresh QR scan
          setTimeout(() => startWhatsAppSocket(), 2000);
        } else {
          // Temporary drop / restart required -> Auto-reconnect
          const delay = statusCode === DisconnectReason.restartRequired ? 1000 : 3000;
          appendLog('info', `🔄 Auto-reconnecting in ${delay}ms...`);
          setTimeout(() => startWhatsAppSocket(), delay);
        }
      } else if (connection === 'open') {
        connectionStatus = 'connected';
        currentQrRaw = null;
        currentQrDataUrl = null;
        appendLog('success', '✅ WhatsApp Connected Successfully & Ready for High-Traffic Stream!');
      }
    });

    // High-Speed Message Ingestion Hook
    sock.ev.on('messages.upsert', async (m) => {
      if (m.type !== 'notify') return;

      for (const msg of m.messages) {
        // Skip messages sent by the bot itself or status broadcasts
        if (msg.key.fromMe || msg.key.remoteJid === 'status@broadcast') continue;

        const senderJid = msg.key.remoteJid || 'unknown';
        const sender = senderJid.replace(/@.+/, '');
        const pushName = msg.pushName || '';

        // Extract message text across different message types (including forwarded messages)
        const messageText =
          msg.message?.conversation ||
          msg.message?.extendedTextMessage?.text ||
          msg.message?.extendedTextMessage?.contextInfo?.quotedMessage?.conversation ||
          msg.message?.imageMessage?.caption ||
          msg.message?.documentMessage?.caption ||
          msg.message?.listMessage?.description ||
          '';

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

        // ─── SESSION STATE MACHINE ─────────────────────────────────────────────────
        // STATE 1: No session → only accept 1pm/6pm/8pm to set shift. Block everything else.
        // STATE 2: Shift set, but no name → only accept customer name. Block everything else.
        // STATE 3: Both shift AND name set → fully LOCKED → only extract ticket numbers. Block everything else.
        // Any state: 'end' resets to STATE 1.
        // ──────────────────────────────────────────────────────────────────────────

        const existingSession = senderSessions.get(sender) || {};
        const hasShift = !!(existingSession.drawShift);
        const hasName  = !!(existingSession.buyerName);
        const hasDate  = !!(existingSession.drawDate);

        // Detect if message is a pure time/shift message (1pm, 6pm, 8pm)
        const isTimeMessage = /^\s*(?:=)?\s*(?:dear\s*)?[168](?::00)?\s*(?:pm|baje)\s*$/i.test(messageText.trim());
        // Detect if message is a pure customer name (via prefix like "Customer: Rajiv" OR standalone name)
        const explicit = extractExplicitShiftAndDate(messageText);
        const isPureNameMessage = !!(explicit.explicitBuyerName && !explicit.explicitShift && !explicit.explicitDrawDate);
        const isPureShiftMessage = !!(explicit.explicitShift && !explicit.explicitBuyerName);
        const isDateMessage      = !!(explicit.explicitDrawDate);

        // ── STATE 1: No shift, no name → WAITING FOR TIME ──────────────────────────
        if (!hasShift && !hasName && !hasDate) {
          if (isPureShiftMessage || isDateMessage) {
            // Accept time/date to start session
            const session = existingSession;
            if (explicit.explicitShift) session.drawShift = explicit.explicitShift;
            if (explicit.explicitDrawDate) session.drawDate = explicit.explicitDrawDate;
            session.lastUpdated = Date.now();
            senderSessions.set(sender, session);
            appendLog('success', `⏰ [SHIFT SET] ${sender}: "${explicit.explicitShift || ''}" locked. Now send customer name to start booking session.`);
          } else {
            appendLog('warn', `🚫 [BLOCKED - NO SESSION] ${sender}: "${messageText.trim().substring(0, 50)}" ignored. Send 1pm/6pm/8pm first.`);
          }
          continue;
        }

        // ── STATE 2: Shift set, name NOT yet set → WAITING FOR NAME ────────────────
        if (hasShift && !hasName) {
          // Accept customer name to complete session
          if (isPureNameMessage || explicit.explicitBuyerName) {
            const session = existingSession;
            session.buyerName = explicit.explicitBuyerName;
            if (explicit.explicitShift) session.drawShift = explicit.explicitShift;
            if (explicit.explicitDrawDate) session.drawDate = explicit.explicitDrawDate;
            session.lastUpdated = Date.now();
            senderSessions.set(sender, session);
            appendLog('success', `👤 [SESSION READY] ${sender}: Customer "${session.buyerName}" + Shift "${session.drawShift}" locked! Now accepting tickets.`);
          } else {
            // Not a name — block it
            appendLog('warn', `🚫 [BLOCKED - WAITING FOR NAME] ${sender}: "${messageText.trim().substring(0, 50)}" ignored. Shift "${existingSession.drawShift}" is set — now send customer name.`);
          }
          continue;
        }

        // ── STATE 2b: Date set, name NOT yet set → WAITING FOR NAME ────────────────
        if (hasDate && !hasName && !hasShift) {
          if (isPureShiftMessage) {
            const session = existingSession;
            session.drawShift = explicit.explicitShift;
            session.lastUpdated = Date.now();
            senderSessions.set(sender, session);
            appendLog('success', `⏰ [SHIFT SET] ${sender}: Shift "${session.drawShift}" added. Now send customer name.`);
          } else if (explicit.explicitBuyerName) {
            const session = existingSession;
            session.buyerName = explicit.explicitBuyerName;
            session.lastUpdated = Date.now();
            senderSessions.set(sender, session);
            appendLog('success', `👤 [SESSION READY] ${sender}: Customer "${session.buyerName}" + Date "${getLocalYmd(session.drawDate)}" locked! Now accepting tickets.`);
          } else {
            appendLog('warn', `🚫 [BLOCKED - WAITING FOR NAME] ${sender}: "${messageText.trim().substring(0, 50)}" ignored. Send customer name.`);
          }
          continue;
        }

        // ── STATE 3: FULLY LOCKED — extract ONLY ticket numbers ────────────────────
        if (hasName && (hasShift || hasDate)) {
          const parsedTickets = parseIncomingTicketText(messageText, existingSession.lastSeries || '12');
          if (parsedTickets.length === 0) {
            appendLog(
              'warn',
              `🔒 [LOCKED / IGNORED] ${sender}: "${messageText.trim().substring(0, 60)}" — no tickets found. (Session: ${existingSession.buyerName} | ${existingSession.drawShift || ''} | ${existingSession.drawDate ? getLocalYmd(existingSession.drawDate) : 'today'})`
            );
            continue;
          }
          // Tickets found — push message into buffer with session-injected metadata so the
          // normal flushBufferToSupabase() pipeline saves them with locked session values.
          const rawBuyerName = existingSession.buyerName || pushName || '';
          const preview = parsedTickets.slice(0, 3).map((p) => `${p.series} #${p.ticketNo}`).join(', ');
          appendLog(
            'info',
            `📥 [PARSED -> ${existingSession.drawShift || 'Auto'} (${existingSession.drawDate ? getLocalYmd(existingSession.drawDate) : 'today'}) *LOCKED*] ${parsedTickets.length} ticket(s) from ${sender}: ${preview}${parsedTickets.length > 3 ? ` (+${parsedTickets.length - 3} more)` : ''}`
          );
          // Inject session overrides into the message entry so the flush pipeline uses them
          const lockedEntry = {
            sender,
            sender_name: rawBuyerName,
            message_text: messageText.trim(),
            message_timestamp: Number(msg.messageTimestamp || Date.now()),
            status: 'pending',
            // Session overrides — picked up in flushBufferToSupabase
            _sessionBuyerName: rawBuyerName,
            _sessionDrawShift: existingSession.drawShift || null,
            _sessionDrawDate: existingSession.drawDate ? getLocalIsoString(existingSession.drawDate, true) : null,
          };
          if (parsedTickets.length > 0) {
            existingSession.lastSeries = parsedTickets[parsedTickets.length - 1].series;
          }
          senderSessions.set(sender, existingSession);
          messageBuffer.push(lockedEntry);
          if (messageBuffer.length >= MAX_BUFFER_SIZE) flushBufferToSupabase();
          continue; // fully handled in STATE 3
        }

        // ── FALLBACK (partial session, no tickets): check if message adds date ──────
        const session = existingSession;
        const parsedTickets = parseIncomingTicketText(messageText, session.lastSeries || '12');

        if (parsedTickets.length === 0) {
          // Case A: Standalone Date or Shift Configuration (DO NOT IGNORE / DO NOT DROP TO RESOLVER)
          if (hasDateOrShift) {
            appendLog(
              'success',
              `📅 [DRAW CONFIGURED] Sender ${sender} (${pushName || 'User'}): Active Shift -> "${session.drawShift || 'Auto-Cycle'}" | Active Date -> "${session.drawDate ? session.drawDate.toLocaleDateString() : 'Today'}"${session.buyerName ? ` | Buyer: ${session.buyerName}` : ''}`
            );
            continue;
          }

          // Case B: Unknown 5-Digit Ticket format -> Save to Resolver for Operator Training
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
            // Case C: Regular non-ticket chat / greetings (0 DB Cost)
            appendLog(
              'warn',
              `🗑️ [IGNORED CHAT] Skipped non-ticket chat from ${sender}: "${messageText.trim()}" (0 DB Cost)`
            );
          }
          continue;
        }

        // Remember last used series in session for seamless subsequent single tickets
        if (parsedTickets.length > 0) {
          session.lastSeries = parsedTickets[parsedTickets.length - 1].series;
          senderSessions.set(sender, session);
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
    hasQr: connectionStatus === 'qr_ready' && Boolean(currentQrDataUrl),
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

// Endpoint: Disconnect & Switch WhatsApp Account (Purges session for fresh QR)
app.post('/unlink', async (req, res) => {
  try {
    appendLog('warn', '🔄 Unlinking active WhatsApp account and purging session...');
    if (sock) {
      try {
        await sock.logout();
      } catch (_) {
        sock.end(undefined);
      }
      sock = null;
    }
    connectionStatus = 'disconnected';
    currentQrRaw = null;
    currentQrDataUrl = null;

    const authDir = path.join(process.cwd(), 'app_session');
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

// Start Express Server
app.listen(PORT, '127.0.0.1', () => {
  appendLog('info', `⚡ WhatsApp Engine REST API listening on http://127.0.0.1:${PORT}`);
});
