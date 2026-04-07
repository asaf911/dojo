#!/usr/bin/env node
/**
 * One-off generator for body_scan_fractional.json — run from functions/:
 *   node scripts/generateBodyScanFractionalCatalog.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..", "catalogs");
const rel = (id) => `modules/body_scan_fractional/asaf/${id}.mp3`;

function v(id, text, role, extra = {}) {
  return {
    clipId: id,
    role,
    text,
    voices: { Asaf: rel(id) },
    ...extra,
  };
}

const clips = [];

clips.push(
  v(
    "BS_SYS_000_INTRO_SHORT_ASAF",
    "We will now begin a body scan",
    "intro",
    { introVariant: "short", order: 0 }
  ),
  v(
    "BS_SYS_010_INTRO_LONG_ASAF",
    "We will now begin a body scan. As each part is named direct your attention there",
    "intro",
    { introVariant: "long", order: 0 }
  )
);

const entries = [
  ["BS_SYS_020_ENTRY_TOP_MACRO_ASAF", "Relax your head face and neck", "top", "macro"],
  ["BS_SYS_030_ENTRY_BOTTOM_MACRO_ASAF", "Relax your legs and feet", "bottom", "macro"],
  ["BS_SYS_040_ENTRY_TOP_REGIONAL_ASAF", "Head", "top", "regional"],
  ["BS_SYS_050_ENTRY_BOTTOM_REGIONAL_ASAF", "Feet", "bottom", "regional"],
  ["BS_SYS_060_ENTRY_TOP_MICRO_ASAF", "Top of your head", "top", "micro"],
  ["BS_SYS_070_ENTRY_BOTTOM_MICRO_ASAF", "Toes", "bottom", "micro"],
];
for (const [id, text, end, tier] of entries) {
  clips.push(
    v(id, text, "entry", {
      entryScanEnd: end,
      entryTier: tier,
      order: 0,
    })
  );
}

clips.push(
  v("BS_SYS_080_FULL_BODY_ASAF", "Your whole body", "integration", {
    integrationOrder: 1,
    order: 9998,
  }),
  v(
    "BS_SYS_090_FULL_BODY_DEEPEN_ASAF",
    "Your entire body",
    "integration",
    { integrationOrder: 2, order: 9999 }
  )
);

function body(zone, tier, id, text, orderUp, orderDown) {
  clips.push(
    v(id, text, "instruction", {
      macroZone: zone,
      bodyTier: tier,
      orderUp,
      orderDown,
      order: orderUp,
    })
  );
}

body(1, "macro", "BS_MAC_100_HEAD_FACE_NECK_ASAF", "Relax your head face and neck", 100, 100);
body(2, "macro", "BS_MAC_120_CHEST_BELLY_ASAF", "Relax your chest and belly", 120, 120);
body(3, "macro", "BS_MAC_140_LEGS_FEET_ASAF", "Relax your legs and feet", 140, 140);

body(1, "regional", "BS_REG_200_HEAD_ASAF", "Head", 200, 230);
body(1, "regional", "BS_REG_210_FACE_ASAF", "Face", 210, 220);
body(1, "regional", "BS_REG_220_NECK_ASAF", "Neck", 220, 210);

// Zone 1 micro: orderDown = feet-to-head within zone (neck micros first when going down into zone 1 from zone 2)
const z1micro = [
  ["BS_MIC_300_HEAD_TOP_ASAF", "Top of your head", 300, 16],
  ["BS_MIC_310_HEAD_FOREHEAD_ASAF", "Forehead", 310, 15],
  ["BS_MIC_320_FACE_EYEBROWS_ASAF", "Eyebrows", 320, 14],
  ["BS_MIC_330_FACE_EYELIDS_ASAF", "Eyelids", 330, 13],
  ["BS_MIC_340_FACE_EYEBALLS_ASAF", "Eyeballs", 340, 12],
  ["BS_MIC_350_FACE_EYE_MUSCLES_ASAF", "Eye muscles", 350, 11],
  ["BS_MIC_360_FACE_TEMPLES_ASAF", "Temples", 360, 10],
  ["BS_MIC_370_FACE_CHEEKS_ASAF", "Cheeks", 370, 9],
  ["BS_MIC_380_FACE_NOSE_ASAF", "Nose", 380, 8],
  ["BS_MIC_390_FACE_MOUTH_ASAF", "Mouth", 390, 7],
  ["BS_MIC_392_FACE_LIPS_ASAF", "Lips", 392, 6],
  ["BS_MIC_394_FACE_TONGUE_ASAF", "Tongue", 394, 5],
  ["BS_MIC_396_FACE_INNER_MOUTH_ASAF", "Inner mouth", 396, 4],
  ["BS_MIC_398_FACE_JAW_ASAF", "Jaw", 398, 3],
  ["BS_MIC_400_NECK_THROAT_ASAF", "Throat", 400, 2],
  ["BS_MIC_410_NECK_BACK_ASAF", "Back of your neck", 410, 1],
];
for (const [id, tx, ou, od] of z1micro) body(1, "micro", id, tx, ou, od);

body(2, "regional", "BS_REG_240_CHEST_ASAF", "Chest", 240, 270);
body(2, "regional", "BS_REG_250_BELLY_SIDES_ASAF", "Belly and sides", 250, 260);
body(2, "regional", "BS_REG_260_PELVIC_LOWERBACK_ASAF", "Pelvic area and lower back", 260, 250);

const z2micro = [
  ["BS_MIC_420_CHEST_HEART_ASAF", "Heart", 420, 7],
  ["BS_MIC_430_RIBCAGE_ASAF", "Ribcage", 430, 6],
  ["BS_MIC_440_UPPER_BACK_ASAF", "Upper back", 440, 5],
  ["BS_MIC_450_BELLY_ASAF", "Belly", 450, 4],
  ["BS_MIC_460_SIDES_BODY_ASAF", "Sides of your body", 460, 3],
  ["BS_MIC_470_LOWER_BACK_ASAF", "Lower back", 470, 2],
  ["BS_MIC_480_PELVIC_FLOOR_ASAF", "Pelvic floor", 480, 1],
];
for (const [id, tx, ou, od] of z2micro) body(2, "micro", id, tx, ou, od);

body(3, "regional", "BS_REG_280_UPPER_LEGS_ASAF", "Upper legs", 280, 295);
body(3, "regional", "BS_REG_290_LOWER_LEGS_ASAF", "Lower legs", 290, 290);
body(3, "regional", "BS_REG_295_FEET_ASAF", "Feet", 295, 280);

const z3micro = [
  ["BS_MIC_500_HIPS_THIGHS_ASAF", "Hips and thighs", 500, 8],
  ["BS_MIC_510_KNEES_ASAF", "Knees", 510, 7],
  ["BS_MIC_520_SHINS_CALVES_ASAF", "Shins and calves", 520, 6],
  ["BS_MIC_530_ANKLES_ASAF", "Ankles", 530, 5],
  ["BS_MIC_540_HEELS_ASAF", "Heels", 540, 4],
  ["BS_MIC_550_FEET_TOPS_ASAF", "Tops of your feet", 550, 3],
  ["BS_MIC_560_FEET_SOLES_ASAF", "Soles of your feet", 560, 2],
  ["BS_MIC_570_FEET_TOES_ASAF", "Toes", 570, 1],
];
for (const [id, tx, ou, od] of z3micro) body(3, "micro", id, tx, ou, od);

const catalog = {
  version: "2.0",
  moduleId: "BS_FRAC",
  title: "Body Scan",
  clips,
};

const outPath = path.join(root, "body_scan_fractional.json");
fs.writeFileSync(outPath, JSON.stringify(catalog, null, 2), "utf8");
console.log("Wrote", outPath, "clips=", clips.length);
