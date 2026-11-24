Fury's Account Sync - Windows tool
==================================

AI disclosure: This tool's code was written with the assistance of an AI coding assistant (Claude by
Anthropic), working from my designs and instructions. I test every release on my own accounts before it
goes up, and I maintain it. Please report any problem in the comments on ESOUI or on GitHub.

What it does
------------
Makes your other ESO accounts on this PC match your main one:
  - every addon's settings and window positions (Bandits, Perfect Pixel, pChat, Combat Alerts and so on)
  - optionally, the base game's chat window place and size, and the quest tracker and meter positions,
    copied from one of your main's characters to every character on the other accounts

Game settings, keybinds and chat colors are copied in game by the Fury's Account Sync addon. The addon can
also copy addon settings in game, for addons that are turned on for the account. This tool covers every
addon in the folder, turned on or not, and makes a full backup first.
Graphics and sound are already the same for every account on one PC.

Version 0.1.7

Where to put it
---------------
Keep this folder anywhere you like: the Desktop, Documents, or a tools folder. It finds your Elder Scrolls
Online folder by itself. Keep the four files together. If you keep it inside the AddOns folder, an addon
manager such as Minion may remove it when it updates the addon.

How to use it
-------------
1. Play on your main account until everything looks right, then close the game completely.
2. Double-click "Fury's Account Sync.cmd".
3. Pick your main account, tick the accounts to copy to, and check the addon list.
4. Press Preview. It lists exactly what would change. Nothing is written yet.
5. Press Apply. It backs up the whole SavedVariables folder first, then writes the changes.
6. Log in on each account.

Undo: press "Restore a backup..." and pick a backup. Your current files are backed up before it restores.

What it never does
------------------
  - It never runs while the game is running.
  - It never copies addon data: inventories, character knowledge, guild history, sales, fight logs,
    maps, catalogues and the like. Each known addon has a rule. Addons it doesn't know are left alone
    unless you tick them.
  - It never changes your main account's own files.
  - It never connects to the internet.

Files it reads and writes
-------------------------
  - Reads and writes:  Documents\Elder Scrolls Online\live\SavedVariables\*.lua
  - Writes backups to: Documents\Elder Scrolls Online\Fury's Account Sync Backups\ (keeps the newest 10)
  - Remembers your choices in: Documents\Elder Scrolls Online\Fury's Account Sync choices.json

A file is only changed if the tool can read it and write it back byte for byte. Every changed file is read
back and checked; if anything doesn't check out, every file is put back from the backup.

The .cmd and .ps1 files are plain text you can open in Notepad. They only run when you start them.

If something goes wrong
----------------------
Anything that fails is shown in a message and written in the box at the bottom of the window. The same
lines are kept in FurysAccountSync-log.txt next to the tool. To send a report, run
    "Fury's Account Sync.cmd" -SelfTest "%USERPROFILE%\Desktop\FAS-check"
It opens the window, runs a preview for the first other account, saves a log and a picture of the window
into that folder, and closes. It never changes a saved file.

If the window can't start at all, a message says why, and the black window stays open so you can read it.
To keep the black window showing all the time, run
    "Fury's Account Sync.cmd" -KeepConsole

Changes
-------
0.1.7  Fixes 0.1.6, where the tool started but its window stayed hidden.
0.1.6  No black window any more: the launcher starts the tool without a console and closes at once,
       so nothing is left on the desktop when the tool closes. (0.1.4 and 0.1.5 could leave a minimized
       black window behind.)
0.1.5  Apply works. (Up to 0.1.4 it stopped right after making the backup and wrote nothing.) A problem
       is shown in a message, not only in the box at the bottom. Everything in that box is also kept in
       FurysAccountSync-log.txt next to the tool. The base game box is named for what it copies: the
       chat window, meters and quest tracker. Chat tabs are kept by the game's server, not in a file,
       so this tool can't copy them.
0.1.3  The window stays open. (0.1.2 closed by itself after a few seconds because it started in its
       troubleshooting mode.) Preview and Apply now include the ticked addons for every ticked account,
       not only the chat tabs and window positions. The title bar shows the version. A problem at start
       is shown instead of the window just closing.
0.1.2  Knows the same addons as the in-game addon.

Not covered yet
---------------
  - Addon settings that an addon saves per character (only account-wide settings are copied).
  - Which addons are turned on.
