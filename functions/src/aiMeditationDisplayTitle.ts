/**
 * Curated display titles for AI-generated custom meditations.
 * Reduces repetitive LLM defaults ("Morning Clarity", "Focus Session", …).
 */

import { createHash, randomInt } from "crypto";
import type { SessionPreferences, UserStructureOverrides } from "./phaseAllocation";
import type { MeditationThemeId, MorningVisualizationVariant } from "./meditationThemes";

export type DisplayTitleBucket =
  | "sleep"
  | "morning_viz_km"
  | "morning_viz_gr"
  | "focus"
  | "anxiety"
  | "relax"
  | "evening"
  | "noon"
  | "night"
  | "gratitude"
  | "morning_general"
  | "default";

const POOLS: Record<DisplayTitleBucket, readonly string[]> = {
  sleep: [
    "Drift Into Stillness",
    "Soft Landing for Sleep",
    "Quiet Before Rest",
    "Evening Unwind",
    "Slow Waves to Sleep",
    "Bedtime Breath",
    "Gentle Descent",
    "Lights-Down Calm",
    "Heavy Blanket Calm",
    "Last Thoughts, Softly",
    "Room for Sleep",
    "Hush and Settle",
    "Moonlit Pause",
    "Deep Pillow Breath",
    "Slip Under the Covers",
    "Nightfall Ease",
    "Dim the Mind",
    "Rest Is Near",
    "Slower Than Today",
    "Close the Day Quietly",
  ],
  morning_viz_km: [
    "First Light, Clear Path",
    "Day Ahead in Quiet Color",
    "Morning Canvas",
    "Sketch the Hours",
    "Sunrise Inner Rehearsal",
    "Quiet Before the Rush",
    "Open the Inner Door",
    "Bright Edges of Today",
    "Walk Through the Morning",
    "Picture the First Step",
    "Warm-Up for the Mind",
    "Soft Launch Into Today",
    "Gather the Thread",
    "Name What Matters",
    "See the Shape of Today",
    "Morning Inner Map",
    "Light on the To-Do",
    "Preview in Peace",
    "Hold the Day Lightly",
    "Gentle Momentum",
    "Rise With Intention",
    "Before the Noise",
    "Still Room for Plans",
    "Paint the Morning Calm",
    "Your Day, Framed Softly",
  ],
  morning_viz_gr: [
    "Thank the Morning",
    "Grateful First Light",
    "Warm Thanks at Sunrise",
    "Small Mercies, Big Sky",
    "Heart Opens With Dawn",
    "Bless the Ordinary",
    "Quiet Thanks Around You",
    "Soft Gratitude, Bright Day",
    "Count the Good Nearby",
    "Morning Appreciation",
    "Light on What You Love",
    "Gentle Thank-Yous",
    "Shelf of Good Things",
    "Gratitude, Unhurried",
    "Sunrise Thank-You Walk",
    "Warm Shelf of Thanks",
    "Hold Good Things Close",
    "Thanks Before the Rush",
    "Grateful Grounding",
    "Morning Thank-You Breath",
  ],
  focus: [
    "Single-Point Attention",
    "Steady Inner Beacon",
    "Quiet Concentration",
    "Mind on One String",
    "Clear Channel",
    "Hold the Line Softly",
    "Unbroken Attention",
    "Soft Laser Focus",
    "Gather the Scattered",
    "Anchor Thought",
    "Breath as Compass",
    "Narrow the Beam",
    "Still Point Practice",
    "One Thing at a Time",
    "Train of One Car",
    "Gentle Lock-In",
    "Return Again, Gently",
    "Focus Without Force",
    "Calm Alertness",
    "Present and Steady",
  ],
  anxiety: [
    "Slow the Spin",
    "Ground Under the Worry",
    "Wider Than the Fear",
    "Room to Breathe Again",
    "Unclench the Future",
    "Softer Than the What-If",
    "Step Back One Pace",
    "Let the Storm Pass Through",
    "Small Safe Circle",
    "Ease the Tight Chest",
    "Quiet the Alarm",
    "Hold Yourself Kindly",
    "Not Everything at Once",
    "Breath Wider Than Thought",
    "Settle the Nerves",
    "Weight in the Feet",
    "Here Still Beats Later",
    "Shrink the Problem",
    "Comfort in the Exhale",
    "Steady Through the Buzz",
  ],
  relax: [
    "Unwind the Edges",
    "Loosen the Day",
    "Soft Shoulders, Soft Mind",
    "Let the Muscle Go",
    "Slow River Calm",
    "Nothing Owed Right Now",
    "Ease Into Neutral",
    "Drop the Rope",
    "Quiet Pool Inside",
    "Rest Without Guilt",
    "Gentle Downshift",
    "Softer Than Effort",
    "Float a Little",
    "Room to Just Be",
    "Calm Without a Reason",
    "Breathe the Tension Out",
    "Simple Stillness",
    "Uncomplicated Quiet",
    "Let the Body Lead",
    "Peace in Small Doses",
  ],
  evening: [
    "Close the Laptop in the Mind",
    "After-Work Decompression",
    "Sunset Soft Reset",
    "Wind-Down Without Rush",
    "Evening Unplug",
    "Dim the Inner Lights",
    "Leave Work at the Door",
    "Twilight Quiet",
    "Last Kind Thought",
    "Evening Buffer",
    "Soft Border to Night",
    "Day's Edge, Gentle",
    "Home in the Body",
    "Ease Out of Doing",
    "Quiet Handoff to Night",
  ],
  noon: [
    "Midday Recenter",
    "Lunch-Break Reset",
    "Pause Between Meetings",
    "Halfway Stillness",
    "Noon Nervous System Break",
    "Quick Center, Long Effect",
    "Refill the Cup",
    "Quiet in the Middle",
    "Between Two Halves",
    "Midday Breath Anchor",
    "Step Off the Treadmill",
    "Small Oasis",
    "Refresh Without Coffee",
    "Center Before Afternoon",
  ],
  night: [
    "Late-Night Still Point",
    "After Dark Calm",
    "Quiet Hours Practice",
    "Night Owl Unwind",
    "When the House Is Still",
    "Soft Glow, Softer Mind",
    "Moonlight Neutral",
    "Deep Blue Pause",
  ],
  gratitude: [
    "Shelf of Small Wins",
    "Notice the Good",
    "Warm Inventory",
    "Quiet Thank-You List",
    "What Already Worked",
    "Grateful Without Drama",
    "Thanks in Plain Sight",
    "Heart Full, Mind Light",
    "Simple Appreciation",
    "Good Enough, Grateful",
    "Light on the Helpers",
    "Bless This Ordinary",
    "Count Without Rushing",
    "Soft Praise for Today",
  ],
  morning_general: [
    "Gentle Start",
    "First Breath of the Day",
    "Rise Without Rush",
    "Morning Still Point",
    "Soft Opening",
    "Daybreak Grounding",
    "Quiet Before the Plan",
    "Warm-Up for Being Human",
    "Ease Into Awake",
    "Slow Hello to Today",
    "Morning Without Agenda",
    "Light Through the Window",
    "Fresh Sheet of Attention",
    "Unhurried Sunrise",
    "Collect Yourself Gently",
    "Before the First Email",
    "Still House, Awake Body",
    "Morning Neutral",
    "Soft Footsteps Inward",
    "Hello Today, Softly",
  ],
  default: [
    "Your Quiet Session",
    "Custom Stillness",
    "Breath and Body",
    "Simple Inner Practice",
    "A Few Minutes Inward",
    "Unlabeled Calm",
    "Just This Practice",
    "Small Sanctuary",
    "Portable Peace",
    "Tune Inward",
    "Quiet Corner",
    "Held in Attention",
    "Nothing Fancy, Just Now",
    "Soft Inner Weather",
    "Practice as Home",
    "Gather and Release",
    "Moment of Care",
    "Self as Friend",
    "Gentle Check-In",
    "What You Asked For",
  ],
};

export function resolveDisplayTitleBucket(args: {
  prompt: string;
  themes: MeditationThemeId[];
  prefs: SessionPreferences;
  mvVariant: MorningVisualizationVariant | null;
  overrides: UserStructureOverrides;
  structureContext: string;
}): DisplayTitleBucket {
  const { prompt, themes, prefs, mvVariant, overrides, structureContext } = args;
  const lower = prompt.toLowerCase();

  if (prefs.isSleep || themes.includes("sleep")) {
    return "sleep";
  }
  if (mvVariant === "MV_GR") {
    return "morning_viz_gr";
  }
  if (mvVariant === "MV_KM") {
    return "morning_viz_km";
  }

  if (
    overrides.focusType === "IM" ||
    overrides.focusType === "NF" ||
    structureContext.includes("IM_FRAC") ||
    structureContext.includes("NF_FRAC")
  ) {
    return "focus";
  }

  if (
    /\b(anxiety|anxious|panic|overwhelm|overwhelmed|worry|worried|racing thoughts?)\b/.test(
      lower
    )
  ) {
    return "anxiety";
  }

  if (
    /\b(relax|relaxation|calm down|unwind|chill|de-?stress|soothe|ease|peace|rest|quiet)\b/.test(
      lower
    )
  ) {
    return "relax";
  }

  if (themes.includes("evening")) {
    return "evening";
  }
  if (themes.includes("noon")) {
    return "noon";
  }
  if (themes.includes("night")) {
    return "night";
  }
  if (themes.includes("gratitude")) {
    return "gratitude";
  }
  if (themes.includes("morning") || prefs.isMorning) {
    return "morning_general";
  }

  return "default";
}

function hashToUint32(input: string): number {
  const buf = createHash("sha256").update(input, "utf8").digest();
  return buf.readUInt32BE(0);
}

export type PickDisplayTitleDeps = {
  /** Returns integer in [0, maxExclusive). Defaults to crypto.randomInt. */
  randomIndex?: (maxExclusive: number) => number;
};

/**
 * Picks a short, non-generic title from a themed pool.
 * Combines SHA-256(prompt, duration, themes, structure) with per-request randomness.
 */
export function pickDisplayTitle(
  args: {
    prompt: string;
    duration: number;
    themes: MeditationThemeId[];
    prefs: SessionPreferences;
    mvVariant: MorningVisualizationVariant | null;
    overrides: UserStructureOverrides;
    structureContext: string;
  },
  deps?: PickDisplayTitleDeps
): { title: string; bucket: DisplayTitleBucket } {
  const bucket = resolveDisplayTitleBucket(args);
  const pool = POOLS[bucket];
  const rnd =
    deps?.randomIndex ??
    ((maxExclusive: number) =>
      maxExclusive <= 1 ? 0 : randomInt(0, maxExclusive));

  const hashInput = [
    args.prompt,
    String(args.duration),
    args.themes.join(","),
    args.structureContext,
  ].join("\0");

  const h = hashToUint32(hashInput);
  const idx = (h + rnd(pool.length)) % pool.length;
  return { title: pool[idx]!, bucket };
}
