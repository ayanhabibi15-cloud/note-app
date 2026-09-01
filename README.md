# Inkwell

A Notability-inspired, handwriting-first note-taking app — folders, paper
templates, Apple Pencil input, and an optional Claude assistant.

It comes in two forms:

| | [`docs/`](docs) — **web app** | [`Inkwell/`](Inkwell) — **native iOS app** |
|---|---|---|
| Runs on | iPad, iPhone, Mac, any modern browser | iPhone, iPad, Mac (Catalyst) |
| Needs | nothing — open a URL | a Mac with Xcode |
| Costs | free | $99/yr to keep it installed past 7 days |
| Install | Safari → Share → Add to Home Screen | build and run from Xcode |
| Built with | vanilla JS, Canvas, IndexedDB | SwiftUI, PencilKit, SwiftData |

**Start with the web app.** It's the one you can actually put on your iPad
today, and it does everything the native version does.

---

## The web app

### Features

- **Apple Pencil writing** with pressure-sensitive strokes, plus a
  highlighter, an eraser, and a typed-text tool.
- **Lasso select** — circle some ink to pick it up, then drag it somewhere
  else, duplicate it, recolour it, or delete it. This is the handwriting
  answer to selecting text, and it replaces the browser's own copy/paste
  selection, which is switched off so a resting palm can't trigger it.
- **Palm rejection** — rest your hand on the screen while you write. "Pencil
  only" mode turns itself on the first time you use a Pencil; from then on a
  touch can never interrupt a stroke, and a single touch on the page does
  nothing at all.
- **Two fingers to pan, pinch to zoom** (or the zoom buttons). Panning takes
  two fingers precisely so that a resting palm can't scroll the page. With
  "Pencil only" off, one finger draws instead.
- **Paper templates**: blank, narrow-ruled, college-ruled, small/large grid,
  dotted, Cornell notes, and checklist — per notebook or per page.
- **Folders that nest as deep as you like**, colour-tagged, with notebooks
  inside them.
- **Multi-page notebooks** with a thumbnail strip, plus PNG export of any page.
- **Ask Claude about a page** — sends an image of the page, so it reads your
  actual handwriting. Optional and off until you add your own API key.
- **Works offline** once loaded, and everything is stored on your device.
- **Backup export/import** so your notes are never trapped in a browser.

### Putting it on your iPad's home screen

1. **Turn on GitHub Pages** (one time). In this repo on github.com:
   **Settings → Pages →** under "Build and deployment", set Source to
   *Deploy from a branch*, pick the branch this code is on, choose the
   **`/docs`** folder, and press **Save**. Wait a minute or two.
2. GitHub will show you a URL like
   `https://<your-username>.github.io/note-app/`. Open it in **Safari on your
   iPad**.
3. Tap the **Share** button (the square with the arrow), scroll down, and tap
   **Add to Home Screen**, then **Add**.
4. Open Inkwell from the home screen. It now runs full screen with no browser
   bars, and works without a connection.

### Turning on the Claude assistant

1. Get an API key from the Anthropic Console (this is a paid API, separate
   from a Claude.ai subscription).
2. In Inkwell, tap the **gear** in the sidebar, paste the key, pick a default
   model, and tap Done.
3. On any page, tap **✦ Ask Claude**, choose a prompt or write your own, and
   tap Ask.

A caveat worth understanding: this is a website with no server, so the key is
stored in your browser and sent straight to Anthropic from your device.
Anyone who can unlock your iPad can read it — fine for a personal device,
not something to do on a shared one.

### Your notes and where they live

Notes are saved in the browser's IndexedDB on the device you wrote them on —
they don't sync between devices, and clearing Safari's website data would
remove them. Use **Settings → Export backup** now and then; the file it saves
can be restored with **Import backup**, including on another device.

### Running it locally

```
cd docs && python3 -m http.server 8000
```

Then open `http://localhost:8000`. (It needs to be served over http, not
opened as a file, because it uses JavaScript modules and a service worker.)

---

## The native iOS app

A SwiftUI + PencilKit version of the same idea, with SwiftData persistence and
on-device Vision handwriting recognition feeding the Claude assistant.

1. Open `Inkwell/Inkwell.xcodeproj` in Xcode 16 or later.
2. Select the **Inkwell** scheme and an iPad simulator, or "My Mac (Mac
   Catalyst)".
3. In **Signing & Capabilities**, choose your own Team. The bundle identifier
   is `com.inkwell.notesapp` — change it to something of your own.
4. Build and run. For real Apple Pencil input, run on a physical iPad.

To keep it installed on a device for more than 7 days you need a paid Apple
Developer account; with a free Apple ID you re-run it from Xcode each week.

### Layout

```
Inkwell/Inkwell/
  InkwellApp.swift     app entry, SwiftData container
  ContentView.swift    NavigationSplitView shell
  Models/              Folder, Notebook, Page, TextBox, PageTemplate
  Views/               sidebar, notebook grid, page editor, canvas, AI sheet
  Services/            Keychain, Claude client, handwriting recognition
```

### Syncing across devices

The native app stores notes locally per device. To sync, switch the
`modelContainer` in `InkwellApp.swift` to a CloudKit-backed configuration and
enable the iCloud capability with your own container.
