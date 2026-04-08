#!/usr/bin/env node
/**
 * Stream each Asaf MP3 from Firebase Storage (public download URL), read duration
 * via music-metadata, write durationSec onto each clip in body scan fractional catalogs.
 *
 * Objects must be readable via the Firebase download URL (same as the app uses).
 *
 * Usage (from functions/):
 *   node scripts/scanBodyScanDurations.mjs
 *   node scripts/scanBodyScanDurations.mjs --dry-run
 *   node scripts/scanBodyScanDurations.mjs body_scan_fractional.json perfect_breath_fractional.json
 */

import { parseStream } from "music-metadata";
import fs from "fs";
import path from "path";
import { Readable } from "stream";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BUCKET = "imagine-c6162.appspot.com";
const VOICE_KEY = "Asaf";

const DEFAULT_CATALOGS = ["body_scan_fractional.json"];

const dryRun = process.argv.includes("--dry-run");
const argvCatalogs = process.argv.filter(
  (a) => !a.startsWith("--") && a.endsWith(".json")
);
const catalogsToScan =
  argvCatalogs.length > 0 ? argvCatalogs : DEFAULT_CATALOGS;

function firebaseMediaUrl(relativePath) {
  const encoded = encodeURIComponent(relativePath);
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media`;
}

function durationFromMetadata(meta) {
  const d = meta?.format?.duration;
  if (d == null || !Number.isFinite(d)) return null;
  return Math.round(d * 1000) / 1000;
}

async function httpAudioDuration(relativePath) {
  const url = firebaseMediaUrl(relativePath);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${url}`);
  }
  if (!res.body) {
    throw new Error(`No body for ${relativePath}`);
  }
  const stream = Readable.fromWeb(res.body);
  try {
    const meta = await parseStream(
      stream,
      { mimeType: "audio/mpeg" },
      { duration: true }
    );
    return durationFromMetadata(meta);
  } finally {
    stream.destroy();
  }
}

async function scanOneCatalog(basename) {
  const catalogPath = path.join(__dirname, "..", "catalogs", basename);

  if (!fs.existsSync(catalogPath)) {
    console.warn(`Skip missing catalog: ${catalogPath}`);
    return;
  }

  const raw = fs.readFileSync(catalogPath, "utf8");
  const catalog = JSON.parse(raw);

  if (!catalog.clips?.length) {
    console.error(`No clips in ${basename}`);
    process.exit(1);
  }

  console.log(
    `\n=== ${basename} (${catalog.clips.length} clips) ===\nScanning via https://firebasestorage.googleapis.com/ …`
  );

  for (const clip of catalog.clips) {
    const rel = clip.voices?.[VOICE_KEY];
    if (!rel || typeof rel !== "string") {
      console.warn(`Skip ${clip.clipId}: no voices.${VOICE_KEY}`);
      continue;
    }
    process.stdout.write(`  ${clip.clipId} (${rel}) … `);
    const sec = await httpAudioDuration(rel);
    if (sec == null) {
      console.log("FAIL (no duration)");
      process.exit(1);
    }
    clip.durationSec = sec;
    console.log(`${sec}s`);
  }

  if (dryRun) {
    console.log(`Dry run: not writing ${basename}.`);
    return;
  }

  const out = `${JSON.stringify(catalog, null, 2)}\n`;
  fs.writeFileSync(catalogPath, out, "utf8");
  console.log(`Wrote ${catalogPath}`);
}

async function main() {
  for (const basename of catalogsToScan) {
    await scanOneCatalog(basename);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
