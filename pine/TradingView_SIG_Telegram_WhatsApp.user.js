// ==UserScript==
// @name         TradingView SL3-AMD-VP — SIG Telegram & WhatsApp Notifier (Free Account)
// @namespace    https://github.com/mafimehdi/EA31337
// @version      1.0.0
// @description  Reads live SIG▲ / SIG▼ signals directly from TradingView DOM (Status Line 31337 bridge & table) without needing a paid TradingView account, and sends instant alerts to Telegram and/or WhatsApp.
// @author       SL3-AMD-VP
// @match        https://*.tradingview.com/chart/*
// @grant        GM_xmlhttpRequest
// @grant        GM_notification
// @connect      api.telegram.org
// @connect      api.callmebot.com
// ==/UserScript==

(function () {
    'use strict';

    // ─── تنظیمات پیش‌فرض (می‌توانید اینجا یا مستقیماً از دکمه 🔔 روی چارت تریدینگ‌ویو وارد کنید) ───
    const DEFAULT_CONFIG = {
        tgToken: '',       // مثال: '7123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        tgChatId: '',      // مثال: '123456789' یا '-1001234567890'
        waPhone: '',       // شماره واتساپ با کد کشور، مثال: '+98912xxxxxxx' یا '+324xxxxxxxx'
        waApiKey: '',      // کلید رایگان CallMeBot واتساپ
        soundOn: true,
    };

    const STORAGE_KEY = 'sl3_sig_notifier_cfg_v1';
    function loadCfg() {
        try {
            const raw = localStorage.getItem(STORAGE_KEY);
            return raw ? Object.assign({}, DEFAULT_CONFIG, JSON.parse(raw)) : Object.assign({}, DEFAULT_CONFIG);
        } catch (e) {
            return Object.assign({}, DEFAULT_CONFIG);
        }
    }
    function saveCfg(cfg) {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg));
    }

    let cfg = loadCfg();
    let maxSeenSigId = null; // در اولین بارگذاری، آخرین شماره SIG ذخیره می‌شود تا سیگنال‌های قدیمی ارسال نشوند
    let lastSentSigId = 0;

    // ─── پخش صدای هشدار در مرورگر ───
    function playBeep() {
        if (!cfg.soundOn) return;
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            [587.33, 880.0].forEach((freq, idx) => {
                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'sine';
                osc.frequency.value = freq;
                gain.gain.setValueAtTime(0.18, ctx.currentTime + idx * 0.16);
                gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + idx * 0.16 + 0.15);
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(ctx.currentTime + idx * 0.16);
                osc.stop(ctx.currentTime + idx * 0.16 + 0.16);
            });
        } catch (e) {}
    }

    // ─── ارسال پیام به تلگرام ───
    function sendTelegram(text, cb) {
        if (!cfg.tgToken || !cfg.tgChatId) {
            if (cb) cb(false, 'توکن یا Chat ID تلگرام وارد نشده است.');
            return;
        }
        const url = `https://api.telegram.org/bot${cfg.tgToken.trim()}/sendMessage`;
        const payload = JSON.stringify({
            chat_id: cfg.tgChatId.trim(),
            text: text,
            parse_mode: 'HTML',
            disable_web_page_preview: true,
        });

        if (typeof GM_xmlhttpRequest === 'function') {
            GM_xmlhttpRequest({
                method: 'POST',
                url: url,
                headers: { 'Content-Type': 'application/json' },
                data: payload,
                onload: (res) => {
                    const ok = res.status >= 200 && res.status < 300;
                    if (cb) cb(ok, ok ? 'ارسال به تلگرام موفق بود!' : res.responseText);
                },
                onerror: (err) => {
                    if (cb) cb(false, 'خطا در اتصال به تلگرام');
                },
            });
        } else {
            fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: payload,
            })
                .then((r) => r.json())
                .then((d) => {
                    if (cb) cb(!!d.ok, d.ok ? 'ارسال به تلگرام موفق بود!' : JSON.stringify(d));
                })
                .catch((e) => {
                    if (cb) cb(false, e.message);
                });
        }
    }

    // ─── ارسال پیام به واتساپ (از طریق سرویس رایگان CallMeBot) ───
    function sendWhatsApp(text, cb) {
        if (!cfg.waPhone || !cfg.waApiKey) {
            if (cb) cb(false, 'شماره یا API Key واتساپ وارد نشده است.');
            return;
        }
        const cleanText = text.replace(/<[^>]+>/g, '');
        const url = `https://api.callmebot.com/whatsapp.php?phone=${encodeURIComponent(cfg.waPhone.trim())}&text=${encodeURIComponent(cleanText)}&apikey=${encodeURIComponent(cfg.waApiKey.trim())}`;

        if (typeof GM_xmlhttpRequest === 'function') {
            GM_xmlhttpRequest({
                method: 'GET',
                url: url,
                onload: (res) => {
                    if (cb) cb(res.status >= 200 && res.status < 300, 'درخواست واتساپ ارسال شد.');
                },
                onerror: () => {
                    if (cb) cb(false, 'خطا در اتصال به واتساپ');
                },
            });
        } else {
            fetch(url, { mode: 'no-cors' }).then(() => {
                if (cb) cb(true, 'درخواست واتساپ ارسال شد.');
            });
        }
    }

    // ─── استخراج سیگنال SIG از Status Line (کلید 31337) روی صفحه تریدینگ‌ویو ───
    function readSigFromPage() {
        // به دنبال آیتم لجند اندیکاتور SL3-AMD-VP یا کل متن لجند می‌گردیم
        const legendItems = document.querySelectorAll('[data-name="legend-source-item"], [class*="sourcesWrapper"], [class*="legendMainSourceWrapper"]');
        let texts = [];
        if (legendItems.length > 0) {
            legendItems.forEach((el) => texts.push(el.innerText || el.textContent || ''));
        } else {
            texts.push(document.body.innerText || '');
        }

        for (const raw of texts) {
            // نرمال‌سازی کاراکترهای منفی یونیکد تریدینگ‌ویو (जैसे − به -) و حذف کاما
            const norm = raw.replace(/[−–—]/g, '-').replace(/,/g, '');
            // الگوی کلید 31337 و ۵ عدد بعدی: SIG_KEY(31337) SIG_ID SIG_DIR SIG_ENTRY SIG_SL SIG_TP
            const re = /\b31337\b[^0-9-]*(-?\d+)[^0-9-]*(-?1|0)[^0-9-]*(-?\d+(?:\.\d+)?)[^0-9-]*(-?\d+(?:\.\d+)?)[^0-9-]*(-?\d+(?:\.\d+)?)/;
            const m = norm.match(re);
            if (m) {
                const sigId = parseInt(m[1], 10);
                const sigDir = parseInt(m[2], 10);
                const entry = parseFloat(m[3]);
                const sl = parseFloat(m[4]);
                const tp = parseFloat(m[5]);
                if (!isNaN(sigId) && sigId >= 0) {
                    return { sigId, sigDir, entry, sl, tp };
                }
            }
        }
        return null;
    }

    function getChartSymbolAndTf() {
        const title = document.title || '';
        return title.split('—')[0].trim() || 'XAUUSD';
    }

    function formatSignalMessage(sig, isTest) {
        const isBuy = sig.sigDir === 1;
        const dirEmoji = isBuy ? '🟢 <b>SIG▲ BUY (خرید)</b>' : '🔴 <b>SIG▼ SELL (فروش)</b>';
        const risk = Math.abs(sig.entry - sig.sl);
        const reward = Math.abs(sig.tp - sig.entry);
        const rr = risk > 0 ? (reward / risk).toFixed(2) : '—';
        const tehranTime = new Date().toLocaleTimeString('fa-IR', { timeZone: 'Asia/Tehran', hour: '2-digit', minute: '2-digit', second: '2-digit' });

        return [
            isTest ? '🧪 <b>[تست اتصال نوتیفیکیشن SL3-AMD-VP]</b>' : '🚨 <b>سیگنال جدید SIG در تریدینگ‌ویو!</b>',
            `📊 <b>چارت:</b> ${getChartSymbolAndTf()}`,
            `🎯 <b>جهت:</b> ${dirEmoji}  (#${sig.sigId})`,
            `💰 <b>قیمت ورود (Entry):</b> <code>${sig.entry}</code>`,
            `🛑 <b>حد ضرر (SL):</b> <code>${sig.sl}</code>  (ریسک: $${risk.toFixed(2)})`,
            `✅ <b>حد سود (TP):</b> <code>${sig.tp}</code>  (سود: $${reward.toFixed(2)})`,
            `⚖️ <b>نسبت R:R:</b> <code>1 : ${rr}</code>`,
            `🕒 <b>ساعت (تهران):</b> ${tehranTime}`,
        ].join('\n');
    }

    // ─── رابط کاربری کوچک روی صفحه تریدینگ‌ویو ───
    const badge = document.createElement('div');
    badge.style.cssText = 'position:fixed;bottom:14px;left:14px;z-index:999999;background:#131722;color:#f0b90b;border:1px solid #f0b90b;border-radius:6px;padding:6px 10px;font:12px/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.5);user-select:none;';
    badge.innerHTML = '🔔 <b>SIG Notifier:</b> در حال اتصال...';
    document.body.appendChild(badge);

    function openConfigModal() {
        const existing = document.getElementById('sl3-sig-modal');
        if (existing) {
            existing.remove();
            return;
        }
        const modal = document.createElement('div');
        modal.id = 'sl3-sig-modal';
        modal.style.cssText = 'position:fixed;bottom:52px;left:14px;z-index:999999;width:340px;background:#1e222d;color:#d1d4dc;border:1px solid #363c4e;border-radius:8px;padding:14px;font:12px/1.5 Tahoma,sans-serif;direction:rtl;text-align:right;box-shadow:0 8px 24px rgba(0,0,0,0.65);';
        modal.innerHTML = `
            <div style="font-weight:bold;color:#f0b90b;margin-bottom:8px;font-size:13px;">⚙️ تنظیمات ارسال سیگنال SIG به تلگرام و واتساپ</div>
            <label style="display:block;margin-top:6px;">توکن ربات تلگرام (Bot Token از @BotFather):</label>
            <input id="sl3-tg-token" type="text" value="${cfg.tgToken}" placeholder="7123456:AAH..." style="width:100%;box-sizing:border-box;padding:5px;margin-top:2px;background:#131722;color:#fff;border:1px solid #434651;border-radius:4px;direction:ltr;">
            <label style="display:block;margin-top:6px;">آیدی عددی چت/کانال تلگرام (Chat ID از @userinfobot):</label>
            <input id="sl3-tg-chat" type="text" value="${cfg.tgChatId}" placeholder="123456789" style="width:100%;box-sizing:border-box;padding:5px;margin-top:2px;background:#131722;color:#fff;border:1px solid #434651;border-radius:4px;direction:ltr;">
            <label style="display:block;margin-top:6px;">شماره واتساپ (اختیاری - با کد کشور):</label>
            <input id="sl3-wa-phone" type="text" value="${cfg.waPhone}" placeholder="+98912..." style="width:100%;box-sizing:border-box;padding:5px;margin-top:2px;background:#131722;color:#fff;border:1px solid #434651;border-radius:4px;direction:ltr;">
            <label style="display:block;margin-top:6px;">کلید CallMeBot واتساپ (اختیاری):</label>
            <input id="sl3-wa-key" type="text" value="${cfg.waApiKey}" placeholder="123456" style="width:100%;box-sizing:border-box;padding:5px;margin-top:2px;background:#131722;color:#fff;border:1px solid #434651;border-radius:4px;direction:ltr;">
            <div style="display:flex;gap:6px;margin-top:10px;">
                <button id="sl3-btn-save" style="flex:1;background:#26a69a;color:#fff;border:none;border-radius:4px;padding:6px;cursor:pointer;font-weight:bold;">ذخیره</button>
                <button id="sl3-btn-test" style="flex:1;background:#f0b90b;color:#000;border:none;border-radius:4px;padding:6px;cursor:pointer;font-weight:bold;">ارسال پیام تست</button>
                <button id="sl3-btn-close" style="background:#ef5350;color:#fff;border:none;border-radius:4px;padding:6px 10px;cursor:pointer;">بستن</button>
            </div>
            <div id="sl3-status-msg" style="margin-top:8px;font-size:11px;color:#9e9e9e;"></div>
        `;
        document.body.appendChild(modal);

        document.getElementById('sl3-btn-close').onclick = () => modal.remove();
        document.getElementById('sl3-btn-save').onclick = () => {
            cfg.tgToken = document.getElementById('sl3-tg-token').value.trim();
            cfg.tgChatId = document.getElementById('sl3-tg-chat').value.trim();
            cfg.waPhone = document.getElementById('sl3-wa-phone').value.trim();
            cfg.waApiKey = document.getElementById('sl3-wa-key').value.trim();
            saveCfg(cfg);
            document.getElementById('sl3-status-msg').style.color = '#26a69a';
            document.getElementById('sl3-status-msg').textContent = '✅ تنظیمات ذخیره شد!';
        };
        document.getElementById('sl3-btn-test').onclick = () => {
            cfg.tgToken = document.getElementById('sl3-tg-token').value.trim();
            cfg.tgChatId = document.getElementById('sl3-tg-chat').value.trim();
            cfg.waPhone = document.getElementById('sl3-wa-phone').value.trim();
            cfg.waApiKey = document.getElementById('sl3-wa-key').value.trim();
            saveCfg(cfg);
            const cur = readSigFromPage() || { sigId: 99, sigDir: 1, entry: 4650.0, sl: 4630.0, tp: 4690.0 };
            const msg = formatSignalMessage(cur, true);
            const stEl = document.getElementById('sl3-status-msg');
            stEl.style.color = '#f0b90b';
            stEl.textContent = 'در حال ارسال پیام تست...';
            playBeep();
            if (cfg.tgToken && cfg.tgChatId) {
                sendTelegram(msg, (ok, info) => {
                    stEl.style.color = ok ? '#26a69a' : '#ef5350';
                    stEl.textContent = info;
                });
            }
            if (cfg.waPhone && cfg.waApiKey) {
                sendWhatsApp(msg, (ok, info) => {
                    if (!cfg.tgToken) {
                        stEl.style.color = ok ? '#26a69a' : '#ef5350';
                        stEl.textContent = info;
                    }
                });
            }
        };
    }

    badge.onclick = openConfigModal;

    // ─── حلقه بررسی زنده هر ۲ ثانیه ───
    setInterval(() => {
        const sig = readSigFromPage();
        if (!sig) {
            badge.innerHTML = '🔔 <b>SIG Notifier:</b> منتظر مقادیر لجند (31337)...';
            return;
        }
        if (maxSeenSigId === null) {
            maxSeenSigId = sig.sigId;
            badge.innerHTML = `🔔 <b>SIG Notifier:</b> فعال (آخرین: SIG#${sig.sigId})`;
            return;
        }
        // فقط زمانی که یک SIG جدیدتر از تمام سیگنال‌های قبلی روی کندل آخر شکل بگیرد:
        if (sig.sigId > maxSeenSigId && sig.sigId !== lastSentSigId && sig.sigDir !== 0) {
            maxSeenSigId = sig.sigId;
            lastSentSigId = sig.sigId;
            const msg = formatSignalMessage(sig, false);
            playBeep();
            sendTelegram(msg);
            sendWhatsApp(msg);
            if (typeof GM_notification === 'function') {
                GM_notification({
                    title: `SIG#${sig.sigId} ${sig.sigDir === 1 ? 'BUY ▲' : 'SELL ▼'} @ ${sig.entry}`,
                    text: `SL: ${sig.sl} | TP: ${sig.tp}`,
                    timeout: 10000,
                });
            }
        }
        badge.innerHTML = `🔔 <b>SIG Notifier:</b> فعال (آخرین: SIG#${maxSeenSigId} ${sig.sigDir === 1 ? '▲' : sig.sigDir === -1 ? '▼' : ''})`;
    }, 2000);
})();
