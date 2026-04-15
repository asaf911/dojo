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
