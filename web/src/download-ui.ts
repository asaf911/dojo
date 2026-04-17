/**
 * Download UI: QR + card only on **wide viewports** with fine pointer + hover.
 * - iOS Safari often reports `(pointer: fine) and (hover: hover)` on phones; the
 *   min-width guard prevents the QR card from appearing on mobile.
 * - App Store CTA when narrow and/or not fine-hover desktop.
 */
export const DOWNLOAD_UI_WIDE_MEDIA = "(min-width: 64.0625rem)" as const;
export const DOWNLOAD_UI_POINTER_MEDIA = "(pointer: fine) and (hover: hover)" as const;

export function prefersQrDownloadUi(w: Window = window): boolean {
  if (typeof w.matchMedia !== "function") return false;
  return (
    w.matchMedia(DOWNLOAD_UI_WIDE_MEDIA).matches && w.matchMedia(DOWNLOAD_UI_POINTER_MEDIA).matches
  );
}

export function applyDownloadUiRootClass(w: Window = window): void {
  w.document.documentElement.classList.toggle("download-ui--qr", prefersQrDownloadUi(w));
}

export function subscribeDownloadUiChange(w: Window, onChange: () => void): void {
  const wide = w.matchMedia(DOWNLOAD_UI_WIDE_MEDIA);
  const ptr = w.matchMedia(DOWNLOAD_UI_POINTER_MEDIA);
  const bind = (mq: MediaQueryList) => {
    if (typeof mq.addEventListener === "function") mq.addEventListener("change", onChange);
    else mq.addListener(onChange);
  };
  bind(wide);
  bind(ptr);
}
