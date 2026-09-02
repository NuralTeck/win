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
  `);
  console.log('✅ [LOCAL SQLITE] Connected to opscore_pro.db at:', dbPath);
} catch (sqliteErr) {
  console.log('⚠️ [LOCAL SQLITE] Could not open local SQLite db:', sqliteErr.message);
}

let supabase = null;
if (SUPABASE_URL && SUPABASE_KEY) {
  supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false },
  });
}

process.stdout?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});
process.stderr?.on('error', (err) => {
  if (err?.code === 'EPIPE') return;
});

process.on('uncaughtException', (err) => {
  if (err?.code === 'EPIPE' || err?.message?.includes('EPIPE')) return;
  try { appendLog('warn', `🛡️ [CRASH GUARD] Exception: ${err?.message || err}`); } catch (_) {}
});
process.on('unhandledRejection', (reason) => {
  try { appendLog('warn', `🛡️ [CRASH GUARD] Rejection: ${reason?.message || reason}`); } catch (_) {}
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
  } catch (_) {}
}

function getEffectiveTarget(senderPhone) {
  readLiveTargetLock();

  // 1. Shift
  let shift = 'Dear 8 PM';
  if (globalTargetConfig.lockedShift && globalTargetConfig.lockedShift !== 'auto') {
    shift = globalTargetConfig.lockedShift;
  }

  // 2. Date
  let date = new Date(2026, 8, 2); // 2026-09-02
  if (globalTargetConfig.lockedDate && globalTargetConfig.lockedDate !== 'auto') {
    const p = globalTargetConfig.lockedDate.split('-');
    if (p.length === 3) {
      date = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
    }
  }

  // 3. Party Name (UI Lock always wins)
  let buyer = globalTargetConfig.lockedBuyerName;
  if (!buyer || buyer.toLowerCase() === 'auto') {
    buyer = `Party ${String(senderPhone).slice(-4)}`;
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
  } catch (_) {}
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
  } catch (_) {}
}

function cleanSeriesNumber(rawSeries, fallback = '12') {
  if (!rawSeries) return fallback;
  const digits = String(rawSeries).replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 4) {
    return digits;
  }
  return fallback;
}

function isPureSeriesLine(line) {
  const clean = line.replace(/[^\w]/g, '').trim();
  if (!clean) return false;
  const digits = clean.replace(/\D/g, '');
  if (digits.length > 0 && digits.length <= 3) {
    const val = parseInt(digits, 10);
    return val > 0 && val <= 120;
  }
  return false;
}

/**
 * Universal Ticket Parser:
 * - Standalone 5-digit number strictly defaults to '12'
 * - Detects top series and bottom series
 */
function parseIncomingTicketText(text, defaultSeries = '12') {
  const cleanedText = text
    .replace(/\b\d{1,2}[=\/\.-]\d{1,2}[=\/\.-]\d{2,4}(?:=[0-9A-Za-z]+)?\b/g, ' ')
    .replace(/\b\d{1,2}\/\d{1,2}\b/g, ' ');

  const items = [];
  const lines = cleanedText.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length > 0);
  let currentSeries = cleanSeriesNumber(defaultSeries, '12');

  // Look-ahead check: agar aakhiri line series ho
  let bottomSeries = null;
  if (lines.length > 1 && isPureSeriesLine(lines[lines.length - 1])) {
    bottomSeries = cleanSeriesNumber(lines[lines.length - 1], '12');
    currentSeries = bottomSeries;
  }

  for (let i = 0; i < lines.length; i++) {
    let l = lines[i].trim();
    if (!l) continue;

    if (/^(?:dear\s*)?[168]\s*(?:pm|am|gm|baje)$/i.test(l)) continue;
    if (/^[A-Za-z][A-Za-z\s]{1,30}\s+(?:boakg|booking|bookin|bokg|bok|bkg)\s*$/i.test(l)) continue;
    if (/^(?:Forwarded|\u203A\u203A\s*Forwarded|fwd|forward)/i.test(l)) continue;

    if (isPureSeriesLine(l)) {
      const extracted = cleanSeriesNumber(l, '');
      if (extracted) {
        currentSeries = extracted;
        for (let j = items.length - 1; j >= 0; j--) {
          if (!items[j].isSeriesLocked) {
            items[j].series = extracted;
            items[j].isSeriesLocked = true;
          } else break;
        }
        continue;
      }
    }

    const lineForTickets = l.replace(/(?:=|\b)(?:dear\s*)?[168]\s*(?:pm|am|qm|gm|baje)\b/gi, ' ').trim();

    // Pattern 1: Triplet Range e.g. 62759-83-25 or 40280-289-10
    const tripletMatch = lineForTickets.match(/(?:([0-9]{1,3})\s*[:=/]\s*)?(\d{5})\s*[-~to]+\s*(\d{1,5})\s*[-=x*,\s]+\s*(\d+)/i);
    if (tripletMatch) {
      const s = tripletMatch[1] ? cleanSeriesNumber(tripletMatch[1], currentSeries) : currentSeries;
      const startNum = parseInt(tripletMatch[2], 10);
      const count = parseInt(tripletMatch[4], 10);
      if (!isNaN(startNum) && count > 0 && count <= 150) {
        for (let k = 0; k < count; k++) {
          items.push({
            series: s || '12',
            isSeriesLocked: true,
            ticketNo: String(startNum + k).padStart(5, '0'),
          });
        }
        currentSeries = s || currentSeries;
        continue;
      }
    }

    // Pattern 2: Hyphen range e.g. 50170-189
    const hyphenMatch = lineForTickets.match(/(?:([0-9]{1,3})\s*[:=/]\s*)?(\d{5})\s*[-~to]+\s*(\d{1,5})/i);
    if (hyphenMatch) {
      const s = hyphenMatch[1] ? cleanSeriesNumber(hyphenMatch[1], currentSeries) : currentSeries;
      const startNum = parseInt(hyphenMatch[2], 10);
      const endPart = hyphenMatch[3];
      const prefix = String(startNum).slice(0, 5 - endPart.length);
      const fullEndNum = parseInt(prefix + endPart, 10);
      if (!isNaN(startNum) && !isNaN(fullEndNum) && fullEndNum >= startNum && fullEndNum - startNum <= 150) {
        for (let n = startNum; n <= fullEndNum; n++) {
          items.push({
            series: s || '12',
            isSeriesLocked: true,
            ticketNo: String(n).padStart(5, '0'),
          });
        }
        currentSeries = s || currentSeries;
        continue;
      }
    }

    // Pattern 3: Prefix Series e.g. 24=62676, 12=36773
    const prefixMatch = lineForTickets.match(/^(?:[\(\[]\s*([0-9]{1,3}[A-Za-z]?)\s*[\)\]]|([0-9]{1,3}[A-Za-z]?)\s*[:=/\-._~*#@+]+)\s*(\d{5})$/);
    if (prefixMatch) {
      const rawS = prefixMatch[1] || prefixMatch[2] || currentSeries;
      const s = cleanSeriesNumber(rawS, currentSeries);
      const tNo = prefixMatch[3];
      items.push({
        series: s || '12',
        isSeriesLocked: true,
        ticketNo: tNo,
      });
      continue;
    }

    // Pattern 4: Suffix Series e.g. 36963 -40
    const suffixMatch = lineForTickets.match(/^(\d{5})\s*[-:,\/=\s._~|*xX#@+]+\s*([0-9]{1,3}[A-Za-z]{0,4}|[A-Za-z]{1,4}[0-9]{1,3})$/);
    if (suffixMatch) {
      const tNo = suffixMatch[1];
      const s = cleanSeriesNumber(suffixMatch[2], currentSeries);
      items.push({
        series: s || '12',
        isSeriesLocked: true,
        ticketNo: tNo,
      });
      continue;
    }

    // Pattern 5: Direct 5-digit number (Default 12)
    const all5s = lineForTickets.match(/\b\d{5}\b/g);
    if (all5s && all5s.length > 0) {
      for (const tNo of all5s) {
        items.push({
          series: currentSeries || '12',
          isSeriesLocked: Boolean(bottomSeries),
          ticketNo: tNo,
        });
      }
      continue;
    }
  }

  return items;
}

// --- 2. BATCH BUFFERING & DATABASE STORAGE ---
async function flushBufferToSupabase() {
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
        try { localDb.exec('ROLLBACK'); } catch (_) {}
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
  if (messageBuffer.length > 0) flushBufferToSupabase();
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
    } catch (_) {}
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
      try { await saveCreds(); } catch (_) {}
    }

    let version = [2, 3000, 1043857760];
    try {
      const v = await fetchLatestBaileysVersion();
      if (v?.version) version = v.version;
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
      getMessage: async () => ({ conversation: '' }),
    });

    sock.ev.on('creds.update', async () => {
      try { await saveCreds(); } catch (_) {}
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

        let messageText =
          msg.message?.conversation ||
          msg.message?.extendedTextMessage?.text ||
          msg.message?.imageMessage?.caption ||
          '';

        if (!messageText || messageText.trim().length === 0) continue;

        // 🔒 STRICT TARGET LOCK LIVE ENFORCEMENT
        const effective = getEffectiveTarget(sender);

        // Parse tickets (Default strictly '12')
        const parsedTickets = parseIncomingTicketText(messageText, '12');

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
            flushBufferToSupabase();
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
    if (messageBuffer.length > 0) await flushBufferToSupabase();
    sock.ev.removeAllListeners();
    sock.end(undefined);
    sock = null;
  } catch (_) {}
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
    supabaseConfigured: Boolean(supabase),
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

app.listen(PORT, '127.0.0.1', () => {
  appendLog('info', `⚡ WhatsApp Engine REST API listening on http://127.0.0.1:${PORT}`);
});