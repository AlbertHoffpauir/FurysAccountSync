# Fury's Account Sync

**AI disclosure:** This addon's code was written with the assistance of an AI coding assistant (Claude by Anthropic), working from my designs and instructions. I test every release in game on my own accounts before it goes up, and I maintain it. Please report any problem in the comments on ESOUI or in the issues here.

An Elder Scrolls Online addon for people who play more than one account on the same PC. Set up your main account the way you like it, and your other accounts copy it: game settings, keybinds, chat look, addon settings and window positions, plus character builds you can load onto any character on any account. Everything starts turned off, and nothing changes on an account until you turn it on there.

## Downloads

- **The addon:** get it from [ESOUI](https://www.esoui.com/downloads/info5106-FurysAccountSync.html) or Minion. The same files are in [`FurysAccountSync/`](FurysAccountSync/) here, and as [FurysAccountSync-0.5.1.zip](https://github.com/AlbertHoffpauir/FurysAccountSync/raw/main/downloads/FurysAccountSync-0.5.1.zip).
- **Windows tool** (optional): copies addon settings and the base game's window positions with the game closed, for every addon in the folder, with a full backup first. Copying addon settings can break an addon, so only a small set of well-known addons is ticked to begin with. **[Download FurysAccountSync-WindowsTool-0.2.1.zip](https://github.com/AlbertHoffpauir/FurysAccountSync/raw/main/downloads/FurysAccountSync-WindowsTool-0.2.1.zip)**, unzip it anywhere and double-click `Fury's Account Sync.cmd`.

The tool is made of plain-text scripts (batch and PowerShell) you can open in Notepad. It only reads and writes the addon saved data files in `Documents\Elder Scrolls Online\live\SavedVariables`, keeps its backups and choices next to that folder, and never connects to the internet. It is a separate download because ESOUI addon zips may only hold addon files.

## What copies what

| | In game (the addon) | Windows tool |
|---|---|---|
| Game settings, keybinds, chat colors | Yes | No (the game keeps these on its server) |
| Addon settings | Yes, for ticked addons that are turned on for the account | Yes, for every ticked addon in the folder |
| Chat window, meters and quest tracker positions | Yes | Yes |
| Character builds (skill bars, champion stars, quickslots, gear) | Yes | No |
| Addon data (inventories, knowledge, history, logs) | Never | Never |

## Repository layout

| Folder | What |
|---|---|
| `FurysAccountSync/` | The addon, exactly as it goes into `Documents\Elder Scrolls Online\live\AddOns`. See its [README](FurysAccountSync/README.md) and [CHANGELOG](FurysAccountSync/CHANGELOG.md). |
| `WindowsTool/` | The Windows tool (`Fury's Account Sync.cmd`). See its [README](WindowsTool/README.txt). |
| `downloads/` | Ready-made zips of both for each release. |
| `docs/` | The ESOUI page description. |

## Credits

- Settings page uses **LibAddonMenu-2.0** by Seerah and sirinsidiator.
- Game API details from the ESOUI wiki and ZeniMax's ESO UI source code.

License: MIT (see [LICENSE](LICENSE)).
