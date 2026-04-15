import "./site.css";
import "./document-page.css";

const wideBpRem = 64.0625;
const mql = window.matchMedia(`(min-width: ${wideBpRem}rem)`);

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

const supportForm = document.querySelector<HTMLFormElement>("#support-form");
supportForm?.addEventListener("submit", (e) => {
  e.preventDefault();
  const fd = new FormData(supportForm);
  const name = String(fd.get("name") ?? "").trim();
  const email = String(fd.get("email") ?? "").trim();
  const message = String(fd.get("message") ?? "").trim();

  if (!email) {
    const input = supportForm.querySelector<HTMLInputElement>("#support-email");
    input?.focus();
    return;
  }

  const lines = [
    name ? `Name: ${name}` : null,
    `Email: ${email}`,
    "",
    message || "(No message provided)",
  ].filter((line) => line !== null) as string[];

  const subject = encodeURIComponent("Dojo support request");
  const bodyText = encodeURIComponent(lines.join("\n"));
  window.location.href = `mailto:asaf@medidojo.com?subject=${subject}&body=${bodyText}`;
});
