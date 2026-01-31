#!/usr/bin/env node
'use strict';

const fs = require('fs/promises');
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
  return (
    buf.length >= 8 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47 &&
    buf[4] === 0x0D && buf[5] === 0x0A && buf[6] === 0x1A && buf[7] === 0x0A
  );
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
    // Try strict first, then fall back to ignoreEncryption for owner-password-only PDFs
    try {
      await PDFDocument.load(pdfBytes, { ignoreEncryption: false });
    } catch (encErr) {
      if (encErr.message && encErr.message.includes('encrypted')) {
        process.stderr.write(`[strict-merge] WARN: ${name} is encrypted (owner-password), loading with ignoreEncryption\n`);
        const doc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
        if (doc.getPageCount() <= 0) {
          throw new Error(`Encrypted PDF has 0 pages: ${name}`);
        }
        return; // readable with ignoreEncryption
      }
      throw encErr; // re-throw non-encryption errors
    }
  } catch (e) {
    const err = new Error(`PDF not readable: ${name}`);
    err.cause = e;
    throw err;
  }
}

// --- strict rm -rf (no swallowing) ---
async function rmrfStrict(p) {
  if (!p) return;
  try {
    await fs.rm(p, { recursive: true, force: false });
  } catch (e) {
    if (e && (e.code === 'ENOENT')) return;
    throw e;
  }
}

// --- main ---
(async () => {
  const args = parseArgs(process.argv);

  const baseDir = args.base || null;
  const inDir = args.dir || (baseDir ? path.join(baseDir, 'in') : null);
  const outPath = args.out || (baseDir ? path.join(baseDir, 'out', 'merged.pdf') : null);
  const emitBase64 = args.emitBase64 === true || args.emitBase64 === 'true';
  const cleanupOnError = args.cleanupOnError === true || args.cleanupOnError === 'true';

  if (!inDir) throw new Error('Missing --base or --dir');
  if (!outPath && !emitBase64) throw new Error('Missing --out (or use --emitBase64 true)');

  let needCleanup = false;

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
        const src = await PDFDocument.load(bytes, { ignoreEncryption: true });
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

    if (outPath) {
      await fs.mkdir(path.dirname(outPath), { recursive: true });
      const tmp = `${outPath}.tmp-${process.pid}`;
      await fs.writeFile(tmp, outBytes);
      await fs.rename(tmp, outPath);
    }

    const fileSize = outBytes.length;

    if (emitBase64) {
      process.stdout.write(Buffer.from(outBytes).toString('base64'));
    } else {
      const payload = {
        ok: true,
        pages: pageCount,
        fileSize,
        outPath: outPath || null,
        baseDir: baseDir || null,
        inDir,
      };
      process.stdout.write(JSON.stringify(payload));
    }

    process.exit(0);
  } catch (e) {
    needCleanup = true;
    process.stderr.write(`[strict-merge] ERROR: ${String(e?.stack || e)}\n`);
    process.exitCode = 1;
  } finally {
    if (cleanupOnError && needCleanup && baseDir) {
      await rmrfStrict(baseDir);
    }
  }
})();
