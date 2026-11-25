(() => {
  "use strict";

  const STALE_AFTER = 10 * 60000;
  const isEmbed = document.documentElement.classList.contains("embed");

  const $ = (id) => document.getElementById(id);
  const pad = (n) => String(n).padStart(2, "0");
  const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

  let data = window.AGENT_QUOTA || {};
  const PALETTE = window.AGENT_PALETTE || {
    thresholds: { warn: 30, crit: 15 },
    engines: {
      codex: { accent: "#E2E8F0", fillFrom: "#94A3B8", fillTo: "#E2E8F0" },
      antigravity: { accent: "#BFDBFE", fillFrom: "#60A5FA", fillTo: "#BFDBFE" },
    },
    tiers: {
      warn: { accent: "#F59E0B", fillFrom: "#D97706", fillTo: "#FBBF24" },
      crit: { accent: "#EF4444", fillFrom: "#DC2626", fillTo: "#F87171" },
    },
  };

  function fmtCountdown(ms) {
    const diff = Math.max(0, ms - Date.now());
    if (diff <= 0) return "已重置";
    const totalMin = Math.floor(diff / 60000);
    const hours = Math.floor(totalMin / 60);
    const mins = totalMin % 60;
    return hours > 0 ? `剩 ${hours}h${pad(mins)}m` : `剩 ${mins}m`;
  }

  function toneFor(remain) {
    if (remain < PALETTE.thresholds.crit) return "crit";
    if (remain < PALETTE.thresholds.warn) return "warn";
    return "ok";
  }

  function applyTone(el, engineKey, tier) {
    el.dataset.tone = tier;
    const tone = tier === "ok"
      ? (PALETTE.engines[engineKey] || PALETTE.tiers.ok)
      : (PALETTE.tiers[tier] || PALETTE.tiers.warn);
    el.style.setProperty("--tone-accent", tone.accent);
    el.style.setProperty("--fill-from", tone.fillFrom);
    el.style.setProperty("--fill-to", tone.fillTo);
  }

  function renderEngine(engineData, prefix, engineKey) {
    const section = $(`${prefix}Engine`);
    const weekLine = $(`${prefix}WeekLine`);
    const windows = (engineData && engineData.windows) || {};
    const session = windows.session;
    const weekly = windows.weekly;

    if (!session && !weekly) {
      $(`${prefix}SessionRemain`).textContent = "—";
      $(`${prefix}Meta`).textContent = "等待读数";
      $(`${prefix}SessionFill`).style.width = "0%";
      $(`${prefix}SessionMarker`).hidden = true;
      weekLine.hidden = true;
      applyTone(section, engineKey, "ok");
      return false;
    }

    if (session) {
      const remain = 100 - clamp(Math.round(session.usedPercent), 0, 100);
      const resetMs = session.resetsAt * 1000;
      $(`${prefix}Meta`).textContent = fmtCountdown(resetMs);
      $(`${prefix}SessionRemain`).textContent = String(remain);
      $(`${prefix}SessionFill`).style.width = `${remain}%`;

      if (session.windowMinutes > 0) {
        const marker = $(`${prefix}SessionMarker`);
        const remainTimePct = clamp(((resetMs - Date.now()) / (session.windowMinutes * 60000)) * 100, 0, 100);
        marker.style.left = `${remainTimePct.toFixed(1)}%`;
        marker.hidden = false;
      }

      applyTone(section, engineKey, toneFor(remain));
    }

    if (weekly) {
      weekLine.hidden = false;
      const wRemain = 100 - clamp(Math.round(weekly.usedPercent), 0, 100);
      const wResetMs = weekly.resetsAt * 1000;
      $(`${prefix}WeekFill`).style.width = `${wRemain}%`;
      $(`${prefix}WeekPct`).textContent = `周 ${wRemain}%`;
      applyTone(weekLine, engineKey, toneFor(wRemain));

      const weekMarker = $(`${prefix}WeekMarker`);
      if (weekly.windowMinutes > 0) {
        const wRemainTimePct = clamp(((wResetMs - Date.now()) / (weekly.windowMinutes * 60000)) * 100, 0, 100);
        weekMarker.style.left = `${wRemainTimePct.toFixed(1)}%`;
        weekMarker.hidden = false;
      } else {
        weekMarker.hidden = true;
      }

      if (!session) {
        $(`${prefix}Meta`).textContent = fmtCountdown(wResetMs);
        $(`${prefix}SessionRemain`).textContent = String(wRemain);
        $(`${prefix}SessionFill`).style.width = `${wRemain}%`;
        $(`${prefix}SessionMarker`).hidden = true;
        applyTone(section, engineKey, toneFor(wRemain));
      }
    } else {
      weekLine.hidden = true;
    }

    const fetchedAt = engineData.fetchedAt ? new Date(engineData.fetchedAt) : null;
    return !fetchedAt || Date.now() - fetchedAt.getTime() > STALE_AFTER;
  }

  function renderAll() {
    const staleCodex = renderEngine(data.codex, "codex", "codex");
    const staleAgy = renderEngine(data.antigravity, "agy", "antigravity");
    $("flag").hidden = !(staleCodex && staleAgy);
  }

  function reportSize() {
    if (isEmbed && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cardSize) {
      requestAnimationFrame(() => {
        const rect = $("card").getBoundingClientRect();
        window.webkit.messageHandlers.cardSize.postMessage({
          width: Math.round(rect.width),
          height: Math.round(rect.height),
        });
      });
    }
  }

  window.updateAgentQuota = (next) => {
    data = next || {};
    window.AGENT_QUOTA = data;
    renderAll();
    renderUsage();
    reportSize();
  };

  renderAll();
  setInterval(renderAll, 30000);
  reportSize();

  // ---- 今日用量（TokenLens 本地服务） --------------------------------------
  const USAGE_URL = "http://127.0.0.1:7777/api/summary?range=today";
  const PRICING_URL = "http://127.0.0.1:7777/api/pricing";
  const usageSection = $("usageSection");
  let lastUsageTotals = null;
  let usdRate = 6.67;

  const fmtCompact = (n) => {
    const v = Number(n) || 0;
    if (v >= 1e9) return (v / 1e9).toFixed(2) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "K";
    return String(Math.round(v));
  };

  function fmtCost(cnyCost) {
    const cny = Number(cnyCost) || 0;
    const currency = (data && data.currency) === "CNY" ? "CNY" : "USD";
    if (currency === "CNY") {
      return "\u00a5" + (cny >= 1000 ? fmtCompact(cny) : cny.toFixed(1));
    }
    const usd = cny / (usdRate > 0 ? usdRate : 6.67);
    return "$" + (usd >= 1000 ? fmtCompact(usd) : usd.toFixed(2));
  }

  function renderUsage() {
    if (!usageSection || !lastUsageTotals) return;
    const t = lastUsageTotals;
    $("usageTokens").textContent = fmtCompact(t.tokens);
    $("usageCost").textContent = fmtCost(t.cost);
    $("usageCache").textContent = t.cacheShare == null ? "\u2014" : "\u547d\u4e2d " + Math.round(t.cacheShare * 100) + "%";
    usageSection.dataset.state = "on";
    usageSection.title = "\u4eca\u65e5\u7528\u91cf\uff08\u6765\u81ea TokenLens \u672c\u673a\u65e5\u5fd7\uff09";
  }

  async function refreshUsage() {
    if (!usageSection) return;
    try {
      const [summaryRes, pricingRes] = await Promise.all([
        fetch(USAGE_URL, { cache: "no-store" }),
        fetch(PRICING_URL, { cache: "no-store" }).catch(() => null),
      ]);
      if (!summaryRes.ok) throw new Error(String(summaryRes.status));
      if (pricingRes && pricingRes.ok) {
        const p = await pricingRes.json();
        if (Number(p.usdRate) > 0) usdRate = Number(p.usdRate);
      }
      lastUsageTotals = (await summaryRes.json()).totals || {};
      renderUsage();
      reportSize();
    } catch (err) {
      lastUsageTotals = null;
      usageSection.dataset.state = "off";
      ["usageTokens", "usageCost", "usageCache"].forEach((id) => { const n = $(id); if (n) n.textContent = "\u2014"; });
      usageSection.title = "TokenLens \u672a\u8fd0\u884c";
      reportSize();
    }
  }
  if (usageSection) {
    refreshUsage();
    setInterval(refreshUsage, 60 * 1000);
  }
})();
