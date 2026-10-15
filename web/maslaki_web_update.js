(function () {
  "use strict";

  var CURRENT_RELEASE = String(window.__MASLAKI_WEB_RELEASE__ || "").trim();
  var CHECK_INTERVAL_MS = 5 * 60 * 1000;
  var promptId = "maslaki-web-update-prompt";
  var checking = false;

  function normalizeVersion(value) {
    return String(value || "").trim();
  }

  function cacheBust(url) {
    var separator = url.indexOf("?") === -1 ? "?" : "&";
    return url + separator + "t=" + Date.now();
  }

  function removePrompt() {
    var old = document.getElementById(promptId);
    if (old && old.parentNode) old.parentNode.removeChild(old);
  }

  function isMandatoryRelease(release) {
    return release && (release.mandatory === true || release.forceUpdate === true);
  }

  function showUpdatePrompt(release) {
    var mandatory = isMandatoryRelease(release);
    var existing = document.getElementById(promptId);
    if (existing) {
      if (mandatory && existing.getAttribute("data-mandatory") !== "true") {
        removePrompt();
      } else {
        return;
      }
    }

    var shell = document.createElement("div");
    shell.id = promptId;
    shell.setAttribute("data-mandatory", mandatory ? "true" : "false");
    shell.setAttribute("dir", "rtl");
    shell.setAttribute("role", "alertdialog");
    shell.setAttribute("aria-modal", mandatory ? "true" : "false");
    shell.setAttribute("aria-live", "assertive");
    shell.style.cssText = mandatory
      ? [
          "position:fixed",
          "inset:0",
          "z-index:2147483647",
          "display:flex",
          "align-items:center",
          "justify-content:center",
          "padding:calc(20px + env(safe-area-inset-top,0px)) 20px calc(20px + env(safe-area-inset-bottom,0px))",
          "background:rgba(7,28,44,.72)",
          "backdrop-filter:blur(8px)",
          "font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif",
          "box-sizing:border-box",
        ].join(";")
      : [
          "position:fixed",
          "left:12px",
          "right:12px",
          "bottom:calc(16px + env(safe-area-inset-bottom,0px))",
          "z-index:2147483647",
          "display:flex",
          "align-items:center",
          "gap:10px",
          "padding:12px",
          "border:1px solid rgba(191,142,47,.35)",
          "border-radius:18px",
          "background:rgba(255,252,246,.98)",
          "box-shadow:0 18px 45px rgba(11,29,43,.22)",
          "font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif",
          "color:#071C2C",
          "max-width:560px",
          "margin:0 auto",
          "box-sizing:border-box",
        ].join(";");

    var card = mandatory ? document.createElement("div") : shell;
    if (mandatory) {
      card.style.cssText = [
        "width:min(100%,440px)",
        "display:flex",
        "flex-direction:column",
        "align-items:stretch",
        "gap:16px",
        "padding:24px",
        "border:1px solid rgba(191,142,47,.4)",
        "border-radius:24px",
        "background:#FFFCF6",
        "box-shadow:0 24px 70px rgba(0,0,0,.3)",
        "color:#071C2C",
        "box-sizing:border-box",
        "text-align:center",
      ].join(";");
      shell.appendChild(card);
    }

    var text = document.createElement("div");
    text.style.cssText = "flex:1;min-width:0;line-height:1.45";
    text.innerHTML =
      '<div style="font-weight:900;font-size:' +
      (mandatory ? "20px" : "14px") +
      '">' +
      (mandatory ? "تحديث مطلوب" : "تحديث جديد جاهز") +
      "</div>" +
      '<div style="font-size:' +
      (mandatory ? "14px" : "12px") +
      ';color:#53616c;margin-top:6px">' +
      escapeHtml(release.message || "حمّل آخر نسخة من مسلكي الآن.") +
      "</div>";

    var updateButton = document.createElement("button");
    updateButton.type = "button";
    updateButton.textContent = "تحديث الآن";
    updateButton.style.cssText = [
      "border:0",
      "border-radius:14px",
      "padding:10px 14px",
      "background:#2F6B4F",
      "color:white",
      "font-weight:900",
      "font-size:" + (mandatory ? "15px" : "13px"),
      "cursor:pointer",
      "white-space:nowrap",
    ].join(";");
    updateButton.addEventListener("click", function () {
      updateButton.disabled = true;
      updateButton.textContent = "جارٍ التحديث...";
      reloadToLatest();
    });

    card.appendChild(text);
    card.appendChild(updateButton);
    if (!mandatory) {
      var laterButton = document.createElement("button");
      laterButton.type = "button";
      laterButton.textContent = "لاحقاً";
      laterButton.style.cssText = [
        "border:0",
        "background:transparent",
        "color:#53616c",
        "font-weight:800",
        "font-size:13px",
        "cursor:pointer",
        "padding:10px 4px",
        "white-space:nowrap",
      ].join(";");
      laterButton.addEventListener("click", removePrompt);
      card.appendChild(laterButton);
    }
    document.body.appendChild(shell);
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  async function clearFlutterCaches() {
    if ("serviceWorker" in navigator) {
      try {
        var registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(
          registrations.map(function (registration) {
            var activeUrl =
              registration.active && registration.active.scriptURL
                ? registration.active.scriptURL
                : "";
            if (activeUrl.indexOf("flutter_service_worker.js") !== -1) {
              return registration.unregister();
            }
            return Promise.resolve();
          }),
        );
      } catch (_) {}
    }

    if ("caches" in window) {
      try {
        var keys = await caches.keys();
        await Promise.all(
          keys
            .filter(function (key) {
              return (
                key.indexOf("flutter-app-cache") !== -1 ||
                key.indexOf("flutter-temp-cache") !== -1 ||
                key.indexOf("flutter-cache") !== -1
              );
            })
            .map(function (key) {
              return caches.delete(key);
            }),
        );
      } catch (_) {}
    }
  }

  async function reloadToLatest() {
    await clearFlutterCaches();
    var url = new URL(window.location.href);
    url.searchParams.set("maslaki_refresh", Date.now().toString());
    window.location.replace(url.toString());
  }

  async function checkForUpdate() {
    if (checking || !CURRENT_RELEASE) return;
    checking = true;
    try {
      var response = await fetch(cacheBust("/maslaki-release.json"), {
        cache: "no-store",
      });
      if (!response.ok) return;
      var release = await response.json();
      var latest = normalizeVersion(release.version);
      if (latest && latest !== CURRENT_RELEASE) {
        showUpdatePrompt(release);
      }
    } catch (_) {
      // Offline or blocked network: keep the current app running.
    } finally {
      checking = false;
    }
  }

  window.MaslakiWebUpdate = {
    checkNow: checkForUpdate,
    reloadToLatest: reloadToLatest,
  };

  window.addEventListener("load", function () {
    setTimeout(checkForUpdate, 2500);
    setInterval(checkForUpdate, CHECK_INTERVAL_MS);
    window.addEventListener("focus", checkForUpdate);
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) checkForUpdate();
    });
  });
})();
