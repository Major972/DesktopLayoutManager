# Desktop Layout Manager

**A small Windows app that remembers where your desktop icons live, and puts them back the moment something scrambles them. It can even switch layouts by itself when your screen resolution changes.**

*Made in Türkiye 🇹🇷 by a Turkish developer, because a game messing up my desktop one too many times was the last straw.*

---

## Why this exists

If you play games on a 2K or 4K monitor, you probably know this pain. You launch a game that only runs at a lower resolution, quit it, and your carefully organized desktop is now a pile of icons crammed into the top-left corner.

Windows doesn't keep a safe copy of your layout, and it doesn't care that you spent twenty minutes arranging everything. So I built one.

Desktop Layout Manager looks at your desktop, saves every icon's position under a name you choose, and puts everything back with one click. If you want, it does that on its own whenever your screen resolution changes.

## What it does

- **Save** your current desktop layout under any name you like
- **Restore** a saved layout with one click (or double-click it in the list)
- **Preview** any layout before restoring it, drawn with your real desktop icons
- **Auto-switch by resolution**: when your screen changes resolution, the layout you saved for that resolution comes back automatically
- **Apply a rule layout**: a ready-made tidy-up that puts apps on the left, folders in the middle and games on the right, in neat two-column groups
- A dark, simple interface. No installer, no background service, nothing hidden.

## Getting started

You need Windows 10 or 11. PowerShell is already on your machine, so there is nothing to install.

1. Download or clone this repository.
2. Run the app:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\DesktopLayoutManager.ps1
   ```

3. Arrange your desktop the way you like it, type a name, and press **Save current layout**.
4. Next time things get messy, pick that layout from the list and press **Restore selected**.

Want a desktop shortcut with a proper icon? Run this once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Create-Shortcut.ps1
```

## Using the app

The window has three parts.

**Saved layouts (left).** Every layout you save shows up here, newest first. Click one to preview it, double-click to restore it. Below the list you see how many layouts you have and your current screen resolution.

**Desktop preview (middle).** A small map of your screen, drawn with the real icons of your desktop items (games, apps, folders). Hover over an icon to see its name. Click **Show current** to preview your desktop as it looks right now. If an icon can't be found, you get a colored tile with its first letter instead.

**Actions (right).**

| Button | What it does |
|--------|--------------|
| Save current layout | Saves the desktop as it is now, under the name in the box |
| Restore selected | Puts every icon back where the selected layout had it |
| Delete selected | Deletes the selected layout (it asks first) |
| Apply rule layout | Runs the tidy-up script described below |
| Open layouts folder | Opens the folder where your layouts are stored |

At the bottom you'll find a status line (green for success, red for errors) and the auto-switch checkbox.

## Auto-switch by resolution

This is the feature I built the whole thing for.

Every layout remembers the screen resolution it was saved at. When you tick the **Auto-switch** checkbox and leave the app running, it keeps an eye on your screen. The moment the resolution changes, it waits five seconds (Windows needs a moment to finish rearranging the icons) and restores the layout that belongs to the new resolution.

**A real example.** My monitor is 2560x1440. One of my games only runs at 1920x1080.

1. At 2560x1440 I arrange my desktop and save it as `Main desk`. The app records "2560x1440".
2. I launch the game. Windows switches to 1920x1080 and shoves all my icons into a corner.
3. I quit the game. The screen goes back to 2560x1440.
4. Five seconds later, the app finds `Main desk` (saved at 2560x1440) and puts every icon back. I didn't touch anything.

**It works for any resolution, not just one.** Want a different arrangement when you plug in a 1080p TV or switch to a lower resolution? Change the resolution, arrange your icons, and save a second layout. From then on, each time the screen switches to that resolution, its own layout appears.

**The rules, in plain words:**

- Layouts are matched by the resolution they were saved at, shown as the "screen" value in the layout details.
- If you have several layouts saved at the same resolution, the one currently selected in the list wins. Otherwise the most recently saved one is used.
- If there is no layout for the new resolution, nothing is moved. The status line tells you so.
- The app has to be running (a minimized window is fine). It only reacts to changes that happen while it is open.
- The first resolution it sees at startup is the starting point; it only reacts to *changes* after that.

## The rule layout (optional)

`DesktopLayout.ps1` is the "tidy everything for me" script, also available from the **Apply rule layout** button. It arranges your desktop in a grid:

| Columns | What goes there |
|---------|-----------------|
| 1-2 | Apps, in small groups |
| 4-5 | Folders and files |
| 7-8 | Games (launchers first, then game shortcuts) |

It leaves an empty column between the groups and moves the Recycle Bin out of the way. The groups and launcher names are listed at the top of the script. Open it in any text editor and swap in your own apps. It expects to sit in the same folder as the app.

## Where your layouts live

Layouts are saved as small, readable JSON files in `Documents\DesktopLayouts`, so they're easy to back up or share. Each one looks like this:

```json
{
  "SavedAt": "2026-11-19T18:30:00",
  "Screen": "2560x1440",
  "Items": [
    { "Name": "Discord", "X": 18, "Y": 306 },
    { "Name": "Steam",   "X": 93, "Y": 10 }
  ]
}
```

## How it works (for the curious)

Windows draws your desktop icons in a normal list control that belongs to Explorer. This app finds that control, asks it for the name and position of every icon, and later sends the positions back. That's it. No registry hacks, no system files touched, no admin rights needed.

The preview gets its icons straight from your desktop shortcuts (including the custom icons that game shortcuts carry), so it looks like your real desktop.

## Good to know

- Windows only. Built and tested on Windows 11 with a 2560x1440 screen.
- If Windows' *Auto arrange icons* or *Align icons to grid* are on, positions may snap back. Turn them off from the desktop right-click menu, under **View**.
- Icons are matched by their displayed name. If you rename a shortcut, it won't be restored to its old spot.
- Only the primary monitor's resolution is watched.
- The interface is in English for now.
- Everything runs locally. Nothing is sent anywhere.

## Contributing

Ideas, bug reports and pull requests are all welcome. If it breaks on your setup, open an issue with your Windows version and screen resolution.

## License

MIT. Use it, change it, share it.
