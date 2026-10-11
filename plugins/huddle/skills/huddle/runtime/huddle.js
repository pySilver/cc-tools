/* huddle runtime: renders the spec in <script id="hd-spec"> and hands the answer back.
   Answer path, first that applies: agterm page bridge (session.overlay.submit), the local
   HTTP fallback server (POST /answer), else a preview banner showing the JSON. */
(function () {
  "use strict";
  const SPEC = JSON.parse(document.getElementById("hd-spec").textContent);
  const KEYS = "123456789";
  const $ = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  // Resolve a theme variable to a concrete rgb() string (mermaid and SVG attributes cannot take var()/color-mix()).
  let probe;
  const css = (name) => {
    if (!probe) { probe = document.createElement("span"); probe.style.display = "none"; (document.querySelector(".hd") || document.body).appendChild(probe); }
    probe.style.color = ""; probe.style.color = `var(${name})`;
    return getComputedStyle(probe).color;
  };
  const rgbOf = (c) => (c.match(/[\d.]+/g) || [0, 0, 0]).slice(0, 3).map(Number);
  const mix = (a, b, t) => { const x = rgbOf(a), y = rgbOf(b); return "#" + x.map((v, i) => Math.round(v * t + y[i] * (1 - t)).toString(16).padStart(2, "0")).join(""); };

  // ---------- markdown (small, safe subset) ----------
  function inline(s) {
    s = esc(s);
    const codes = [];
    s = s.replace(/`([^`]+)`/g, (_, c) => { codes.push(c); return "\u0000" + (codes.length - 1) + "\u0000"; });
    s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
      .replace(/~~([^~]+)~~/g, "<s>$1</s>")
      .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2">$1</a>');
    return s.replace(/\u0000(\d+)\u0000/g, (_, i) => "<code>" + codes[+i] + "</code>");
  }
  function md(src) {
    const lines = String(src).replace(/\r/g, "").split("\n");
    let out = "", i = 0;
    while (i < lines.length) {
      const l = lines[i];
      if (/^```/.test(l)) {
        const lang = l.slice(3).trim(), buf = [];
        i++; while (i < lines.length && !/^```/.test(lines[i])) buf.push(lines[i++]);
        i++; out += codeHTML(buf.join("\n"), lang); continue;
      }
      let m;
      if ((m = /^(#{1,3})\s+(.*)/.exec(l))) { out += `<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`; i++; continue; }
      if (/^\s*[-*]\s+/.test(l) || /^\s*\d+[.)]\s+/.test(l)) {
        const ordered = /^\s*\d/.test(l), tag = ordered ? "ol" : "ul"; out += `<${tag}>`;
        while (i < lines.length && (/^\s*[-*]\s+/.test(lines[i]) || /^\s*\d+[.)]\s+/.test(lines[i])))
          out += "<li>" + inline(lines[i++].replace(/^\s*([-*]|\d+[.)])\s+/, "")) + "</li>";
        out += `</${tag}>`; continue;
      }
      if (/^>\s?/.test(l)) { const buf = []; while (i < lines.length && /^>\s?/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, "")); out += "<blockquote>" + inline(buf.join(" ")) + "</blockquote>"; continue; }
      if (!l.trim()) { i++; continue; }
      const buf = [];
      while (i < lines.length && lines[i].trim() && !/^(```|#{1,3}\s|>|\s*[-*]\s|\s*\d+[.)]\s)/.test(lines[i])) buf.push(lines[i++]);
      out += "<p>" + buf.map(inline).join("<br>") + "</p>";
    }
    return out;
  }
  // `start` numbers the lines from that value, so a note can say "line 47" (the script sets it for {"file": …} code).
  function codeHTML(code, lang, start) {
    let body = esc(code);
    if (lang === "diff") body = code.split("\n").map((ln) => {
      const c = ln.startsWith("@@") ? "hunk" : ln.startsWith("+") ? "add" : ln.startsWith("-") ? "del" : "";
      return c ? `<span class="${c}">${esc(ln)}</span>` : esc(ln);
    }).join("\n");
    else if (typeof start === "number") {
      const lines = code.split("\n"), w = String(start + lines.length - 1).length;
      body = lines.map((ln, i) => `<span class="ln" style="width:${w}ch">${start + i}</span>${esc(ln)}`).join("\n");
    }
    return `<pre class="hd-code" data-lang="${esc(lang || "")}">${body}</pre>`;
  }

  // ---------- palette ----------
  function palette() {
    const p = [css("--accent"), css("--ok"), css("--warn"), css("--magenta"), css("--cyan"), css("--bad")].filter(Boolean);
    return p.length ? p : ["#3d7cf5", "#2f9e5b", "#c99a14", "#a35bd6", "#1d9fb3", "#d0453f"];
  }
  const fmt = (v, unit) => {
    if (typeof v !== "number") return esc(v);
    const a = Math.abs(v), s = a >= 1e6 ? (v / 1e6).toFixed(a >= 1e7 ? 0 : 1) + "M" : a >= 1e4 ? (v / 1e3).toFixed(a >= 1e5 ? 0 : 1) + "k" : (Math.round(v * 100) / 100).toLocaleString();
    return esc(s + (unit || ""));
  };
  function niceMax(v) { if (v <= 0) return 1; const p = Math.pow(10, Math.floor(Math.log10(v))), n = v / p; return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p; }

  // ---------- charts (inline SVG, theme-colored) ----------
  function chart(c) {
    const wrap = $("div", "hd-chart"), type = c.type || "bar", unit = c.unit || "", cols = palette();
    const series = c.series || (c.values ? [{ name: c.name || "", values: c.values }] : []);
    const labels = c.labels || (series[0] ? series[0].values.map((_, i) => String(i + 1)) : []);
    const colorOf = (i) => (series[i] && series[i].color) || cols[i % cols.length];
    const isHl = (i) => c.highlight != null && (i === c.highlight || labels[i] === c.highlight);
    if (c.title) wrap.appendChild($("div", "hd-btitle", esc(c.title)));
    let svg = "";
    if (type === "donut" || type === "pie") {
      const vals = series[0].values, total = vals.reduce((a, b) => a + b, 0) || 1, R = 70, r = type === "pie" ? 0 : 44, cx = 90, cy = 90;
      let a0 = -Math.PI / 2;
      vals.forEach((v, i) => {
        const a1 = a0 + (v / total) * Math.PI * 2, large = a1 - a0 > Math.PI ? 1 : 0;
        const p = (rad, ang) => [cx + rad * Math.cos(ang), cy + rad * Math.sin(ang)];
        const [x0, y0] = p(R, a0), [x1, y1] = p(R, a1), [x2, y2] = p(r, a1), [x3, y3] = p(r, a0);
        const col = (c.colors && c.colors[i]) || cols[i % cols.length];
        const d = vals.length === 1 ? `M${cx - R},${cy}a${R},${R} 0 1,0 ${2 * R},0a${R},${R} 0 1,0 ${-2 * R},0` + (r ? `M${cx - r},${cy}a${r},${r} 0 1,1 ${2 * r},0a${r},${r} 0 1,1 ${-2 * r},0` : "")
          : `M${x0},${y0}A${R},${R} 0 ${large} 1 ${x1},${y1}L${x2},${y2}` + (r ? `A${r},${r} 0 ${large} 0 ${x3},${y3}` : `L${cx},${cy}`) + "Z";
        svg += `<path d="${d}" fill="${col}" fill-rule="evenodd" stroke="var(--bg)" stroke-width="2"><title>${esc(labels[i])}: ${fmt(v, unit)} (${Math.round((v / total) * 100)}%)</title></path>`;
        a0 = a1;
      });
      if (r && c.center !== false) svg += `<text x="${cx}" y="${cy + 5}" text-anchor="middle" class="vl" style="font-size:16px;font-weight:650">${esc(c.center || fmt(total, unit))}</text>`;
      wrap.insertAdjacentHTML("beforeend", `<svg viewBox="0 0 180 180" style="max-width:${c.size || 200}px;margin:0 auto">${svg}</svg>`);
      const lg = $("div", "hd-legend");
      vals.forEach((v, i) => lg.insertAdjacentHTML("beforeend", `<span><i style="background:${(c.colors && c.colors[i]) || cols[i % cols.length]}"></i>${esc(labels[i])} · ${fmt(v, unit)}${unit === "%" ? "" : ` (${Math.round((v / total) * 100)}%)`}</span>`));
      wrap.appendChild(lg); return wrap;
    }
    if (type === "hbar") {
      const vals = series[0].values, max = c.max || niceMax(Math.max(...vals)), rowH = 26, labW = c.labelWidth || 120, W = 560, H = vals.length * rowH + 4;
      vals.forEach((v, i) => {
        const y = i * rowH + 3, w = Math.max(1, (v / max) * (W - labW - 60)), col = c.highlight == null || isHl(i) ? colorOf(0) : css("--line-strong");
        svg += `<text x="${labW - 8}" y="${y + 15}" text-anchor="end">${esc(labels[i])}</text><rect x="${labW}" y="${y + 3}" width="${w}" height="${rowH - 9}" rx="3" fill="${col}"><title>${esc(labels[i])}: ${fmt(v, unit)}</title></rect><text class="vl" x="${labW + w + 6}" y="${y + 15}">${fmt(v, unit)}</text>`;
      });
      wrap.insertAdjacentHTML("beforeend", `<svg viewBox="0 0 ${W} ${H}">${svg}</svg>`); return wrap;
    }
    // bar / line / area: shared axes
    const W = 600, H = c.height || 220, L = 44, R = 12, T = 12, B = 26, all = series.flatMap((s) => s.values);
    const min = c.min != null ? c.min : Math.min(0, ...all), max = c.max || niceMax(Math.max(...all)), pw = W - L - R, ph = H - T - B;
    const yOf = (v) => T + ph - ((v - min) / (max - min || 1)) * ph;
    for (let k = 0; k <= 4; k++) { const v = min + ((max - min) * k) / 4, y = yOf(v); svg += `<line class="grid" x1="${L}" x2="${W - R}" y1="${y}" y2="${y}"/><text x="${L - 6}" y="${y + 4}" text-anchor="end">${fmt(v, unit)}</text>`; }
    const n = labels.length, step = pw / Math.max(1, n), every = Math.ceil(n / 12);
    labels.forEach((lb, i) => { if (i % every === 0) svg += `<text x="${L + step * i + step / 2}" y="${H - 8}" text-anchor="middle">${esc(lb)}</text>`; });
    if (type === "bar") {
      const g = series.length, bw = Math.min(42, (step * 0.72) / g);
      series.forEach((s, si) => s.values.forEach((v, i) => {
        const x = L + step * i + (step - bw * g) / 2 + si * bw, y = yOf(Math.max(v, 0)), h = Math.abs(yOf(v) - yOf(0));
        svg += `<rect x="${x + 1}" y="${y}" width="${bw - 2}" height="${Math.max(1, h)}" rx="3" fill="${c.highlight == null || g > 1 || isHl(i) ? colorOf(si) : css("--line-strong")}"><title>${esc(s.name ? s.name + " · " : "")}${esc(labels[i])}: ${fmt(v, unit)}</title></rect>`;
        if (c.values_on_bars !== false && g === 1 && n <= 16) svg += `<text class="vl" x="${x + bw / 2}" y="${y - 4}" text-anchor="middle">${fmt(v, unit)}</text>`;
      }));
    } else {
      series.forEach((s, si) => {
        const pts = s.values.map((v, i) => [L + step * i + step / 2, yOf(v)]), col = colorOf(si);
        if (type === "area") svg += `<path d="M${pts[0][0]},${yOf(Math.max(min, 0))}L${pts.map((p) => p.join(",")).join("L")}L${pts[pts.length - 1][0]},${yOf(Math.max(min, 0))}Z" fill="${col}" opacity=".15"/>`;
        svg += `<polyline points="${pts.map((p) => p.join(",")).join(" ")}" fill="none" stroke="${col}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>`;
        pts.forEach((p, i) => (svg += `<circle cx="${p[0]}" cy="${p[1]}" r="${n > 30 ? 0 : 3}" fill="${col}"><title>${esc(s.name ? s.name + " · " : "")}${esc(labels[i])}: ${fmt(s.values[i], unit)}</title></circle>`));
      });
    }
    if (type !== "bar" && c.highlight != null) labels.forEach((lb, i) => {
      if (!isHl(i)) return;
      const x = L + step * i + step / 2;
      svg += `<line x1="${x}" x2="${x}" y1="${T}" y2="${T + ph}" stroke="${css("--line-strong")}" stroke-dasharray="3 3"/>`;
      series.forEach((s2, si) => (svg += `<circle cx="${x}" cy="${yOf(s2.values[i])}" r="5" fill="${colorOf(si)}" stroke="var(--bg)" stroke-width="2"/>`));
    });
    (c.marks || []).forEach((m) => { const y = yOf(m.value); svg += `<line x1="${L}" x2="${W - R}" y1="${y}" y2="${y}" stroke="${css("--bad")}" stroke-dasharray="4 3"/><text x="${W - R}" y="${y - 4}" text-anchor="end" style="fill:${css("--bad")}">${esc(m.label || "")}</text>`; });
    svg += `<line class="axis" x1="${L}" x2="${W - R}" y1="${yOf(Math.max(min, 0))}" y2="${yOf(Math.max(min, 0))}"/>`;
    wrap.insertAdjacentHTML("beforeend", `<svg viewBox="0 0 ${W} ${H}">${svg}</svg>`);
    if (series.length > 1 || (series[0] && series[0].name)) {
      const lg = $("div", "hd-legend");
      series.forEach((s, i) => lg.insertAdjacentHTML("beforeend", `<span><i style="background:${colorOf(i)}"></i>${esc(s.name || "")}</span>`));
      wrap.appendChild(lg);
    }
    return wrap;
  }

  // ---------- blocks ----------
  let mermaidN = 0;
  const pendingMermaid = [];
  const blockJS = [];
  function block(b) {
    if (b == null) return $("div");
    if (typeof b === "string") return $("div", "hd-md", md(b));
    if (Array.isArray(b)) { const d = $("div", "hd-blocks"); b.forEach((x) => d.appendChild(block(x))); d.style.margin = "0"; return d; }
    let el;
    if (b.md != null) el = $("div", "hd-md", md(b.md));
    else if (b.mermaid != null) {
      el = $("div", "hd-mermaid"); el.dataset.src = b.mermaid; el.id = "hd-mm-" + mermaidN++;
      el.appendChild($("pre", "hd-code", esc(b.mermaid))); pendingMermaid.push(el);
    } else if (b.chart) el = chart(b.title && !b.chart.title ? Object.assign({}, b.chart, { title: b.title }) : b.chart);
    else if (b.stats) {
      el = $("div", "hd-stats");
      b.stats.forEach((s) => {
        const dir = s.good === true ? "good" : s.good === false ? "bad" : "flat";
        el.insertAdjacentHTML("beforeend", `<div class="hd-stat"><div class="l">${esc(s.label)}</div><div class="v">${esc(s.value)}</div>${s.delta ? `<div class="d ${dir}">${esc(s.delta)}</div>` : ""}${s.sub ? `<div class="l">${esc(s.sub)}</div>` : ""}</div>`);
      });
    } else if (b.image === "") el = $("div", "hd-missing", esc(b.alt || "image missing"));
    else if (b.image) {
      el = $("div");
      const img = $("img", "hd-img"); img.src = b.image; img.alt = b.alt || "";
      if (b.height) { img.style.height = b.height + "px"; img.style.objectFit = b.fit || "contain"; img.style.width = "100%"; }
      el.appendChild(img);
    } else if (b.svg) { el = $("div", "hd-svg", b.svg); el.style.textAlign = "center"; }
    else if (b.html != null) el = $("div", "hd-html", b.html);
    else if (b.code != null) el = $("div", "", codeHTML(b.code, b.lang, b.start));
    else if (b.diff != null) el = $("div", "", codeHTML(b.diff, "diff"));
    else if (b.table) {
      const t = b.table, num = (v) => typeof v === "number";
      let h = `<table class="hd-table"><thead><tr>${(t.columns || []).map((c, i) => `<th class="${t.rows && t.rows[0] && num(t.rows[0][i]) ? "num" : ""}">${esc(c)}</th>`).join("")}</tr></thead><tbody>`;
      (t.rows || []).forEach((r) => (h += "<tr>" + r.map((v) => `<td class="${num(v) ? "num" : ""}">${num(v) ? esc(v.toLocaleString()) : inline(v)}</td>`).join("") + "</tr>"));
      el = $("div", "", h + "</tbody></table>");
    } else if (b.kv) {
      let h = '<table class="hd-table"><tbody>';
      (Array.isArray(b.kv) ? b.kv : Object.entries(b.kv)).forEach(([k, v]) => (h += `<tr><th style="width:35%">${esc(k)}</th><td>${inline(v)}</td></tr>`));
      el = $("div", "", h + "</tbody></table>");
    } else if (b.callout != null) el = $("div", "hd-callout hd-md " + (b.tone || ""), md(b.callout));
    else if (b.radius != null) {
      el = $("div", "hd-sample"); const box = $("div", "hd-radius-box"); box.style.borderRadius = typeof b.radius === "number" ? b.radius + "px" : b.radius; el.appendChild(box);
    } else if (b.gap != null) {
      el = $("div", "hd-sample"); const row = $("div", "hd-gap-row" + (b.direction === "column" ? " col" : ""));
      row.style.gap = typeof b.gap === "number" ? b.gap + "px" : b.gap; for (let k = 0; k < (b.items || 3); k++) row.appendChild($("div")); el.appendChild(row);
    } else if (b.colors) {
      el = $("div", "hd-sample"); const sw = $("div", "hd-swatches");
      b.colors.forEach((c) => { const v = typeof c === "string" ? c : c.value, n = typeof c === "string" ? c : c.name || c.value; sw.insertAdjacentHTML("beforeend", `<div class="hd-swatch"><i style="background:${esc(v)}"></i>${esc(n)}</div>`); });
      el.appendChild(sw);
    } else if (b.type) {
      const f = b.type; el = $("div", "hd-sample");
      const d = $("div", "hd-type"), s = $("div"); s.textContent = f.text || "The quick brown fox · 素早い茶色の狐";
      Object.assign(s.style, { fontFamily: f.family || "", fontSize: f.size ? f.size + (typeof f.size === "number" ? "px" : "") : "", fontWeight: f.weight || "", lineHeight: f.lineHeight || "", letterSpacing: f.tracking || "" });
      d.appendChild(s); d.appendChild($("div", "meta", esc([f.family, f.size && f.size + (typeof f.size === "number" ? "px" : ""), f.weight].filter(Boolean).join(" · ")))); el.appendChild(d);
    } else if (b.style) { el = $("div", "hd-sample"); const s = $("div", "", b.text != null ? esc(b.text) : ""); Object.assign(s.style, b.style); el.appendChild(s); }
    else if (b.row) { el = $("div", "hd-row"); b.row.forEach((x) => el.appendChild(block(x))); }
    else if (b.js != null) { el = $("div", "hd-js"); blockJS.push([el, b.js]); }
    else el = $("pre", "hd-err", "unknown block: " + esc(JSON.stringify(b)));
    // A code title is usually a path, and uppercasing a path changes what it names.
    if (b.title && !b.chart) { const w = $("div"); w.appendChild($("div", "hd-btitle" + (b.code != null ? " path" : ""), esc(b.title))); w.appendChild(el); el = w; }
    if (b.card) { const w = $("div", "hd-card"); w.appendChild(el); el = w; }
    if (b.caption) el.appendChild($("div", "hd-cap", inline(b.caption)));
    return el;
  }
  function blocks(list) { const d = $("div", "hd-blocks"); (Array.isArray(list) ? list : [list]).forEach((b) => d.appendChild(block(b))); return d; }

  // block() queues js and mermaid work; flush() runs whatever is queued. A controls preview is rebuilt on
  // every change, so it flushes after each redraw, not only once at startup.
  let ready = false, mermaidReady = false, mermaidChain = Promise.resolve();
  function flush() {
    blockJS.splice(0).forEach(([el, code]) => { try { new Function("el", "api", code)(el, api); } catch (e) { el.appendChild($("pre", "hd-err", "js: " + esc(e.message || e))); } });
    const els = pendingMermaid.splice(0);
    if (els.length) mermaidChain = mermaidChain.then(() => renderMermaid(els));
  }
  async function renderMermaid(els) {
    if (!window.mermaid) { els.forEach((el) => el.classList.add("err")); return; }
    if (!mermaidReady) { mermaidReady = true; initMermaid(); }
    for (const el of els) {
      try { const { svg } = await window.mermaid.render(el.id + "-svg", el.dataset.src); el.innerHTML = svg; }
      catch (e) { el.classList.add("err"); el.appendChild($("div", "hd-err", "mermaid: " + esc(e.message || e))); }
    }
  }
  function initMermaid() {
    const fg = css("--fg"), bg = getComputedStyle(document.body).backgroundColor, acc = css("--accent");
    const dark = rgbOf(bg).reduce((a, b) => a + b, 0) < 384, hex = (c) => mix(c, c, 1);
    try {
      window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "base", fontFamily: "-apple-system, system-ui, sans-serif",
        themeVariables: { darkMode: dark, background: hex(bg), mainBkg: mix(acc, bg, 0.16), primaryColor: mix(acc, bg, 0.16), primaryBorderColor: mix(acc, bg, 0.75), primaryTextColor: hex(fg), nodeTextColor: hex(fg),
          lineColor: mix(fg, bg, 0.5), textColor: hex(fg), secondaryColor: mix(css("--ok"), bg, 0.16), tertiaryColor: mix(fg, bg, 0.06), clusterBkg: mix(fg, bg, 0.04), clusterBorder: mix(fg, bg, 0.22),
          edgeLabelBackground: hex(bg), noteBkgColor: mix(css("--warn"), bg, 0.15), noteTextColor: hex(fg), actorBkg: mix(acc, bg, 0.16), actorBorder: mix(acc, bg, 0.75), actorTextColor: hex(fg), signalColor: hex(fg), signalTextColor: hex(fg), fontSize: "14px" } });
    } catch (e) { /* initialize is best effort */ }
  }

  // ---------- questions ----------
  const qs = (SPEC.questions || [SPEC]).map((q, qi) => ({
    id: q.id || (SPEC.questions ? "q" + (qi + 1) : "answer"),
    spec: q,
    mode: q.mode || (q.controls ? "tune" : q.options && q.options.length ? "single" : "text"),
    controls: (q.controls || []).map((c) => Object.assign({ type: "range" }, c)),
    values: {}, from: null,
    options: (q.options || []).map((o, i) => (typeof o === "string" ? { id: o, label: o } : Object.assign({ id: o.id || "o" + (i + 1) }, o))),
    sel: new Set(), hl: 0, el: null, ta: null, optEls: [],
  }));
  if (!qs.length) { document.getElementById("app").innerHTML = '<pre class="hd-err">huddle: the spec has no questions</pre>'; return; }
  qs.forEach((q) => q.options.forEach((o, i) => { if (o.default || o.selected) q.sel.add(i); }));
  let cur = 0, finished = false, reviewing = false, showHelp = false;

  const app = $("div", "hd");
  app.dataset.style = SPEC.style || "refined";
  if (SPEC.width === "narrow") app.classList.add("narrow");
  document.getElementById("app").appendChild(app);

  const top = $("div", "hd-top", `<span class="hd-dot"></span><span class="hd-src">${esc(SPEC.source || "Claude is asking")}</span>${SPEC.subtitle ? `<span class="hd-subt">${esc(SPEC.subtitle)}</span>` : ""}`);
  app.appendChild(top);
  if (SPEC.title) app.appendChild($("div", "hd-title", inline(SPEC.title)));
  // One question: the question comes first and its evidence under it. Several: shared context above the tabs.
  if (SPEC.context != null && qs.length > 1) app.appendChild(blocks(SPEC.context));

  let tabs = null;
  if (qs.length > 1) {
    tabs = $("div", "hd-tabs"); app.appendChild(tabs);
    qs.forEach((q, i) => { const t = $("button", "hd-tab", `<span class="n">${i + 1}</span><span class="h">${esc(q.spec.header || q.spec.prompt || q.id)}</span><span class="a"></span>`); t.type = "button"; t.onclick = () => go(i); tabs.appendChild(t); q.tab = t; });
  }

  qs.forEach((q, qi) => {
    const s = q.spec, el = $("div", "hd-q " + q.mode); q.el = el;
    if (s.prompt) el.appendChild($("div", "hd-prompt", inline(s.prompt)));
    const hint = s.hint || (q.mode === "multi" ? `Choose ${s.min ? "at least " + s.min : "any"}${s.max ? ", up to " + s.max : ""}` : "");
    if (hint) el.appendChild($("div", "hd-hint", inline(hint)));
    if (SPEC.context != null && qs.length === 1) el.appendChild(blocks(SPEC.context));
    if (qs.length > 1 && s.context != null) el.appendChild(blocks(s.context)); // a question's own evidence, like body
    if (s.body != null) el.appendChild(blocks(s.body));
    if (q.mode === "tune") el.appendChild(buildTune(q));
    if (s.recommendation) el.appendChild($("div", "hd-recsum", `<b class="lab">★ Recommendation</b>${inline(s.recommendation)}`));

    if (q.options.length) {
      const hasPrev = q.options.some((o) => o.preview != null);
      const layout = s.layout || (q.mode === "tune" ? "inline" : hasPrev ? "grid" : "list");
      const box = $("div", "hd-opts " + layout);
      const cols = s.columns || (layout === "compare" ? Math.min(q.options.length, 3) : Math.min(q.options.length <= 4 ? q.options.length : 3, 4));
      box.style.setProperty("--cols", cols);
      q.options.forEach((o, i) => {
        const b = $("div", "hd-opt" + (o.recommended ? " rec" : "")); b.tabIndex = -1; b.setAttribute("role", "button");
        const key = $("span", "hd-key", i < 9 ? KEYS[i] : ""), cardLike = layout === "grid" || layout === "compare";
        if (!cardLike) b.appendChild(key);
        if (o.preview != null && layout !== "list" && layout !== "inline") { const p = $("div", "hd-prev"); p.appendChild(block(o.preview)); b.appendChild(p); }
        const body = $("div", "hd-body");
        const lab = $("div", "hd-label", inline(o.label || o.id));
        if (cardLike) lab.prepend(key); // on cards the key sits by the label, never over the picture
        if (o.recommended) lab.appendChild($("span", "hd-badge", esc(o.badge || "Recommended")));
        (o.tags || []).forEach((t) => lab.appendChild($("span", "hd-tag", esc(t))));
        body.appendChild(lab);
        if (o.subtitle) body.appendChild($("div", "hd-sub", inline(o.subtitle)));
        if (typeof o.recommended === "string") body.appendChild($("div", "hd-why", inline(o.recommended)));
        const more = $("div", "hd-more");
        if ((o.pros && o.pros.length) || (o.cons && o.cons.length)) {
          const pc = $("div", "hd-pc");
          pc.appendChild($("ul", "pro", (o.pros || []).map((x) => `<li>${inline(x)}</li>`).join("")));
          pc.appendChild($("ul", "con", (o.cons || []).map((x) => `<li>${inline(x)}</li>`).join("")));
          more.appendChild(pc);
        }
        if (o.detail != null) { const d = $("div", "hd-detail"); d.appendChild(blocks(o.detail)); more.appendChild(d); }
        if (o.preview != null && (layout === "list")) { const d = $("div", "hd-detail"); d.appendChild(block(o.preview)); more.appendChild(d); }
        const hasMore = more.childNodes.length > 0;
        if (hasMore) {
          body.appendChild(more);
          if (s.expanded || layout === "compare") b.classList.add("open");
          else if (layout !== "inline") {
            // A full-width row of its own, so opening details never selects the option by a near miss.
            const np = (o.pros || []).length, nc = (o.cons || []).length;
            const what = [np && `${np} pro${np > 1 ? "s" : ""}`, nc && `${nc} con${nc > 1 ? "s" : ""}`, (o.detail != null || (o.preview != null && layout === "list")) && "details"].filter(Boolean).join(" · ");
            const c = $("button", "hd-toggle", `<span class="tw">▸</span> <span class="what">${esc(what)}</span>`); c.type = "button";
            c.onclick = (e) => { e.stopPropagation(); b.classList.toggle("open"); };
            body.appendChild(c);
          }
          more.addEventListener("click", (e) => e.stopPropagation()); // reading pros/cons is not choosing
        }
        b.appendChild(body);
        b.addEventListener("click", () => { q.hl = i; choose(q, i); });
        b.addEventListener("dblclick", () => { if (q.mode === "single") { q.sel = new Set([i]); next(); } });
        box.appendChild(b); q.optEls.push(b);
      });
      el.appendChild(box);
    }

    const t = s.text === false ? null : Object.assign({}, typeof s.text === "object" ? s.text : {});
    if (t) {
      const w = $("div", "hd-text" + (q.mode === "text" ? " big" : ""));
      if (t.label || q.mode === "text") w.appendChild($("label", "", esc(t.label || "Your answer")));
      const ta = $("textarea"); ta.placeholder = t.placeholder || (q.mode === "text" ? "Type here…" : q.options.length || q.mode === "tune" ? "Add a note, or answer in your own words…" : "Type here…");
      w.appendChild($("kbd", "hd-tabkey", "Tab"));
      if (t.value) ta.value = t.value;
      ta.rows = q.mode === "text" ? 5 : 1;
      ta.addEventListener("input", () => { autosize(ta); refresh(); });
      w.appendChild(ta); el.appendChild(w); q.ta = ta;
    }
    app.appendChild(el);
  });

  const review = $("div", "hd-review"); app.appendChild(review);
  app.appendChild($("div", "hd-spacer"));
  const foot = $("div", "hd-foot");
  const keys = $("div", "hd-keys");
  foot.appendChild(keys);
  const status = $("span", "hd-status"); foot.appendChild(status);
  const backBtn = $("button", "hd-btn ghost", "Back <kbd>Esc</kbd>"); backBtn.type = "button"; backBtn.onclick = () => leaveReview(); backBtn.hidden = true; foot.appendChild(backBtn);
  const chatBtn = $("button", "hd-btn ghost", "Discuss in chat <kbd>⌥⏎</kbd>"); chatBtn.type = "button"; chatBtn.onclick = () => deliver({ status: "chat", text: allText() });
  if (SPEC.chat !== false) foot.appendChild(chatBtn);
  const submitBtn = $("button", "hd-btn primary", ""); submitBtn.type = "button"; submitBtn.onclick = () => next();
  foot.appendChild(submitBtn);
  app.appendChild(foot);

  function autosize(ta) { ta.style.height = "auto"; ta.style.height = Math.min(ta.scrollHeight + 3, 260) + "px"; }
  function allText() { return qs.map((q) => (q.ta ? q.ta.value.trim() : "")).filter(Boolean).join("\n\n"); }

  function choose(q, i) {
    if (q.mode === "tune") {
      const o = q.options[i]; q.sel = new Set([i]); q.from = o.id;
      Object.assign(q.values, o.values || {}); q.syncControls(); q.draw(); refresh(); return;
    }
    if (q.mode === "multi") {
      if (q.sel.has(i)) q.sel.delete(i);
      else { if (q.spec.max && q.sel.size >= q.spec.max) return flash(`At most ${q.spec.max}`); q.sel.add(i); }
    } else if (q.mode === "single") q.sel = q.sel.has(i) && q.spec.toggle !== false ? new Set() : new Set([i]);
    refresh();
  }
  function valid(q) {
    if (q.mode === "tune") return true;
    const txt = q.ta ? q.ta.value.trim() : "";
    const t = typeof q.spec.text === "object" ? q.spec.text : {};
    if (t.required && !txt) return false;
    if (q.mode === "text") return !!txt || q.spec.optional === true;
    if (q.mode === "multi" && q.spec.min && q.sel.size < q.spec.min && !txt) return false;
    return q.sel.size > 0 || !!txt || q.spec.optional === true;
  }
  let flashT;
  function flash(msg) { status.textContent = msg; clearTimeout(flashT); flashT = setTimeout(() => (status.textContent = ""), 1800); }
  function summary(q) {
    const sel = [...q.sel].sort((a, b) => a - b).map((i) => q.options[i].label || q.options[i].id);
    const txt = q.ta ? q.ta.value.trim() : "";
    return { sel, txt };
  }
  function refresh() {
    qs.forEach((q, qi) => {
      q.optEls.forEach((b, i) => { b.classList.toggle("on", q.sel.has(i)); b.classList.toggle("hl", qi === cur && i === q.hl && kbdNav && !reviewing); });
      q.el.classList.toggle("cur", qi === cur && !reviewing);
      if (q.tab) {
        const { sel, txt } = summary(q);
        q.tab.classList.toggle("cur", qi === cur && !reviewing); q.tab.classList.toggle("done", valid(q) && (sel.length || txt));
        q.tab.querySelector(".a").textContent = q.mode === "tune" ? (sel.length ? sel.join(", ") : tuned(q) ? "custom" : "") + (txt ? " + note" : "")
          : sel.length ? sel.join(", ") + (txt ? " + note" : "") : txt ? "note" : "";
      }
    });
    review.classList.toggle("cur", reviewing);
    if (tabs) tabs.classList.toggle("reviewing", reviewing);
    backBtn.hidden = !reviewing;
    const last = cur === qs.length - 1, q = qs[cur];
    if (reviewing) {
      submitBtn.innerHTML = esc(SPEC.submitLabel || "Send answers") + " <kbd>⏎</kbd>"; submitBtn.disabled = false;
      keys.innerHTML = `<span><kbd>⏎</kbd> send</span><span><kbd>1</kbd>–<kbd>${Math.min(qs.length, 9)}</kbd> edit an answer</span><span><kbd>Esc</kbd> back</span>`;
      return;
    }
    submitBtn.innerHTML = esc(last ? (willReview() ? "Review" : SPEC.submitLabel || "Submit") : "Next") + " <kbd>⏎</kbd>";
    submitBtn.disabled = !valid(q);
    const n = Math.min(q.options.length, 9), list = n && q.optEls[0].parentElement.classList.contains("list");
    const full = [
      n ? `<span><kbd>1</kbd>–<kbd>${n}</kbd> ${q.mode === "multi" ? "toggle" : q.mode === "tune" ? "presets" : "choose"}</span>` : "",
      q.mode === "tune" ? `<span><kbd>↓</kbd> sliders · <kbd>←</kbd><kbd>→</kbd> adjust · <kbd>r</kbd> replay</span>` : "",
      q.ta ? `<span><kbd>Tab</kbd> note</span>` : "",
      qs.length > 1 ? `<span><kbd>[</kbd><kbd>]</kbd> questions</span>` : "",
    ];
    const more = [
      n ? `<span>${list ? "<kbd>↑</kbd><kbd>↓</kbd>" : "<kbd>←</kbd><kbd>→</kbd><kbd>↑</kbd><kbd>↓</kbd>"} move · <kbd>Space</kbd> pick</span>` : "",
      q.ta ? `<span><kbd>Esc</kbd> leave note · <kbd>⌘⏎</kbd> send from note</span>` : "",
      n && q.el.querySelector(".hd-toggle") ? `<span><kbd>e</kbd> details · <kbd>E</kbd> all</span>` : "",
      `<span><kbd>⌥⏎</kbd> discuss in chat · <kbd>⌘W</kbd> dismiss</span>`,
    ];
    keys.innerHTML = full.concat(showHelp ? more : ['<span class="hd-more-keys"><kbd>?</kbd> more keys</span>']).filter(Boolean).join("");
  }
  function willReview() {
    const r = SPEC.review || "auto";
    if (r === "never" || r === false) return false;
    if (r === "always" || r === true) return true;
    return qs.length > 1 || qs.some((q) => q.mode !== "text" && q.ta && q.ta.value.trim()); // auto: several questions, or a note on a choice
  }
  function showReview() {
    reviewing = true;
    review.innerHTML = "";
    review.appendChild($("div", "hd-prompt", "Review your answers"));
    const list = $("div", "hd-rlist");
    qs.forEach((q, qi) => {
      const { sel, txt } = summary(q), row = $("button", "hd-ritem"); row.type = "button";
      row.innerHTML = `<span class="hd-key">${qi < 9 ? KEYS[qi] : ""}</span><div class="hd-rq">${inline(q.spec.header ? q.spec.header : q.spec.prompt || q.id)}${q.spec.header && q.spec.prompt ? `<span class="hd-rp">${inline(q.spec.prompt)}</span>` : ""}</div>`
        + `<div class="hd-ra">${q.mode === "tune" ? tuneSummary(q) : sel.length ? sel.map((x) => `<span class="hd-chip">${inline(x)}</span>`).join("") : txt ? "" : '<span class="hd-none">no choice</span>'}${thumbs(q)}${txt ? `<div class="hd-note">${esc(txt).replace(/\n/g, "<br>")}</div>` : ""}</div><span class="hd-edit">Edit</span>`;
      row.onclick = () => { reviewing = false; go(qi); };
      list.appendChild(row);
    });
    review.appendChild(list);
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    refresh(); window.scrollTo({ top: 0 });
  }
  const differs = (vals, ref) => Object.keys(ref).some((k) => vals[k] !== ref[k]);
  const preset = (q) => q.from && q.options.find((o) => o.id === q.from);
  const presetKept = (q) => !!preset(q) && !differs(q.values, Object.assign({}, q.initial, preset(q).values));
  const tuned = (q) => differs(q.values, q.initial);
  function tuneSummary(q) {
    return (presetKept(q) ? `<span class="hd-chip">${inline(q.options.find((o) => o.id === q.from).label)}</span>` : "")
      + q.controls.map((c) => `<span class="hd-chip val"><span>${esc(c.label || c.id)}</span> ${esc(showVal(c, q.values[c.id]))}</span>`).join("")
      + (q.live ? `<div class="hd-rthumbs"><div class="hd-rthumb wide">${q.live.outerHTML}</div></div>` : "");
  }
  function thumbs(q) {
    const prevs = [...q.sel].sort((a, b) => a - b).map((i) => q.optEls[i] && q.optEls[i].querySelector(".hd-prev")).filter(Boolean);
    if (!prevs.length) return "";
    return '<div class="hd-rthumbs">' + prevs.map((p) => `<div class="hd-rthumb">${p.outerHTML}</div>`).join("") + "</div>";
  }
  function leaveReview() { reviewing = false; go(qs.length - 1); }
  function go(i) { reviewing = false; cur = Math.max(0, Math.min(qs.length - 1, i)); if (qs[cur].draw) qs[cur].draw(); refresh(); const q = qs[cur]; if (q.mode === "text" && q.ta) q.ta.focus(); else if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); window.scrollTo({ top: 0 }); }
  function next() {
    if (finished) return;
    if (reviewing) return finish();
    const q = qs[cur];
    if (!valid(q)) return flash(q.mode === "text" ? "Type an answer first" : "Pick an option or write something");
    if (cur < qs.length - 1) return go(cur + 1);
    const bad = qs.findIndex((x) => !valid(x));
    if (bad >= 0) { go(bad); return flash("This one still needs an answer"); }
    if (willReview()) return showReview();
    finish();
  }
  function finish() {
    const answers = {};
    qs.forEach((x) => {
      const sel = [...x.sel].sort((a, b) => a - b).map((i) => x.options[i]);
      const a = { selected: sel.map((o) => o.id), labels: sel.map((o) => o.label || o.id) };
      const txt = x.ta ? x.ta.value.trim() : ""; if (txt) a.text = txt;
      if (api.extra[x.id] !== undefined) a.extra = api.extra[x.id];
      if (x.mode === "tune") {
        a.values = Object.assign({}, x.values);
        a.selected = presetKept(x) ? [x.from] : []; a.labels = a.selected.map((id) => preset(x).label);
        if (x.from && !presetKept(x)) a.from = x.from;
      }
      answers[x.id] = a;
    });
    deliver({ status: "answered", answers });
  }
  async function deliver(v) {
    if (finished) return; finished = true;
    const value = JSON.stringify(v);
    try {
      if (window.agterm && window.agterm.request) { await window.agterm.request("session.overlay.submit", { args: { value } }); return; }
      if (location.protocol.startsWith("http")) {
        await fetch("/answer", { method: "POST", headers: { "content-type": "application/json" }, body: value });
        document.body.appendChild($("div", "hd-done", "Answer sent — you can close this tab.")); return;
      }
      document.body.appendChild($("div", "hd-done", `<div>Preview mode (no agterm bridge). Answer:<pre>${esc(JSON.stringify(v, null, 2))}</pre></div>`));
      console.log("[huddle] answer", value);
    } catch (e) { finished = false; flash("Could not send: " + (e.message || e)); }
  }

  // ---------- keyboard ----------
  let kbdNav = false;
  document.addEventListener("keydown", (e) => {
    if (finished) return;
    const q = qs[cur], inText = document.activeElement && document.activeElement.tagName === "TEXTAREA";
    if (e.key === "Enter" && e.altKey) { e.preventDefault(); if (SPEC.chat !== false) chatBtn.click(); return; }
    const tag = document.activeElement && document.activeElement.tagName;
    const inCtl = document.activeElement && document.activeElement.closest && document.activeElement.closest(".hd-ctl");
    if (tag === "INPUT" || tag === "SELECT" || inCtl) {
      const ctl = inCtl;
      if (e.key === "Escape") document.activeElement.blur();
      else if (ctl && ctl.classList.contains("select") && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
        e.preventDefault();
        const bs = [...ctl.querySelectorAll(".hd-seg button")], i = bs.findIndex((x) => x.classList.contains("on")) + (e.key === "ArrowRight" ? 1 : -1);
        if (bs[i]) { bs[i].click(); bs[i].focus(); }
      }
      else if (ctl && (e.key === "ArrowUp" || e.key === "ArrowDown")) { e.preventDefault(); focusCtl(ctl, e.key === "ArrowDown" ? 1 : -1); }
      else if (ctl && e.key === "Enter") { e.preventDefault(); next(); }
      return;
    }
    if (inText) {
      if (e.key === "Escape") { e.preventDefault(); document.activeElement.blur(); }
      else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); next(); }
      else if (e.key === "Enter" && !e.shiftKey && q.mode !== "text" && !(q.spec.text && q.spec.text.multiline)) { e.preventDefault(); next(); }
      return;
    }
    if (e.metaKey || e.ctrlKey) return;
    if (e.key === "?") { showHelp = !showHelp; refresh(); return; }
    if (reviewing) {
      const k = KEYS.indexOf(e.key);
      if (k >= 0 && k < qs.length) { e.preventDefault(); go(k); }
      else if (e.key === "Enter") { e.preventDefault(); finish(); }
      else if (e.key === "Escape" || e.key === "Backspace" || e.key === "[") { e.preventDefault(); leaveReview(); }
      return;
    }
    const n = q.options.length, cols = (q.optEls[0] && q.optEls[0].parentElement.classList.contains("list")) ? 1 : +getComputedStyle(q.optEls[0] ? q.optEls[0].parentElement : document.body).getPropertyValue("--cols") || 1;
    if (q.mode === "tune" && (e.key === "ArrowDown" || e.key === "j")) { e.preventDefault(); const f = q.el.querySelector(".hd-ctl input, .hd-ctl button:not(.hd-ctl-r)"); if (f) f.focus(); return; }
    const k = KEYS.indexOf(e.key);
    if (k >= 0 && k < n && !e.altKey) { e.preventDefault(); q.hl = k; kbdNav = true; choose(q, k); return; }
    switch (e.key) {
      case "Enter": e.preventDefault(); if (kbdNav && q.mode === "single" && n && !q.sel.size) choose(q, q.hl); next(); return;
      case "Tab": if (q.ta) { e.preventDefault(); q.ta.focus(); } return;
      case "/": if (q.ta) { e.preventDefault(); q.ta.focus(); } return;
      case " ": if (n) { e.preventDefault(); kbdNav = true; choose(q, q.hl); } return;
      case "ArrowDown": case "j": if (n) { e.preventDefault(); kbdNav = true; q.hl = Math.min(n - 1, q.hl + (cols || 1)); refresh(); scrollHl(q); } return;
      case "ArrowUp": case "k": if (n) { e.preventDefault(); kbdNav = true; q.hl = Math.max(0, q.hl - (cols || 1)); refresh(); scrollHl(q); } return;
      case "ArrowRight": case "l": if (n && cols > 1) { e.preventDefault(); kbdNav = true; q.hl = Math.min(n - 1, q.hl + 1); refresh(); scrollHl(q); } return;
      case "ArrowLeft": case "h": if (n && cols > 1) { e.preventDefault(); kbdNav = true; q.hl = Math.max(0, q.hl - 1); refresh(); scrollHl(q); } return;
      case "e": if (n) { kbdNav = true; q.optEls[q.hl].classList.toggle("open"); refresh(); } return;
      case "E": app.classList.toggle("expand-all"); return;
      case "r": if (q.mode === "tune") q.draw(); return;
      case "]": go(cur + 1); return;
      case "[": go(cur - 1); return;
    }
  });
  function scrollHl(q) { const b = q.optEls[q.hl]; if (b && b.scrollIntoView) b.scrollIntoView({ block: "nearest", behavior: "smooth" }); }

  // ---------- tune: controls with a live preview ----------
  function showVal(c, v) {
    if (c.type === "toggle") return v ? "on" : "off";
    if (c.type === "hue") return v + "°";
    return v + (c.unit || "");
  }
  // {id} in a preview is the raw value (12, "#0d9488", "Georgia"); var(--id) carries the unit (12px).
  function rawVal(c, v) { return c.type === "toggle" ? (v ? (c.on != null ? c.on : "1") : (c.off != null ? c.off : "0")) : String(v); }
  function cssVal(c, v) { return c.type === "range" && c.unit ? v + c.unit : rawVal(c, v); }
  function fill(node, q) {
    if (typeof node === "string") return node
      .replace(/\{@([\w-]+)(?:\.([\w-]+))?\}/g, (m, qid, part) => linked(qid, part, m))
      .replace(/\{([\w-]+)\}/g, (m, id) => { const c = q.controls.find((x) => x.id === id); return c ? rawVal(c, q.values[id]) : m; });
    if (Array.isArray(node)) return node.map((x) => fill(x, q));
    if (node && typeof node === "object") { const o = {}; for (const k in node) o[k] = fill(node[k], q); return o; }
    return node;
  }
  // {@qid} = the option id(s) chosen on another question, {@qid.label} their labels, {@qid.ctl} its slider value.
  function linked(qid, part, fallback) {
    const o = qs.find((x) => x.id === qid);
    if (!o) return fallback;
    if (part && part !== "label") return o.values[part] != null ? String(o.values[part]) : "";
    return [...o.sel].sort((a, b) => a - b).map((i) => (part ? o.options[i].label : o.options[i].id)).join(",");
  }
  function focusCtl(ctl, d) {
    const all = [...ctl.parentElement.querySelectorAll(".hd-ctl")], i = all.indexOf(ctl) + d;
    if (i >= 0 && i < all.length) all[i].querySelector("input, .hd-seg button").focus();
    else if (i < 0) document.activeElement.blur();
  }
  function buildTune(q) {
    const s = q.spec, wrap = $("div", "hd-tune"), stage = $("div", "hd-stage"), panel = $("div", "hd-controls");
    q.controls.forEach((c) => {
      if (c.value == null) c.value = c.type === "toggle" ? false : c.type === "color" ? "#3d7cf5" : c.type === "select" ? (c.options || [""])[0] : c.type === "hue" ? 210 : c.min || 0;
      q.values[c.id] = c.value;
    });
    const panes = [];
    const mkPane = (label, live) => {
      const p = $("div", "hd-pane" + (live ? " live" : ""));
      if (label) p.appendChild($("div", "hd-pane-l", esc(label)));
      const body = $("div", "hd-pane-b"); p.appendChild(body); stage.appendChild(p); panes.push({ body, live }); return body;
    };
    if (s.baseline) { mkPane(s.baseline === true ? "Now" : s.baseline, false); mkPane("Yours", true); }
    else mkPane("", true);
    const replay = $("button", "hd-replay", "⟳ replay"); replay.type = "button"; replay.title = "Replay the preview (r)";
    replay.onclick = () => q.draw(); stage.appendChild(replay);
    const initial = q.initial = Object.assign({}, q.values);
    const dflt = q.options.find((o) => o.default || o.selected);
    if (dflt) { q.from = dflt.id; Object.assign(q.values, dflt.values || {}); }
    q.draw = () => {
      panes.forEach((p) => {
        const vals = p.live ? q.values : initial, saved = q.values; q.values = vals;
        p.body.innerHTML = ""; p.body.appendChild(block(fill(s.preview, q)));
        q.controls.forEach((c) => p.body.style.setProperty("--" + c.id, cssVal(c, vals[c.id])));
        q.values = saved; if (p.live) q.live = p.body;
      });
      if (ready) flush();
    };
    const outs = {};
    q.controls.forEach((c) => {
      const row = $("div", "hd-ctl " + c.type), head = $("div", "hd-ctl-h");
      head.appendChild($("span", "hd-ctl-l", esc(c.label || c.id)));
      const out = $("span", "hd-ctl-v"); head.appendChild(out); outs[c.id] = out;
      const reset = $("button", "hd-ctl-r", "↺"); reset.type = "button"; reset.title = "Back to " + showVal(c, initial[c.id]);
      reset.onclick = () => set(c, initial[c.id]); head.appendChild(reset);
      row.appendChild(head);
      let input;
      if (c.type === "select") {
        input = $("div", "hd-seg");
        (c.options || []).forEach((v) => { const b = $("button", "", esc(v)); b.type = "button"; b.dataset.v = v; b.onclick = () => set(c, v); input.appendChild(b); });
      } else {
        input = $("input"); input.type = c.type === "toggle" ? "checkbox" : c.type === "color" ? "color" : "range";
        if (c.type === "range") { input.min = c.min != null ? c.min : 0; input.max = c.max != null ? c.max : 100; input.step = c.step || 1; }
        if (c.type === "hue") { input.min = 0; input.max = 360; input.step = 1; }
        input.addEventListener("input", () => set(c, input.type === "checkbox" ? input.checked : input.type === "range" ? +input.value : input.value));
      }
      row.appendChild(input); c.el = input; panel.appendChild(row);
    });
    function set(c, v) {
      q.values[c.id] = v;
      if (q.from) q.sel = presetKept(q) ? new Set([q.options.indexOf(preset(q))]) : new Set();
      q.syncControls(); q.draw(); refresh();
    }
    q.syncControls = () => q.controls.forEach((c) => {
      const v = q.values[c.id], el = c.el;
      if (c.type === "select") [...el.children].forEach((b) => b.classList.toggle("on", b.dataset.v === String(v)));
      else if (el.type === "checkbox") el.checked = !!v; else if (el.value !== String(v)) el.value = v;
      outs[c.id].textContent = showVal(c, v);
    });
    wrap.appendChild(stage); wrap.appendChild(panel);
    q.syncControls(); q.draw();
    return wrap;
  }

  // ---------- custom JS hooks ----------
  const api = {
    spec: SPEC, extra: {}, md, chart, block,
    question: (id) => qs.find((q) => q.id === id),
    setText(id, text) { const q = api.question(id) || qs[cur]; if (q.ta) { q.ta.value = text; autosize(q.ta); refresh(); } },
    setExtra(id, value) { api.extra[id] = value; refresh(); },
    select(id, optId) { const q = api.question(id) || qs[cur], i = q.options.findIndex((o) => o.id === optId); if (i >= 0) { if (q.mode === "multi") q.sel.add(i); else q.sel = new Set([i]); refresh(); } },
    submit: () => next(),
    send: (v) => deliver(v),
    css,
  };
  window.huddle = api;

  refresh();
  if (qs[0].mode === "text" && qs[0].ta) qs[0].ta.focus();
  qs.forEach((q) => q.ta && autosize(q.ta));
  ready = true; flush();
  if (SPEC.script) { try { new Function("api", SPEC.script)(api); } catch (e) { app.appendChild($("pre", "hd-err", "script: " + esc(e.message || e))); } }
  if (!window.agterm && location.protocol.startsWith("http"))
    window.addEventListener("pagehide", () => { if (!finished) navigator.sendBeacon("/answer", JSON.stringify({ status: "dismissed" })); });
  window.focus();
})();
