/**
 * When Sensei sends an explicit product blueprint or a structured "Create a … meditation"
 * prompt with theme tags and no chat history, intent classification must not downgrade
 * the request to conversation/text — otherwise the client shows a timely greeting with
 * no meditation card.
 */

import { parseClientBlueprintId } from "./meditationBlueprints";

export function shouldForceMeditationIntent(args: {
  blueprintId?: string | null;
  meditationThemes?: string[] | null;
  prompt: string;
  historyLen: number;
}): boolean {
  if (parseClientBlueprintId(args.blueprintId ?? null)) {
    return true;
  }
  const themes = args.meditationThemes;
  if (!Array.isArray(themes) || themes.length === 0) return false;
  if (args.historyLen !== 0) return false;
  const p = args.prompt.trim().toLowerCase();
  if (!p.startsWith("create a ")) return false;
  if (!p.includes("meditation")) return false;
  return true;
}
