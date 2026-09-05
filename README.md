# Card Offload

A small iPhone/iPad app that copies photos and video off a camera's SD card straight onto an
external SSD — no Mac, no cloud, no import into the Photos library. Plug both into the phone,
pick two folders, tap **Start copying**.

It is deliberately boring: it reads the card, writes the drive, checks the result, and never
deletes anything.

> **Status:** v1, freshly written. It has not yet been compiled on a Mac or run against real
> hardware, so treat the first build as a shakedown — expect to fix a signing setting or two.
> Until you have verified a run end to end, keep the card until the copy is somewhere else too.

---

## What it does

- **Copies from any card reader iOS can mount** — SD, CFexpress, microSD, or the card slot on a
  hub. If the card shows up in the Files app, the app can read it.
- **Finds the media for you.** Recursively walks the folder you pick and matches JPEG, HEIC, PNG,
  TIFF and ~25 RAW formats (CR2/CR3, NEF, ARW, RAF, ORF, RW2, DNG, GPR…), plus MOV, MP4, MTS,
  BRAW, R3D, INSV and friends. Skips `.DS_Store` and macOS `._` resource forks.
- **Organises as it copies.** Folders by capture date (`2026/2026-09-05/IMG_0042.CR3`), one flat
  folder, or a mirror of the card's own layout.
- **Skips what's already there,** so re-running after a stall only copies the gap.
- **Verifies every file.** Each copy is re-read from the SSD and its SHA-256 compared with the
  card. A flaky cable or a half-seated reader can't silently corrupt a shoot.
- **Survives interruption.** Cancel mid-file and the partial file is deleted, not left behind
  looking complete.
- **Never writes to the card.** Format in-camera when you're satisfied the copy is safe.

## What it doesn't do

- No App Store build — you compile and install it yourself (see below).
- No background copying. iOS suspends apps that leave the foreground, so the screen stays on
  (the app disables the idle timer) and you leave it open while it runs.
- No previews, culling, ratings, or editing. It's an offload tool.
- No deleting or formatting the card. On purpose.

---

## What you need

| | |
|---|---|
| **Device** | iPhone or iPad running **iOS/iPadOS 17 or later** |
| **Card reader** | Any USB reader iOS mounts in Files |
| **Drive** | External SSD formatted **APFS, ExFAT, FAT32 or HFS+** |
| **Hub** | A USB-C hub, ideally **powered** — see below |
| **To build it** | A Mac with **Xcode 16+** |

### About power — read this before blaming the app

An iPhone supplies very little bus power over USB-C. A card reader alone is usually fine; a card
reader *and* a bus-powered SSD at the same time is often not. If the drive keeps disappearing
mid-copy, or refuses to mount at all, use a **powered hub** (one with its own USB-C PD input).
That fixes it nearly every time.

Speed is capped by the port, not by this app:

- iPhone 15/16 **Pro** and recent iPads: USB 3, expect roughly 300–800 MB/s
- Non-Pro iPhone 15/16: USB 2, expect roughly 30–40 MB/s
- Lightning iPhones: USB 2 via a Camera Adapter — use the model with a power passthrough port

Verification re-reads everything, so a verified run takes about twice as long. It's worth it for
a paid shoot; turn it off in Settings when you're in a hurry.

---

## Installing it

There's no App Store release, so you build it once and install it on your own device.

```bash
git clone https://github.com/kolec94/card-offload.git
cd card-offload
open CardOffload.xcodeproj
```

Then in Xcode:

1. Select the **CardOffload** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing** and choose your team. A free Apple ID works.
3. Change the bundle identifier to something of your own, e.g. `com.yourname.cardoffload`
   (the one in the repo is already taken by this project).
4. Pick your iPhone as the run destination and hit **Run**.
5. On the phone: **Settings → General → VPN & Device Management** → trust your developer
   certificate.

With a free Apple ID the app stops launching after 7 days — plug in and re-run to renew it. A
paid developer account ($99/yr) extends that to a year.

If the project file ever gets mangled, it can be regenerated from `project.yml`:

```bash
brew install xcodegen && xcodegen generate
```

---

## Using it

1. Plug the reader and the SSD into the phone (via a powered hub if you have one).
2. Open the app, tap **Copy from**, and select the card — pick the **DCIM** folder, or the whole
   card volume if you also want the camera's sidecar folders.
3. Tap **Copy to** and select a folder on the SSD. Create one first in Files if you want a
   dedicated home for the shoot.
4. The app scans the card and shows what it found, broken down by photos, RAW, video and
   sidecars.
5. Tap **Start copying** and leave the app open.
6. When it's done, **See every file** lists each one — anything that failed is at the top.

Both folder choices are remembered between launches. Reconnect the same drive and they light up
again; while it's unplugged the row shows *Not connected* until you pick it again.

### Settings

| Setting | Default | What it does |
|---|---|---|
| Layout | Folders by date | `byDate`, `flat`, or `mirror the card` |
| Photos and RAW / Videos / Sidecars | all on | Which kinds of file to include |
| Only recent files | off | Ignore anything shot before a date you choose |
| Skip files already on the drive | on | Same name + same byte size counts as already copied |
| Verify every copy | on | SHA-256 the copy and compare against the card |

Changing a filter re-scans the card when you close Settings.

---

## How it works

iOS won't let an app roam the filesystem, but the system folder picker (`fileImporter` with
`UTType.folder`) grants **recursive, security-scoped access** to whatever the user picks. That's the whole trick:
one pick for the card, one for the drive, and the app can read and write everything underneath
them. Both picks are stored as bookmarks so they survive a relaunch.

Files are copied in 4 MB chunks rather than with `FileManager.copyItem`, for three reasons: the
progress bar can move *inside* a single 40-minute clip, a cancel takes effect immediately instead
of at the next file boundary, and the SHA-256 of the source falls out of the copy for free — so
verification costs one extra read instead of two.

```
CardOffload/
├── Models/
│   ├── MediaFile.swift          File found on the card + the extension tables
│   ├── OffloadSettings.swift    User preferences, persisted to UserDefaults
│   └── TransferResult.swift     Per-file outcome and the run summary
├── Services/
│   ├── FolderBookmark.swift     Security-scoped bookmarks for the two folders
│   ├── VolumeScanner.swift      Recursive walk + filtering
│   ├── FileCopier.swift         Chunked copy, hashing, timestamp preservation
│   ├── TransferEngine.swift     Destination layout, dedupe, verify, per-file results
│   ├── OffloadSession.swift     Observable state the UI binds to
│   └── OffloadError.swift       Plain-language failure messages
└── Views/
    ├── ContentView.swift        Main screen
    ├── SettingsView.swift
    ├── ResultsList.swift
    └── Formatters.swift
```

## Troubleshooting

**The drive vanishes partway through.** Almost always power. Use a powered hub.

**The card doesn't appear in the picker.** Check it mounts in the Files app first — under
*Browse → Locations*. If Files can't see it, neither can this app. Some readers need a moment
after being plugged in.

**"Nothing new to copy" but the card is full.** Either everything is already on the drive, or a
filter is excluding it — check *Only recent files* and the photo/video toggles in Settings.

**A file failed verification.** The copy was deleted and the card was left untouched. Reseat the
cable and run again; the skip logic means you only redo the missing files.

**It's slower than expected.** Check which iPhone you have (USB 2 vs USB 3 above), then try
turning verification off.

## Licence

MIT — see [LICENSE](LICENSE).
