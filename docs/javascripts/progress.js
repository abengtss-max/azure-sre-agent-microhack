// Client-side MicroHack progress tracking (localStorage). No backend required.
(function () {
  "use strict";

  var TOTAL = 8;
  var KEY = "srehack:progress:v1";

  function load() {
    try { return new Set(JSON.parse(localStorage.getItem(KEY) || "[]")); }
    catch (e) { return new Set(); }
  }
  function save(set) {
    try {
      localStorage.setItem(KEY, JSON.stringify(Array.from(set).sort(function (a, b) { return a - b; })));
    } catch (e) { /* storage disabled — session-only */ }
  }
  function pct(set) { return Math.round((set.size / TOTAL) * 100); }

  function seenIntro() { try { return localStorage.getItem("srehack:seen-intro") === "1"; } catch (e) { return false; } }

  function currentChallenge() {
    var m = location.pathname.match(/challenges\/(\d{2})-/);
    return m ? parseInt(m[1], 10) : null;
  }
  function isHome() {
    var p = location.pathname;
    if (/challenges\/|getting-started\/|reference\//.test(p)) return false;
    return /\/(index\.html)?$/.test(p);
  }

  function makeSteps(set, current, label) {
    var wrap = document.createElement("div");
    wrap.className = "aet-steps-wrap";
    wrap.setAttribute("role", "progressbar");
    wrap.setAttribute("aria-valuemin", "0");
    wrap.setAttribute("aria-valuemax", String(TOTAL));
    wrap.setAttribute("aria-valuenow", String(set.size));
    if (current) wrap.dataset.current = String(current);
    wrap.dataset.label = label || "Your progress";
    var seg = "";
    for (var i = 1; i <= TOTAL; i++) {
      var cls = "aet-step";
      if (set.has(i)) cls += " is-done";
      if (current && i === current) cls += " is-current";
      seg += '<span class="' + cls + '" title="Challenge ' + i + '">' + (set.has(i) ? "\u2713" : i) + "</span>";
    }
    var allDone = set.size >= TOTAL;
    if (allDone) wrap.classList.add("is-complete");
    wrap.innerHTML =
      '<div class="aet-steps-head">' +
        '<span class="aet-steps-label">' + (label || "Your progress") + "</span>" +
        '<span class="aet-steps-count">' + set.size + " of " + TOTAL + " complete \u00b7 " + pct(set) + "%</span>" +
      "</div>" +
      '<div class="aet-steps">' + seg + "</div>" +
      (allDone ? '<div class="aet-steps-done">\ud83c\udf89 All challenges complete \u2014 nicely flown!</div>' : "");
    return wrap;
  }

  function addFooter(wrap) {
    var foot = document.createElement("div");
    foot.className = "aet-steps-foot";
    var hint = document.createElement("span");
    hint.className = "aet-steps-hint";
    hint.textContent = "Progress is saved in this browser";
    var reset = document.createElement("button");
    reset.type = "button";
    reset.className = "aet-progress-reset";
    reset.textContent = "Reset progress";
    reset.addEventListener("click", function () { save(new Set()); location.reload(); });
    foot.appendChild(hint);
    foot.appendChild(reset);
    wrap.appendChild(foot);
    return wrap;
  }

  function missingBefore(n, set) {
    var missing = [];
    for (var i = 1; i < n; i++) if (!set.has(i)) missing.push(i);
    return missing;
  }
  function status(n, set) {
    if (set.has(n)) return "done";
    if (missingBefore(n, set).length === 0) return "open";
    return "locked";
  }
  function applyStatus(a, st) {
    a.classList.toggle("aet-nav-done", st === "done");
    a.classList.toggle("aet-nav-locked", st === "locked");
    if (st === "locked") a.setAttribute("title", "Locked \u2014 finish the previous challenge first");
    else if ((a.getAttribute("title") || "").indexOf("Locked") === 0) a.removeAttribute("title");
  }
  function markNav(set) {
    document.querySelectorAll(".md-nav__link").forEach(function (a) {
      var href = a.getAttribute("href") || "";
      var m = href.match(/(\d{2})-[a-z]/);
      if (!m) return;
      applyStatus(a, status(parseInt(m[1], 10), set));
    });
    // The current page's own sidebar link uses href "./" (no number) — mark via active state.
    var cur = currentChallenge();
    if (cur) {
      document.querySelectorAll(".md-nav--primary .md-nav__link--active").forEach(function (a) {
        applyStatus(a, status(cur, set));
      });
    }
  }

  function rerender() {
    var set = load();
    markNav(set);
    document.querySelectorAll(".aet-steps-wrap").forEach(function (w) {
      var cur = w.dataset.current ? parseInt(w.dataset.current, 10) : null;
      var lbl = w.dataset.label || "Your progress";
      w.replaceWith(addFooter(makeSteps(set, cur, lbl)));
    });
  }

  function celebrate() {
    if (document.querySelector(".aet-celebrate")) return;
    var o = document.createElement("div");
    o.className = "aet-celebrate";
    o.innerHTML =
      '<div class="aet-confetti" aria-hidden="true"></div>' +
      '<div class="aet-celebrate-card" role="dialog" aria-label="MicroHack complete">' +
        '<div class="aet-celebrate-emoji">\ud83c\udf89</div>' +
        '<div class="aet-celebrate-title">All 8 challenges complete!</div>' +
        '<div class="aet-celebrate-sub">You built an AI SRE teammate from scratch \u2014 nicely flown.</div>' +
        '<button type="button" class="aet-celebrate-close">Close</button>' +
      "</div>";
    var conf = o.querySelector(".aet-confetti");
    var colors = ["#0078d4", "#54b054", "#f7a845", "#e4626f", "#a084e8"];
    for (var i = 0; i < 44; i++) {
      var p = document.createElement("span");
      p.style.left = (Math.random() * 100) + "%";
      p.style.background = colors[i % colors.length];
      p.style.animationDelay = (Math.random() * 0.7).toFixed(2) + "s";
      p.style.transform = "rotate(" + Math.floor(Math.random() * 360) + "deg)";
      conf.appendChild(p);
    }
    var closeBtn = o.querySelector(".aet-celebrate-close");
    function onKey(e) {
      if (e.key === "Escape") close();
      else if (e.key === "Tab") { e.preventDefault(); closeBtn.focus(); }
    }
    function close() { document.removeEventListener("keydown", onKey); o.remove(); }
    o.addEventListener("click", function (e) {
      if (e.target === o || e.target.classList.contains("aet-celebrate-close")) close();
    });
    document.addEventListener("keydown", onKey);
    document.body.appendChild(o);
    closeBtn.focus();
    setTimeout(close, 7000);
  }

  function boot() {
    var set = load();
    var challenge = currentChallenge();
    markNav(set);

    if (challenge) {
      var header = document.querySelector(".md-content .admonition.abstract");
      if (header && !document.querySelector(".aet-steps-wrap")) {
        header.parentNode.insertBefore(addFooter(makeSteps(set, challenge)), header.nextSibling);
      }

      if (status(challenge, set) === "locked" && !document.querySelector(".aet-locked-note")) {
        var missing = missingBefore(challenge, set);
        var linkFor = function (n) {
          var pad = n < 10 ? "0" + n : String(n);
          var l = document.querySelector('.md-nav--primary a[href*="' + pad + '-"]');
          var h = l ? l.getAttribute("href") : null;
          return h ? '<a href="' + h + '">Challenge ' + n + "</a>" : "Challenge " + n;
        };
        var parts = missing.map(linkFor);
        var list = parts.length === 1
          ? parts[0]
          : parts.slice(0, -1).join(", ") + " and " + parts[parts.length - 1];
        var note = document.createElement("div");
        note.className = "aet-locked-note";
        note.innerHTML =
          '<span class="aet-lock-ico" aria-hidden="true"></span>' +
          "<span>This challenge is <strong>locked</strong>. Complete " + list +
          " first for the intended flow \u2014 or read ahead if you\u2019re just exploring.</span>";
        var h1 = document.querySelector(".md-content h1");
        if (h1) h1.parentNode.insertBefore(note, h1.nextSibling);
      }

      if (!seenIntro() && !document.querySelector(".aet-coach")) {
        var sb = document.querySelector(".aet-steps-wrap");
        if (sb) {
          var coach = document.createElement("div");
          coach.className = "aet-coach";
          coach.innerHTML =
            "<div><strong>New here?</strong> Mark each challenge complete with the button near the bottom \u2014 " +
            "the progress bar fills and the next challenge unlocks. Your progress saves in this browser. " +
            '<button type="button" class="aet-coach-close">Got it</button></div>';
          sb.parentNode.insertBefore(coach, sb.nextSibling);
          coach.querySelector(".aet-coach-close").addEventListener("click", function () {
            try { localStorage.setItem("srehack:seen-intro", "1"); } catch (e) {}
            coach.remove();
          });
        }
      }

      var successes = document.querySelectorAll(".md-content .admonition.success");
      var completion = successes.length ? successes[successes.length - 1] : null;
      if (completion && !completion.querySelector(".aet-complete")) {
        var box = document.createElement("div");
        box.className = "aet-complete";
        var btn = document.createElement("button");
        btn.type = "button";
        btn.className = "aet-complete-btn";

        var render = function () {
          var done = load().has(challenge);
          btn.classList.toggle("is-done", done);
          btn.setAttribute("aria-pressed", String(done));
          btn.innerHTML = done
            ? '<span class="aet-check">\u2713</span> Challenge ' + challenge + " complete \u2014 click to undo"
            : '<span class="aet-check">\u2713</span> Mark Challenge ' + challenge + " complete";
        };
        btn.addEventListener("click", function () {
          var s = load();
          if (s.has(challenge)) s.delete(challenge); else s.add(challenge);
          save(s);
          render();
          rerender();
          if (s.size === TOTAL && s.has(challenge)) celebrate();
        });
        render();
        box.appendChild(btn);
        var title = completion.querySelector(".admonition-title");
        if (title && title.nextSibling) completion.insertBefore(box, title.nextSibling);
        else completion.appendChild(box);
      }
    }

    if (isHome()) {
      var acts = document.querySelector(".md-content .grid.cards");
      if (acts && !document.querySelector(".aet-steps-wrap")) {
        // Place the progress bar above the "The five acts" heading (if present),
        // so the order reads: journey -> progress -> heading -> act cards.
        var anchor = acts;
        var prev = acts.previousElementSibling;
        if (prev && prev.tagName === "H2") anchor = prev;
        anchor.parentNode.insertBefore(addFooter(makeSteps(set, null, "Your MicroHack progress")), anchor);
      }
      document.querySelectorAll('.md-content .grid.cards a[href*="challenges/"]').forEach(function (a) {
        var m = a.getAttribute("href").match(/(\d{2})-/);
        if (m && set.has(parseInt(m[1], 10)) && !a.querySelector(".aet-check-inline")) {
          var c = document.createElement("span");
          c.className = "aet-check-inline";
          c.textContent = "\u2713";
          a.appendChild(c);
        }
      });
    }

    if (location.pathname.indexOf("/challenges/finish/") !== -1) {
      var h1f = document.querySelector(".md-content h1");
      if (h1f && !document.querySelector(".aet-steps-wrap")) {
        h1f.parentNode.insertBefore(addFooter(makeSteps(set, null, "Your MicroHack progress")), h1f.nextSibling);
      }
      var nextLink = document.querySelector(".md-footer__link--next");
      if (nextLink) nextLink.style.display = "none";
    }
  }

  // Run now (first load) and on every Material instant navigation.
  function ready() {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }
  ready();
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(boot);
  }
})();
