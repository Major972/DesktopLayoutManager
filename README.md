# Desktop Layout Manager

**A tiny Windows app that remembers where your desktop icons live, and puts them back when something scrambles them.**

*Made in Türkiye 🇹🇷 by a Turkish developer, because a game messing up my desktop one too many times was the last straw.*

---

## Why this exists

If you play games on a 2K or 4K monitor, you probably know this pain: you launch a game that only runs at a lower resolution, quit it, and your carefully organized desktop is now a pile of icons crammed into the top-left corner.

Windows doesn't keep a safe copy of your layout. So I built one.

Desktop Layout Manager looks at your desktop, saves every icon's position under a name you choose, and restores it with one click. It can even do it automatically when your screen returns to its normal resolution.

## What it does

- **Save** your current desktop layout under any name
- **Restore** a saved layout with one click (or double-click it in the list)
- **Preview** a layout before restoring it, drawn with your real desktop icons
- **Auto-restore** after a game changes your resolution and you come back to 2560x1440
- **Apply a rule layout**: a ready-made tidy-up script that puts apps on the left, folders in the middle and games on the right, in neat two-column groups
- Dark, simple interface. No installer, no background service, nothing hidden.

## Getting started

You need Windows 10 or 11. PowerShell is already on your machine, so there is nothing to install.

1. Download or clone this repository.
2. Run the app:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\DesktopLayoutManager.ps1
   ```

3. Arrange your desktop the way you like it, type a name, and press **Save current layout**.
4. Next time things get messy, pick the layout from the list and press **Restore selected**.

Want a desktop shortcut with a nice icon? Run this once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Create-Shortcut.ps1
```

Your saved layouts are stored as small JSON files in `Documents\DesktopLayouts`, so they're easy to back up or share.

## The rule layout (optional)

`DesktopLayout.ps1` is the "tidy everything for me" script. It arranges your desktop in a grid:

| Columns | What goes there |
|---------|-----------------|
| 1-2 | Apps, in small groups |
| 4-5 | Folders and files |
| 7-8 | Games |

The groups and launcher names are listed at the top of the script. Open it in any text editor and swap in your own apps.

## Auto-restore

Tick the box at the bottom of the app, select the layout you want, and leave the app running (minimized is fine). When your screen goes back to 2560x1440, it waits a few seconds and restores that layout for you.

If your monitor isn't 2560x1440, change the resolution in the script (search for `2560x1440`).

## How it works (for the curious)

Windows draws your desktop icons in a normal list control owned by Explorer. This app finds that control, asks it for each icon's name and position, and later sends the positions back. No registry hacks and no modifying system files.

## Good to know

- Windows only. Built and tested on Windows 11 with a 2560x1440 screen.
- If Windows' *Auto arrange icons* or *Align icons to grid* are on, positions may snap back. Turn them off from the desktop right-click menu, under **View**.
- Icons are matched by their displayed name. If you rename a shortcut, it won't be restored to its old spot.
- The interface is in English for now.
- Pull requests and ideas are welcome.

## License

MIT. Use it, change it, share it.
