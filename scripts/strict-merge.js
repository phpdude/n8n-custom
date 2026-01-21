#!/usr/bin/env node
'use strict';

const fs = require('fs/promises');
const fss = require('fs');
const path = require('path');
const { PDFDocument } = require('pdf-lib');

const A4_W = 595.28;
const A4_H = 841.89;
const MARGIN = 24;

// --- args ---
function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const k = a.slice(2);
    const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    out[k] = v;
  }
  return out;
}

// --- sniffers ---
function isPdf(buf) {
  return buf.length >= 5 && buf[0] === 0x25 && buf[1] === 0x50 && buf[2] === 0x44 && buf[3] === 0x46 && buf[4] === 0x2d; // %PDF-
}
function isPng(buf) {
  return buf.length >= 8 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47 &&
    buf[4] === 0x0D && buf[5] === 0x0A && buf[6] === 0x1A && buf[7] === 0x0A;
}
function isJpeg(buf) {
  return buf.length >= 3 && buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF;
}

async function listSortedFiles(dir) {
  const names = await fs.readdir(dir);
  return names
    .filter((x) => !x.startsWith('.'))
    .sort((a, b) => a.localeCompare(b, 'en'))
    .map((x) => path.join(dir, x));
}

function addA4Page(doc) {
  return doc.addPage([A4_W, A4_H]);
}

function fitToA4(imgW, imgH) {
  const maxW = A4_W - MARGIN * 2;
  const maxH = A4_H - MARGIN * 2;
  const scale = Math.min(maxW / imgW, maxH / imgH);
  const w = imgW * scale;
  const h = imgH * scale;
  const x = (A4_W - w) / 2;
  const y = (A4_H - h) / 2;
  return { x, y, w, h };
}

async function ensurePdfReadable(pdfBytes, name) {
  try {
    await PDFDocument.load(pdfBytes, { ignoreEncryption: false });
  } catch (e) {
    const err = new Error(`PDF not readable or encrypted: ${name}`);
    err.cause = e;
    throw err;
  }
}

// --- cleanup helpers ---
async function rmrf(p) {
  if (!p) return;
  await fs.rm(p, { recursive: true, force: true }).catch(() => {});
}

// --- main ---
(async () => {
  const args = parseArgs(process.argv);

  // base dir like /tmp/pdf-merge/<runId>
  const baseDir = args.base || null;

  // if you pass --dir, use it, else baseDir/in
  const inDir = args.dir || (baseDir ? path.join(baseDir, 'in') : null);

  // if you pass --out, use it, else baseDir/out/merged.pdf
  const outPath = args.out || (baseDir ? path.join(baseDir, 'out', 'merged.pdf') : null);

  // if set: prints base64 of merged pdf to stdout (so n8n can pack into binary),
  // and you MAY choose to not keep the file on disk.
  const emitBase64 = args.emitBase64 === true || args.emitBase64 === 'true';

  // if set: cleanup baseDir always (recommended)
  const cleanup = args.cleanup === true || args.cleanup === 'true';

  if (!inDir) throw new Error('Missing --base or --dir');
  if (!outPath && !emitBase64) throw new Error('Missing --out (or use --emitBase64 true)');

  // ALWAYS cleanup on any exit path if cleanup enabled
  try {
    const files = await listSortedFiles(inDir);
    if (!files.length) throw new Error(`No input files in: ${inDir}`);

    const outPdf = await PDFDocument.create();

    for (const fp of files) {
      const name = path.basename(fp);
      const st = await fs.stat(fp);
      if (!st.isFile()) throw new Error(`Not a file: ${fp}`);
      if (st.size <= 0) throw new Error(`Empty file: ${fp}`);
      if (st.size > 80 * 1024 * 1024) throw new Error(`File too large (>80MB): ${name}`);

      const bytes = await fs.readFile(fp);

      if (isPdf(bytes)) {
        await ensurePdfReadable(bytes, name);
        const src = await PDFDocument.load(bytes, { ignoreEncryption: false });
        const pages = await outPdf.copyPages(src, src.getPageIndices());
        for (const p of pages) outPdf.addPage(p);
        continue;
      }

      if (isJpeg(bytes)) {
        const img = await outPdf.embedJpg(bytes);
        const { width, height } = img.size();
        if (!(width > 0 && height > 0)) throw new Error(`Bad JPG dimensions: ${name} ${width}x${height}`);
        const page = addA4Page(outPdf);
        const { x, y, w, h } = fitToA4(width, height);
        page.drawImage(img, { x, y, width: w, height: h });
        continue;
      }

      if (isPng(bytes)) {
        const img = await outPdf.embedPng(bytes);
        const { width, height } = img.size();
        if (!(width > 0 && height > 0)) throw new Error(`Bad PNG dimensions: ${name} ${width}x${height}`);
        const page = addA4Page(outPdf);
        const { x, y, w, h } = fitToA4(width, height);
        page.drawImage(img, { x, y, width: w, height: h });
        continue;
      }

      throw new Error(`Unsupported type (need PDF/PNG/JPEG): ${name}`);
    }

    const pageCount = outPdf.getPageCount();
    if (pageCount <= 0) throw new Error('Output has 0 pages');

    const outBytes = await outPdf.save();

    // Write to disk (atomic), unless you only want base64 and no file
    if (outPath) {
      await fs.mkdir(path.dirname(outPath), { recursive: true });
      const tmp = `${outPath}.tmp-${process.pid}`;
      await fs.writeFile(tmp, outBytes);
      await fs.rename(tmp, outPath);
    }

    if (emitBase64) {
      // ONLY base64 to stdout (strict, no extra logs)
      process.stdout.write(Buffer.from(outBytes).toString('base64'));
    } else {
      process.stdout.write(`[strict-merge] OK pages=${pageCount} bytes=${outBytes.length} out=${outPath}\n`);
    }

    process.exit(0);
  } catch (e) {
    // strict fail
    process.stderr.write(`[strict-merge] ERROR: ${String(e?.stack || e)}\n`);
    process.exitCode = 1;
  } finally {
    if (cleanup && baseDir) {
      await rmrf(baseDir);
    }
  }
})();
