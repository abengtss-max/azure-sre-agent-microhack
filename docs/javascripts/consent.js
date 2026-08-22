// Cookie / browser-storage consent for the workshop site (issue #62).
//
// The site has no backend and no third-party analytics. The only storage it uses
// is localStorage for progress tracking, so this gates that rather than cookies.
// Exposes window.aetConsent so progress.js can ask before it writes anything.
(function () {
  "use strict";

  var KEY = "srehack:consent:v1";
  var VERSION = 1;
  // Written by us for progress tracking, and by the Material theme when the
  // reader uses the light/dark toggle. The theme prefixes its key with the site
  // base path (e.g. "/azure-sre-agent-microhack/.__palette"), so it is matched
  // by suffix rather than by exact name.
  var FUNCTIONAL_KEYS = ["srehack:progress:v1", "srehack:seen-intro"];
  var FUNCTIONAL_SUFFIXES = ["__palette"];

  var state = null;      // null = no decision recorded yet
  var listeners = [];

  function read() {
    try {
      var raw = localStorage.getItem(KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      // A version bump invalidates the old choice and re-asks.
      if (!parsed || parsed.v !== VERSION) return null;
      return { functional: !!parsed.functional, ts: parsed.ts };
    } catch (e) { return null; }
  }

  function write(functional) {
    state = { functional: !!functional, ts: new Date().toISOString() };
    try {
      localStorage.setItem(KEY, JSON.stringify({ v: VERSION, functional: state.functional, ts: state.ts }));
    } catch (e) { /* storage blocked entirely - the choice applies for this session */ }
    if (!state.functional) forget();
    listeners.forEach(function (fn) { try { fn(state); } catch (e) {} });
  }

  function forget() {
    FUNCTIONAL_KEYS.forEach(function (k) {
      try { localStorage.removeItem(k); } catch (e) {}
    });
    try {
      Object.keys(localStorage).forEach(function (k) {
        FUNCTIONAL_SUFFIXES.forEach(function (suffix) {
          if (k.slice(-suffix.length) === suffix) localStorage.removeItem(k);
        });
      });
    } catch (e) {}
  }

  function allows(category) {
    if (category === "essential") return true;
    return !!(state && state.functional);
  }

  // ---- UI ------------------------------------------------------------------

  function el(tag, cls, html) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  }

  function close() {
    var existing = document.querySelector(".aet-consent");
    if (!existing) return;
    var restore = existing.getAttribute("data-restore-focus");
    existing.remove();
    if (restore) {
      var target = document.getElementById(restore);
      if (target) target.focus();
    }
  }

  function render(opts) {
    close();
    opts = opts || {};

    var box = el("div", "aet-consent");
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-labelledby", "aet-consent-title");
    box.setAttribute("aria-describedby", "aet-consent-desc");
    if (opts.restoreFocus) box.setAttribute("data-restore-focus", opts.restoreFocus);

    var detailsOpen = !!opts.manage;

    box.appendChild(el("h2", "aet-consent-title", "Cookies and browser storage"));
    box.querySelector(".aet-consent-title").id = "aet-consent-title";

    box.appendChild(el("p", "aet-consent-desc",
      "This site stores your challenge progress in your own browser. There is no account, " +
      "no server-side profile and no advertising or third-party analytics. " +
      "You can change your choice at any time on the " +
      '<a href="' + rootRelative("reference/privacy/") + '">privacy and storage</a> page.'));
    box.querySelector(".aet-consent-desc").id = "aet-consent-desc";

    var details = el("div", "aet-consent-cats");
    details.hidden = !detailsOpen;
    details.innerHTML =
      '<div class="aet-consent-cat">' +
      '<label><input type="checkbox" checked disabled> <strong>Strictly necessary</strong></label>' +
      "<p>Remembers this choice so you are not asked again. Cannot be turned off, " +
      "because it is the record of your decision.</p>" +
      "<p class=\"aet-consent-keys\"><code>srehack:consent:v1</code></p>" +
      "</div>" +
      '<div class="aet-consent-cat">' +
      '<label><input type="checkbox" id="aet-consent-functional"' + (allows("functional") ? " checked" : "") +
      "> <strong>Functional</strong></label>" +
      "<p>Remembers which challenges you have marked complete, whether you have seen the " +
      "introductory hint, and your light/dark preference. Turn this off and the site still " +
      "works: progress is kept for the current tab only and is lost when you close it.</p>" +
      '<p class="aet-consent-keys"><code>srehack:progress:v1</code>, <code>srehack:seen-intro</code>, <code>__palette</code></p>' +
      "</div>";
    box.appendChild(details);

    var actions = el("div", "aet-consent-actions");

    var accept = el("button", "aet-consent-btn aet-consent-accept", "Accept all");
    accept.type = "button";
    accept.addEventListener("click", function () { write(true); close(); });

    var reject = el("button", "aet-consent-btn", "Reject non-essential");
    reject.type = "button";
    reject.addEventListener("click", function () { write(false); close(); });

    var manage = el("button", "aet-consent-btn aet-consent-link", detailsOpen ? "Save preferences" : "Manage preferences");
    manage.type = "button";
    manage.addEventListener("click", function () {
      if (!detailsOpen) { render({ manage: true, restoreFocus: opts.restoreFocus }); return; }
      var cb = document.getElementById("aet-consent-functional");
      write(!!(cb && cb.checked));
      close();
    });

    actions.appendChild(accept);
    actions.appendChild(reject);
    actions.appendChild(manage);
    box.appendChild(actions);

    document.body.appendChild(box);
    (detailsOpen ? manage : accept).focus();

    box.addEventListener("keydown", function (ev) {
      if (ev.key !== "Tab") return;
      var focusable = box.querySelectorAll("button, input, a[href]");
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (ev.shiftKey && document.activeElement === first) { last.focus(); ev.preventDefault(); }
      else if (!ev.shiftKey && document.activeElement === last) { first.focus(); ev.preventDefault(); }
    });
  }

  // The site is served from a project subpath on GitHub Pages, so the link has to
  // be resolved against the deployment root. The theme's logo always points at it.
  function rootRelative(path) {
    var logo = document.querySelector(".md-header .md-logo, .md-nav__title .md-logo");
    if (logo) {
      var href = logo.getAttribute("href");
      if (href) {
        try { return new URL(href, location.href).pathname.replace(/\/?$/, "/") + path; }
        catch (e) { /* fall through */ }
      }
    }
    var marker = "/challenges/";
    var here = location.pathname;
    var idx = here.indexOf(marker);
    if (idx !== -1) return here.slice(0, idx + 1) + path;
    return here.replace(/[^/]*$/, "") + path;
  }

  function boot() {
    state = read();
    if (state === null && !document.querySelector(".aet-consent")) render({});
    wireManageButtons();
  }

  // Any page can offer a "change your choice" control.
  function wireManageButtons() {
    var buttons = document.querySelectorAll("[data-aet-consent-open]");
    Array.prototype.forEach.call(buttons, function (btn) {
      if (btn.getAttribute("data-aet-wired") === "1") return;
      btn.setAttribute("data-aet-wired", "1");
      if (!btn.id) btn.id = "aet-consent-opener";
      btn.addEventListener("click", function () {
        render({ manage: true, restoreFocus: btn.id });
      });
    });
  }

  window.aetConsent = {
    allows: allows,
    open: function () { render({ manage: true }); },
    onChange: function (fn) { if (typeof fn === "function") listeners.push(fn); },
    decided: function () { return state !== null; }
  };

  state = read();

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
  if (window.document$ && typeof window.document$.subscribe === "function") {
    window.document$.subscribe(boot);
  }
})();
