# Inkwell

A Notability-inspired, handwriting-first note-taking app built with SwiftUI
and PencilKit. It targets iPhone, iPad, and Mac (via Mac Catalyst) from a
single Xcode project.

## Features

- **Apple Pencil note-taking** — a `PKCanvasView`-backed canvas with Apple's
  native tool picker (pen, highlighter, pencil, eraser, lasso, ruler, color
  picker), pinch-to-zoom, and an optional "Apple Pencil only" mode for palm
  rejection.
- **Paper templates** — blank, narrow/college-ruled lined, small/large grid,
  dotted, Cornell notes, and checklist layouts, chosen per notebook or
  overridden per page.
- **Folders, your way** — nest folders as deep as you like, color- and
  icon-tag them, and organize notebooks however suits you (by class, by
  project, by year).
- **Typed text tool** — an independent, movable/resizable text layer on each
  page, so typed and handwritten notes can coexist (Notability calls this
  the "type tool").
- **Page management** — add, delete, and page through a notebook via a
  thumbnail strip; export any page as an image via the share sheet.
- **Optional Claude AI assistant** — recognizes a page's handwriting
  on-device with Vision (no network call for OCR), then lets you ask
  Claude Sonnet or Claude Opus a question about the page (e.g.
  "summarize this" or "quiz me on this"). Fully opt-in: nothing is sent
  anywhere until you add your own Anthropic API key in Settings.

## Project layout

```
Inkwell.xcodeproj/        Xcode project (open this in Xcode)
Inkwell/
  InkwellApp.swift        App entry point, SwiftData model container
  ContentView.swift        Top-level NavigationSplitView
  Models/                  SwiftData models (Folder, Notebook, Page, TextBox, PageTemplate)
  Views/                   SwiftUI screens (sidebar, notebook grid, page editor, canvas, AI sheet, settings)
  Services/                Keychain, Claude API client, on-device handwriting recognition
  Support/                 Color palette helpers
  Assets.xcassets/         App icon + accent color placeholders
```

## Getting started

1. Open `Inkwell.xcodeproj` in Xcode 16 or later.
2. Select the **Inkwell** scheme and choose an iPhone or iPad simulator (or
   "My Mac (Mac Catalyst)") as the run destination.
3. In **Signing & Capabilities**, set your own Team so Xcode can code-sign
   the app for a device or Catalyst build. The bundle identifier is
   `com.inkwell.notesapp` — change it if you want your own.
4. Build and run. The app starts with an empty folder list — tap **+** to
   create your first folder, then create a notebook inside it.
5. To use the Apple Pencil, run on a real iPad; the simulator only supports
   mouse/trackpad input for PencilKit.

### Enabling the Claude AI assistant

1. Get an API key from the Anthropic Console.
2. In the app, open **Settings** (gear icon in the sidebar toolbar), paste
   your key, and pick a default model (Sonnet is the fast/cheap default;
   Opus is available for harder reasoning).
3. On any page, tap **Ask AI** in the toolbar. The app recognizes your
   handwriting with on-device Vision OCR, shows you what it read, and lets
   you ask a question about it.

The API key is stored only in the device's Keychain and is sent directly
to `api.anthropic.com` — never anywhere else.

### Notes on syncing across devices

This first version stores notes locally per device via SwiftData. To sync
across your iPhone, iPad, and Mac, the natural next step is switching the
`modelContainer` in `InkwellApp.swift` to a CloudKit-backed configuration
and enabling the iCloud capability (with your own Team/container) in
Signing & Capabilities.
