# Inkwell

An all-in-one workspace for one person, built in SwiftUI for iPad and Mac from
a single Xcode project. Handwritten notes, a to-do list, a document library, a
morning briefing, and a Claude assistant that can read all of it — in one app
instead of five.

It's built around five **areas** — School, Home, Activities, Projects, and
Personal — that run through every feature. A task, a notebook, and a document
all carry one, so the whole app can be filtered down to "just school" or opened
up to everything at once.

## What's in it

### Today — the morning briefing
Opens on facts assembled entirely on device: today's calendar events, Apple
Reminders that are due, overdue tasks, what's due today, and what's coming in
the next three days. That much works with no network and no API key.

On top of that, Claude writes a short prioritized plan for the day — what to do
first, what can wait, and any real collisions between the schedule and the
deadlines. It's generated once per calendar day and cached, so opening the app
repeatedly doesn't re-bill an API call. **What Claude Was Told** in the toolbar
shows the exact text that was sent.

### Notes — the Notability-style notebook
- Apple Pencil drawing on a `PKCanvasView` with Apple's native tool picker
  (pen, highlighter, pencil, eraser, lasso, ruler, color picker), pinch-to-zoom,
  and an "Apple Pencil only" mode for palm rejection.
- Paper templates: blank, narrow/college-ruled, small/large grid, dotted,
  Cornell notes, and checklist — set per notebook and overridable per page.
- Folders that nest as deep as you like, with color and icon tags.
- A separate typed-text layer, so typed and handwritten notes coexist on a page
  (Notability's "type tool").
- Page thumbnails, add/delete pages, and export a page as an image.
- Per-page AI: on-device Vision OCR reads your handwriting, then you can ask
  Claude about that page — summarize it, quiz you on it.

### Tasks
One list across all five areas, groupable by date, area, or priority.
Sub-steps, priority flags, due dates with optional times, and recurrence
(daily, weekdays, weekly, monthly) where completing a repeating task rolls it
forward instead of archiving it. A task can link to a notebook, so "study
chapter 4" is a shortcut into the pages for it.

Quick entry understands shorthand: `#school`, `!!` for priority, and `today` /
`tomorrow` for due dates. `Lab report #school !! tomorrow` becomes exactly what
you'd expect.

### Documents
Add PDFs, photos of handouts, and text files. The file is **copied into the
app**, so it survives the original being moved, renamed, or removed from iCloud
Drive — and because it lands in the app's own Documents folder, the whole
library is also browsable from the Files app on iPad and from Finder on the Mac.

Text is extracted on device — PDFKit for PDFs with a text layer, Vision OCR for
scanned pages and photos, direct read for plain text. That extracted text is
what the assistant reads, which is why you can ask about a document without the
file itself ever being uploaded. Each document shows you exactly how much text
was pulled out.

### Assistant
A saved conversation with Claude that can see your workspace: open tasks,
notebook titles, today's calendar, and the text of any document you've pinned
or attached. The picture is rebuilt on every turn, so answers reflect what's
true now rather than when the thread started.

What it can see is yours to set. **What Claude Sees** lets you switch areas in
and out of scope and attach specific documents, and a one-line summary of what
went with each question sits under that message in the transcript.

## Privacy

Every AI feature is optional and off until you add a key. Notes, tasks,
documents, and the fact-based half of the briefing all work with no API key at
all.

- Your Anthropic API key lives in the device Keychain and goes only to
  `api.anthropic.com`.
- Handwriting recognition and document text extraction run on device (Vision,
  PDFKit). No file is ever uploaded — only extracted text, and only in a
  question you sent.
- Calendar and Reminders access is read-only. The app never writes to them.

## Project layout

```
Inkwell/
  Inkwell.xcodeproj/       Open this in Xcode
  Inkwell/
    InkwellApp.swift       Entry point and SwiftData container
    ContentView.swift      Sidebar shell and section routing
    Models/                SwiftData models + LifeArea
    Views/                 Every screen
    Services/              Claude client, workspace context, documents,
                           text extraction, calendar, briefing, Keychain
    Support/               Color palette, schema list
Tools/
  generate_project.py      Regenerates project.pbxproj from the files on disk
```

### Adding a Swift file

The Xcode project lists every source file in three places, which is tedious to
maintain by hand. Add your file under `Inkwell/Inkwell/` and run:

```sh
python3 Tools/generate_project.py
```

Object identifiers are hashed from file paths, so re-running produces a
byte-identical project and never churns the diff. A new subdirectory needs one
line added to `GROUP_ORDER` in that script — it will tell you if you forget.

## Getting started

1. Open `Inkwell/Inkwell.xcodeproj` in Xcode 16 or later.
2. Pick the **Inkwell** scheme, and an iPad simulator or **My Mac (Mac
   Catalyst)** as the destination.
3. In **Signing & Capabilities**, set your Team. The bundle identifier is
   `com.inkwell.notesapp` — change it to your own.
4. Build and run.

The Apple Pencil needs a real iPad; the simulator only gives you mouse and
trackpad input for PencilKit.

### Turning on Claude

1. Get an API key from the Anthropic Console.
2. Open **Settings** (gear icon in the sidebar), paste the key, and pick a
   default model — Sonnet is the balanced default, Opus for long documents and
   harder planning, Haiku for the cheapest pass.

### Mac Catalyst notes

Xcode generates the App Sandbox entitlements for the Catalyst build
automatically. If picking a document or reaching the API fails on the Mac, open
**Signing & Capabilities**, select the Mac Catalyst destination, and confirm
**Outgoing Connections (Client)** and **User Selected File: Read/Write** are on
under App Sandbox.

## Syncing across devices

This version stores everything locally per device. To sync your iPhone, iPad,
and Mac, switch the `ModelContainer` in `InkwellApp.swift` to a CloudKit-backed
configuration and enable the iCloud capability with your own container. Note
that CloudKit requires every model property to be optional or have a default and
every relationship to be optional — the models here are close, but `@Attribute(.unique)`
on `DailyBriefing.dayKey` would need to go, since CloudKit doesn't support
unique constraints.
