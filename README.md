# rsyncer

A native macOS app for syncing files and folders between local drives and mounted volumes. Requires macOS 14 or later.

![Preview of a one-way sync plan](docs/preview-plan.jpg)

## Features

- **One-way sync** — Copies a file or a folder's contents to a destination. Optionally protects newer destination files and removes files that no longer exist at the source.
- **Two-way sync** — Merges two folders in both directions, with the newest version of each file winning.
- **Safe previews** — Shows planned additions, updates, and deletions before changing anything, with searchable item details and affected file sizes.
- **Transfer controls** — Start, pause, resume, or stop a sync and follow its per-file progress in the app, menu bar, or Dock.
- **Scheduling** — Run saved syncs hourly, daily, weekly, or when a drive connects. Missed timed runs resume when the app is available.
- **Saved syncs** — Automatically saves paths, options, schedules, names, and sidebar order for repeat use.
- **Transfer options** — Supports timestamps, permissions, links, Mac metadata, checksums, exclusions, bandwidth limits, partial files, and other common `rsync` controls.
- **Volume status** — Displays free space, capacity, availability, read-only state, and low-space warnings for connected drives.
- **History and logs** — Keeps the latest 250 runs in the app and writes a complete log for every run.
- **Menu bar and login launch** — Continues running after the window closes and can launch automatically when you sign in.
- **Themes** — Includes six accent and sidebar colour themes.

## Using rsyncer

1. Click **+** beside **Saved syncs** and choose a one-way or two-way sync.
2. Drop in the source and destination, or browse to them, then choose the transfer options and schedule.
3. Select **Preview** to review the plan, then **Sync now** to run it.

If you enable **Launch at login**, macOS may require approval under **System Settings → General → Login Items**.

## Sync behaviour

One-way sync never removes source files. Destination-only files are retained unless deletion is explicitly enabled. Deletion applies to scheduled runs and bypasses the Trash.

Two-way sync runs source to destination first, then returns changes in the other direction. Newer modification dates win; deletion is disabled, so a file removed from one side is restored from the other. Checksums can detect equal-size files whose dates also match.

The scheduler runs one job at a time. The app prevents idle sleep during transfers, but cannot wake a sleeping or powered-off Mac. Drive-connection schedules only detect mount events while the app is running.

## Access and data

Allow access to files and folders when macOS prompts you. Protected locations may require **Full Disk Access**.

The app rejects missing, overlapping, or unsafe locations before a run. Cancellation may leave partial files at the destination.

Settings and logs are stored in:

```text
~/Library/Application Support/rsyncer/state.json
~/Library/Application Support/rsyncer/Logs/
```
