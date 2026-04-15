import assert from "node:assert/strict";
import { test } from "node:test";
import { allocateReminderSilencesWithLongTail } from "./fractionalTimeline";

test("allocateReminderSilencesWithLongTail: surplus split with linear weights (no single-slot swallow)", () => {
  const floors = { beforeFirst: 32, between: 32, afterLast: 32 };
  const n = 3;
  const min = 32 * 4;
  const total = min + 200;
  const g = allocateReminderSilencesWithLongTail(total, n, floors);
  assert.ok(g);
  assert.equal(g!.length, 4);
  const sum = g!.reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(sum - total) < 0.01, `sum ${sum} vs total ${total}`);
  const extra = g!.map((x, i) => x - 32);
  const w = [1, 2, 3, 4];
  const ws = w.reduce((a, b) => a + b, 0);
  const unit = 200 / ws;
  for (let i = 0; i < 4; i++) {
    assert.ok(Math.abs(extra[i]! - unit * w[i]!) < 0.01, `slot ${i} extra`);
  }
  assert.ok(g![3]! < g![0]! * 2.5, "last gap should not dwarf first (was long-tail bug)");
});

test("allocateReminderSilencesWithLongTail: monotone floors preserved then weighted extra", () => {
  const floors = { beforeFirst: 10, between: 10, afterLast: 40 };
  const g = allocateReminderSilencesWithLongTail(100, 2, floors);
  assert.ok(g);
  assert.equal(g!.length, 3);
  assert.ok(g![0]! <= g![1]! && g![1]! <= g![2]!, "non-decreasing after allocation");
});
