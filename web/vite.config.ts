import { defineConfig, loadEnv } from "vite";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));

/** GA4 Measurement IDs are public; still validate shape before injecting into HTML. */
const GA_MEASUREMENT_ID_PATTERN = /^G-[A-Z0-9]+$/i;

/** AppsFlyer Smart Banner Web key — conservative charset for safe inline script embedding. */
const APPSFLYER_BANNER_WEB_KEY_PATTERN = /^[\w.-]{4,512}$/;

function ga4HeadSnippet(measurementId: string): string {
  const id = measurementId.trim();
  if (!GA_MEASUREMENT_ID_PATTERN.test(id)) return "";
  return (
    `    <!-- Google tag (gtag.js) -->\n` +
    `    <script async src="https://www.googletagmanager.com/gtag/js?id=${id}"></script>\n` +
    `    <script>\n` +
    `      window.dataLayer = window.dataLayer || [];\n` +
    `      function gtag() {\n` +
    `        dataLayer.push(arguments);\n` +
    `      }\n` +
    `      gtag("js", new Date());\n` +
    `      gtag("config", "${id}");\n` +
    `    </script>\n`
  );
}

/**
 * OneLink Smart Banner V2 — Standard “Smart Banners only” (AppsFlyer Help Center).
 * @see https://dev.appsflyer.com/hc/docs/dl_smart_banner_v2
 */
function appsFlyerSmartBannerEarlyHeadSnippet(webKey: string): string {
  const k = webKey.trim();
  if (!k || !APPSFLYER_BANNER_WEB_KEY_PATTERN.test(k)) return "";
  const keyLiteral = JSON.stringify(k);
  return (
    `    <!-- AppsFlyer OneLink Smart Banner V2 -->\n` +
    `    <script>\n` +
    `      !(function (t, e, n, s, a, c, i, o, p) {\n` +
    `        t.AppsFlyerSdkObject = a;\n` +
    `        t.AF =\n` +
    `          t.AF ||\n` +
    `          function () {\n` +
    `            (t.AF.q = t.AF.q || []).push([Date.now()].concat(Array.prototype.slice.call(arguments)));\n` +
    `          };\n` +
    `        t.AF.id = t.AF.id || i;\n` +
    `        t.AF.plugins = {};\n` +
    `        o = e.createElement(n);\n` +
    `        p = e.getElementsByTagName(n)[0];\n` +
    `        o.async = 1;\n` +
    `        o.src =\n` +
    `          "https://websdk.appsflyersdk.com?" +\n` +
    `          (c.length > 0 ? "st=" + c.split(",").sort().join(",") + "&" : "") +\n` +
    `          (i.length > 0 ? "af_id=" + i : "");\n` +
    `        p.parentNode.insertBefore(o, p);\n` +
    `      })(window, document, "script", 0, "AF", "banners", { banners: { key: ` +
    keyLiteral +
    ` } });\n` +
    `      AF("banners", "showBanner");\n` +
    `    </script>\n`
  );
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const gaHeadSnippet = ga4HeadSnippet(env.VITE_GA_MEASUREMENT_ID ?? "");
  const appsFlyerBannerSnippet = appsFlyerSmartBannerEarlyHeadSnippet(
    env.VITE_APPSFLYER_BANNER_WEB_KEY ?? "",
  );

  return {
    root: ".",
    publicDir: "public",
    server: {
      proxy: {
        "/api/support": {
          target: "https://imaginedev-e5fd3.web.app",
          changeOrigin: true,
          secure: true,
        },
      },
    },
    plugins: [
      {
        name: "inject-head-marketing",
        transformIndexHtml(html) {
          let out = html;
          if (appsFlyerBannerSnippet) {
            out = out.replace(/<head>/i, `<head>\n${appsFlyerBannerSnippet}`);
          }
          if (gaHeadSnippet) {
            out = out.replace(/\r?\n\s*<\/head>/i, `\n${gaHeadSnippet}  </head>`);
          }
          return out;
        },
      },
    ],
    build: {
      rollupOptions: {
        input: {
          main: resolve(root, "index.html"),
          privacyPolicy: resolve(root, "privacy-policy/index.html"),
          support: resolve(root, "support/index.html"),
        },
      },
    },
  };
});
