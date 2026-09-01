// Stroke model and rendering.
// A stroke is { id, tool, color, size, points: [[x, y, pressure], ...] } in page coordinates.

import { drawTemplate, PAGE } from './templates.js';

const HIGHLIGHTER_ALPHA = 0.38;
const HIGHLIGHTER_WIDTH = 2.6; // multiplier on the chosen size

const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];

/** Pen width tapers with pencil pressure; a flat 0.5 is used for mouse/finger. */
const penWidth = (size, pressure) => size * (0.35 + 0.85 * pressure);

export function drawStroke(ctx, stroke) {
  const pts = stroke.points;
  if (!pts || pts.length === 0) return;

  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.strokeStyle = stroke.color;
  ctx.fillStyle = stroke.color;

  if (stroke.tool === 'highlighter') {
    ctx.globalAlpha = HIGHLIGHTER_ALPHA;
    ctx.lineWidth = stroke.size * HIGHLIGHTER_WIDTH;
    // One continuous path, so the stroke never blends with itself.
    ctx.beginPath();
    if (pts.length === 1) {
      ctx.moveTo(pts[0][0], pts[0][1]);
      ctx.lineTo(pts[0][0] + 0.01, pts[0][1]);
    } else {
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length - 1; i++) {
        const m = mid(pts[i], pts[i + 1]);
        ctx.quadraticCurveTo(pts[i][0], pts[i][1], m[0], m[1]);
      }
      const last = pts[pts.length - 1];
      ctx.lineTo(last[0], last[1]);
    }
    ctx.stroke();
    ctx.restore();
    return;
  }

  // Pen: each segment gets its own width so pressure shows through.
  if (pts.length === 1) {
    ctx.beginPath();
    ctx.arc(pts[0][0], pts[0][1], penWidth(stroke.size, pts[0][2]) / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
    return;
  }

  for (let i = 1; i < pts.length; i++) {
    const prev = pts[i - 1];
    const cur = pts[i];
    const from = i === 1 ? prev : mid(prev, cur);
    const to = i === pts.length - 1 ? cur : mid(cur, pts[i + 1] || cur);

    ctx.beginPath();
    ctx.lineWidth = Math.max(0.4, penWidth(stroke.size, (prev[2] + cur[2]) / 2));
    ctx.moveTo(from[0], from[1]);
    ctx.quadraticCurveTo(cur[0], cur[1], to[0], to[1]);
    ctx.stroke();
  }

  ctx.restore();
}

/** Repaint a whole layer of committed strokes. */
export function drawStrokes(ctx, strokes, w = PAGE.w, h = PAGE.h) {
  ctx.clearRect(0, 0, w, h);
  for (const stroke of strokes) drawStroke(ctx, stroke);
}

function distanceToSegment(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const denom = dx * dx + dy * dy;
  let t = denom === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / denom;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

/** True when an eraser at (x, y) with the given radius touches this stroke. */
export function strokeHitsPoint(stroke, x, y, radius) {
  const pts = stroke.points;
  const width = stroke.tool === 'highlighter' ? stroke.size * HIGHLIGHTER_WIDTH : stroke.size;
  const reach = radius + width / 2;

  if (pts.length === 1) return Math.hypot(x - pts[0][0], y - pts[0][1]) <= reach;
  for (let i = 1; i < pts.length; i++) {
    if (distanceToSegment(x, y, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]) <= reach) {
      return true;
    }
  }
  return false;
}

/** Paint text annotations onto a canvas (used for thumbnails, export and AI). */
export function drawTextBoxes(ctx, boxes) {
  if (!boxes || !boxes.length) return;
  ctx.save();
  ctx.textBaseline = 'top';
  for (const box of boxes) {
    if (!box.text) continue;
    ctx.fillStyle = box.color || '#111827';
    ctx.font = `${box.fontSize || 18}px -apple-system, "Helvetica Neue", Arial, sans-serif`;
    const lineHeight = (box.fontSize || 18) * 1.35;
    let y = box.y;
    for (const paragraph of String(box.text).split('\n')) {
      for (const line of wrapText(ctx, paragraph, box.width || 240)) {
        ctx.fillText(line, box.x, y);
        y += lineHeight;
      }
    }
  }
  ctx.restore();
}

function wrapText(ctx, text, maxWidth) {
  if (!text) return [''];
  const words = text.split(/\s+/);
  const lines = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (ctx.measureText(candidate).width > maxWidth && line) {
      lines.push(line);
      line = word;
    } else {
      line = candidate;
    }
  }
  lines.push(line);
  return lines;
}

/**
 * Render a complete page (paper + ink + typed text) into a canvas.
 * Used by page thumbnails, PNG export and the image sent to Claude.
 */
export function renderPage(canvas, page, { scale = 1 } = {}) {
  canvas.width = Math.round(PAGE.w * scale);
  canvas.height = Math.round(PAGE.h * scale);
  const ctx = canvas.getContext('2d');
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  drawTemplate(ctx, page.template, PAGE.w, PAGE.h);
  for (const stroke of page.strokes || []) drawStroke(ctx, stroke);
  drawTextBoxes(ctx, page.textBoxes);
  return canvas;
}
