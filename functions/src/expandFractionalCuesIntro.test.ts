/** @see ../../docs/fractional-module-intro-rule.md */
import assert from "node:assert/strict";
import { test } from "node:test";
import { expandFractionalCues } from "./fractionalComposer";
import { INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC } from "./introFractionalPlan";

test("expandFractionalCues: INT_FRAC first atomic cue at 7s", () => {
  const out = expandFractionalCues(
    [
      {
        id: "INT_FRAC",
        name: "Intro",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  const first = out.find((c) => c.id.startsWith("INT_"));
  assert.ok(first);
  assert.equal(first!.trigger, `s${INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC}`);
});

test("expandFractionalCues: second fractional row skips PB OPEN for 2m block (even if trigger is start)", () => {
  const out = expandFractionalCues(
    [
      {
        id: "IM_FRAC",
        name: "I AM",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
      {
        id: "PB_FRAC",
        name: "PB",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    !out.some((c) => c.id === "PBV_OPEN_000_INTRO_ASAF"),
    "PB block under 5m and not first fractional row must not emit OPEN"
  );
});

test("expandFractionalCues: INT_GEN before IM_FRAC at start skips IM framing intro for 3m", () => {
  const out = expandFractionalCues(
    [
      {
        id: "INT_GEN_1",
        name: "Intro",
        url: "",
        trigger: "start",
      },
      {
        id: "IM_FRAC",
        name: "I AM",
        url: "",
        trigger: "start",
        durationMinutes: 3,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    !out.some((c) => c.id === "IM_C001"),
    "regular intro first → fractional module must not emit IM framing intro"
  );
});

test("expandFractionalCues: sole PB_FRAC row still gets OPEN for 2m when first fractional", () => {
  const out = expandFractionalCues(
    [
      {
        id: "PB_FRAC",
        name: "PB",
        url: "",
        trigger: "start",
        durationMinutes: 2,
      },
    ],
    10,
    "Asaf"
  );
  assert.ok(
    out.some((c) => c.id === "PBV_OPEN_000_INTRO_ASAF"),
    "single PB row is first fractional — OPEN allowed for >60s window"
  );
});
