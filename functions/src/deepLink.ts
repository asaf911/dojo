/**
 * Generates a OneLink deep link URL for a meditation configuration.
 * Format matches client: https://medidojo.onelink.me/miw9/share?dur=X&bs=Y&bb=Z&cu=...&c=ai&af_sub1=Title
 */

const ONE_LINK_BASE = "https://medidojo.onelink.me/miw9/share";

export interface DeepLinkCue {
  id: string;
  trigger: string | number;
}

export interface DeepLinkInput {
  duration: number;
  backgroundSoundId: string;
  binauralBeatId: string | null;
  cues: DeepLinkCue[];
  title?: string | null;
}

export function generateDeepLink(config: DeepLinkInput): string {
  const params = new URLSearchParams();
  params.set("dur", String(config.duration));
  params.set("bs", config.backgroundSoundId);
  params.set("bb", config.binauralBeatId ?? "None");

  const cuRaw = config.cues
    .map((c) => {
      const trigger =
        c.trigger === "start"
          ? "S"
          : c.trigger === "end"
            ? "E"
            : String(c.trigger);
      return `${c.id}:${trigger}`;
    })
    .join(",");
  params.set("cu", cuRaw);
  params.set("c", "ai");
  params.set("af_sub1", config.title ?? "AI Meditation");

  return `${ONE_LINK_BASE}?${params.toString()}`;
}
