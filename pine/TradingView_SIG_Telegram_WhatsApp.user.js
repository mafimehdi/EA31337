// ==UserScript==
// @name         TradingView SL3-AMD-VP — SIG Telegram & WhatsApp Notifier (Free Account)
// @namespace    https://github.com/mafimehdi/EA31337
// @version      1.2.0
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

    const STORAGE_KEY = 'sl3_sig_notifier_cfg_v1';
    const DEFAULT_CONFIG = {
        tgToken: '',
        tgChatId: '',
        waPhone: '',
        waApiKey: '',
        soundOn: true,
    };

    function loadCfg() {
        try {
            const raw = localStorage.getItem(STORAGE_KEY);
            return raw ? Object.assign({}, DEFAULT_CONFIG, JSON.parse(raw)) : Object.assign({}, DEFAULT_CONFIG);
        } catch (e) {
            return Object.assign({}, DEFAULT_CONFIG);
        }
    }

    function saveCfg(cfg) {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(cfg));
        } catch (e) {}
    }

    let cfg = loadCfg();
    let maxSeenSigId = null;
    let lastSentSigId = null;

    function playBeep() {
        if (!cfg.soundOn) return;
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            osc.type = 'sine';
            osc.frequency.setValueAtTime(880, ctx.currentTime);
            osc.frequency.setValueAtTime(1174.66, ctx.currentTime + 0.12);
            gain.gain.setValueAtTime(0.18, ctx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.38);
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.start();
            osc.stop(ctx.currentTime + 0.4);
        } catch (e) {}
    }

    function isLikelyPhoneNumber(v) {
        if (!v) return false;
        const s = v.trim();
        return s.startsWith('+98') || s.startsWith('09') || s.startsWith('0098') || (s.startsWith('+') && s.length >= 11);
    }

    // دریافت خودکار Chat ID از طریق getUpdates تلگرام (فقط با داشتن Bot Token!)
    function autoFindChatId(token, cb) {
        if (!token) {
            cb(false, null, '❌ ابتدا توکن ربات (Bot Token) دریافتی از @BotFather را در کادر اول وارد کنید.');
            return;
        }
        const url = `https://api.telegram.org/bot${token.trim()}/getUpdates`;
        fetch(url)
            .then((r) => r.json())
            .then((d) => {
                if (!d.ok) {
                    cb(false, null, '❌ کد Bot Token اشتباه است: ' + (d.description || 'توکن را دقیق از @BotFather کپی کنید.'));
                    return;
                }
                const updates = d.result || [];
                for (let i = updates.length - 1; i >= 0; i--) {
                    const u = updates[i];
                    const chat =
                        (u.message && u.message.chat) ||
                        (u.channel_post && u.channel_post.chat) ||
                        (u.my_chat_member && u.my_chat_member.chat) ||
                        (u.edited_message && u.edited_message.chat);
                    if (chat && chat.id) {
                        cb(true, String(chat.id), `✅ شناسه چت تلگرام شما به صورت خودکار پیدا شد: ${chat.id}`);
                        return;
                    }
                }
                cb(
                    false,
                    null,
                    '⚠️ توکن ربات درست است، اما هنوز در تلگرام وارد ربات خودتان نشده‌اید! در تلگرام وارد ربات خود شوید، دکمه Start را بزنید (یا یک پیام مثل "سلام" بفرستید) و دوباره این دکمه را بزنید.'
                );
            })
            .catch(() => {
                cb(
                    false,
                    null,
                    '❌ مرورگر نتوانست به سرور تلگرام (api.telegram.org) وصل شود! لطفاً مطمئن شوید فیلترشکن (VPN) سیستم/مرورگر شما روشن است.'
                );
            });
    }

    function sendTelegram(text, cb) {
        const token = (cfg.tgToken || '').trim();
        let chatId = (cfg.tgChatId || '').trim();

        if (!token) {
            if (cb) cb(false, '❌ لطفاً توکن ربات (Bot Token) را در کادر اول وارد کنید.');
            return;
        }

        const doSend = (finalChatId) => {
            const url = `https://api.telegram.org/bot${token}/sendMessage`;
            const payload = JSON.stringify({
                chat_id: finalChatId,
                text: text,
                parse_mode: 'HTML',
                disable_web_page_preview: true,
            });
            fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: payload,
            })
                .then((r) => r.json())
                .then((d) => {
                    if (d.ok) {
                        if (cb) cb(true, '✅ پیام با موفقیت به تلگرام شما ارسال شد! (تلگرام خود را چک کنید)');
                    } else {
                        if (cb)
                            cb(
                                false,
                                `❌ خطای تلگرام (${d.error_code || ''}): ${d.description || ''} — توجه: در کادر دوم نباید شماره موبایل وارد شود؛ باید Chat ID عددی باشد (یا کادر دوم را خالی بگذارید تا خودکار پیدا شود).`
                            );
                    }
                })
                .catch(() => {
                    if (cb)
                        cb(
                            false,
                            '❌ مرورگر نتوانست به سرور تلگرام (api.telegram.org) وصل شود! لطفاً مطمئن شوید فیلترشکن (VPN) سیستم یا مرورگر شما روشن است.'
                        );
                });
        };

        // اگر کادر Chat ID خالی است یا کاربر به اشتباه شماره موبایل وارد کرده، خودکار از getUpdates پیدایش کن!
        if (!chatId || isLikelyPhoneNumber(chatId)) {
            autoFindChatId(token, (ok, foundId, msg) => {
                if (!ok) {
                    if (cb) cb(false, msg);
                    return;
                }
                cfg.tgChatId = foundId;
                saveCfg(cfg);
                const cidInput = document.getElementById('sl3_tg_cid');
                if (cidInput) cidInput.value = foundId;
                doSend(foundId);
            });
        } else {
            doSend(chatId);
        }
    }

    function sendWhatsApp(text, cb) {
        if (!cfg.waPhone || !cfg.waApiKey) {
            if (cb) cb(false, 'شماره یا API Key واتساپ وارد نشده است.');
            return;
        }
        const cleanText = text.replace(/<[^>]+>/g, '');
        const url = `https://api.callmebot.com/whatsapp.php?phone=${encodeURIComponent(cfg.waPhone.trim())}&text=${encodeURIComponent(cleanText)}&apikey=${encodeURIComponent(cfg.waApiKey.trim())}`;
        fetch(url, { mode: 'no-cors' })
            .then(() => {
                if (cb) cb(true, '✅ درخواست واتساپ ارسال شد.');
            })
            .catch(() => {
                if (cb) cb(false, '❌ خطا در اتصال به سرویس واتساپ.');
            });
    }

    function readSigFromPage() {
        const bodyTxt = (document.body.innerText || '').replace(/[−–—]/g, '-').replace(/,/g, '');

        const reHeader = /SIG#(\d+)\s+(BUY|SELL)\s+@(-?\d+(?:\.\d+)?)\s+SL:(-?\d+(?:\.\d+)?)\s+TP:(-?\d+(?:\.\d+)?)/;
        const mh = bodyTxt.match(reHeader);
        if (mh) {
            return {
                sigId: parseInt(mh[1], 10),
                sigDir: mh[2] === 'BUY' ? 1 : -1,
                entry: parseFloat(mh[3]),
                sl: parseFloat(mh[4]),
                tp: parseFloat(mh[5]),
            };
        }

        const re31337 = /\b31337\b[^0-9-]*(-?\d+)[^0-9-]*(-?1|0)[^0-9-]*(-?\d+(?:\.\d+)?)[^0-9-]*(-?\d+(?:\.\d+)?)[^0-9-]*(-?\d+(?:\.\d+)?)/;
        const m3 = bodyTxt.match(re31337);
        if (m3) {
            const sigId = parseInt(m3[1], 10);
            const sigDir = parseInt(m3[2], 10);
            const entry = parseFloat(m3[3]);
            const sl = parseFloat(m3[4]);
            const tp = parseFloat(m3[5]);
            if (!isNaN(sigId) && sigId >= 0) {
                return { sigId, sigDir, entry, sl, tp };
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
        const tehranTime = new Date().toLocaleTimeString('fa-IR', {
            timeZone: 'Asia/Tehran',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
        });

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

    const oldBadge = document.getElementById('sl3-sig-badge');
    if (oldBadge) oldBadge.remove();
    const badge = document.createElement('div');
    badge.id = 'sl3-sig-badge';
    badge.style.cssText =
        'position:fixed;bottom:14px;left:14px;z-index:999999;background:#131722;color:#f0b90b;border:2px solid #f0b90b;border-radius:6px;padding:7px 12px;font:12px/1.4 Tahoma,sans-serif;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,0.65);user-select:none;';
    badge.innerHTML = '🔔 <b>SIG Notifier:</b> آماده (کلیک برای تنظیمات تلگرام)';
    document.body.appendChild(badge);

    function openConfigModal() {
        const old = document.getElementById('sl3-sig-modal');
        if (old) old.remove();

        const modal = document.createElement('div');
        modal.id = 'sl3-sig-modal';
        modal.style.cssText =
            'position:fixed;inset:0;z-index:1000000;background:rgba(0,0,0,0.68);display:flex;align-items:center;justify-content:center;direction:rtl;font-family:Tahoma,sans-serif;';
        modal.innerHTML = `
            <div style="background:#1e222d;color:#d1d4dc;border:2px solid #f0b90b;border-radius:10px;width:440px;max-width:94vw;padding:18px;box-shadow:0 10px 30px rgba(0,0,0,0.8);">
                <h3 style="margin:0 0 10px;color:#f0b90b;font-size:15px;">🔔 تنظیمات ارسال خودکار SIG به تلگرام و واتساپ</h3>
                <div style="background:#131722;border-right:3px solid #26a69a;padding:8px 10px;margin-bottom:12px;font-size:11.5px;line-height:1.6;color:#e0e3eb;">
                    <b>راهنمای ۳ ثانیه‌ای تلگرام:</b><br>
                    ۱) کد <b>Bot Token</b> که از <code>@BotFather</code> گرفته‌اید را در کادر اول بگذارید.<br>
                    ۲) در تلگرام وارد ربات خودتان شوید و یک بار دکمه <b>Start</b> (یا پیام «سلام») بفرستید.<br>
                    ۳) کادر دوم را <b>خالی بگذارید</b> (شماره موبایل ننویسید!) و مستقیم دکمه سبز <b>«🧪 تشخیص خودکار و ارسال تست»</b> را بزنید!
                </div>
                <label style="font-size:12px;color:#9db2bd;">۱. کد توکن ربات تلگرام (Bot Token از @BotFather):</label>
                <input id="sl3_tg_tok" type="text" value="${cfg.tgToken}" placeholder="مثال: 7123456789:AAH..." style="width:100%;box-sizing:border-box;margin:4px 0 10px;padding:7px;border-radius:5px;border:1px solid #363c4e;background:#131722;color:#fff;direction:ltr;">
                <label style="font-size:12px;color:#9db2bd;">۲. شناسه عددی چت (Chat ID — خالی بگذارید تا خودکار پر شود، شماره موبایل ننویسید):</label>
                <input id="sl3_tg_cid" type="text" value="${isLikelyPhoneNumber(cfg.tgChatId) ? '' : cfg.tgChatId}" placeholder="خالی بگذارید تا خودکار پیدا شود (مثال: 123456789)" style="width:100%;box-sizing:border-box;margin:4px 0 10px;padding:7px;border-radius:5px;border:1px solid #363c4e;background:#131722;color:#fff;direction:ltr;">
                <div id="sl3_st" style="font-size:12px;line-height:1.5;min-height:22px;margin:8px 0 12px;padding:6px 8px;border-radius:5px;background:#131722;color:#f0b90b;">وضعیت: آماده تست اتصال</div>
                <div style="display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;">
                    <button id="sl3_test" style="background:#26a69a;color:#fff;border:none;padding:8px 14px;border-radius:5px;cursor:pointer;font-weight:bold;">🧪 تشخیص خودکار و ارسال تست</button>
                    <button id="sl3_save" style="background:#f0b90b;color:#000;border:none;padding:8px 14px;border-radius:5px;cursor:pointer;font-weight:bold;">💾 ذخیره</button>
                    <button id="sl3_cls" style="background:#363c4e;color:#fff;border:none;padding:8px 12px;border-radius:5px;cursor:pointer;">بستن</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);

        const pullInputs = () => {
            cfg.tgToken = document.getElementById('sl3_tg_tok').value.trim();
            const rawCid = document.getElementById('sl3_tg_cid').value.trim();
            cfg.tgChatId = isLikelyPhoneNumber(rawCid) ? '' : rawCid;
            saveCfg(cfg);
        };

        document.getElementById('sl3_cls').onclick = () => modal.remove();
        document.getElementById('sl3_save').onclick = () => {
            pullInputs();
            modal.remove();
        };
        document.getElementById('sl3_test').onclick = () => {
            pullInputs();
            const stEl = document.getElementById('sl3_st');
            stEl.style.color = '#f0b90b';
            stEl.textContent = '⏳ در حال اتصال به تلگرام و ارسال پیام تست...';
            const liveSig = readSigFromPage() || { sigId: 999, sigDir: 1, entry: 4182.5, sl: 4170.0, tp: 4207.5 };
            const msg = formatSignalMessage(liveSig, true);
            playBeep();
            sendTelegram(msg, (ok, info) => {
                if (stEl) {
                    stEl.style.color = ok ? '#26a69a' : '#ef5350';
                    stEl.textContent = info;
                }
            });
        };
    }

    badge.onclick = openConfigModal;
    openConfigModal();

    if (window.__sl3SigTimer) clearInterval(window.__sl3SigTimer);
    window.__sl3SigTimer = setInterval(() => {
        const sig = readSigFromPage();
        if (!sig) return;
        if (maxSeenSigId === null) {
            maxSeenSigId = sig.sigId;
            badge.innerHTML = `🔔 <b>SIG Notifier:</b> فعال (آخرین: SIG#${sig.sigId})`;
            return;
        }
        if (sig.sigId > maxSeenSigId && sig.sigId !== lastSentSigId && sig.sigDir !== 0) {
            maxSeenSigId = sig.sigId;
            lastSentSigId = sig.sigId;
            const msg = formatSignalMessage(sig, false);
            playBeep();
            sendTelegram(msg);
            sendWhatsApp(msg);
        }
        badge.innerHTML = `🔔 <b>SIG Notifier:</b> فعال (آخرین: SIG#${maxSeenSigId})`;
    }, 2000);
})();
