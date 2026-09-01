// Paper templates, drawn straight onto a 2D canvas context.
// Geometry mirrors the native app so a page looks the same in both.

export const PAGE = { w: 816, h: 1056 }; // US Letter at 96dpi

export const TEMPLATES = [
  { id: 'blank', name: 'Blank' },
  { id: 'linedNarrow', name: 'Lined · narrow' },
  { id: 'linedWide', name: 'Lined · college' },
  { id: 'gridSmall', name: 'Grid · small' },
  { id: 'gridLarge', name: 'Grid · large' },
  { id: 'dotted', name: 'Dotted' },
  { id: 'cornell', name: 'Cornell notes' },
  { id: 'checklist', name: 'Checklist' },
];

const LINE = 'rgba(99, 112, 133, 0.34)';
const MARGIN = 'rgba(214, 84, 84, 0.32)';

function hLines(ctx, w, h, spacing, from = 0) {
  ctx.beginPath();
  for (let y = spacing; y < h; y += spacing) {
    ctx.moveTo(from, y);
    ctx.lineTo(w, y);
  }
  ctx.stroke();
}

function vLines(ctx, w, h, spacing) {
  ctx.beginPath();
  for (let x = spacing; x < w; x += spacing) {
    ctx.moveTo(x, 0);
    ctx.lineTo(x, h);
  }
  ctx.stroke();
}

function marginRule(ctx, h, x) {
  ctx.save();
  ctx.strokeStyle = MARGIN;
  ctx.beginPath();
  ctx.moveTo(x, 0);
  ctx.lineTo(x, h);
  ctx.stroke();
  ctx.restore();
}

/** Paint the paper (white ground plus the template's rules) at page scale. */
export function drawTemplate(ctx, templateId, w = PAGE.w, h = PAGE.h) {
  ctx.save();
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, w, h);

  ctx.strokeStyle = LINE;
  ctx.lineWidth = 1;

  switch (templateId) {
    case 'linedNarrow':
      hLines(ctx, w, h, 32);
      marginRule(ctx, h, 74);
      break;

    case 'linedWide':
      hLines(ctx, w, h, 42);
      marginRule(ctx, h, 74);
      break;

    case 'gridSmall':
      vLines(ctx, w, h, 24);
      hLines(ctx, w, h, 24);
      break;

    case 'gridLarge':
      vLines(ctx, w, h, 42);
      hLines(ctx, w, h, 42);
      break;

    case 'dotted': {
      const spacing = 32;
      ctx.fillStyle = LINE;
      for (let y = spacing; y < h; y += spacing) {
        for (let x = spacing; x < w; x += spacing) {
          ctx.beginPath();
          ctx.arc(x, y, 1.4, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      break;
    }

    case 'cornell': {
      const cue = w * 0.28;
      const summary = 120;
      ctx.save();
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(cue, 0);
      ctx.lineTo(cue, h - summary);
      ctx.moveTo(0, h - summary);
      ctx.lineTo(w, h - summary);
      ctx.stroke();
      ctx.restore();

      ctx.beginPath();
      for (let y = 42; y < h - summary; y += 37) {
        ctx.moveTo(cue, y);
        ctx.lineTo(w, y);
      }
      ctx.stroke();
      break;
    }

    case 'checklist': {
      const spacing = 48;
      for (let y = spacing; y < h; y += spacing) {
        ctx.beginPath();
        ctx.roundRect ? ctx.roundRect(22, y - 16, 21, 21, 4) : ctx.rect(22, y - 16, 21, 21);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(58, y);
        ctx.lineTo(w - 22, y);
        ctx.stroke();
      }
      break;
    }

    case 'blank':
    default:
      break;
  }

  ctx.restore();
}

export const templateName = (id) => (TEMPLATES.find((t) => t.id === id) || TEMPLATES[0]).name;
