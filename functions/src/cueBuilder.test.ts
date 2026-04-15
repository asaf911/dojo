import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCuesFromAllocation } from "./cueBuilder";
import {
  allocatePhases,
  minFocusMinutesForMorningVisualization,
  rebalanceAllocationForMinimumFocus,
} from "./phaseAllocation";

test("buildCuesFromAllocation: NF focus emits monolithic NF5 when focus minutes is 5", () => {
  const cues = buildCuesFromAllocation(
    {
      intro: 0,
      breath: 1,
      relax: 2,
      focus: 5,
      insight: 0,
      focusType: "NF",
    },
    {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    },
    { bodyScanDirection: "down" }
  );
  const nf = cues.find((c) => c.id.startsWith("NF") && /^NF\d+$/.test(c.id));
  assert.equal(nf?.id, "NF5");
});

test("buildCuesFromAllocation: NF focus clamps to NF10 when focus > 10", () => {
  const cues = buildCuesFromAllocation(
    {
      intro: 0,
      breath: 0,
      relax: 0,
      focus: 15,
      insight: 0,
      focusType: "NF",
    },
    {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    },
    {}
  );
  const nf = cues.find((c) => /^NF\d+$/.test(c.id));
  assert.equal(nf?.id, "NF10");
});

test("buildCuesFromAllocation (dev project): NF focus emits NF_FRAC", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const cues = buildCuesFromAllocation(
      {
        intro: 0,
        breath: 1,
        relax: 2,
        focus: 5,
        insight: 0,
        focusType: "NF",
      },
      {
        noBreathwork: false,
        isSleep: false,
        isMorning: false,
        isEvening: false,
      },
      { bodyScanDirection: "down" }
    );
    assert.ok(cues.some((c) => c.id === "NF_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});

test("buildCuesFromAllocation (dev): practiceDurationMinutes 4 omits INT_FRAC", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const cues = buildCuesFromAllocation(
      {
        intro: 0,
        breath: 1,
        relax: 2,
        focus: 5,
        insight: 0,
        focusType: "NF",
      },
      {
        noBreathwork: false,
        isSleep: false,
        isMorning: false,
        isEvening: false,
      },
      { bodyScanDirection: "down", practiceDurationMinutes: 4 }
    );
    assert.equal(cues[0]?.id, "PB_FRAC");
    assert.ok(!cues.some((c) => c.id === "INT_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});

test("buildCuesFromAllocation (dev): rebalanced 4m + MV_KM_FRAC emits morning viz row", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const prefs = {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    };
    const base = allocatePhases(4, prefs);
    const minF = minFocusMinutesForMorningVisualization(
      4,
      "4 minutes morning visualization"
    );
    const alloc = rebalanceAllocationForMinimumFocus(base, 4, minF);
    assert.equal(alloc.focus, 2);
    const cues = buildCuesFromAllocation(alloc, prefs, {
      practiceDurationMinutes: 4,
      themeCueHints: { focusFractionalId: "MV_KM_FRAC" },
    });
    assert.ok(cues.some((c) => c.id === "MV_KM_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});

test("buildCuesFromAllocation (dev): rebalanced 4m + EV_KM_FRAC emits evening viz row", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const prefs = {
      noBreathwork: false,
      isSleep: false,
      isMorning: false,
      isEvening: false,
    };
    const base = allocatePhases(4, prefs);
    const minF = minFocusMinutesForMorningVisualization(
      4,
      "4 minutes evening visualization"
    );
    const alloc = rebalanceAllocationForMinimumFocus(base, 4, minF);
    assert.equal(alloc.focus, 2);
    const cues = buildCuesFromAllocation(alloc, prefs, {
      practiceDurationMinutes: 4,
      themeCueHints: { focusFractionalId: "EV_KM_FRAC" },
    });
    assert.ok(cues.some((c) => c.id === "EV_KM_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});

test("buildCuesFromAllocation (dev): theme gratitude + focus uses MV_GR_FRAC when no IM/NF", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const cues = buildCuesFromAllocation(
      {
        intro: 0,
        breath: 1,
        relax: 2,
        focus: 5,
        insight: 0,
        focusType: undefined,
      },
      {
        noBreathwork: false,
        isSleep: false,
        isMorning: false,
        isEvening: false,
      },
      {
        practiceDurationMinutes: 10,
        themeCueHints: { focusFractionalId: "MV_GR_FRAC" },
      }
    );
    assert.ok(cues.some((c) => c.id === "MV_GR_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});

test("buildCuesFromAllocation (dev): practiceDurationMinutes 5 includes INT_FRAC", () => {
  const prev = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "imaginedev-e5fd3";
  try {
    const cues = buildCuesFromAllocation(
      {
        intro: 0,
        breath: 1,
        relax: 2,
        focus: 5,
        insight: 0,
        focusType: "NF",
      },
      {
        noBreathwork: false,
        isSleep: false,
        isMorning: false,
        isEvening: false,
      },
      { bodyScanDirection: "down", practiceDurationMinutes: 5 }
    );
    assert.equal(cues[0]?.id, "INT_FRAC");
    assert.ok(cues.some((c) => c.id === "INT_FRAC"));
  } finally {
    if (prev === undefined) {
      delete process.env.GCLOUD_PROJECT;
    } else {
      process.env.GCLOUD_PROJECT = prev;
    }
  }
});
