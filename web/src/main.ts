import "./site.css";
import "./layout-header-over-hero.css"; /* typography + header tweaks; load after layered site bundle */
import { applyDownloadUiRootClass, subscribeDownloadUiChange } from "./download-ui";
import { initAppsFlyerSmartScript, syncAppsFlyerDownloadUi } from "./appsflyer-smart-script";

applyDownloadUiRootClass();
initAppsFlyerSmartScript();

if (typeof window.matchMedia === "function") {
  const onDownloadUiChange = () => {
    applyDownloadUiRootClass();
    syncAppsFlyerDownloadUi(window, document);
  };
  subscribeDownloadUiChange(window, onDownloadUiChange);
}

const wideBpRem = 64.0625;
const mql = window.matchMedia(`(min-width: ${wideBpRem}rem)`);

const header = document.querySelector<HTMLElement>("#site-header");
const hero = document.querySelector<HTMLElement>("#hero");

function updateHeaderSolid() {
  if (!header || !hero) return;
  const { bottom } = hero.getBoundingClientRect();
  header.classList.toggle("site-header--solid", bottom < 56);
}

window.addEventListener("scroll", updateHeaderSolid, { passive: true });
window.addEventListener("resize", updateHeaderSolid);
updateHeaderSolid();

const menuToggle = document.querySelector<HTMLButtonElement>("#menu-toggle");
const menuPanel = document.querySelector<HTMLElement>("#menu-panel");
const body = document.body;

function setNavOpen(open: boolean) {
  menuPanel?.classList.toggle("is-open", open);
  menuToggle?.setAttribute("aria-expanded", open ? "true" : "false");
  body.classList.toggle("is-nav-open", open);
}

menuToggle?.addEventListener("click", () => {
  const open = !menuPanel?.classList.contains("is-open");
  setNavOpen(Boolean(open));
});

const prefersReducedMotion = () =>
  typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** In-page anchors: close mobile overlay first (body overflow) then scroll — native hash nav often fails on iOS when the menu was open. */
function wireHeaderNavigation() {
  const header = document.querySelector("#site-header");
  if (!header) return;

  header.querySelectorAll<HTMLAnchorElement>("nav a[href]").forEach((anchor) => {
    anchor.addEventListener("click", (e) => {
      const href = anchor.getAttribute("href") ?? "";
      const overlayOpen = Boolean(menuPanel?.classList.contains("is-open"));

      if (href.startsWith("#") && href.length > 1) {
        const el = document.getElementById(href.slice(1));
        if (!el) return;
        e.preventDefault();
        if (overlayOpen) setNavOpen(false);
        const scrollToTarget = () => {
          el.scrollIntoView({
            behavior: prefersReducedMotion() ? "auto" : "smooth",
            block: "start",
          });
          history.pushState(null, "", href);
        };
        if (overlayOpen) {
          requestAnimationFrame(() => requestAnimationFrame(scrollToTarget));
        } else {
          scrollToTarget();
        }
        return;
      }

      if (overlayOpen) setNavOpen(false);
    });
  });
}

wireHeaderNavigation();

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") setNavOpen(false);
});

function onBpChange() {
  if (mql.matches) setNavOpen(false);
}

if (typeof mql.addEventListener === "function") {
  mql.addEventListener("change", onBpChange);
} else {
  mql.addListener(onBpChange);
}

if (mql.matches) setNavOpen(false);

/* About image: scroll-driven “enhance” from 343×222 toward 450×291 (rounded Elementor sizes). */
const ABOUT_W0 = 343;
const ABOUT_H0 = 222;
const ABOUT_W1 = 450;
const ABOUT_H1 = 291;

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function updateAboutMediaEnhance() {
  const about = document.querySelector<HTMLElement>("#About");
  const media = about?.querySelector<HTMLElement>(".section__media");
  if (!about || !media) return;

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let t = 1;
  if (!reduce) {
    const rect = about.getBoundingClientRect();
    const vh = window.innerHeight;
    const start = vh * 0.9;
    const end = vh * 0.28;
    t = clamp((start - rect.top) / (start - end), 0, 1);
  }

  const w = Math.round(ABOUT_W0 + t * (ABOUT_W1 - ABOUT_W0));
  const h = Math.round(ABOUT_H0 + t * (ABOUT_H1 - ABOUT_H0));

  media.style.setProperty("--about-media-mw", `${w}px`);
  media.style.setProperty("--about-ar-w", String(w));
  media.style.setProperty("--about-ar-h", String(h));
}

window.addEventListener("scroll", updateAboutMediaEnhance, { passive: true });
window.addEventListener("resize", updateAboutMediaEnhance);
updateAboutMediaEnhance();
