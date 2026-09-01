import { db, uid } from './db.js';
import { PAGE, TEMPLATES, drawTemplate, templateName } from './templates.js';
import { drawStroke, drawStrokes, strokeHitsPoint, renderPage } from './ink.js';
import { MODELS, askClaude } from './ai.js';

/* ── Constants ──────────────────────────────────────────────────── */

const COVER_COLORS = [
  { id: 'slate', hex: '#475569' },
  { id: 'red', hex: '#dc2626' },
  { id: 'orange', hex: '#ea580c' },
  { id: 'amber', hex: '#d97706' },
  { id: 'green', hex: '#16a34a' },
  { id: 'teal', hex: '#0d9488' },
  { id: 'blue', hex: '#2563eb' },
  { id: 'indigo', hex: '#4f46e5' },
  { id: 'purple', hex: '#7c3aed' },
  { id: 'pink', hex: '#db2777' },
];

const INK_COLORS = ['#111827', '#1d4ed8', '#dc2626', '#15803d', '#b45309', '#7c3aed', '#0891b2', '#eab308'];

const ERASER_RADIUS = 9;
const MAX_UNDO = 80;

/* ── State ──────────────────────────────────────────────────────── */

const state = {
  folders: [],
  notebooks: [],
  selectedFolderId: null,
  showAll: true,
  expanded: new Set(),

  notebook: null,
  pages: [],
  pageIndex: 0,

  tool: 'pen',
  color: INK_COLORS[0],
  size: 3,
  zoom: 1,
  pencilOnly: false,

  undo: [],
  redo: [],
};

const settings = {
  get(key, fallback = null) {
    try {
      const raw = localStorage.getItem(`inkwell.${key}`);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (_) {
      return fallback;
    }
  },
  set(key, value) {
    try {
      localStorage.setItem(`inkwell.${key}`, JSON.stringify(value));
    } catch (_) {
      /* private mode or full quota — settings just won't stick */
    }
  },
};

/* ── Element lookups ────────────────────────────────────────────── */

const $ = (sel) => document.querySelector(sel);
const el = {
  library: $('#library'),
  editor: $('#editor'),
  folderList: $('#folder-list'),
  notebookGrid: $('#notebook-grid'),
  libTitle: $('#lib-title'),
  libEmpty: $('#lib-empty'),
  sidebarScrim: $('#sidebar-scrim'),

  editorTitle: $('#editor-title'),
  wrap: $('#canvas-wrap'),
  stage: $('#page-stage'),
  bg: $('#bg-canvas'),
  ink: $('#ink-canvas'),
  live: $('#live-canvas'),
  textLayer: $('#text-layer'),
  strip: $('#pages-strip'),
  swatches: $('#swatches'),
  sizeSlider: $('#size-slider'),
  zoomLabel: $('#btn-zoom-level'),
  toast: $('#toast'),
};

const ctx = {
  bg: el.bg.getContext('2d'),
  ink: el.ink.getContext('2d'),
  live: el.live.getContext('2d'),
};

/* ── Small helpers ──────────────────────────────────────────────── */

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const coverHex = (id) => (COVER_COLORS.find((c) => c.id === id) || COVER_COLORS[6]).hex;

let toastTimer = null;
function toast(message) {
  el.toast.textContent = message;
  el.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.toast.hidden = true;
  }, 3200);
}

function askText(title, initial = '') {
  const dlg = $('#dlg-prompt');
  $('#prompt-title').textContent = title;
  const input = $('#prompt-input');
  input.value = initial;
  dlg.showModal();
  input.select();
  return new Promise((resolve) => {
    dlg.addEventListener(
      'close',
      () => resolve(dlg.returnValue === 'ok' ? input.value.trim() : null),
      { once: true }
    );
  });
}

function actionSheet(title, actions) {
  const dlg = $('#dlg-menu');
  $('#menu-title').textContent = title;
  const host = $('#menu-actions');
  host.textContent = '';
  return new Promise((resolve) => {
    let picked = null;
    actions.forEach((action) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = action.label;
      if (action.danger) b.className = 'danger';
      b.addEventListener('click', () => {
        picked = action.id;
        dlg.close();
      });
      host.appendChild(b);
    });
    dlg.addEventListener('close', () => resolve(picked), { once: true });
    $('#menu-cancel').onclick = () => dlg.close();
    dlg.showModal();
  });
}

function templatePicker(host, selectedId, onPick) {
  host.textContent = '';
  TEMPLATES.forEach((tpl) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'template-opt';
    btn.setAttribute('aria-pressed', String(tpl.id === selectedId));
    btn.dataset.id = tpl.id;

    const canvas = document.createElement('canvas');
    canvas.width = 120;
    canvas.height = 156;
    const c = canvas.getContext('2d');
    c.setTransform(120 / PAGE.w, 0, 0, 156 / PAGE.h, 0, 0);
    drawTemplate(c, tpl.id);

    const label = document.createElement('span');
    label.textContent = tpl.name;

    btn.append(canvas, label);
    btn.addEventListener('click', () => {
      host.querySelectorAll('.template-opt').forEach((b) => b.setAttribute('aria-pressed', 'false'));
      btn.setAttribute('aria-pressed', 'true');
      onPick(tpl.id);
    });
    host.appendChild(btn);
  });
}

/* ── Library: folders ───────────────────────────────────────────── */

function childrenOf(parentId) {
  return state.folders
    .filter((f) => (f.parentId || null) === parentId)
    .sort((a, b) => a.name.localeCompare(b.name));
}

function notebooksIn(folderId) {
  return state.notebooks.filter((n) => (n.folderId || null) === folderId);
}

function renderFolders() {
  el.folderList.textContent = '';

  const allRow = document.createElement('div');
  allRow.className = 'folder-row' + (state.showAll ? ' selected' : '');
  allRow.innerHTML = '<span class="twisty"></span><span class="dot" style="background:#94a3b8"></span>';
  const allName = document.createElement('span');
  allName.className = 'name';
  allName.textContent = 'All notebooks';
  const allCount = document.createElement('span');
  allCount.className = 'count';
  allCount.textContent = String(state.notebooks.length);
  allRow.append(allName, allCount);
  allRow.addEventListener('click', () => {
    state.showAll = true;
    state.selectedFolderId = null;
    renderFolders();
    renderNotebooks();
    closeSidebar();
  });
  el.folderList.appendChild(allRow);

  const build = (parentId, host) => {
    childrenOf(parentId).forEach((folder) => {
      const kids = childrenOf(folder.id);
      const row = document.createElement('div');
      row.className =
        'folder-row' + (!state.showAll && state.selectedFolderId === folder.id ? ' selected' : '');

      const twisty = document.createElement('span');
      twisty.className = 'twisty' + (state.expanded.has(folder.id) ? ' open' : '');
      twisty.textContent = kids.length ? '▶' : '';
      twisty.addEventListener('click', (e) => {
        e.stopPropagation();
        if (!kids.length) return;
        state.expanded.has(folder.id)
          ? state.expanded.delete(folder.id)
          : state.expanded.add(folder.id);
        renderFolders();
      });

      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = coverHex(folder.color);

      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = folder.name;

      const count = document.createElement('span');
      count.className = 'count';
      count.textContent = String(notebooksIn(folder.id).length || '');

      const more = document.createElement('button');
      more.className = 'more';
      more.type = 'button';
      more.textContent = '⋯';
      more.addEventListener('click', (e) => {
        e.stopPropagation();
        folderMenu(folder);
      });

      row.append(twisty, dot, name, count, more);
      row.addEventListener('click', () => {
        state.showAll = false;
        state.selectedFolderId = folder.id;
        renderFolders();
        renderNotebooks();
        closeSidebar();
      });
      host.appendChild(row);

      if (kids.length && state.expanded.has(folder.id)) {
        const sub = document.createElement('div');
        sub.className = 'folder-children';
        build(folder.id, sub);
        host.appendChild(sub);
      }
    });
  };

  build(null, el.folderList);
}

async function folderMenu(folder) {
  const choice = await actionSheet(folder.name, [
    { id: 'rename', label: 'Rename' },
    { id: 'subfolder', label: 'New folder inside' },
    { id: 'color', label: 'Change colour' },
    { id: 'delete', label: 'Delete folder and its notebooks', danger: true },
  ]);
  if (!choice) return;

  if (choice === 'rename') {
    const name = await askText('Rename folder', folder.name);
    if (name) {
      folder.name = name;
      await db.put('folders', folder);
    }
  } else if (choice === 'subfolder') {
    const name = await askText('New folder');
    if (name) {
      await db.put('folders', {
        id: uid(),
        name,
        parentId: folder.id,
        color: COVER_COLORS[Math.floor(Math.random() * COVER_COLORS.length)].id,
        createdAt: Date.now(),
      });
      state.expanded.add(folder.id);
    }
  } else if (choice === 'color') {
    const pick = await actionSheet(
      'Folder colour',
      COVER_COLORS.map((c) => ({ id: c.id, label: c.id[0].toUpperCase() + c.id.slice(1) }))
    );
    if (pick) {
      folder.color = pick;
      await db.put('folders', folder);
    }
  } else if (choice === 'delete') {
    const confirmed = await actionSheet(`Delete “${folder.name}”?`, [
      { id: 'yes', label: 'Delete folder, subfolders and notebooks', danger: true },
    ]);
    if (confirmed !== 'yes') return;
    await deleteFolderDeep(folder.id);
    if (state.selectedFolderId === folder.id) {
      state.showAll = true;
      state.selectedFolderId = null;
    }
  }

  await loadLibrary();
}

async function deleteFolderDeep(folderId) {
  for (const child of childrenOf(folderId)) await deleteFolderDeep(child.id);
  for (const notebook of notebooksIn(folderId)) await deleteNotebook(notebook.id);
  await db.del('folders', folderId);
}

async function deleteNotebook(notebookId) {
  const pages = await db.byIndex('pages', 'notebookId', notebookId);
  await db.delMany('pages', pages.map((p) => p.id));
  await db.del('notebooks', notebookId);
}

/* ── Library: notebooks ─────────────────────────────────────────── */

function visibleNotebooks() {
  const list = state.showAll ? state.notebooks.slice() : notebooksIn(state.selectedFolderId);
  return list.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}

function renderNotebooks() {
  const folder = state.folders.find((f) => f.id === state.selectedFolderId);
  el.libTitle.textContent = state.showAll ? 'All notebooks' : folder ? folder.name : 'Notebooks';

  const list = visibleNotebooks();
  el.notebookGrid.textContent = '';
  el.libEmpty.hidden = list.length > 0;

  list.forEach((notebook) => {
    const card = document.createElement('div');
    card.className = 'nb-card';

    const cover = document.createElement('div');
    cover.className = 'nb-cover';
    const hex = coverHex(notebook.color);
    cover.style.background = `linear-gradient(150deg, ${hex}, ${hex}cc 60%, ${hex}99)`;

    const paper = document.createElement('div');
    paper.className = 'paper';
    paper.textContent = templateName(notebook.template);

    const pages = document.createElement('div');
    pages.className = 'pages';
    const count = notebook.pageCount || 0;
    pages.textContent = `${count} page${count === 1 ? '' : 's'}`;

    cover.append(paper, pages);

    const title = document.createElement('div');
    title.className = 'title';
    title.textContent = notebook.title;

    const sub = document.createElement('div');
    sub.className = 'sub';
    const when = document.createElement('span');
    when.textContent = relativeTime(notebook.updatedAt);
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'more';
    more.textContent = '⋯';
    more.addEventListener('click', (e) => {
      e.stopPropagation();
      notebookMenu(notebook);
    });
    sub.append(when, more);

    card.append(cover, title, sub);
    card.addEventListener('click', () => openNotebook(notebook.id));
    el.notebookGrid.appendChild(card);
  });
}

function relativeTime(ts) {
  if (!ts) return '';
  const mins = Math.round((Date.now() - ts) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  if (days < 30) return `${days} day${days === 1 ? '' : 's'} ago`;
  return new Date(ts).toLocaleDateString();
}

async function notebookMenu(notebook) {
  const folderOptions = state.folders.map((f) => ({ id: `move:${f.id}`, label: `Move to ${f.name}` }));
  const choice = await actionSheet(notebook.title, [
    { id: 'rename', label: 'Rename' },
    ...(notebook.folderId ? [{ id: 'move:none', label: 'Move out of folder' }] : []),
    ...folderOptions.filter((o) => o.id !== `move:${notebook.folderId}`),
    { id: 'delete', label: 'Delete notebook', danger: true },
  ]);
  if (!choice) return;

  if (choice === 'rename') {
    const title = await askText('Rename notebook', notebook.title);
    if (title) {
      notebook.title = title;
      await db.put('notebooks', notebook);
    }
  } else if (choice.startsWith('move:')) {
    const target = choice.slice(5);
    notebook.folderId = target === 'none' ? null : target;
    await db.put('notebooks', notebook);
  } else if (choice === 'delete') {
    const confirmed = await actionSheet(`Delete “${notebook.title}”?`, [
      { id: 'yes', label: 'Delete notebook and all its pages', danger: true },
    ]);
    if (confirmed !== 'yes') return;
    await deleteNotebook(notebook.id);
  }

  await loadLibrary();
}

async function loadLibrary() {
  state.folders = await db.all('folders');
  state.notebooks = await db.all('notebooks');
  renderFolders();
  renderNotebooks();
}

/* ── New notebook dialog ────────────────────────────────────────── */

let newNotebookDraft = { color: COVER_COLORS[6].id, template: 'linedWide' };

function openNewNotebook() {
  newNotebookDraft = { color: COVER_COLORS[6].id, template: 'linedWide' };
  $('#nb-title').value = '';

  const colors = $('#nb-colors');
  colors.textContent = '';
  COVER_COLORS.forEach((c) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.style.background = c.hex;
    b.setAttribute('aria-pressed', String(c.id === newNotebookDraft.color));
    b.addEventListener('click', () => {
      newNotebookDraft.color = c.id;
      colors.querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', 'false'));
      b.setAttribute('aria-pressed', 'true');
    });
    colors.appendChild(b);
  });

  templatePicker($('#nb-templates'), newNotebookDraft.template, (id) => {
    newNotebookDraft.template = id;
  });

  const dlg = $('#dlg-notebook');
  dlg.showModal();
  dlg.addEventListener(
    'close',
    async () => {
      if (dlg.returnValue !== 'create') return;
      const title = $('#nb-title').value.trim() || 'Untitled';
      const notebookId = uid();
      const now = Date.now();
      await db.put('notebooks', {
        id: notebookId,
        title,
        folderId: state.showAll ? null : state.selectedFolderId,
        color: newNotebookDraft.color,
        template: newNotebookDraft.template,
        pageCount: 1,
        createdAt: now,
        updatedAt: now,
      });
      await db.put('pages', blankPage(notebookId, 0, newNotebookDraft.template));
      await loadLibrary();
      openNotebook(notebookId);
    },
    { once: true }
  );
}

function blankPage(notebookId, index, template) {
  return {
    id: uid(),
    notebookId,
    index,
    template,
    strokes: [],
    textBoxes: [],
    updatedAt: Date.now(),
  };
}

/* ── Editor: open / close ───────────────────────────────────────── */

async function openNotebook(notebookId) {
  const notebook = await db.get('notebooks', notebookId);
  if (!notebook) return;
  const pages = (await db.byIndex('pages', 'notebookId', notebookId)).sort((a, b) => a.index - b.index);
  if (!pages.length) pages.push(blankPage(notebookId, 0, notebook.template));

  state.notebook = notebook;
  state.pages = pages;
  state.pageIndex = 0;
  state.undo = [];
  state.redo = [];
  state.zoom = 1;

  el.editorTitle.textContent = notebook.title;
  el.library.hidden = true;
  el.editor.hidden = false;

  layout();
  renderStrip();
  updateUndoButtons();
  // Start with the page fitted to the available width on small screens.
  fitWidth();
}

function closeEditor() {
  flushSave();
  state.notebook = null;
  el.editor.hidden = true;
  el.library.hidden = false;
  loadLibrary();
}

const currentPage = () => state.pages[state.pageIndex];

/* ── Editor: layout and rendering ───────────────────────────────── */

function layout() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const scale = Math.min(dpr * state.zoom, 4);

  el.stage.style.width = `${PAGE.w * state.zoom}px`;
  el.stage.style.height = `${PAGE.h * state.zoom}px`;

  for (const canvas of [el.bg, el.ink, el.live]) {
    canvas.width = Math.round(PAGE.w * scale);
    canvas.height = Math.round(PAGE.h * scale);
    canvas.getContext('2d').setTransform(scale, 0, 0, scale, 0, 0);
  }

  el.textLayer.style.width = `${PAGE.w}px`;
  el.textLayer.style.height = `${PAGE.h}px`;
  el.textLayer.style.transform = `scale(${state.zoom})`;

  el.zoomLabel.textContent = `${Math.round(state.zoom * 100)}%`;
  redraw();
  renderTextBoxes();
}

function redraw() {
  const page = currentPage();
  if (!page) return;
  drawTemplate(ctx.bg, page.template);
  drawStrokes(ctx.ink, page.strokes);
  ctx.live.clearRect(0, 0, PAGE.w, PAGE.h);
}

function setZoom(next) {
  const wrap = el.wrap;
  const oldZoom = state.zoom;
  const clamped = clamp(next, 0.25, 4);
  if (Math.abs(clamped - oldZoom) < 0.001) return;

  // Keep whatever is in the middle of the viewport in the middle.
  const midX = wrap.scrollLeft + wrap.clientWidth / 2;
  const midY = wrap.scrollTop + wrap.clientHeight / 2;
  const ratio = clamped / oldZoom;

  state.zoom = clamped;
  layout();

  wrap.scrollLeft = midX * ratio - wrap.clientWidth / 2;
  wrap.scrollTop = midY * ratio - wrap.clientHeight / 2;
}

function fitWidth() {
  const available = el.wrap.clientWidth - 48;
  if (available > 100) setZoom(clamp(available / PAGE.w, 0.25, 1));
}

/* ── Editor: saving ─────────────────────────────────────────────── */

let saveTimer = null;
function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flushSave, 400);
}

async function flushSave() {
  clearTimeout(saveTimer);
  const page = currentPage();
  if (!page) return;
  page.updatedAt = Date.now();
  await db.put('pages', page);
  if (state.notebook) {
    state.notebook.updatedAt = Date.now();
    state.notebook.pageCount = state.pages.length;
    await db.put('notebooks', state.notebook);
  }
}

window.addEventListener('pagehide', flushSave);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') flushSave();
});

/* ── Editor: undo / redo ────────────────────────────────────────── */

function pushUndo(entry) {
  state.undo.push(entry);
  if (state.undo.length > MAX_UNDO) state.undo.shift();
  state.redo.length = 0;
  updateUndoButtons();
}

function updateUndoButtons() {
  $('#btn-undo').disabled = state.undo.length === 0;
  $('#btn-redo').disabled = state.redo.length === 0;
}

function applyInverse(entry, forward) {
  const page = currentPage();
  const add = (entry.type === 'add') === forward;

  if (entry.type === 'add') {
    if (add) page.strokes.push(entry.stroke);
    else page.strokes = page.strokes.filter((s) => s.id !== entry.stroke.id);
  } else if (entry.type === 'erase') {
    if (forward) {
      // redo the erase
      const ids = new Set(entry.items.map((i) => i.stroke.id));
      page.strokes = page.strokes.filter((s) => !ids.has(s.id));
    } else {
      entry.items
        .slice()
        .sort((a, b) => a.index - b.index)
        .forEach((item) => page.strokes.splice(item.index, 0, item.stroke));
    }
  } else if (entry.type === 'text-add') {
    if (forward) page.textBoxes.push(entry.box);
    else page.textBoxes = page.textBoxes.filter((b) => b.id !== entry.box.id);
    renderTextBoxes();
  } else if (entry.type === 'text-del') {
    if (forward) page.textBoxes = page.textBoxes.filter((b) => b.id !== entry.box.id);
    else page.textBoxes.push(entry.box);
    renderTextBoxes();
  }

  redraw();
  scheduleSave();
  refreshCurrentThumb();
}

function undo() {
  const entry = state.undo.pop();
  if (!entry) return;
  applyInverse(entry, false);
  state.redo.push(entry);
  updateUndoButtons();
}

function redo() {
  const entry = state.redo.pop();
  if (!entry) return;
  applyInverse(entry, true);
  state.undo.push(entry);
  updateUndoButtons();
}

/* ── Editor: pointer input ──────────────────────────────────────── */

const pointers = new Map();
let stroke = null;
let erased = null;
let gesture = null;
let panning = null;

function pagePoint(e) {
  const rect = el.stage.getBoundingClientRect();
  return {
    x: (e.clientX - rect.left) / state.zoom,
    y: (e.clientY - rect.top) / state.zoom,
  };
}

function pressureOf(e) {
  if (e.pointerType === 'pen') {
    // Pens report 0 while hovering; treat a real contact with no reading as medium.
    return e.pressure > 0 ? e.pressure : 0.5;
  }
  return 0.5;
}

function canDraw(e) {
  if (state.tool === 'text') return false;
  if (state.pencilOnly && e.pointerType !== 'pen') return false;
  return true;
}

// Palm rejection. A hand resting on the glass arrives as an ordinary touch
// pointer. Two things keep it from interfering: a touch can never interrupt
// a stroke the Pencil is drawing, and in pencil-only mode a *single* touch
// does nothing at all — panning and zooming take two fingers, the way they
// do in other note apps. That second rule is what makes this reliable, since
// contact-size reporting varies between browsers.
let penActive = false;
let lastPenAt = 0;
const PALM_CONTACT = 40; // CSS px; fingertips report well under this

function isPalmSized(e) {
  return e.width > PALM_CONTACT || e.height > PALM_CONTACT;
}

function shouldIgnoreTouch(e) {
  if (e.pointerType !== 'touch') return false;
  // Never let a touch interrupt a stroke that is being drawn.
  if (penActive) return true;
  // A contact patch this big is a hand, not a fingertip.
  return state.pencilOnly && isPalmSized(e);
}

el.stage.addEventListener('pointerdown', (e) => {
  if (!state.notebook) return;
  if (shouldIgnoreTouch(e)) return;

  if (e.pointerType === 'pen') {
    lastPenAt = Date.now();
    // The pencil takes over: abandon any pan or pinch a resting hand began.
    panning = null;
    if (gesture) {
      gesture = null;
      el.stage.style.transform = '';
    }
    for (const [id, info] of pointers) {
      if (info.type === 'touch') pointers.delete(id);
    }
  }

  pointers.set(e.pointerId, { x: e.clientX, y: e.clientY, type: e.pointerType });

  if (e.pointerType === 'pen' && !settings.get('sawPen', false)) {
    settings.set('sawPen', true);
    if (!state.pencilOnly) {
      setPencilOnly(true);
      toast('Apple Pencil detected — finger drawing is off. Change it in Settings.');
    }
  }

  // Two fingers means pinch/pan — but only fingers, and never mid-stroke.
  if (pointers.size >= 2 && !penActive) {
    cancelStroke();
    startGesture();
    return;
  }

  if (canDraw(e)) {
    if (e.pointerType === 'pen') penActive = true;
    if (state.tool === 'eraser') {
      erased = [];
      eraseAt(pagePoint(e));
    } else {
      const point = pagePoint(e);
      stroke = {
        id: uid(),
        tool: state.tool,
        color: state.color,
        size: state.size,
        points: [[point.x, point.y, pressureOf(e)]],
      };
      drawLive();
    }
  } else if (e.pointerType !== 'pen') {
    // In pencil-only mode a lone touch on the page is most likely the hand
    // resting there, so it scrolls nothing — two fingers pan instead.
    const lonePalmRisk = e.pointerType === 'touch' && state.pencilOnly && state.tool !== 'text';
    if (!lonePalmRisk) {
      panning = { x: e.clientX, y: e.clientY, left: el.wrap.scrollLeft, top: el.wrap.scrollTop };
    }
  }
});

window.addEventListener(
  'pointermove',
  (e) => {
    if (!pointers.has(e.pointerId)) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY, type: e.pointerType });
    if (e.pointerType === 'pen') lastPenAt = Date.now();

    if (gesture && pointers.size >= 2) {
      updateGesture();
      return;
    }

    if (stroke) {
      const events = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : [e];
      for (const ev of events.length ? events : [e]) {
        const point = pagePoint(ev);
        stroke.points.push([point.x, point.y, pressureOf(ev)]);
      }
      drawLive();
      return;
    }

    if (erased) {
      eraseAt(pagePoint(e));
      return;
    }

    if (panning) {
      el.wrap.scrollLeft = panning.left - (e.clientX - panning.x);
      el.wrap.scrollTop = panning.top - (e.clientY - panning.y);
    }
  },
  { passive: true }
);

function endPointer(e) {
  if (e.pointerType === 'pen') {
    penActive = false;
    lastPenAt = Date.now();
  }
  if (!pointers.has(e.pointerId)) return; // a palm we chose to ignore
  pointers.delete(e.pointerId);

  if (gesture && pointers.size < 2) commitGesture();

  // Only the hand is left on the glass — finish the stroke anyway.
  const onlyTouchesLeft = [...pointers.values()].every((p) => p.type === 'touch');

  if (stroke && (pointers.size === 0 || onlyTouchesLeft)) {
    const finished = stroke;
    stroke = null;
    ctx.live.clearRect(0, 0, PAGE.w, PAGE.h);
    if (finished.points.length) {
      currentPage().strokes.push(finished);
      drawStroke(ctx.ink, finished);
      pushUndo({ type: 'add', stroke: finished });
      scheduleSave();
      refreshCurrentThumb();
    }
  }

  if (erased && (pointers.size === 0 || onlyTouchesLeft)) {
    if (erased.length) {
      pushUndo({ type: 'erase', items: erased });
      scheduleSave();
      refreshCurrentThumb();
    }
    erased = null;
  }

  if (pointers.size === 0) panning = null;
}

window.addEventListener('pointerup', endPointer);
window.addEventListener('pointercancel', endPointer);

function cancelStroke() {
  if (!stroke) return;
  stroke = null;
  ctx.live.clearRect(0, 0, PAGE.w, PAGE.h);
}

function drawLive() {
  ctx.live.clearRect(0, 0, PAGE.w, PAGE.h);
  if (stroke) drawStroke(ctx.live, stroke);
}

function eraseAt(point) {
  const page = currentPage();
  const radius = ERASER_RADIUS / state.zoom;
  let hit = false;
  for (let i = page.strokes.length - 1; i >= 0; i--) {
    if (strokeHitsPoint(page.strokes[i], point.x, point.y, radius)) {
      erased.push({ index: i, stroke: page.strokes[i] });
      page.strokes.splice(i, 1);
      hit = true;
    }
  }
  if (hit) drawStrokes(ctx.ink, page.strokes);
}

/* ── Editor: pinch to zoom ──────────────────────────────────────── */

function startGesture() {
  const [a, b] = [...pointers.values()];
  gesture = {
    dist: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)),
    cx: (a.x + b.x) / 2,
    cy: (a.y + b.y) / 2,
    scale: 1,
    left: el.wrap.scrollLeft,
    top: el.wrap.scrollTop,
  };
}

function updateGesture() {
  const [a, b] = [...pointers.values()];
  const dist = Math.hypot(a.x - b.x, a.y - b.y);
  const cx = (a.x + b.x) / 2;
  const cy = (a.y + b.y) / 2;

  gesture.scale = clamp(dist / gesture.dist, 0.25 / state.zoom, 4 / state.zoom);
  el.stage.style.transform = `scale(${gesture.scale})`;
  el.wrap.scrollLeft = gesture.left - (cx - gesture.cx);
  el.wrap.scrollTop = gesture.top - (cy - gesture.cy);
}

function commitGesture() {
  const scale = gesture ? gesture.scale : 1;
  gesture = null;
  el.stage.style.transform = '';
  if (Math.abs(scale - 1) > 0.01) setZoom(state.zoom * scale);
}

/* ── Editor: text boxes ─────────────────────────────────────────── */

function renderTextBoxes() {
  const page = currentPage();
  el.textLayer.textContent = '';
  el.textLayer.classList.toggle('inactive', state.tool !== 'text');
  if (!page) return;

  page.textBoxes.forEach((box) => el.textLayer.appendChild(textBoxNode(box)));
}

function textBoxNode(box) {
  const node = document.createElement('div');
  node.className = 'text-box';
  node.style.left = `${box.x}px`;
  node.style.top = `${box.y}px`;
  node.style.width = `${box.width}px`;

  const bar = document.createElement('div');
  bar.className = 'tb-bar';
  const drag = document.createElement('button');
  drag.type = 'button';
  drag.className = 'drag';
  drag.textContent = '✥ drag';
  const del = document.createElement('button');
  del.type = 'button';
  del.textContent = '✕';

  const area = document.createElement('textarea');
  area.value = box.text;
  area.rows = 1;
  area.style.fontSize = `${box.fontSize}px`;
  area.style.color = box.color;

  const autosize = () => {
    area.style.height = 'auto';
    area.style.height = `${Math.max(28, area.scrollHeight)}px`;
  };

  area.addEventListener('input', () => {
    box.text = area.value;
    autosize();
    scheduleSave();
  });
  area.addEventListener('blur', () => {
    refreshCurrentThumb();
    if (!box.text.trim()) removeTextBox(box, false);
  });

  del.addEventListener('click', () => removeTextBox(box, true));

  drag.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    drag.setPointerCapture(e.pointerId);
    const start = { x: e.clientX, y: e.clientY, bx: box.x, by: box.y };
    const move = (ev) => {
      box.x = Math.max(0, start.bx + (ev.clientX - start.x) / state.zoom);
      box.y = Math.max(0, start.by + (ev.clientY - start.y) / state.zoom);
      node.style.left = `${box.x}px`;
      node.style.top = `${box.y}px`;
    };
    const up = () => {
      drag.removeEventListener('pointermove', move);
      drag.removeEventListener('pointerup', up);
      scheduleSave();
      refreshCurrentThumb();
    };
    drag.addEventListener('pointermove', move);
    drag.addEventListener('pointerup', up);
  });

  bar.append(drag, del);
  node.append(bar, area);
  requestAnimationFrame(autosize);
  return node;
}

function removeTextBox(box, undoable) {
  const page = currentPage();
  page.textBoxes = page.textBoxes.filter((b) => b.id !== box.id);
  if (undoable) pushUndo({ type: 'text-del', box });
  renderTextBoxes();
  scheduleSave();
  refreshCurrentThumb();
}

el.textLayer.addEventListener('pointerdown', (e) => {
  if (state.tool !== 'text' || e.target !== el.textLayer) return;
  // Without this the follow-up mousedown moves focus back to the page,
  // which blurs the brand new box and immediately discards it.
  e.preventDefault();

  const rect = el.textLayer.getBoundingClientRect();
  const box = {
    id: uid(),
    x: (e.clientX - rect.left) / state.zoom,
    y: (e.clientY - rect.top) / state.zoom,
    width: 240,
    fontSize: 18,
    color: '#111827',
    text: '',
  };
  currentPage().textBoxes.push(box);
  pushUndo({ type: 'text-add', box });

  const node = textBoxNode(box);
  el.textLayer.appendChild(node);
  // Focus synchronously so iOS treats it as part of the tap and opens the keyboard.
  node.querySelector('textarea').focus();
});

/* ── Editor: pages strip ────────────────────────────────────────── */

function renderStrip() {
  el.strip.textContent = '';
  state.pages.forEach((page, index) => {
    const item = document.createElement('div');
    item.className = 'page-thumb' + (index === state.pageIndex ? ' current' : '');
    const canvas = document.createElement('canvas');
    renderPage(canvas, page, { scale: 0.135 });
    const label = document.createElement('span');
    label.textContent = String(index + 1);
    item.append(canvas, label);
    item.addEventListener('click', () => goToPage(index));
    el.strip.appendChild(item);
  });

  const add = document.createElement('button');
  add.type = 'button';
  add.className = 'add-page';
  add.textContent = '＋';
  add.title = 'Add page';
  add.addEventListener('click', addPage);
  el.strip.appendChild(add);
}

function refreshCurrentThumb() {
  const item = el.strip.children[state.pageIndex];
  const canvas = item?.querySelector('canvas');
  if (canvas) renderPage(canvas, currentPage(), { scale: 0.135 });
}

async function goToPage(index) {
  if (index === state.pageIndex) return;
  await flushSave();
  state.pageIndex = clamp(index, 0, state.pages.length - 1);
  state.undo = [];
  state.redo = [];
  updateUndoButtons();
  redraw();
  renderTextBoxes();
  renderStrip();
  el.wrap.scrollTop = 0;
}

async function addPage() {
  await flushSave();
  const page = blankPage(state.notebook.id, state.pages.length, state.notebook.template);
  state.pages.push(page);
  await db.put('pages', page);
  state.notebook.pageCount = state.pages.length;
  await db.put('notebooks', state.notebook);
  state.pageIndex = state.pages.length - 1;
  state.undo = [];
  state.redo = [];
  redraw();
  renderTextBoxes();
  renderStrip();
}

async function deleteCurrentPage() {
  if (state.pages.length <= 1) {
    toast('A notebook needs at least one page.');
    return;
  }
  const confirmed = await actionSheet(`Delete page ${state.pageIndex + 1}?`, [
    { id: 'yes', label: 'Delete this page', danger: true },
  ]);
  if (confirmed !== 'yes') return;

  const [removed] = state.pages.splice(state.pageIndex, 1);
  await db.del('pages', removed.id);
  state.pages.forEach((page, i) => {
    page.index = i;
  });
  await db.putMany('pages', state.pages);
  state.notebook.pageCount = state.pages.length;
  await db.put('notebooks', state.notebook);

  state.pageIndex = clamp(state.pageIndex, 0, state.pages.length - 1);
  state.undo = [];
  state.redo = [];
  redraw();
  renderTextBoxes();
  renderStrip();
}

/* ── Editor: toolbar wiring ─────────────────────────────────────── */

function setTool(tool) {
  state.tool = tool;
  document.querySelectorAll('.tool-btn').forEach((b) => {
    b.setAttribute('aria-pressed', String(b.dataset.tool === tool));
  });
  el.textLayer.classList.toggle('inactive', tool !== 'text');
  el.sizeSlider.disabled = tool === 'text';
}

function setPencilOnly(on) {
  state.pencilOnly = on;
  settings.set('pencilOnly', on);
  $('#btn-pencil-only').setAttribute('aria-pressed', String(on));
  const box = $('#set-pencil-only');
  if (box) box.checked = on;
}

function buildSwatches() {
  el.swatches.textContent = '';
  INK_COLORS.forEach((hex) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'swatch';
    b.style.background = hex;
    b.setAttribute('aria-pressed', String(hex === state.color));
    b.title = hex;
    b.addEventListener('click', () => {
      state.color = hex;
      el.swatches.querySelectorAll('.swatch').forEach((s) => s.setAttribute('aria-pressed', 'false'));
      b.setAttribute('aria-pressed', 'true');
    });
    el.swatches.appendChild(b);
  });
}

document.querySelectorAll('.tool-btn').forEach((b) => {
  b.addEventListener('click', () => setTool(b.dataset.tool));
});

el.sizeSlider.addEventListener('input', () => {
  state.size = Number(el.sizeSlider.value);
});

$('#btn-undo').addEventListener('click', undo);
$('#btn-redo').addEventListener('click', redo);
$('#btn-back').addEventListener('click', closeEditor);
$('#btn-zoom-in').addEventListener('click', () => setZoom(state.zoom * 1.25));
$('#btn-zoom-out').addEventListener('click', () => setZoom(state.zoom / 1.25));
$('#btn-zoom-level').addEventListener('click', () => setZoom(1));
$('#btn-pencil-only').addEventListener('click', () => setPencilOnly(!state.pencilOnly));

$('#btn-page-menu').addEventListener('click', async () => {
  const choice = await actionSheet(`Page ${state.pageIndex + 1} of ${state.pages.length}`, [
    { id: 'add', label: 'Add page after this one' },
    { id: 'export', label: 'Export this page as PNG' },
    { id: 'fit', label: 'Fit page to width' },
    { id: 'rename', label: 'Rename notebook' },
    { id: 'delete', label: 'Delete this page', danger: true },
  ]);
  if (choice === 'add') addPage();
  else if (choice === 'export') exportPagePNG();
  else if (choice === 'fit') fitWidth();
  else if (choice === 'delete') deleteCurrentPage();
  else if (choice === 'rename') {
    const title = await askText('Rename notebook', state.notebook.title);
    if (title) {
      state.notebook.title = title;
      el.editorTitle.textContent = title;
      await db.put('notebooks', state.notebook);
    }
  }
});

function exportPagePNG() {
  const canvas = document.createElement('canvas');
  renderPage(canvas, currentPage(), { scale: 2 });
  canvas.toBlob((blob) => {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${state.notebook.title} p${state.pageIndex + 1}.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }, 'image/png');
}

$('#btn-template').addEventListener('click', () => {
  const page = currentPage();
  let chosen = page.template;
  templatePicker($('#page-templates'), chosen, (id) => {
    chosen = id;
  });
  const dlg = $('#dlg-template');
  dlg.showModal();
  dlg.addEventListener(
    'close',
    async () => {
      if (dlg.returnValue === 'apply') {
        page.template = chosen;
        redraw();
        refreshCurrentThumb();
        await flushSave();
      } else if (dlg.returnValue === 'apply-all') {
        state.pages.forEach((p) => {
          p.template = chosen;
        });
        state.notebook.template = chosen;
        await db.putMany('pages', state.pages);
        await db.put('notebooks', state.notebook);
        redraw();
        renderStrip();
      }
    },
    { once: true }
  );
});

/* ── Ask Claude ─────────────────────────────────────────────────── */

const QUICK_PROMPTS = [
  'Summarise this page',
  'Turn this into flashcards',
  'Explain this more simply',
  'What am I missing?',
  'Type this out as clean notes',
];

$('#btn-ai').addEventListener('click', () => {
  const modelSelect = $('#ai-model');
  modelSelect.textContent = '';
  MODELS.forEach((m) => {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = `${m.name} — ${m.note}`;
    modelSelect.appendChild(opt);
  });
  modelSelect.value = settings.get('model', MODELS[0].id);

  const chips = $('#ai-chips');
  chips.textContent = '';
  QUICK_PROMPTS.forEach((prompt) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = prompt;
    b.addEventListener('click', () => {
      $('#ai-question').value = prompt;
    });
    chips.appendChild(b);
  });

  const canvas = document.createElement('canvas');
  renderPage(canvas, currentPage(), { scale: 1.45 });
  $('#ai-preview').src = canvas.toDataURL('image/png');
  $('#ai-preview').dataset.png = canvas.toDataURL('image/png');

  $('#ai-answer').hidden = true;
  $('#ai-error').hidden = true;
  $('#ai-nokey').hidden = Boolean(settings.get('apiKey', ''));
  $('#dlg-ai').showModal();
});

$('#ai-ask').addEventListener('click', async () => {
  const button = $('#ai-ask');
  const question = $('#ai-question').value.trim();
  const errorBox = $('#ai-error');
  const answerBox = $('#ai-answer');

  errorBox.hidden = true;
  if (!question) {
    errorBox.textContent = 'Type a question first.';
    errorBox.hidden = false;
    return;
  }

  const apiKey = settings.get('apiKey', '');
  const model = $('#ai-model').value;
  settings.set('model', model);

  const page = currentPage();
  const typedText = (page.textBoxes || []).map((b) => b.text).filter(Boolean).join('\n');
  const imageBase64 = ($('#ai-preview').dataset.png || '').split(',')[1];

  button.disabled = true;
  button.textContent = 'Asking…';
  answerBox.hidden = false;
  answerBox.textContent = 'Reading your page…';

  try {
    answerBox.textContent = await askClaude({ apiKey, model, question, imageBase64, typedText });
  } catch (err) {
    answerBox.hidden = true;
    errorBox.textContent = err.message;
    errorBox.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = 'Ask';
  }
});

/* ── Settings ───────────────────────────────────────────────────── */

$('#btn-settings').addEventListener('click', async () => {
  const modelSelect = $('#set-model');
  modelSelect.textContent = '';
  MODELS.forEach((m) => {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = `${m.name} — ${m.note}`;
    modelSelect.appendChild(opt);
  });
  modelSelect.value = settings.get('model', MODELS[0].id);
  $('#set-key').value = settings.get('apiKey', '');
  $('#set-pencil-only').checked = state.pencilOnly;

  if (navigator.storage?.estimate) {
    try {
      const { usage } = await navigator.storage.estimate();
      const mb = (usage || 0) / 1048576;
      $('#set-storage').textContent = `Saved in this browser · about ${mb.toFixed(1)} MB used. Export a backup now and then.`;
    } catch (_) {
      /* leave the default copy */
    }
  }

  const dlg = $('#dlg-settings');
  dlg.showModal();
  dlg.addEventListener(
    'close',
    () => {
      settings.set('apiKey', $('#set-key').value.trim());
      settings.set('model', $('#set-model').value);
      setPencilOnly($('#set-pencil-only').checked);
    },
    { once: true }
  );
});

$('#btn-export').addEventListener('click', async () => {
  const data = await db.exportAll();
  const blob = new Blob([JSON.stringify(data)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `inkwell-backup-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
  toast('Backup saved.');
});

$('#btn-import').addEventListener('click', () => $('#import-file').click());

$('#import-file').addEventListener('change', async (e) => {
  const file = e.target.files?.[0];
  if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    await db.importAll(data);
    await loadLibrary();
    toast('Backup imported.');
  } catch (err) {
    toast(err.message || 'Could not read that file.');
  }
  e.target.value = '';
});

$('#btn-wipe').addEventListener('click', async () => {
  const confirmed = await actionSheet('Erase everything?', [
    { id: 'yes', label: 'Delete all folders, notebooks and pages', danger: true },
  ]);
  if (confirmed !== 'yes') return;
  await db.clearAll();
  await loadLibrary();
  toast('All notes erased.');
});

/* ── Library chrome ─────────────────────────────────────────────── */

$('#btn-new-notebook').addEventListener('click', openNewNotebook);

$('#btn-new-folder').addEventListener('click', async () => {
  const name = await askText('New folder');
  if (!name) return;
  await db.put('folders', {
    id: uid(),
    name,
    parentId: null,
    color: COVER_COLORS[Math.floor(Math.random() * COVER_COLORS.length)].id,
    createdAt: Date.now(),
  });
  await loadLibrary();
});

function closeSidebar() {
  el.library.classList.remove('sidebar-open');
  el.sidebarScrim.hidden = true;
}

$('#btn-toggle-sidebar').addEventListener('click', () => {
  const open = el.library.classList.toggle('sidebar-open');
  el.sidebarScrim.hidden = !open;
});
el.sidebarScrim.addEventListener('click', closeSidebar);

window.addEventListener('keydown', (e) => {
  if (el.editor.hidden) return;
  const typing = ['TEXTAREA', 'INPUT'].includes(document.activeElement?.tagName);
  if (typing) return;
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
    e.preventDefault();
    e.shiftKey ? redo() : undo();
  }
});

let resizeTimer = null;
window.addEventListener('resize', () => {
  if (el.editor.hidden) return;
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(layout, 150);
});

/* ── Boot ───────────────────────────────────────────────────────── */

async function boot() {
  state.pencilOnly = settings.get('pencilOnly', false);
  setPencilOnly(state.pencilOnly);
  setTool('pen');
  buildSwatches();
  el.sizeSlider.value = String(state.size);

  await loadLibrary();

  if (!state.notebooks.length && !state.folders.length) {
    const notebookId = uid();
    const now = Date.now();
    await db.put('notebooks', {
      id: notebookId,
      title: 'My first notebook',
      folderId: null,
      color: 'blue',
      template: 'linedWide',
      pageCount: 1,
      createdAt: now,
      updatedAt: now,
    });
    await db.put('pages', blankPage(notebookId, 0, 'linedWide'));
    await loadLibrary();
  }

  if (navigator.storage?.persist) {
    navigator.storage.persist().catch(() => {});
  }
}

// Registered up front rather than on `load`, which may already have fired
// by the time the async boot above gets this far.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('./sw.js').catch(() => {});

  // A new version took over. Reload to pick it up, but never mid-page:
  // interrupting someone while they are writing is worse than waiting.
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloading) return;
    reloading = true;
    if (el.editor.hidden) {
      location.reload();
    } else {
      toast('Update ready — it will apply next time you open Inkwell.');
    }
  });
}

boot();

// Exposed purely so the test harness can drive the app.
window.__inkwell = { state, db, layout, redraw, openNotebook, loadLibrary };
