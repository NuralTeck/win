/**
 * ==============================================================================
 * PRODUCTION-GRADE BAILEYS WHATSAPP CONNECTION MANAGER
 * Features:
 *   1. useMultiFileAuthState('app_session') for 1-Time QR Scan Persistence.
 *   2. Continuous creds.update listening to prevent key corruption.
 *   3. Intelligent auto-reconnect on temporary disconnects / network changes.
 *   4. Clean session purge and QR regeneration on DisconnectReason.loggedOut (401).
 * ==============================================================================
 */

const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
} = require('@whiskeysockets/baileys');
const pino = require('pino');
const path = require('path');
const fs = require('fs');

// Session directory path (Safe writable path on Windows)
function getSessionDir() {
  const baseDir = process.env.APPDATA || process.env.LOCALAPPDATA || process.env.USERPROFILE || 'C:\\Lottery_Reports';
  const targetDir = path.join(baseDir, 'OpsCore_Pro', 'whatsapp_session');
  try {
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir, { recursive: true });
    }
    return targetDir;
  } catch (err) {
    return path.join(process.cwd(), 'app_session');
  }
}
const SESSION_DIR = getSessionDir();

// Pino logger (silent to prevent CPU overhead / I/O latency)
const logger = pino({ level: 'silent' });

/**
 * Connect to WhatsApp with session persistence and self-healing lifecycle.
 * @param {Object} options
 * @param {Function} [options.onQR] - Callback when QR code is generated: (qrString) => void
 * @param {Function} [options.onConnected] - Callback when socket is open: (sock) => void
 * @param {Function} [options.onMessage] - Callback for incoming messages: (messagesArray) => void
 * @param {Function} [options.onDisconnected] - Callback on disconnect: (reason) => void
 * @returns {Promise<Object>} Baileys WASocket instance
 */
async function connectToWhatsApp(options = {}) {
  const { onQR, onConnected, onMessage, onDisconnected } = options;

  // 1. Ensure Session Directory Exists
  if (!fs.existsSync(SESSION_DIR)) {
    fs.mkdirSync(SESSION_DIR, { recursive: true });
  }

  // 2. Initialize Multi-File Auth State for Persistent 1-Time QR Authentication
  const { state, saveCreds } = await useMultiFileAuthState(SESSION_DIR);

  // 3. Fetch latest WhatsApp Web Protocol Version
  const { version, isLatest } = await fetchLatestBaileysVersion();
  console.log(`[BAILEYS] Using WhatsApp Web version: v${version.join('.')} (Latest: ${isLatest})`);

  // 4. Instantiate WhatsApp Socket
  const sock = makeWASocket({
    version,
    logger,
    printQRInTerminal: true, // Also prints in terminal for quick scan
    auth: {
      creds: state.creds,
      // Wrap keys in cacheable keystore to avoid excessive disk I/O
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    browser: ['OpsCore Desktop Bot', 'Chrome', '120.0.0'],
    syncFullHistory: false,
    markOnlineOnConnect: true,
    generateHighQualityLinkPreview: false,
    connectTimeoutMs: 60000,
    keepAliveIntervalMs: 25000,
    defaultQueryTimeoutMs: 60000,
  });

  // 5. Clean Handshake: Continuously persist credentials whenever updated
  sock.ev.on('creds.update', async () => {
    try {
      await saveCreds();
      // console.log('[BAILEYS] Session credentials saved successfully.');
    } catch (err) {
      console.error('[BAILEYS] Error saving session credentials:', err);
    }
  });

  // 6. Handle Connection Lifecycle Updates
  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    // --- CASE A: QR Code Generated (Only on 1st time or after logout) ---
    if (qr) {
      console.log('[BAILEYS] 📲 Scan the QR Code above to link WhatsApp device.');
      if (typeof onQR === 'function') {
        onQR(qr);
      }
    }

    // --- CASE B: Socket Disconnected ---
    if (connection === 'close') {
      const statusCode = lastDisconnect?.error?.output?.statusCode;
      const isLoggedOut = statusCode === DisconnectReason.loggedOut;

      console.warn(
        `[BAILEYS] ⚠️ Connection closed (Status Code: ${statusCode || 'Unknown'}). Logged Out: ${isLoggedOut}`
      );

      if (typeof onDisconnected === 'function') {
        onDisconnected({ statusCode, isLoggedOut, error: lastDisconnect?.error });
      }

      if (isLoggedOut) {
        // Logged out: Purge corrupted or invalid session directory and restart for fresh QR
        console.log('[BAILEYS] 🗑️ Device was logged out. Clearing app_session directory...');
        try {
          if (fs.existsSync(SESSION_DIR)) {
            fs.rmSync(SESSION_DIR, { recursive: true, force: true });
            console.log('[BAILEYS] ✅ Session directory deleted. Ready for fresh pairing.');
          }
        } catch (fsErr) {
          console.error('[BAILEYS] Error deleting session directory:', fsErr);
        }

        // Reconnect to display a fresh QR code
        setTimeout(() => connectToWhatsApp(options), 2000);
      } else {
        // Temporary network drop, server reset, or restart required -> Immediate auto-reconnect
        const reconnectDelayMs = statusCode === DisconnectReason.restartRequired ? 1000 : 3000;
        console.log(`[BAILEYS] 🔄 Auto-reconnecting in ${reconnectDelayMs}ms...`);
        setTimeout(() => connectToWhatsApp(options), reconnectDelayMs);
      }
    }

    // --- CASE C: Connection Established ---
    else if (connection === 'open') {
      console.log('---------------------------------------------------------');
      console.log(`✅ [BAILEYS] Connected as: ${sock.user?.id || 'Authenticated User'}`);
      console.log('⚡ WhatsApp Session is Active & Listening for Messages!');
      console.log('---------------------------------------------------------');

      if (typeof onConnected === 'function') {
        onConnected(sock);
      }
    }
  });

  // 7. Incoming Messages Hook
  sock.ev.on('messages.upsert', async (m) => {
    if (m.type !== 'notify') return;
    if (typeof onMessage === 'function') {
      onMessage(m.messages, sock);
    }
  });

  return sock;
}

// Export function as modular library
module.exports = {
  connectToWhatsApp,
  SESSION_DIR,
};

// If executed directly (e.g. `node whatsapp_connection.js`), run standalone
if (require.main === module) {
  connectToWhatsApp({
    onQR: () => console.log('QR Code ready for scan!'),
    onConnected: () => console.log('Bot is live and ready!'),
    onMessage: (msgs) => {
      for (const msg of msgs) {
        if (!msg.key.fromMe) {
          const from = msg.key.remoteJid;
          const body = msg.message?.conversation || msg.message?.extendedTextMessage?.text || '';
          console.log(`📩 [INCOMING] From: ${from} | Msg: ${body}`);
        }
      }
    },
  });
}
