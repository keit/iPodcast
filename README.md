# iPodcast

A macOS app for downloading podcasts to a Rockbox-equipped iPod. Syncs new episodes from Apple Podcasts feeds, browses past episodes, and cleans up listened files using Rockbox's `playback.log`.

This is a SwiftUI port of [podcast_downloader](https://github.com/keitakashima/podcast_downloader), a Python CLI for the same workflow.

## Features

- Resolve Apple Podcasts URLs to RSS feeds via the iTunes lookup API
- Download new episodes directly to the iPod's `Podcasts/` folder
- Detect played episodes by parsing `.rockbox/playback.log`
- Delete fully-listened episodes (≥90% playtime) with **Remove Played**
- Browse every available episode in a show's RSS feed via **More…** and download older ones
- Manually toggle the played flag (useful if you played the episode on another device)
- Manage the list of subscribed feeds (Add / Remove with full undo support)
- One-click **Eject iPod**

## Requirements

- macOS 26.2 or later
- An iPod running [Rockbox](https://www.rockbox.org) mounted at `/Volumes/IPOD` (configurable)
- Xcode 26+ to build

## Install

From the project root:

```bash
./install.sh
```

This builds the Release configuration and copies `iPodcast.app` to `/Applications`.

Alternatively, open `iPodcast.xcodeproj` in Xcode and choose **Product → Archive** (or **Run** with the **Release** configuration).

## Usage

1. Plug in your iPod. The default mount point is `/Volumes/IPOD` (editable in the UI).
2. (Optional) Open **Manage Feeds** to add or remove Apple Podcasts URLs.
3. Click **Sync New Podcasts** to fetch the latest N episodes (default 5) of each feed.
4. After listening on the iPod, click **Remove Played** to delete episodes that Rockbox marked as ≥90% played.
5. Click **Eject iPod** when done.

To grab an older episode, click **More…** in a show's row and pick the episode to download.

## How it works

- **Feeds → episodes** — The iTunes Lookup API resolves each Apple Podcasts URL to the show's RSS feed. The XML is parsed for `<item>` entries with `<enclosure>` audio URLs.
- **Skip logic** — An episode is skipped if its filename already exists on disk, or if its basename appears in `playback.log` (meaning Rockbox played it previously).
- **Played detection** — Each line in `playback.log` is `timestamp:elapsed:length:/path`. A file is "fully played" when `elapsed / length >= 0.90`.
- **Persistence** — Feed URLs are stored in `UserDefaults`. Downloaded state is implicit from the filesystem; played state lives in `playback.log` on the iPod.

## Project layout

```
iPodcast/
  iPodcastApp.swift        – App entry point
  ContentView.swift        – Main window (Device, Actions, Podcasts, Log panels)
  PodcastManager.swift     – Sync, downloading, feed resolution, RSS parsing
  RockboxDatabase.swift    – Reads .rockbox/playback.log for cleanup
  ManageFeedsView.swift    – Add / remove feeds with undo
  ShowEpisodesView.swift   – Browse and download past episodes per show
```

## Hammerspoon integration (optional)

A companion Hammerspoon spoon, `iPodcastAutoLaunch`, can launch iPodcast automatically when an iPod is mounted. It lives in a separate Hammerspoon dotfiles repo.
