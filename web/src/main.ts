import "./site.css";
import "./layout-header-over-hero.css";

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

menuPanel?.querySelectorAll("a").forEach((a) => {
  a.addEventListener("click", () => setNavOpen(false));
});

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
