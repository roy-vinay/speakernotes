<p align="center"><img src="app/Icon/AppIcon-1024.png" width="128" alt="SpeakerNotes icon"></p>

<h1 align="center">SpeakerNotes</h1>

<p align="center">Speaker notes that float over your slides on Zoom and Google Meet,<br>and stay out of your screen share.</p>

<p align="center"><img src="docs/img/app-present.png" width="520" alt="SpeakerNotes showing a slide's notes with highlighted phrases"></p>

Presenter View doesn't survive a full-screen share on one laptop screen: either you lose your notes, or
everyone sees them. SpeakerNotes is a small Mac window that sits on top of everything, follows your slides,
and asks macOS to leave it out of screen captures. You click your slides as usual; the notes never move
out of the way.

## Install

Paste this in Terminal (macOS 13 or later, Apple silicon or Intel; instructions need macOS 26 with Apple Intelligence):

```bash
curl -fsSL https://raw.githubusercontent.com/roy-vinay/speakernotes/main/install.sh | bash
```

Run the same command any time to update. Or download **SpeakerNotes-macOS.zip** from the
[latest release](https://github.com/roy-vinay/speakernotes/releases/latest) and drag the app into
Applications. The app isn't notarized yet, so the first time macOS says it "could not verify" it: open
**System Settings > Privacy & Security** and click **Open Anyway**.

SpeakerNotes has a Dock icon and a speech bubble in the menu bar. Click the Dock icon any time to bring
the notes back. **SpeakerNotes > Open at Login** starts it with your Mac, so it's ready before every call.
If it ever quits, it reopens on the same file and slide.

## Use it

1. Write your notes in Markdown, with a line of `---` between slides. If there are no `---` lines, each
   `#` or `##` heading starts a new slide.
2. Open the file with **⌘O**, drop it on the window, or right-click it in Finder and choose
   **Open With > SpeakerNotes**. You can also just type or paste notes with **⌘E**.
3. Start your slides, share your screen, and place the notes window wherever you like.

```markdown
# Opening
- Thank everyone for joining
- **The one number:** three hours saved every week

---

## The problem
Pause here. Ask who has seen this before.
```

## Make it easy to read

- **Aa** in the header: text size, typeface (System, Rounded, Serif, Mono) and line spacing.
- **Emphasis** (the highlighter): highlight, bold, color or underline phrases everywhere they appear.
  - Select text in your notes, right-click, and pick a style.
  - Write `==like this==` in your notes for a highlight.
  - Or describe it: "highlight the names of the engines". On macOS 26 with Apple Intelligence, Apple's
    on-device model reads your notes and finds them. Nothing leaves your Mac. On other Macs, type the exact
    phrase instead.

Emphasis is saved for each file and never changes the file itself. Remove it from the same panel.

## Shortcuts

These work from any app, while your slides are in front:

| Shortcut | What it does |
| --- | --- |
| ⌃⌥→ / ⌃⌥← | Next / previous slide |
| ⌃⌥Space | Start or stop auto-scroll (teleprompter) |
| ⌃⌥↑ / ⌃⌥↓ | Scroll faster / slower |
| ⌃⌥T | Click-through on or off: clicks pass through the notes to what's under them |
| ⌃⌥N | Show or hide the notes |
| ⌃⌥E | Edit or present |

After clicking inside the notes window:

| Shortcut | What it does |
| --- | --- |
| → ← Space | Next / previous slide |
| ⌘E | Edit or present (edits save back to your file) |
| ⌘O / ⌘S | Open a file / save |
| ⌘T | Text size and typeface |
| ⌘+ / ⌘− | Text size |
| ⌘] / ⌘[ | Less / more see-through |
| ⌘W | Hide (bring it back from the menu bar) |

**Move with My Slide Keys** (menu bar) makes the notes follow when you press → or ← in your slides app,
so you only press one key. macOS asks for Accessibility permission the first time. After each update,
macOS may ask again because the app is ad-hoc signed.

## Before a demo

- Turn on **Open at Login** once, and keep the notes file somewhere stable.
- If a projector or second display comes and goes, the window moves back onto a screen you can see.
- Run the test below once on the Mac you'll present from.

## Test before a real call

macOS lets an app ask to be left out of screen captures, and most video apps honor it. Some capture
methods on recent macOS versions don't. Before an important call: start a Zoom or Meet with just
yourself, share your **entire screen**, and record it. If the notes show up in the recording, share just
your slides window instead of the whole screen; the notes then can't appear.

## Build from source

```bash
git clone https://github.com/roy-vinay/speakernotes
cd speakernotes/app
swift test
./scripts/build-app.sh
open build/SpeakerNotes.app
```

Needs Xcode or the Command Line Tools (`xcode-select --install`).

## License

MIT. See [LICENSE](LICENSE).
