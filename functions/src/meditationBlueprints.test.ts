import assert from "node:assert/strict";
import { test } from "node:test";
import {
  parseClientBlueprintId,
  pickBackgroundSoundForBlueprint,
  resolveBlueprintFromContext,
} from "./meditationBlueprints";
import type { SessionPreferences } from "./phaseAllocation";

test("parseClientBlueprintId accepts known ids", () => {
  assert.equal(parseClientBlueprintId("timely.morning"), "timely.morning");
  assert.equal(parseClientBlueprintId("  timely.night  "), "timely.night");
});

test("parseClientBlueprintId rejects unknown or empty", () => {
  assert.equal(parseClientBlueprintId("nope"), null);
  assert.equal(parseClientBlueprintId(""), null);
  assert.equal(parseClientBlueprintId(null), null);
});

const prefs: SessionPreferences = {
  noBreathwork: false,
  isSleep: false,
  isMorning: false,
  isEvening: false,
};

test("resolveBlueprintFromContext prefers explicit client blueprint over themes", () => {
  const bp = resolveBlueprintFromContext({
    clientBlueprintId: "timely.sleep",
    themes: ["morning"],
    prefs,
  });
  assert.equal(bp?.id, "timely.sleep");
});

test("resolveBlueprintFromContext maps sleep theme to timely.sleep", () => {
  const bp = resolveBlueprintFromContext({
    clientBlueprintId: null,
    themes: ["sleep"],
    prefs,
  });
  assert.equal(bp?.id, "timely.sleep");
});

test("resolveBlueprintFromContext maps night theme to timely.night", () => {
  const bp = resolveBlueprintFromContext({
    clientBlueprintId: null,
    themes: ["night"],
    prefs,
  });
  assert.equal(bp?.id, "timely.night");
});

const catalog = [
  { id: "OC", name: "Ocean" },
  { id: "LI", name: "Light" },
  { id: "ZZ", name: "Unknown" },
];

test("pickBackgroundSoundForBlueprint returns undefined for empty catalog", () => {
  assert.equal(
    pickBackgroundSoundForBlueprint([], undefined, { preferCategory: "focus" }, []),
    undefined
  );
});

test("pickBackgroundSoundForBlueprint with tiny random returns first catalog row", () => {
  const original = Math.random;
  Math.random = () => 0.000_000_1;
  try {
    const hints = { preferCategory: "focus" as const, preferredIds: ["LI"] };
    const picked = pickBackgroundSoundForBlueprint(
      catalog,
      undefined,
      hints,
      []
    );
    assert.equal(picked?.id, "OC");
  } finally {
    Math.random = original;
  }
});

test("pickBackgroundSoundForBlueprint down-weights recent id so preferred wins", () => {
  const original = Math.random;
  Math.random = () => 0.99;
  try {
    const two = [
      { id: "OC", name: "Ocean" },
      { id: "LI", name: "Light" },
    ];
    const hints = { preferCategory: "focus" as const, preferredIds: ["LI", "DH"] };
    const picked = pickBackgroundSoundForBlueprint(
      two,
      undefined,
      hints,
      ["OC"]
    );
    assert.equal(picked?.id, "LI");
  } finally {
    Math.random = original;
  }
});

test("pickBackgroundSoundForBlueprint excludes excludeId", () => {
  const original = Math.random;
  Math.random = () => 0.5;
  try {
    const picked = pickBackgroundSoundForBlueprint(
      catalog,
      "OC",
      { preferredIds: ["OC", "LI"] },
      []
    );
    assert.notEqual(picked?.id, "OC");
    assert.ok(picked?.id);
  } finally {
    Math.random = original;
  }
});
