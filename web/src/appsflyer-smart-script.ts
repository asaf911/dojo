/**
 * AppsFlyer OneLink Smart Script — rewrites CTA hrefs and renders desktop QR codes.
 * @see https://support.appsflyer.com/hc/en-us/articles/360000677217-OneLink-Smart-Script-overview
 */

declare global {
  interface Window {
    AF_SMART_SCRIPT?: {
      generateOneLinkURL: (args: {
        oneLinkURL: string;
        afParameters: Record<
          string,
          { keys: string[]; defaultValue: string }
        >;
      }) => { clickURL?: string } | undefined;
      displayQrCode: (elementId: string, opts: { codeColor: string }) => void;
    };
    __AF_SAFE_INIT_DONE?: boolean;
  }
}

const BUTTON_SELECTOR = ".onelink-btn a, a.onelink-btn";
const QR_COLOR = "#2E2E4C";
const MAX_TRIES = 120;
/** Must match CSS wide breakpoint (see src/css/01-tokens.css). */
const DESKTOP_MQ = "(min-width: 64.0625rem)";

const DEFAULT_ONELINK = "https://medidojo.onelink.me/miw9";

function oneLinkTemplateUrl(): string {
  const raw = import.meta.env.VITE_APPSFLYER_ONELINK_TEMPLATE_URL as string | undefined;
  const trimmed = raw?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : DEFAULT_ONELINK;
}

type QrElement = HTMLElement & { __afQrDone?: boolean };

function isDesktop(w: Window): boolean {
  return Boolean(w.matchMedia?.(DESKTOP_MQ).matches);
}

function loadSmartScript(w: Window, d: Document, onReady: (ok: boolean) => void): void {
  if (w.AF_SMART_SCRIPT && typeof w.AF_SMART_SCRIPT.generateOneLinkURL === "function") {
    onReady(true);
    return;
  }
  const s = d.createElement("script");
  s.async = true;
  s.src = "https://onelinksmartscript.appsflyer.com/onelink-smart-script-latest.js";
  s.onload = () => onReady(true);
  s.onerror = () => onReady(false);
  d.head.appendChild(s);
}

function generateClickURL(w: Window, oneLinkURL: string): string {
  try {
    const result = w.AF_SMART_SCRIPT?.generateOneLinkURL({
      oneLinkURL,
      afParameters: {
        mediaSource: { keys: ["utm_source"], defaultValue: "website" },
        campaign: { keys: ["utm_campaign"], defaultValue: "homepage" },
        channel: { keys: ["utm_medium"], defaultValue: "site" },
      },
    });
    return result?.clickURL ?? "";
  } catch {
    return "";
  }
}

function bindButtons(d: Document, url: string): void {
  if (!url) return;
  d.querySelectorAll<HTMLAnchorElement>(BUTTON_SELECTOR).forEach((a) => {
    a.setAttribute("href", url);
    a.setAttribute("target", "_blank");
    a.setAttribute("rel", "noopener");
  });
}

function renderAllQrs(w: Window, d: Document): boolean {
  if (!isDesktop(w)) return true;
  if (!w.AF_SMART_SCRIPT?.displayQrCode) return false;

  const nodes = d.querySelectorAll<QrElement>(".af-qr");
  if (!nodes.length) return false;

  nodes.forEach((node, i) => {
    if (!node.id) node.id = `af-qr-${i}`;
    if (node.__afQrDone) return;
    node.__afQrDone = true;
    node.innerHTML = "";
    w.AF_SMART_SCRIPT?.displayQrCode(node.id, { codeColor: QR_COLOR });
  });

  return true;
}

function runWithRetries(w: Window, d: Document, oneLinkURL: string): void {
  const url = generateClickURL(w, oneLinkURL);
  bindButtons(d, url);

  let tries = 0;
  const t = w.setInterval(() => {
    tries += 1;
    const ok = renderAllQrs(w, d);
    if (ok || tries >= MAX_TRIES) w.clearInterval(t);
  }, 100);
}

function initAppsFlyerSmartScript(): void {
  const w = window;
  const d = document;
  if (w.__AF_SAFE_INIT_DONE) return;
  w.__AF_SAFE_INIT_DONE = true;

  const oneLinkURL = oneLinkTemplateUrl();

  loadSmartScript(w, d, (loaded) => {
    if (!loaded) return;
    runWithRetries(w, d, oneLinkURL);
  });
}

initAppsFlyerSmartScript();
