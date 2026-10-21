# Ask My Mac

Ask My Mac is a private assistant that lives on your Mac. You talk to it in a chat window. It can find files, read a document, check your calendar and reminders, and open something you name. When you ask it to move, rename, copy, trash, make a folder, or add a calendar event, it shows a preview and waits for you to approve.

Chat goes to Osaurus on this Mac (`http://127.0.0.1:1337`). Speech stays on this Mac too. Nothing is sent to the cloud.

## Open it

1. Open the Osaurus app and leave it running. The pill at the top of the window says when the brain is ready. If it says Osaurus is offline, open Osaurus and ask again.
2. From this folder, run `bash Scripts/install-app.sh`. That builds Ask My Mac, puts it in `~/Applications/Ask My Mac.app`, and opens it.
3. Type a question and press Return.

You can also hold the mic button, speak, and release. The words land in the text field. Press Return to send. If this Mac cannot do on-device dictation, the mic is dimmed and you just type.

Try “Find my resume”, “What’s on my calendar tomorrow?”, or “Move last week’s screenshots to an Archive folder”. The gear button opens Settings, where you can change the local address and model. The usual model is `raptor-0.6-4b-jang_6m`.

## Permissions to click

The first time a feature needs access, macOS asks. Allow it. If you said no earlier, turn it on under System Settings > Privacy & Security, then try again.

- **Calendars** (full access) — read your schedule, and add an event only after you approve it. Path: Calendars.
- **Reminders** (full access) — list reminders that are still open. Path: Reminders.
- **Microphone** — only when you hold the mic. Audio stays on this Mac. Path: Microphone.
- **Speech Recognition** — turns what you say into text on this Mac. Path: Speech Recognition.

## Safety rules

- It only looks at files inside your home folder. It refuses `~/Library`, hidden folders (names that start with a dot), and system folders.
- Looking something up runs right away. A small chip in the chat names what it used.
- A move, rename, copy, new folder, trash, or new calendar event waits on a preview card. Approve runs it. Cancel drops it.
- Trash puts things in the Trash. Undo moves them back.
- If a name is already taken, the new copy gets a “ 2” on the end. It does not overwrite the old one.
- After something runs, use Undo on the card, or Undo Last Action (⌘Z).
- Opening a file, an app, or a link does not need approval.

Photo questions need the Photo Reader app running on this Mac. If it is not open, the chat says so.
