#!/usr/bin/env node
'use strict';

const fs = require('fs/promises');
const path = require('path');
const { PDFDocument } = require('pdf-lib');

const A4_W = 595.28;
const A4_H = 841.89;
const MARGIN = 24;

function die(msg, err) {
  const extra = err ? `\n${err.stack || err}` : '';
  process.stderr.write(`[strict-merge] ERROR: ${msg}${extra}\n`);
  process.exit(1);
}

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

function isPdf(buf) {
  return buf.length >= 5 && buf[0] === 0x25 && buf[1] === 0x50 && buf[2] === 0x44 && buf[3] === 0x46 && buf[4] === 0x2d;
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
  const page = doc.addPage([A4_W, A4_H]);
  return page;
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
    die(`PDF not readable or encrypted: ${name}`, e);
  }
}

(async () => {
  const args = parseArgs(process.argv);
  const inDir = args.dir;
  const outPath = args.out;

  if (!inDir) die('Missing --dir');
  if (!outPath) die('Missing --out');

  const files = await listSortedFiles(inDir);
  if (!files.length) die(`No input files in: ${inDir}`);

  const outPdf = await PDFDocument.create();

  for (const fp of files) {
    const name = path.basename(fp);
    const st = await fs.stat(fp).catch((e) => die(`Input not found: ${fp}`, e));
    if (!st.isFile()) die(`Not a file: ${fp}`);
    if (st.size <= 0) die(`Empty file: ${fp}`);
    if (st.size > 80 * 1024 * 1024) die(`File too large (>80MB): ${name}`);

    const bytes = await fs.readFile(fp);

    if (isPdf(bytes)) {
      await ensurePdfReadable(bytes, name);
      const src = await PDFDocument.load(bytes, { ignoreEncryption: false }).catch((e) => die(`Failed to load PDF: ${name}`, e));
      const pages = await outPdf.copyPages(src, src.getPageIndices()).catch((e) => die(`Failed to copy PDF pages: ${name}`, e));
      for (const p of pages) outPdf.addPage(p);
      continue;
    }

    if (isJpeg(bytes)) {
      const img = await outPdf.embedJpg(bytes).catch((e) => die(`Failed to embed JPG: ${name}`, e));
      const { width, height } = img.size();
      if (!(width > 0 && height > 0)) die(`Bad JPG dimensions: ${name} ${width}x${height}`);
      const page = addA4Page(outPdf);
      const { x, y, w, h } = fitToA4(width, height);
      page.drawImage(img, { x, y, width: w, height: h });
      continue;
    }

    if (isPng(bytes)) {
      const img = await outPdf.embedPng(bytes).catch((e) => die(`Failed to embed PNG: ${name}`, e));
      const { width, height } = img.size();
      if (!(width > 0 && height > 0)) die(`Bad PNG dimensions: ${name} ${width}x${height}`);
      const page = addA4Page(outPdf);
      const { x, y, w, h } = fitToA4(width, height);
      page.drawImage(img, { x, y, width: w, height: h });
      continue;
    }

    die(`Unsupported type (need PDF/PNG/JPEG): ${name}`);
  }

  const pageCount = outPdf.getPageCount();
  if (pageCount <= 0) die('Output has 0 pages');

  const outBytes = await outPdf.save().catch((e) => die('Failed to save output PDF', e));

  await fs.mkdir(path.dirname(outPath), { recursive: true });
  const tmp = `${outPath}.tmp-${process.pid}`;
  await fs.writeFile(tmp, outBytes).catch((e) => die(`Failed to write tmp: ${tmp}`, e));
  await fs.rename(tmp, outPath).catch((e) => die(`Failed to rename to output: ${outPath}`, e));

  process.stdout.write(`[strict-merge] OK pages=${pageCount} bytes=${outBytes.length}\n`);
  process.exit(0);
})().catch((e) => die('Unhandled top-level error', e));
