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
const supportFormStatus = document.querySelector<HTMLParagraphElement>("#support-form-status");

function setSupportFormStatus(message: string, kind: "error" | "success" | "info") {
  if (!supportFormStatus) return;
  supportFormStatus.hidden = false;
  supportFormStatus.textContent = message;
  supportFormStatus.classList.remove(
    "support-form__status--error",
    "support-form__status--success",
    "support-form__status--info",
  );
  supportFormStatus.classList.add(`support-form__status--${kind}`);
}

supportForm?.addEventListener("submit", (e) => {
  e.preventDefault();
  void (async () => {
    const fd = new FormData(supportForm);
    const name = String(fd.get("name") ?? "").trim();
    const email = String(fd.get("email") ?? "").trim();
    const message = String(fd.get("message") ?? "").trim();

    if (!email) {
      const input = supportForm.querySelector<HTMLInputElement>("#support-email");
      input?.focus();
      setSupportFormStatus("Please enter your email address.", "error");
      return;
    }

    const submitBtn = supportForm.querySelector<HTMLButtonElement>('button[type="submit"]');
    submitBtn?.setAttribute("disabled", "disabled");
    setSupportFormStatus("Sending…", "info");

    try {
      const res = await fetch("/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email, message }),
      });
      const data = (await res.json().catch(() => ({}))) as { error?: string; ok?: boolean };

      if (!res.ok) {
        setSupportFormStatus(data.error ?? "Something went wrong. Please try again.", "error");
        return;
      }

      setSupportFormStatus("Message sent. We will get back to you soon.", "success");
      supportForm.reset();
    } catch {
      setSupportFormStatus("Could not reach the server. Check your connection and try again.", "error");
    } finally {
      submitBtn?.removeAttribute("disabled");
    }
  })();
});
