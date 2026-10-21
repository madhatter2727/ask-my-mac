# Ask My Mac

Private native macOS assistant. Swift package, command-line tools only, Apple frameworks only. Chat stays on this Mac.

## M1 — Shell
Chat window (hidden title bar, material, teal). Message list, suggestion chips, Return to send. Placeholder reply. App activates and keys the window. Info.plist and install script.

## M2 — Osaurus chat
Local POST to 127.0.0.1:1337 `/v1/chat/completions`, model `raptor-0.6-4b-jang_6m`. Status pill. Settings for base URL and model (UserDefaults). On launch, GET `/v1/models` and use the first model if the configured one is missing.

## M3 — Read-only tools
Home-only paths. search_files, list_folder, file_info, read_file_text, list_files_by_date. Tool chips. Function-call loop, JSON-in-content fallback, and a small pre-router. `--selftest-find`, `--selftest-ask`.

## M4 — Approve and undo
move, rename, copy, create_folder, trash as preview cards. Approve runs them. Collisions get a " 2" suffix. Undo log under Application Support. Undo on the card and ⌘Z. `--selftest-move`.

## M5 — Calendar and settings
EventKit events and reminders, approved event creation, on-device push-to-talk, `--selftest-calendar`, plain README.
