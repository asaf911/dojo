import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizeFractionalSurfaceCueIdsForProd } from "./fractionalSurfaceCueNormalize";

test("normalizeFractionalSurfaceCueIdsForProd: NF_FRAC rewrites to NF3 for 3-minute window before next cue", () => {
  const cues = normalizeFractionalSurfaceCueIdsForProd(
    [
      { id: "INT_GEN_1", trigger: "start" },
      { id: "PB_FRAC", trigger: "1", durationMinutes: 1 },
      { id: "NF_FRAC", trigger: "3" },
      { id: "IM_FRAC", trigger: "6" },
      { id: "GB", trigger: "end" },
    ],
    10
  );
  const nf = cues.find((c) => c.id.startsWith("NF"));
  assert.equal(nf?.id, "NF3");
});

test("normalizeFractionalSurfaceCueIdsForProd: no-op when fractional ids absent (same reference)", () => {
  const original = [{ id: "NF5", trigger: "3" }];
  const out = normalizeFractionalSurfaceCueIdsForProd(original, 10);
  assert.strictEqual(out, original);
});

test("normalizeFractionalSurfaceCueIdsForProd: uses durationMinutes on NF_FRAC when set", () => {
  const cues = normalizeFractionalSurfaceCueIdsForProd(
    [{ id: "NF_FRAC", trigger: "2", durationMinutes: 4 }],
    20
  );
  assert.equal(cues[0]?.id, "NF4");
});

test("normalizeFractionalSurfaceCueIdsForProd: PB_FRAC to PB2", () => {
  const cues = normalizeFractionalSurfaceCueIdsForProd(
    [
      { id: "INT_GEN_1", trigger: "start" },
      { id: "PB_FRAC", trigger: "1", durationMinutes: 2 },
      { id: "GB", trigger: "end" },
    ],
    10
  );
  const pb = cues.find((c) => c.id.startsWith("PB"));
  assert.equal(pb?.id, "PB2");
});

test("normalizeFractionalSurfaceCueIdsForProd: BS_FRAC_UP to BS4", () => {
  const cues = normalizeFractionalSurfaceCueIdsForProd(
    [
      { id: "INT_GEN_1", trigger: "start" },
      { id: "PB_FRAC", trigger: "1", durationMinutes: 1 },
      { id: "BS_FRAC_UP", trigger: "2", durationMinutes: 4 },
      { id: "GB", trigger: "end" },
    ],
    15
  );
  const bs = cues.find((c) => /^BS[0-9]+$/.test(c.id));
  assert.equal(bs?.id, "BS4");
});
