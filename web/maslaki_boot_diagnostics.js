(function () {
  "use strict";

  function urlOf(input) {
    try {
      if (typeof input === "string") return input;
      if (input && typeof input.url === "string") return input.url;
      return String(input || "");
    } catch (_) {
      return "";
    }
  }

  function report(kind, url, status, contentType) {
    var type = String(contentType || "").toLowerCase();
    var looksLikeJson = /\.json(?:$|[?#])|\/api\//i.test(String(url || ""));
    var wrongJsonType = looksLikeJson && type.indexOf("text/html") !== -1;
    if (Number(status || 0) >= 400 || wrongJsonType) {
      console.error("[maslaki-network]", kind, status, contentType || "", url);
    }
  }

  if (typeof window.fetch === "function") {
    var originalFetch = window.fetch.bind(window);
    window.fetch = async function (input, init) {
      var response = await originalFetch(input, init);
      report(
        "fetch",
        urlOf(input),
        response.status,
        response.headers.get("content-type"),
      );
      return response;
    };
  }

  if (typeof window.XMLHttpRequest === "function") {
    var originalOpen = window.XMLHttpRequest.prototype.open;
    window.XMLHttpRequest.prototype.open = function (method, url) {
      this.__maslakiRequestUrl = urlOf(url);
      this.addEventListener("loadend", function () {
        report(
          "xhr",
          this.__maslakiRequestUrl,
          this.status,
          this.getResponseHeader("content-type"),
        );
      });
      return originalOpen.apply(this, arguments);
    };
  }
})();
