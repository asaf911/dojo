import { defineConfig, loadEnv } from "vite";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));

/** GA4 Measurement IDs are public; still validate shape before injecting into HTML. */
const GA_MEASUREMENT_ID_PATTERN = /^G-[A-Z0-9]+$/i;

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

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const gaHeadSnippet = ga4HeadSnippet(env.VITE_GA_MEASUREMENT_ID ?? "");

  return {
    root: ".",
    publicDir: "public",
    plugins: [
      {
        name: "inject-ga4",
        transformIndexHtml(html) {
          if (!gaHeadSnippet) return html;
          /* Avoid leaving indent from `  </head>` on the first injected line; normalize closing tag indent. */
          return html.replace(/\r?\n\s*<\/head>/i, `\n${gaHeadSnippet}  </head>`);
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
