// =========================================================================
// OPSCORE MASTER ADMIN WEB CONTROLLER
// Real-time Supabase Data Fetching, Live Device Tracking, Remote Kill Switch,
// User Account Creation & Remote Party Hisab
// =========================================================================

const SUPABASE_CONFIG = {
  url: 'https://wagslwsfhbrcyakazibv.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndhZ3Nsd3NmaGJyY3lha2F6aWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MjE3NDMsImV4cCI6MjEwMTQ5Nzc0M30.vpEfCQhToOjGH6U_8dqN1EqT0Dd13prQtDHYvhoUtGA'
};

// Initialize Supabase client
let supabaseClient = null;
try {
  if (window.supabase) {
    supabaseClient = window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey);
    console.log('⚡ [MASTER ADMIN] Connected to Supabase Cloud.');
  }
} catch (e) {
  console.error('⚠️ [SUPABASE INIT ERROR]:', e);
}

// State
let allSessions = [];
let allLicenses = [];
let allPartyHisabs = [];
let refreshTimerSecs = 10;
let refreshInterval = null;

// DOM Elements
const cloudStatusPill = document.getElementById('cloudStatusPill');
const cloudStatusText = document.getElementById('cloudStatusText');
const systemClock = document.getElementById('systemClock');
const btnManualRefresh = document.getElementById('btnManualRefresh');
const refreshCountdown = document.getElementById('refreshCountdown');
const toastEl = document.getElementById('toast');

// KPIs
const kpiActiveCount = document.getElementById('kpiActiveCount');
const kpiActiveFoot = document.getElementById('kpiActiveFoot');
const kpiPartyCount = document.getElementById('kpiPartyCount');
const kpiTotalHisab = document.getElementById('kpiTotalHisab');
const kpiTotalSessions = document.getElementById('kpiTotalSessions');

// Badges
const activeBadgeCount = document.getElementById('activeBadgeCount');
const licensesBadgeCount = document.getElementById('licensesBadgeCount');
const partyBadgeCount = document.getElementById('partyBadgeCount');

// Views & Containers
const liveSessionsGrid = document.getElementById('liveSessionsGrid');
const licensesTableBody = document.getElementById('licensesTableBody');
const partyHisabTableBody = document.getElementById('partyHisabTableBody');
const auditHistoryTableBody = document.getElementById('auditHistoryTableBody');

// Inputs & Buttons
const partySearchInput = document.getElementById('partySearchInput');
const auditSearchInput = document.getElementById('auditSearchInput');
const licenseSearchInput = document.getElementById('licenseSearchInput');
const btnCopySql = document.getElementById('btnCopySql');
const sqlCodeBlock = document.getElementById('sqlCodeBlock');

// User Creation Form
const newUserForm = document.getElementById('newUserForm');
const newEmailInput = document.getElementById('newEmail');
const newNameInput = document.getElementById('newName');
const newPasswordInput = document.getElementById('newPassword');
const newValiditySelect = document.getElementById('newValidity');
const newNotesInput = document.getElementById('newNotes');
const btnGenPass = document.getElementById('btnGenPass');
const btnCreateUser = document.getElementById('btnCreateUser');

// ─── INITIALIZATION ─────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  setupTabs();
  startClock();
  setupSearch();
  setupSqlCopy();
  setupUserCreation();
  setupModalEvents();

  if (btnManualRefresh) {
    btnManualRefresh.addEventListener('click', () => {
      refreshAllData(true);
    });
  }

  // Initial load
  refreshAllData(false);

  // Auto-refresh countdown loop
  startAutoRefreshLoop();
});

// ─── TABS & MULTI-PAGE SWITCHER ─────────────────────────────────────────────

function setupTabs() {
  const tabs = document.querySelectorAll('button.tab-btn[data-tab]');
  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-view').forEach(v => v.classList.remove('active'));

      btn.classList.add('active');
      const targetId = btn.getAttribute('data-tab');
      const targetView = document.getElementById(targetId);
      if (targetView) targetView.classList.add('active');
    });
  });
}

// ─── LIVE CLOCK & IST TIME FORMATTER ────────────────────────────────────────

function formatISTDate(dateInput, includeSeconds = false) {
  if (!dateInput) return '—';
  try {
    const d = new Date(dateInput);
    if (isNaN(d.getTime())) return String(dateInput);
    return d.toLocaleString('en-IN', {
      timeZone: 'Asia/Kolkata',
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: includeSeconds ? '2-digit' : undefined,
      hour12: true
    }) + ' IST';
  } catch (_) {
    return String(dateInput);
  }
}

function startClock() {
  if (!systemClock) return;
  function updateTime() {
    const now = new Date();
    systemClock.textContent = now.toLocaleTimeString('en-IN', {
      timeZone: 'Asia/Kolkata',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: true
    }) + ' IST';
  }
  updateTime();
  setInterval(updateTime, 1000);
}

function startAutoRefreshLoop() {
  refreshTimerSecs = 10;
  if (refreshInterval) clearInterval(refreshInterval);

  refreshInterval = setInterval(() => {
    refreshTimerSecs--;
    if (refreshCountdown) refreshCountdown.textContent = `${refreshTimerSecs}s`;

    if (refreshTimerSecs <= 0) {
      refreshTimerSecs = 10;
      refreshAllData(false);
    }
  }, 1000);
}

// ─── TOAST NOTIFICATION ─────────────────────────────────────────────────────

function showToast(msg) {
  toastEl.textContent = msg;
  toastEl.classList.add('show');
  setTimeout(() => toastEl.classList.remove('show'), 3500);
}

// ─── DATA FETCHING & MASTER DISPATCH ────────────────────────────────────────

async function refreshAllData(showUserFeedback = false) {
  if (!supabaseClient) {
    setCloudStatus(false, 'Supabase Client Not Loaded');
    return;
  }

  try {
    // 1. Fetch Live Sessions
    const { data: sessions, error: sessErr } = await supabaseClient
      .from('app_sessions')
      .select('*')
      .order('login_time', { ascending: false });

    if (!sessErr && sessions) {
      allSessions = sessions;
      renderSessionsData(allSessions);
    }

    // 2. Fetch User Licenses
    const { data: licenses, error: licErr } = await supabaseClient
      .from('app_licenses')
      .select('*')
      .order('created_at', { ascending: false });

    if (!licErr && licenses) {
      allLicenses = licenses;
      renderLicensesData(allLicenses);
    } else {
      renderLicensesData([]);
    }

    // 3. Fetch Party Hisab Summaries
    const { data: parties, error: partyErr } = await supabaseClient
      .from('party_hisab')
      .select('*')
      .order('updated_at', { ascending: false });

    if (!partyErr && parties) {
      allPartyHisabs = parties;
      renderPartyHisabData(allPartyHisabs);
    } else {
      renderPartyHisabData([]);
    }

    setCloudStatus(true, 'Supabase Cloud Connected');
    if (showUserFeedback) showToast('✅ Data refreshed successfully!');
  } catch (err) {
    console.error('Error fetching data:', err);
    setCloudStatus(false, 'Connection Error');
  }
}

function setCloudStatus(isOnline, text) {
  if (cloudStatusPill && cloudStatusText) {
    if (isOnline) {
      cloudStatusPill.className = 'live-pill';
      cloudStatusText.textContent = text || 'Supabase Connected';
    } else {
      cloudStatusPill.className = 'live-pill disconnected';
      cloudStatusText.textContent = text || 'Offline / Disconnected';
    }
  }
}

// ─── TAB 1: RENDER SESSIONS & LIVE ONLINE DEVICES ───────────────────────────

function renderSessionsData(sessions) {
  const now = new Date();

  // Active instances: heartbeat within last 3 minutes (180s) AND NOT blocked
  // NOTE: Supabase stores timestamps in UTC. new Date() correctly parses ISO UTC strings.
  const activeSessions = sessions.filter(s => {
    if (s.is_blocked || s.status === 'Blocked' || s.status === 'Killed') return false;
    if (!s.last_heartbeat) return false;
    const hbDate = new Date(s.last_heartbeat); // Supabase returns ISO UTC → correct
    const diffSecs = (now.getTime() - hbDate.getTime()) / 1000;
    return diffSecs <= 180; // 3 minutes window
  });

  // Update Top KPIs if present
  if (kpiActiveCount) kpiActiveCount.textContent = activeSessions.length;
  if (activeBadgeCount) activeBadgeCount.textContent = activeSessions.length;
  if (kpiTotalSessions) kpiTotalSessions.textContent = sessions.length;
  if (kpiActiveFoot) kpiActiveFoot.textContent = `${activeSessions.length} device(s) online right now`;

  // Render Grid Cards for Live Sessions
  // Only show: (1) Blocked sessions [admin needs to see them], (2) Recent heartbeat sessions
  // Hide: pure Offline / Kicked / stale sessions (no recent heartbeat AND not blocked)
  if (!liveSessionsGrid) {
    renderAuditHistoryTable(sessions);
    return;
  }

  // Strict Deduplication:
  // Sort with newest heartbeat or login_time first
  const sorted = [...sessions].sort((a, b) => {
    const timeB = new Date(b.last_heartbeat || b.login_time).getTime();
    const timeA = new Date(a.last_heartbeat || a.login_time).getTime();
    return timeB - timeA;
  });

  const deduped = [];
  const seenEmails = new Set();
  const seenDevices = new Set();

  for (const s of sorted) {
    const email = (s.user_email || '').trim().toLowerCase();
    const device = (s.device_name || '').trim().toLowerCase();

    // 1 user account = only 1 active instance allowed
    if (email && seenEmails.has(email)) continue;
    // 1 physical computer = only 1 active instance allowed
    if (device && seenDevices.has(device)) continue;

    if (email) seenEmails.add(email);
    if (device) seenDevices.add(device);
    deduped.push(s);
  }

  // Filter: show blocked ones always + recent heartbeat ones
  const visibleSessions = deduped.filter(s => {
    const isBlocked = s.is_blocked === true || s.status === 'Blocked';
    if (isBlocked) return true; // Always show blocked — admin needs to unblock
    if (s.status === 'Offline' || s.status === 'Kicked') return false; // Hide clean offline
    const hbDate = s.last_heartbeat ? new Date(s.last_heartbeat) : null;
    const diffSecs = hbDate ? (now.getTime() - hbDate.getTime()) / 1000 : 9999;
    return diffSecs <= 300; // Show if heartbeat within last 5 minutes
  });

  if (visibleSessions.length === 0) {
    liveSessionsGrid.innerHTML = `
      <div class="loading-state" style="grid-column: 1 / -1;">
        <p style="font-size: 15px; color: #94A3B8;">ℹ️ No active software sessions right now.<br>
        <span style="font-size: 12px; color: #64748B;">Once users login via the desktop app, their device and online duration will appear here live!</span></p>
      </div>
    `;
  } else {
    liveSessionsGrid.innerHTML = visibleSessions.map(s => {
      const hbDate = s.last_heartbeat ? new Date(s.last_heartbeat) : null;
      const hbDiffSecs = hbDate ? Math.max(0, Math.floor((now - hbDate) / 1000)) : 9999;
      const isBlocked = s.is_blocked === true || s.status === 'Blocked';
      const isLiveNow = !isBlocked && hbDiffSecs <= 180; // 3 min window, no is_online dependency

      const loginDate = new Date(s.login_time);
      const loginStr = formatISTDate(s.login_time);

      const totalSecs = s.total_online_seconds || (isLiveNow ? Math.floor((now - loginDate) / 1000) : 0);
      const durationStr = formatDuration(totalSecs);

      let statusBadgeHtml = '';
      if (isBlocked) {
        statusBadgeHtml = '<span class="status-indicator status-offline" style="background:rgba(239,68,68,0.2); color:#F87171; border-color:rgba(239,68,68,0.5);">🔒 LOCKED</span>';
      } else if (isLiveNow) {
        statusBadgeHtml = '<span class="status-indicator status-online"><span class="pulsing-dot"></span> LIVE ONLINE</span>';
      } else {
        statusBadgeHtml = '<span class="status-indicator status-offline">⚪ OFFLINE</span>';
      }

      return `
        <div class="session-card ${isBlocked ? 'is-offline' : (isLiveNow ? 'is-online' : 'is-offline')}" 
             style="${isBlocked ? 'border-left: 4px solid #EF4444;' : ''}"
             onclick="openUserHistoryModal('${escapeHtml(s.user_email)}', '${escapeHtml(s.device_name)}')">
          <div class="card-top">
            <div class="device-badge-row">
              <div class="device-icon-box">${isBlocked ? '🔒' : '💻'}</div>
              <div class="device-title-wrap">
                <h3>${escapeHtml(s.device_name || 'Windows PC')}</h3>
                <span class="device-os">${escapeHtml(s.os_info || 'Windows Desktop')}</span>
              </div>
            </div>
            ${statusBadgeHtml}
          </div>

          <div style="font-size: 13.5px; font-weight: 600; color: #F8FAFC; margin-bottom: 2px;">
            👤 ${escapeHtml(s.user_name || s.user_email || 'Authorized User')}
          </div>
          <div style="font-size: 11.5px; color: #38BDF8; font-family: monospace;">
            ✉️ ${escapeHtml(s.user_email || '—')}
          </div>

          <div class="card-metrics-row">
            <div class="metric-item">
              <span class="metric-lbl">ONLINE TIME</span>
              <span class="metric-val" style="color: ${isBlocked ? '#F87171' : '#34D399'};">${durationStr}</span>
            </div>
            <div class="metric-item">
              <span class="metric-lbl">HEARTBEAT PING</span>
              <span class="metric-val" style="font-size: 12px; color: ${isLiveNow ? '#38BDF8' : '#64748B'};">
                ${isBlocked ? 'Locked by Owner' : (isLiveNow ? `${hbDiffSecs}s ago` : 'Disconnected')}
              </span>
            </div>
          </div>

          <div class="card-footer-info">
            <span>📅 Login: <strong>${loginStr}</strong></span>
            <span>Ver: <strong>${s.app_version || '2.0.0'}</strong></span>
          </div>

          <div class="card-hint-badge">
            <span>📜 Click to view full session history & details</span>
          </div>

          <!-- Remote Kill & Lock Buttons -->
          <div class="card-actions-row">
            ${isBlocked ? `
              <button class="btn-action btn-success" onclick="event.stopPropagation(); unblockSession('${escapeHtml(s.session_id)}', '${escapeHtml(s.user_email)}')">
                🔓 Unlock Software
              </button>
            ` : `
              <button class="btn-action btn-danger" onclick="event.stopPropagation(); blockSession('${escapeHtml(s.session_id)}', '${escapeHtml(s.user_email)}')">
                🔒 Block & Lock
              </button>
              ${isLiveNow ? `
                <button class="btn-action btn-warning" onclick="event.stopPropagation(); killSession('${escapeHtml(s.session_id)}')">
                  ⚡ Force Logout
                </button>
              ` : ''}
            `}
          </div>
        </div>
      `;
    }).join('');
  }

  renderAuditHistoryTable(sessions);
}

// ─── TAB 2: USER & LICENSE MANAGEMENT ───────────────────────────────────────

function setupUserCreation() {
  if (btnGenPass && newPasswordInput) {
    btnGenPass.addEventListener('click', () => {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$';
      let pass = '';
      for (let i = 0; i < 10; i++) {
        pass += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      newPasswordInput.value = pass;
      showToast('🎲 Generated random password: ' + pass);
    });
  }

  if (newUserForm) {
    newUserForm.addEventListener('submit', async (e) => {
      e.preventDefault();

      const email = newEmailInput ? newEmailInput.value.trim() : '';
      const name = newNameInput ? newNameInput.value.trim() : '';
      const pass = newPasswordInput ? newPasswordInput.value.trim() : '';
      const validity = newValiditySelect ? newValiditySelect.value : 'Lifetime';
      const notes = newNotesInput ? newNotesInput.value.trim() : '';

      if (!email || !name || !pass) {
        showToast('⚠️ Please fill email, name, and password.');
        return;
      }

      if (btnCreateUser) {
        btnCreateUser.disabled = true;
        btnCreateUser.innerHTML = '<span>⏳ Creating Account...</span>';
      }

      try {
        // 1. Create Supabase Auth Account
        const { data: authData, error: authErr } = await supabaseClient.auth.signUp({
          email: email,
          password: pass,
          options: {
            data: {
              full_name: name,
              role: 'Administrator',
            }
          }
        });

        if (authErr) {
          if (authErr.message && authErr.message.toLowerCase().includes('already registered')) {
            console.log('Account already exists in Auth, updating license record...');
          } else {
            throw new Error(authErr.message);
          }
        }

        // 2. Insert / Upsert into app_licenses table (with graceful fallback if table not yet created)
        const licId = 'lic_' + Date.now();
        let licTableSynced = false;
        try {
          const { error: licErr } = await supabaseClient.from('app_licenses').upsert({
            id: licId,
            user_email: email.toLowerCase(),
            full_name: name,
            license_status: 'Active',
            is_blocked: false,
            valid_until: validity,
            notes: notes,
            created_at: new Date().toISOString(),
          }, { onConflict: 'user_email' });

          if (!licErr) {
            licTableSynced = true;
          } else {
            console.warn('app_licenses cloud table notice:', licErr.message);
          }
        } catch (tableErr) {
          console.warn('app_licenses table not available:', tableErr);
        }

        // 3. Always cache in local state & localStorage so user appears in table immediately
        const newLicObj = {
          id: licId,
          user_email: email.toLowerCase(),
          full_name: name,
          license_status: 'Active',
          is_blocked: false,
          valid_until: validity,
          notes: notes,
          created_at: new Date().toISOString(),
        };

        const cachedLicenses = JSON.parse(localStorage.getItem('cached_licenses') || '[]');
        const existingIdx = cachedLicenses.findIndex(c => (c.user_email || '').toLowerCase() === email.toLowerCase());
        if (existingIdx >= 0) {
          cachedLicenses[existingIdx] = newLicObj;
        } else {
          cachedLicenses.unshift(newLicObj);
        }
        localStorage.setItem('cached_licenses', JSON.stringify(cachedLicenses));

        // Re-render table with new user
        allLicenses = cachedLicenses;
        renderLicensesData(allLicenses);

        if (licTableSynced) {
          showToast(`🎉 User ${email} created & activated successfully!`);
        } else {
          showToast(`🎉 User ${email} created in Supabase Auth successfully!`);
        }

        newUserForm.reset();
      } catch (err) {
        console.error('Error creating user:', err);
        const errMsg = err.message || String(err);
        if (errMsg.toLowerCase().includes('rate limit')) {
          showToast('⚠️ Supabase Email Limit: Turn OFF "Confirm email" in Supabase Auth -> Providers -> Email to allow unlimited instant logins!');
        } else {
          showToast('⚠️ Error creating user: ' + errMsg);
        }
      } finally {
        if (btnCreateUser) {
          btnCreateUser.disabled = false;
          btnCreateUser.innerHTML = '<span>🚀 CREATE & ACTIVATE USER</span>';
        }
      }
    });
  }
}

function renderLicensesData(licenses) {
  if (licensesBadgeCount) licensesBadgeCount.textContent = licenses.length;
  if (!licensesTableBody) return;

  const query = (licenseSearchInput ? licenseSearchInput.value : '').trim().toLowerCase();
  const filtered = licenses.filter(l => {
    if (!query) return true;
    return (l.user_email || '').toLowerCase().includes(query) ||
           (l.full_name || '').toLowerCase().includes(query);
  });

  if (filtered.length === 0) {
    licensesTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="text-center py-5" style="color: #64748B;">
          ${licenses.length === 0 ? 'No client licenses created yet. Use the form on the left to create a user!' : 'No license matched your search.'}
        </td>
      </tr>
    `;
    return;
  }

  licensesTableBody.innerHTML = filtered.map(l => {
    const isBlocked = l.is_blocked === true || l.license_status === 'Blocked';
    const createdStr = formatISTDate(l.created_at);

    return `
      <tr>
        <td>
          <strong style="color: #38BDF8; font-size: 13.5px;">${escapeHtml(l.user_email)}</strong>
          ${l.notes ? `<div style="font-size: 10.5px; color: #94A3B8;">📝 ${escapeHtml(l.notes)}</div>` : ''}
        </td>
        <td><strong>${escapeHtml(l.full_name || '—')}</strong></td>
        <td><span class="badge-tag badge-blue">${escapeHtml(l.valid_until || 'Lifetime')}</span></td>
        <td style="font-size: 11.5px; color: #94A3B8;">${createdStr}</td>
        <td>
          <span class="status-indicator ${isBlocked ? 'status-offline' : 'status-online'}" style="${isBlocked ? 'background:rgba(239,68,68,0.15); color:#F87171;' : ''}">
            ${isBlocked ? '🔒 Blocked / Locked' : '🟢 Active License'}
          </span>
        </td>
        <td>
          <div style="display: flex; gap: 6px; align-items: center; flex-wrap: wrap;">
            ${isBlocked ? `
              <button class="btn-action btn-success" title="Unblock user software access" onclick="toggleUserLock('${escapeHtml(l.user_email)}', false)">
                🔓 UNBLOCK
              </button>
            ` : `
              <button class="btn-action btn-danger" title="Block / Lock user software access" onclick="toggleUserLock('${escapeHtml(l.user_email)}', true)">
                🔒 BLOCK
              </button>
            `}
            <button class="btn-action" style="background: rgba(14, 165, 233, 0.15); color: #38BDF8; border: 1px solid rgba(14, 165, 233, 0.35);" title="Only Admin can reset password" onclick="openResetPassModal('${escapeHtml(l.user_email)}')">
              🔑 Reset Pass
            </button>
            <button class="btn-action btn-warning" title="Delete record" onclick="deleteLicense('${escapeHtml(l.id)}', '${escapeHtml(l.user_email)}')">
              🗑️
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

// ─── ADMIN-ONLY PASSWORD RESET CONTROLLER ─────────────────────────────────

let currentResetEmail = '';

window.openResetPassModal = function(email) {
  currentResetEmail = (email || '').trim();
  const modal = document.getElementById('resetPassModal');
  const targetLabel = document.getElementById('resetTargetEmail');
  const passInput = document.getElementById('resetNewPass');
  if (targetLabel) targetLabel.textContent = currentResetEmail;
  if (passInput) passInput.value = '';
  if (modal) modal.style.display = 'flex';
};

window.closeResetPassModal = function() {
  const modal = document.getElementById('resetPassModal');
  if (modal) modal.style.display = 'none';
  currentResetEmail = '';
};

window.generateResetPassword = function() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%';
  let pass = '';
  for (let i = 0; i < 10; i++) {
    pass += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  const input = document.getElementById('resetNewPass');
  if (input) input.value = pass;
  showToast('🎲 Generated password: ' + pass);
};

window.submitPasswordReset = async function() {
  const passInput = document.getElementById('resetNewPass');
  const newPass = passInput ? passInput.value.trim() : '';
  if (!newPass || newPass.length < 6) {
    showToast('⚠️ Password must be at least 6 characters long.');
    return;
  }
  if (!currentResetEmail) {
    showToast('⚠️ No target user selected.');
    return;
  }

  const btnConfirm = document.getElementById('btnConfirmResetPass');
  if (btnConfirm) {
    btnConfirm.disabled = true;
    btnConfirm.textContent = 'Updating...';
  }

  try {
    // 1. Call Postgres SECURITY DEFINER RPC function to update password in auth.users
    const { data, error } = await supabaseClient.rpc('admin_reset_user_password', {
      target_email: currentResetEmail,
      new_password: newPass
    });

    if (error) {
      console.warn('admin_reset_user_password RPC notice:', error);
      showToast('⚠️ Error: ' + error.message + ' (Make sure SQL function admin_reset_user_password is run in Supabase)');
    } else {
      showToast(`🔑 Success! Password for ${currentResetEmail} has been reset by Admin.`);
      closeResetPassModal();
    }
  } catch (err) {
    console.error('Password reset failed:', err);
    showToast('⚠️ Password reset failed: ' + (err.message || String(err)));
  } finally {
    if (btnConfirm) {
      btnConfirm.disabled = false;
      btnConfirm.textContent = 'Update Password';
    }
  }
};

// ─── REMOTE LOCK / UNBLOCK / KILL ACTIONS ───────────────────────────────────

window.toggleUserLock = async function(email, shouldBlock) {
  const rawEmail = (email || '').trim();
  const cleanEmail = rawEmail.toLowerCase();
  const actionName = shouldBlock ? 'BLOCK & LOCK' : 'UNBLOCK';

  if (!rawEmail) {
    showToast('⚠️ Error: No user email provided.');
    return;
  }

  if (!confirm(`Are you sure you want to ${actionName} software access for:\n${rawEmail}?`)) {
    return;
  }

  console.log(`[toggleUserLock] Action: ${actionName}, Email: ${rawEmail}, supabaseClient: ${!!supabaseClient}`);

  // 1. Instant Optimistic UI Update
  const lic = allLicenses.find(l => (l.user_email || '').toLowerCase() === cleanEmail);
  if (lic) {
    lic.is_blocked = shouldBlock;
    lic.license_status = shouldBlock ? 'Blocked' : 'Active';
    renderLicensesData(allLicenses);
  }

  // 2. Show working toast
  showToast(`⏳ ${actionName} in progress for ${rawEmail}...`);

  try {
    // Try supabase-js client first (if available)
    if (supabaseClient) {
      console.log('[toggleUserLock] Using supabaseClient SDK...');

      // Update app_licenses — use eq() for exact match (more reliable than ilike)
      const { error: licErr } = await supabaseClient
        .from('app_licenses')
        .update({
          is_blocked: shouldBlock,
          license_status: shouldBlock ? 'Blocked' : 'Active',
        })
        .eq('user_email', rawEmail);

      if (licErr) {
        // Try lowercase as fallback
        console.warn('[toggleUserLock] eq() with raw failed, trying lowercase...', licErr);
        const { error: licErr2 } = await supabaseClient
          .from('app_licenses')
          .update({
            is_blocked: shouldBlock,
            license_status: shouldBlock ? 'Blocked' : 'Active',
          })
          .ilike('user_email', cleanEmail);
        if (licErr2) throw new Error('app_licenses update failed: ' + licErr2.message);
      }

      // Update app_sessions
      await supabaseClient
        .from('app_sessions')
        .update({
          is_blocked: shouldBlock,
          status: shouldBlock ? 'Blocked' : 'Online',
        })
        .ilike('user_email', cleanEmail);

    } else {
      // Fallback: Use fetch() with direct Supabase REST API
      console.warn('[toggleUserLock] supabaseClient is null — using fetch() REST API fallback...');
      const headers = {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_CONFIG.anonKey,
        'Authorization': `Bearer ${SUPABASE_CONFIG.anonKey}`,
        'Prefer': 'return=minimal'
      };

      // Update app_licenses
      const licRes = await fetch(
        `${SUPABASE_CONFIG.url}/rest/v1/app_licenses?user_email=ilike.${encodeURIComponent(cleanEmail)}`,
        {
          method: 'PATCH',
          headers,
          body: JSON.stringify({
            is_blocked: shouldBlock,
            license_status: shouldBlock ? 'Blocked' : 'Active'
          })
        }
      );
      if (!licRes.ok) {
        const errText = await licRes.text();
        throw new Error('REST PATCH app_licenses failed: ' + errText);
      }

      // Update app_sessions
      await fetch(
        `${SUPABASE_CONFIG.url}/rest/v1/app_sessions?user_email=ilike.${encodeURIComponent(cleanEmail)}`,
        {
          method: 'PATCH',
          headers,
          body: JSON.stringify({
            is_blocked: shouldBlock,
            status: shouldBlock ? 'Blocked' : 'Online'
          })
        }
      );
    }

    // Update localStorage cache
    localStorage.setItem('cached_licenses', JSON.stringify(allLicenses));

    showToast(shouldBlock
      ? `🔒 LOCKED! Software access BLOCKED for ${rawEmail}. Desktop will freeze.`
      : `🔓 UNLOCKED! Software access restored for ${rawEmail}.`);

    console.log(`[toggleUserLock] SUCCESS: ${actionName} applied for ${rawEmail}`);

    // Refresh data from server after 1.5s to confirm
    setTimeout(() => refreshAllData(false), 1500);

  } catch (err) {
    console.error('[toggleUserLock] FAILED:', err);
    showToast('⚠️ ' + actionName + ' failed: ' + (err.message || String(err)));
    // Rollback optimistic update
    if (lic) {
      lic.is_blocked = !shouldBlock;
      lic.license_status = !shouldBlock ? 'Blocked' : 'Active';
      renderLicensesData(allLicenses);
    }
  }
};

// ─── SHARED REST PATCH HELPER ─────────────────────────────────────────────────
async function supabasePatch(table, filter, body) {
  if (supabaseClient) {
    // Use supabase-js SDK
    let q = supabaseClient.from(table).update(body);
    // filter is { column, op, value }
    if (filter.op === 'eq')  q = q.eq(filter.col, filter.val);
    if (filter.op === 'ilike') q = q.ilike(filter.col, filter.val);
    const { error } = await q;
    if (error) throw new Error(table + ' update failed: ' + error.message);
  } else {
    // Fallback: direct REST fetch
    const params = `${filter.col}=${filter.op}.${encodeURIComponent(filter.val)}`;
    const res = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/${table}?${params}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_CONFIG.anonKey,
        'Authorization': `Bearer ${SUPABASE_CONFIG.anonKey}`,
        'Prefer': 'return=minimal'
      },
      body: JSON.stringify(body)
    });
    if (!res.ok) throw new Error(await res.text());
  }
}

window.blockSession = async function(sessionId, email) {
  if (!confirm(`Are you sure you want to BLOCK & LOCK this machine?\nUser: ${email}`)) return;

  try {
    const rawEmail = (email || '').trim();
    const cleanEmail = rawEmail.toLowerCase();
    showToast('⏳ Blocking machine...');

    // 1. Update this specific session by session_id
    await supabasePatch('app_sessions',
      { col: 'session_id', op: 'eq', val: sessionId },
      { is_blocked: true, status: 'Blocked' }
    );

    // 2. Sync app_licenses so user cannot re-login
    if (rawEmail) {
      await supabasePatch('app_licenses',
        { col: 'user_email', op: 'ilike', val: cleanEmail },
        { is_blocked: true, license_status: 'Blocked' }
      );
    }

    // 3. Update local state
    const sess = allSessions.find(s => s.session_id === sessionId);
    if (sess) { sess.is_blocked = true; sess.status = 'Blocked'; }
    const lic = allLicenses.find(l => (l.user_email||'').toLowerCase() === cleanEmail);
    if (lic) { lic.is_blocked = true; lic.license_status = 'Blocked'; }

    renderSessionsData(allSessions);
    renderLicensesData(allLicenses);
    showToast(`🔒 Machine LOCKED for ${rawEmail || sessionId}! Screen will freeze instantly.`);
    setTimeout(() => refreshAllData(false), 1500);
  } catch (err) {
    console.error('[blockSession] FAILED:', err);
    showToast('⚠️ Block failed: ' + (err.message || String(err)));
  }
};

window.unblockSession = async function(sessionId, email) {
  if (!confirm(`Are you sure you want to UNBLOCK this machine?\nUser: ${email}`)) return;

  try {
    const rawEmail = (email || '').trim();
    const cleanEmail = rawEmail.toLowerCase();
    showToast('⏳ Unblocking machine...');

    // 1. Update this specific session
    await supabasePatch('app_sessions',
      { col: 'session_id', op: 'eq', val: sessionId },
      { is_blocked: false, status: 'Online' }
    );

    // 2. Sync app_licenses
    if (rawEmail) {
      await supabasePatch('app_licenses',
        { col: 'user_email', op: 'ilike', val: cleanEmail },
        { is_blocked: false, license_status: 'Active' }
      );
    }

    // 3. Update local state
    const sess = allSessions.find(s => s.session_id === sessionId);
    if (sess) { sess.is_blocked = false; sess.status = 'Online'; }
    const lic = allLicenses.find(l => (l.user_email||'').toLowerCase() === cleanEmail);
    if (lic) { lic.is_blocked = false; lic.license_status = 'Active'; }

    renderSessionsData(allSessions);
    renderLicensesData(allLicenses);
    showToast(`🔓 Machine UNBLOCKED for ${rawEmail || sessionId}! Screen will restore.`);
    setTimeout(() => refreshAllData(false), 1500);
  } catch (err) {
    console.error('[unblockSession] FAILED:', err);
    showToast('⚠️ Unblock failed: ' + (err.message || String(err)));
  }
};

window.killSession = async function(sessionId) {
  if (!confirm(`Force logout this active machine right now?`)) return;

  try {
    await supabaseClient.from('app_sessions').update({
      is_online: false,
      status: 'Killed',
      logout_time: new Date().toISOString(),
    }).eq('session_id', sessionId);

    showToast(`⚡ Force logout sent! Active user kicked to login screen.`);
    refreshAllData(false);
  } catch (err) {
    showToast('⚠️ Failed to force logout: ' + err.message);
  }
};

window.deleteLicense = async function(id, email) {
  if (!confirm(`Are you sure you want to permanently delete license record for ${email}?`)) return;

  try {
    await supabaseClient.from('app_licenses').delete().eq('user_email', email);
    showToast(`🗑️ License record deleted for ${email}`);
    refreshAllData(false);
  } catch (err) {
    showToast('⚠️ Delete failed: ' + err.message);
  }
};

// ─── TAB 3: REMOTE PARTY HISAB TABLE ────────────────────────────────────────

function renderPartyHisabData(parties) {
  if (kpiPartyCount) kpiPartyCount.textContent = parties.length;
  if (partyBadgeCount) partyBadgeCount.textContent = parties.length;

  const totalHisabAmt = parties.reduce((sum, p) => sum + (parseFloat(p.net_hisab) || 0), 0);
  if (kpiTotalHisab) kpiTotalHisab.textContent = formatRupees(totalHisabAmt);

  if (!partyHisabTableBody) return;

  const query = (partySearchInput ? partySearchInput.value : '').trim().toLowerCase();
  const filtered = parties.filter(p => {
    if (!query) return true;
    return (p.party_name || '').toLowerCase().includes(query) ||
           (p.dealer_name || '').toLowerCase().includes(query);
  });

  if (filtered.length === 0) {
    partyHisabTableBody.innerHTML = `
      <tr>
        <td colspan="8" class="text-center py-5" style="color: #64748B;">
          ${parties.length === 0 ? 'No Party Hisab records uploaded to Cloud yet.' : 'No party matched your search.'}
        </td>
      </tr>
    `;
    updateTableFoot(0, 0, 0, 0);
    return;
  }

  let totTickets = 0;
  let totSales = 0;
  let totPrize = 0;
  let totNet = 0;

  partyHisabTableBody.innerHTML = filtered.map(p => {
    const tCount = parseInt(p.total_tickets) || 0;
    const sAmt = parseFloat(p.total_sales) || 0;
    const pAmt = parseFloat(p.total_prize) || 0;
    const netAmt = parseFloat(p.net_hisab) || 0;

    totTickets += tCount;
    totSales += sAmt;
    totPrize += pAmt;
    totNet += netAmt;

    const syncDateStr = p.updated_at ? formatISTDate(p.updated_at) : (p.last_active_date || '—');

    return `
      <tr>
        <td>
          <strong style="color: #FFF; font-size: 13.5px;">${escapeHtml(p.party_name)}</strong>
          ${p.category ? `<div style="font-size: 10.5px; color: #94A3B8;">${escapeHtml(p.category)}</div>` : ''}
        </td>
        <td>${p.dealer_name ? `🏢 ${escapeHtml(p.dealer_name)}` : '<span style="color: #64748B;">Direct</span>'}</td>
        <td style="font-family: monospace;">${tCount.toLocaleString()}</td>
        <td style="font-family: monospace;">₹${sAmt.toFixed(2)}</td>
        <td style="font-family: monospace; color: #F87171;">₹${pAmt.toFixed(2)}</td>
        <td>
          <strong class="highlight-net">₹${netAmt.toFixed(2)}</strong>
        </td>
        <td style="font-size: 11.5px; color: #94A3B8;">${syncDateStr}</td>
        <td>
          <span class="badge-tag badge-purple">Cloud Synced</span>
        </td>
      </tr>
    `;
  }).join('');

  updateTableFoot(totTickets, totSales, totPrize, totNet);
}

function updateTableFoot(tickets, sales, prize, net) {
  const fTickets = document.getElementById('footTotalTickets');
  const fSales = document.getElementById('footTotalSales');
  const fPrize = document.getElementById('footTotalPrize');
  const fNet = document.getElementById('footNetHisab');
  if (fTickets) fTickets.textContent = tickets.toLocaleString();
  if (fSales) fSales.textContent = formatRupees(sales);
  if (fPrize) fPrize.textContent = formatRupees(prize);
  if (fNet) fNet.textContent = formatRupees(net);
}

// ─── TAB 4: AUDIT HISTORY ───────────────────────────────────────────────────

function renderAuditHistoryTable(sessions) {
  if (!auditHistoryTableBody) return;
  const query = (auditSearchInput ? auditSearchInput.value : '').trim().toLowerCase();
  const filtered = sessions.filter(s => {
    if (!query) return true;
    return (s.user_email || '').toLowerCase().includes(query) ||
           (s.user_name || '').toLowerCase().includes(query) ||
           (s.device_name || '').toLowerCase().includes(query);
  });

  if (filtered.length === 0) {
    auditHistoryTableBody.innerHTML = `
      <tr>
        <td colspan="7" class="text-center py-5" style="color: #64748B;">No matching session logs found.</td>
      </tr>
    `;
    return;
  }

  const now = new Date();
  auditHistoryTableBody.innerHTML = filtered.map(s => {
    const loginStr = formatISTDate(s.login_time);
    const hbDate = s.last_heartbeat ? new Date(s.last_heartbeat) : null;
    const hbDiffSecs = hbDate ? Math.max(0, Math.floor((now - hbDate) / 1000)) : 9999;
    const isTerminated = s.status === 'Offline' || s.status === 'Kicked' || s.status === 'Killed' || s.status === 'Blocked' || s.is_blocked === true;
    const isLive = !isTerminated && s.is_online === true && hbDiffSecs <= 180;

    let stHtml = '';
    if (s.is_blocked === true || s.status === 'Blocked') {
      stHtml = '<span class="status-indicator status-offline" style="color:#F87171; border-color:rgba(239,68,68,0.5);">🔒 Blocked</span>';
    } else if (s.status === 'Kicked') {
      stHtml = '<span class="status-indicator status-offline" style="color:#F59E0B; border-color:rgba(245,158,11,0.5);">⚡ Kicked (Single Device)</span>';
    } else if (isLive) {
      stHtml = '<span class="status-indicator status-online">🟢 Online</span>';
    } else {
      stHtml = '<span class="status-indicator status-offline">⚪ Logged Out</span>';
    }

    const logoutStr = isLive ? '<span style="color:#34D399; font-weight:bold;">Active Now</span>' : (s.logout_time ? formatISTDate(s.logout_time) : 'Closed');

    return `
      <tr>
        <td>
          <div style="font-weight: 600; color: #FFF;">${escapeHtml(s.user_name || 'User')}</div>
          <div style="font-size: 11px; color: #38BDF8;">${escapeHtml(s.user_email || '—')}</div>
        </td>
        <td><strong>${escapeHtml(s.device_name || 'PC')}</strong></td>
        <td><span class="badge-tag badge-blue">${escapeHtml(s.os_info || 'Windows')}</span></td>
        <td>${loginStr}</td>
        <td>${logoutStr}</td>
        <td><strong style="color: #FBBF24; font-family: monospace;">${formatDuration(s.total_online_seconds || 0)}</strong></td>
        <td>${stHtml}</td>
      </tr>
    `;
  }).join('');
}

// ─── SEARCH HANDLERS ────────────────────────────────────────────────────────

function setupSearch() {
  // Read ?search=... from URL for seamless navigation from modal
  try {
    const urlParams = new URLSearchParams(window.location.search);
    const searchParam = urlParams.get('search');
    if (searchParam && auditSearchInput) {
      auditSearchInput.value = searchParam;
    }
  } catch (_) {}

  if (partySearchInput) {
    partySearchInput.addEventListener('input', () => {
      renderPartyHisabData(allPartyHisabs);
    });
  }

  if (auditSearchInput) {
    auditSearchInput.addEventListener('input', () => {
      renderAuditHistoryTable(allSessions);
    });
  }

  if (licenseSearchInput) {
    licenseSearchInput.addEventListener('input', () => {
      renderLicensesData(allLicenses);
    });
  }
}

// ─── SQL COPY HANDLER ───────────────────────────────────────────────────────

function setupSqlCopy() {
  if (btnCopySql && sqlCodeBlock) {
    btnCopySql.addEventListener('click', () => {
      const sqlText = sqlCodeBlock.textContent;
      navigator.clipboard.writeText(sqlText).then(() => {
        showToast('📋 SQL Script copied to clipboard! Paste it into Supabase SQL Editor.');
      }).catch(() => {
        showToast('⚠️ Could not copy SQL script automatically.');
      });
    });
  }
}

// ─── UTILITY FORMATTERS ─────────────────────────────────────────────────────

function formatDuration(seconds) {
  const s = Math.max(0, parseInt(seconds) || 0);
  const hrs = Math.floor(s / 3600);
  const mins = Math.floor((s % 3600) / 60);
  const secs = s % 60;

  if (hrs > 0) {
    return `${hrs}h ${mins}m ${secs}s`;
  } else if (mins > 0) {
    return `${mins}m ${secs}s`;
  } else {
    return `${secs}s`;
  }
}

function formatRupees(amount) {
  const num = parseFloat(amount) || 0;
  return '₹' + num.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// ─── USER & MACHINE SESSION HISTORY MODAL ───────────────────────────────────

function setupModalEvents() {
  const modal = document.getElementById('userHistoryModal');
  const btnClose = document.getElementById('btnCloseModal');

  if (btnClose) {
    btnClose.addEventListener('click', closeUserHistoryModal);
  }

  if (modal) {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        closeUserHistoryModal();
      }
    });
  }

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeUserHistoryModal();
    }
  });
}

function openUserHistoryModal(userEmail, deviceName) {
  const modal = document.getElementById('userHistoryModal');
  if (!modal) return;

  const targetEmail = (userEmail || '').trim().toLowerCase();
  const targetDevice = (deviceName || '').trim().toLowerCase();

  // Filter all sessions for this specific user or device
  const history = allSessions.filter(s => {
    const sEmail = (s.user_email || '').trim().toLowerCase();
    const sDevice = (s.device_name || '').trim().toLowerCase();
    if (targetEmail && sEmail === targetEmail) return true;
    if (targetDevice && sDevice === targetDevice) return true;
    return false;
  }).sort((a, b) => new Date(b.login_time || 0) - new Date(a.login_time || 0));

  if (history.length === 0) {
    showToast('⚠️ No session history records found for this user/device.');
    return;
  }

  const latest = history[0];
  const now = new Date();
  const hbDate = latest.last_heartbeat ? new Date(latest.last_heartbeat) : null;
  const hbDiffSecs = hbDate ? Math.max(0, Math.floor((now - hbDate) / 1000)) : 9999;
  const isBlocked = latest.is_blocked === true || latest.status === 'Blocked';
  const isLiveNow = !isBlocked && hbDiffSecs <= 180;

  // Header info
  const modalUserIcon = document.getElementById('modalUserIcon');
  const modalUserName = document.getElementById('modalUserName');
  const modalUserEmail = document.getElementById('modalUserEmail');
  if (modalUserIcon) modalUserIcon.textContent = isBlocked ? '🔒' : (isLiveNow ? '🟢' : '💻');
  if (modalUserName) modalUserName.textContent = latest.user_name || latest.user_email || 'Authorized User';
  if (modalUserEmail) modalUserEmail.textContent = `✉️ ${latest.user_email || '—'}  •  🖥️ ${latest.device_name || 'PC'}`;

  // Summary KPIs
  const modalStatusVal = document.getElementById('modalStatusVal');
  const modalDeviceVal = document.getElementById('modalDeviceVal');
  const modalTotalTimeVal = document.getElementById('modalTotalTimeVal');
  const modalTotalLoginsVal = document.getElementById('modalTotalLoginsVal');

  if (modalStatusVal) {
    if (isBlocked) {
      modalStatusVal.innerHTML = '<span style="color: #F87171;">🔒 LOCKED</span>';
    } else if (isLiveNow) {
      modalStatusVal.innerHTML = '<span style="color: #34D399;">🟢 LIVE ONLINE</span>';
    } else {
      modalStatusVal.innerHTML = '<span style="color: #94A3B8;">⚪ OFFLINE</span>';
    }
  }

  if (modalDeviceVal) modalDeviceVal.textContent = latest.device_name || 'Windows Desktop';

  // Calculate total online seconds across all sessions
  let totalSecsAll = 0;
  for (const s of history) {
    totalSecsAll += parseInt(s.total_online_seconds || 0);
  }
  if (modalTotalTimeVal) modalTotalTimeVal.textContent = formatDuration(totalSecsAll);
  if (modalTotalLoginsVal) modalTotalLoginsVal.textContent = history.length;

  // Render Table Rows
  const modalTbody = document.getElementById('modalHistoryTableBody');
  if (modalTbody) {
    modalTbody.innerHTML = history.map(s => {
      const loginStr = formatISTDate(s.login_time);
      const logoutStr = s.logout_time ? formatISTDate(s.logout_time) : (s.is_online ? '<span style="color:#34D399; font-weight:bold;">Active Now</span>' : 'Closed');
      const durStr = formatDuration(s.total_online_seconds || 0);
      const isBlk = s.is_blocked === true || s.status === 'Blocked';
      const isLive = !isBlk && s.is_online;

      let stHtml = '';
      if (isBlk) {
        stHtml = '<span class="status-indicator status-offline" style="color:#F87171; border-color:rgba(239,68,68,0.5);">🔒 Blocked</span>';
      } else if (isLive) {
        stHtml = '<span class="status-indicator status-online">🟢 Active</span>';
      } else if (s.status === 'Kicked') {
        stHtml = '<span class="status-indicator status-offline" style="color:#F59E0B;">⚡ Kicked</span>';
      } else {
        stHtml = '<span class="status-indicator status-offline">⚪ Logged Out</span>';
      }

      return `
        <tr>
          <td><strong style="color: #FFF;">${loginStr}</strong></td>
          <td style="color: #94A3B8;">${logoutStr}</td>
          <td><strong style="color: #FBBF24; font-family: monospace;">${durStr}</strong></td>
          <td>
            <div style="font-weight: 500;">${escapeHtml(s.device_name || 'PC')}</div>
            <div style="font-size: 11px; color: #64748B;">${escapeHtml(s.os_info || 'Windows')}</div>
          </td>
          <td>${stHtml}</td>
        </tr>
      `;
    }).join('');
  }

  // Footer Actions
  const modalFooterActions = document.getElementById('modalFooterActions');
  if (modalFooterActions) {
    if (isBlocked) {
      modalFooterActions.innerHTML = `
        <button class="btn-action btn-success" onclick="unblockSession('${escapeHtml(latest.session_id)}', '${escapeHtml(latest.user_email)}'); closeUserHistoryModal();">
          🔓 Unlock Software Access
        </button>
      `;
    } else {
      modalFooterActions.innerHTML = `
        <button class="btn-action btn-danger" onclick="blockSession('${escapeHtml(latest.session_id)}', '${escapeHtml(latest.user_email)}'); closeUserHistoryModal();">
          🔒 Block & Lock System
        </button>
        ${isLiveNow ? `
          <button class="btn-action btn-warning" onclick="killSession('${escapeHtml(latest.session_id)}'); closeUserHistoryModal();">
            ⚡ Force Logout
          </button>
        ` : ''}
      `;
    }
  }

  // Set audit trail link
  const modalViewAuditLink = document.getElementById('modalViewAuditLink');
  if (modalViewAuditLink) {
    modalViewAuditLink.href = `logs.html?search=${encodeURIComponent(latest.user_email || latest.device_name)}`;
  }

  modal.classList.add('show');
}

function closeUserHistoryModal() {
  const modal = document.getElementById('userHistoryModal');
  if (modal) modal.classList.remove('show');
}

