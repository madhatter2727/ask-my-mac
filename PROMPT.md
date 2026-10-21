# Task — "Ask My Mac": native, private macOS assistant (REAL Grok Build)

Build a complete, compile-ready SwiftUI macOS app in THIS directory. Target: Tara's M5 MacBook Air, macOS 26, Swift via Command Line Tools only (NO Xcode project; use Package.swift, swift-tools-version 5.9, platforms .macOS(.v14), executable product `AskMyMac`). Cannot compile here (Linux box) — write carefully; use only Apple frameworks (SwiftUI, AppKit, EventKit, Speech, AVFoundation, Foundation). No third-party packages.

Siblings to copy patterns from: `../photo-reader-mac/` (app bundle install script, activation/keyboard focus fix, Info.plist), `../one-space-mac/` (style, NoToolbarPocket-style: no white title/toolbar bar — use `.windowStyle(.hiddenTitleBar)` / full-size content view, etc). Read their sources first.

## Process rules
1. FIRST write PLAN.md (short), then immediately create real source files. No stubs, no TODO shells.
2. No GitHub push. Stay in this folder. Plain-language README.md for a vibe coder.
3. Include `Resources/Info.plist` (bundle id com.tara.askmymac, name "Ask My Mac", NSCalendarsFullAccessUsageDescription, NSCalendarsUsageDescription, NSRemindersFullAccessUsageDescription, NSRemindersUsageDescription, NSSpeechRecognitionUsageDescription, NSMicrophoneUsageDescription, LSMinimumSystemVersion 14.0) and `Scripts/install-app.sh` modeled on photo-reader's (installs to "$HOME/Applications/Ask My Mac.app", ad-hoc codesign, opens it).
4. Activation fix: in AppDelegate `NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)` and make the window key so the text field accepts typing immediately.

## Product
Chat window: message list + text field (Return sends) + optional push-to-talk mic button (on-device SFSpeechRecognizer with `requiresOnDeviceRecognition = true`; if unavailable, hide/disable gracefully). Header status pill shows brain status (Osaurus reachable or not, with calm setup hint if not).

Brain: local Osaurus, OpenAI-compatible `POST http://127.0.0.1:1337/v1/chat/completions`, model `raptor-0.6-4b-jang_6m` (make model + base URL configurable in a small Settings sheet, persisted in UserDefaults; on launch GET /v1/models and if the configured model is missing pick first available). Use the `tools` / `tool_calls` function-calling loop (max ~6 rounds), non-streaming is fine. Nothing goes to the cloud. System prompt includes today's date/time, the user's home path, and terse instructions to use tools rather than guess. Be robust: if the model returns a tool call as JSON text in content instead of tool_calls, parse it anyway. Also add a fast deterministic pre-router for obvious intents ("find my X", "what's on my calendar today/tomorrow/this week", "open X") so core tasks work even if the small model fumbles — but still route everything else through the model.

## Tools (all paths must resolve — after standardizing & resolving symlinks — inside the user's home folder; refuse anything else, and refuse ~/Library, hidden dot-folders, and system folders)
Read-only (run immediately, show a compact "used tool" chip in the chat):
- search_files(query, kind?): Spotlight via `/usr/bin/mdfind -onlyin $HOME` (name match `kMDItemFSName`/`kMDItemDisplayName` contains query, case-insensitive, PLUS content match), dedupe, top 15, skip Library/hidden. Results rendered as clickable rows (open / reveal in Finder). Optionally also call One Space CLI `"$HOME/Applications/One Space.app/Contents/MacOS/OneSpace" --search "<q>"` if it exists, with a 10s timeout, and merge its text output as extra hints; never depend on it.
- list_folder(path), file_info(path), read_file_text(path) (txt/md/rtf via NSAttributedString, pdf via PDFKit first ~4000 chars).
- list_files_by_date(folder, days_back, name_contains?) — needed for "last week's screenshots" (screenshots: name begins "Screenshot" / "Screen Shot", default folder Desktop or the `com.apple.screencapture location`).
- calendar_events(start, end) and reminders(incomplete) via EventKit, requesting full access (`requestFullAccessToEvents` / `requestFullAccessToReminders` on macOS 14+). If denied, explain plainly how to enable in System Settings > Privacy & Security.
- open_item(path or app name or URL) — opening is allowed without approval (it changes nothing). Apps via NSWorkspace / `open -a`.
- ask_photo_reader(path, question): POST to local Photo Reader llama server at http://127.0.0.1:8093/v1/chat/completions with base64 image_url content; if offline say so.
Changing (NEVER run directly): move_items(paths, destination_folder), rename_item(path, new_name), copy_items, create_folder(path), trash_items(paths) (use FileManager.trashItem — never permanent delete), create_calendar_event(title,start,end). These produce a **Pending Action** shown as a clear preview card: title, plain-English summary, list of each source → destination, warnings (name collisions get " 2" suffix, never overwrite), and Approve / Cancel buttons. Only on Approve execute. Results reported back to the model/chat.
Undo log: every executed move/rename/copy/create_folder/trash recorded (JSON in ~/Library/Application Support/AskMyMac/undo.json — app's own support dir is the one allowed Library write) with reverse ops; an "Undo" button on the completed card and an Undo Last in the menu/toolbar (⌘Z). Trash undo = move back from Trash using the resulting URL from trashItem.

## Headless test mode (important — used for verification over SSH, no GUI)
`AskMyMac --selftest-find "<query>"` prints top results of search_files.
`AskMyMac --selftest-calendar` prints authorization status and tomorrow's events (or "no access").
`AskMyMac --selftest-move <srcFile> <destFolder>` plans the move, prints the preview text, executes it as if approved, prints undo record, then performs undo and prints whether the file is back. Exit codes 0 on success.
`AskMyMac --selftest-ask "<prompt>"` runs one full brain turn (with tools; changing tools only print the pending card, never execute) and prints transcript.
Also a test hook: if env `ASKMYMAC_AUTOPROMPT` is set, the GUI app types and sends that prompt on launch (for demo/testing).

## Look
Tasteful native: system fonts, materials (`.regularMaterial`), soft neutral grays with a single calm accent (deep teal), rounded cards, SF Symbols, suggestions chips on empty state ("Find my resume", "What's on my calendar tomorrow?", "Move last week's screenshots to an Archive folder", "Open the PDF about…"). Approval card visually distinct (accent border, clear Approve primary button). Not purple AI sludge.

When finished, summarize the files written.
