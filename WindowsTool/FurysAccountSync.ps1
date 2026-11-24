# Fury's Account Sync - Windows tool
# Copies your main account's addon settings and the base game's window positions to your other accounts
# on this PC. Run it with the game closed. It backs up first, shows what will change, and can undo.
#
# It only reads and writes files in Documents\Elder Scrolls Online\live\SavedVariables, plus its own
# backups and choices next to that folder. It never connects to the internet.
#
#   -Live <folder>      use another "live" folder (for example a copy, to try it out)
#   -SelfTest <folder>  for troubleshooting: opens the window, runs a preview for the first other
#                       account, saves a log and a picture of the window into <folder>, and closes.
#                       It never changes a saved file.
#   -KeepConsole        (given to the .cmd file) keep the black console window open while the tool runs
#   -Launch, -Detached  used by the .cmd file: start the tool again without a console window, then leave

param([string]$Live, [string]$SelfTest, [switch]$KeepConsole, [switch]$Launch, [switch]$Detached)

$ErrorActionPreference = 'Stop'
$toolVersion = '0.1.6'

# Anything that goes wrong while the window is being built is shown instead of the window just closing.
# Started by the .cmd file: start this script again in a process of its own with no console window,
# then leave, so the black window closes at once and nothing is left behind when the tool closes.
if ($Launch) {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Detached')
    if ($Live) { $relaunch += @('-Live', ('"' + $Live + '"')) }
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $relaunch -WindowStyle Hidden
    exit 0
}

trap {
    $problem = "Fury's Account Sync couldn't start.`n`n$($_.Exception.Message)`n(line $($_.InvocationInfo.ScriptLineNumber))"
    Write-Host $problem
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($problem, "Fury's Account Sync") | Out-Null
    exit 1
}
. (Join-Path $PSScriptRoot 'FurysAccountSyncEngine.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:testing = ($SelfTest -ne '')
$script:problems = 0
$script:logLines = New-Object System.Collections.Generic.List[string]

$paths = Get-FasPaths $Live
if (-not (Test-Path -LiteralPath $paths.SavedVars)) {
    $missing = "Can't find $($paths.SavedVars).`n`nStart the game once, log in, then close it and try again."
    if ($script:testing) { Write-Output $missing; exit 2 }
    [System.Windows.Forms.MessageBox]::Show($missing, "Fury's Account Sync") | Out-Null
    exit 1
}

# ---- Fury Night colors ----
function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml('#' + $hex) }
$col = @{
    Void = C '07060E'; Panel = C '0F0E1F'; Stripe = C '16142C'; Select = C '2D2566'; Edge = C '4A3D99'
    Violet = C 'A08CFF'; Blue = C '5CC2FF'; Text = C 'ECEAF8'; Sub = C 'B4B0D8'; Muted = C '8A86B0'
    Good = C '5EE6A0'; Warn = C 'FFC857'; Bad = C 'FF6B86'
}
$fontBody  = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$fontTitle = New-Object System.Drawing.Font('Palatino Linotype', 20)
$cursorWait   = [System.Windows.Forms.Cursors]::WaitCursor
$cursorNormal = [System.Windows.Forms.Cursors]::Default

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 15000

function New-Label($text, $x, $y, $w, $h, $color = $col.Text, $font = $fontBody) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Left = $x; $l.Top = $y; $l.Width = $w; $l.Height = $h
    $l.ForeColor = $color; $l.Font = $font; $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}

function New-Button($text, $x, $y, $w, $tipText) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Left = $x; $b.Top = $y; $b.Width = $w; $b.Height = 34
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $b.FlatAppearance.BorderColor = $col.Edge
    $b.BackColor = $col.Stripe; $b.ForeColor = $col.Text; $b.Font = $fontBold
    $tip.SetToolTip($b, $tipText)
    return $b
}

# ---- window ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Fury's Account Sync - Windows tool $toolVersion"
$form.ClientSize = New-Object System.Drawing.Size(1000, 780)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $col.Panel; $form.ForeColor = $col.Text; $form.Font = $fontBody
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle; $form.MaximizeBox = $false

$form.Controls.Add((New-Label "Fury's Account Sync" 20 10 500 40 $col.Text $fontTitle))
$line = New-Object System.Windows.Forms.Panel
$line.Left = 20; $line.Top = 54; $line.Width = 960; $line.Height = 2; $line.BackColor = $col.Violet
$form.Controls.Add($line)

$gameLabel = New-Label '' 560 20 420 24 $col.Good $fontBold
$gameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$form.Controls.Add($gameLabel)

# main account
$form.Controls.Add((New-Label 'Copy from (your main account):' 20 70 230 24 $col.Sub))
$mainBox = New-Object System.Windows.Forms.ComboBox
$mainBox.Left = 250; $mainBox.Top = 67; $mainBox.Width = 220
$mainBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$mainBox.BackColor = $col.Void; $mainBox.ForeColor = $col.Text; $mainBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$tip.SetToolTip($mainBox, 'The account the others should look like. Its own files are never changed.')
$form.Controls.Add($mainBox)

# alts
$form.Controls.Add((New-Label 'Copy to these accounts:' 20 108 260 24 $col.Blue $fontBold))
$altList = New-Object System.Windows.Forms.CheckedListBox
$altList.Left = 20; $altList.Top = 134; $altList.Width = 260; $altList.Height = 250
$altList.CheckOnClick = $true; $altList.BackColor = $col.Void; $altList.ForeColor = $col.Text
$altList.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tip.SetToolTip($altList, 'Tick the accounts that should copy the main. Accounts that have never logged in with an addon still get its settings.')
$form.Controls.Add($altList)

# base game
$form.Controls.Add((New-Label 'Base game (per character):' 20 400 260 24 $col.Blue $fontBold))
$baseCheck = New-Object System.Windows.Forms.CheckBox
$baseCheck.Text = 'Chat window, meters, quest tracker'; $baseCheck.Left = 20; $baseCheck.Top = 426; $baseCheck.Width = 260
$baseCheck.ForeColor = $col.Text
$tip.SetToolTip($baseCheck, "Copies the place and size of the chat window, and the place of the quest tracker and the frame rate and ping meters, from one of your main's characters to every character on the ticked accounts.")
$form.Controls.Add($baseCheck)
$form.Controls.Add((New-Label 'from this character:' 38 454 240 22 $col.Sub))
$charBox = New-Object System.Windows.Forms.ComboBox
$charBox.Left = 38; $charBox.Top = 478; $charBox.Width = 242
$charBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$charBox.BackColor = $col.Void; $charBox.ForeColor = $col.Text; $charBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$tip.SetToolTip($charBox, "The main's character whose chat window, meters and quest tracker positions the others get.")
$form.Controls.Add($charBox)

$note = New-Label ("Game settings, keybinds and chat colors are copied in game by the Fury's Account Sync addon. " +
    "Graphics and sound are already shared by every account on this PC.") 20 516 260 100 $col.Muted
$form.Controls.Add($note)

# addons
$form.Controls.Add((New-Label 'Addons:' 300 108 300 24 $col.Blue $fontBold))
$list = New-Object System.Windows.Forms.ListView
$list.Left = 300; $list.Top = 134; $list.Width = 680; $list.Height = 440
$list.View = [System.Windows.Forms.View]::Details; $list.CheckBoxes = $true; $list.FullRowSelect = $true
$list.BackColor = $col.Void; $list.ForeColor = $col.Text
$list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$list.Columns.Add('Saved file', 220)
[void]$list.Columns.Add('What happens', 336)
[void]$list.Columns.Add('Will change', 100)
$tip.SetToolTip($list, 'Ticked addons copy their settings from the main. Data (inventories, knowledge, guild history and the like) is never copied, even if ticked.')
$form.Controls.Add($list)

$btnAllAddons = New-Button 'Tick all settings' 300 582 160 'Ticks every addon whose settings can be copied.'
$btnNoAddons  = New-Button 'Tick none' 468 582 110 'Unticks every addon.'
$form.Controls.Add($btnAllAddons); $form.Controls.Add($btnNoAddons)

# actions
$btnPreview = New-Button 'Preview' 20 630 140 'Works out exactly what would change. Nothing is written.'
$btnApply   = New-Button 'Apply' 168 630 140 'Backs up the whole SavedVariables folder, then writes the changes shown in the preview.'
$btnRestore = New-Button 'Restore a backup...' 316 630 190 'Puts every saved file back the way it was in a backup. Your current files are backed up first.'
$btnFolder  = New-Button 'Open backups folder' 514 630 190 'Opens the folder that holds the backups.'
$btnApply.Enabled = $false
$form.Controls.AddRange(@($btnPreview, $btnApply, $btnRestore, $btnFolder))

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Left = 20; $logBox.Top = 674; $logBox.Width = 960; $logBox.Height = 94
$logBox.Multiline = $true; $logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical; $logBox.ReadOnly = $true
$logBox.BackColor = $col.Void; $logBox.ForeColor = $col.Sub
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($logBox)

# Every line also goes into a text file next to this script, so nothing is lost when the window closes.
$script:logFile = Join-Path $PSScriptRoot 'FurysAccountSync-log.txt'
$script:logFileOk = $true
function Log([string]$text) {
    $stamped = (Get-Date -Format 'HH:mm:ss') + '  ' + $text
    $script:logLines.Add($stamped)
    $script:logBox.AppendText($stamped + "`r`n")
    if ($script:logFileOk -and -not $script:testing) {
        try {
            [System.IO.File]::AppendAllText($script:logFile, ((Get-Date -Format 'yyyy-MM-dd ') + $stamped + "`r`n"))
        } catch {
            $script:logFileOk = $false
        }
    }
}

# A problem is shown in a message as well: a line in the box at the bottom is easy to miss.
function Show-Problem([string]$text) {
    Log $text
    if (-not $script:testing) {
        [System.Windows.Forms.MessageBox]::Show($text, "Fury's Account Sync", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

# Runs one button's work. If anything goes wrong the reason goes in the log instead of being lost.
function Guard([scriptblock]$work) {
    try {
        & $work
    } catch {
        $script:problems++
        $form.Cursor = $cursorNormal
        Show-Problem ("Something went wrong: {0} (line {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
    }
}

# ---- state ----
$script:inventory = $null
$script:plan = $null
$script:loading = $false
$script:choices = Read-FasChoices $paths

function Update-GameStatus {
    if (Test-GameRunning) {
        $gameLabel.Text = 'The game is running: close it before applying'
        $gameLabel.ForeColor = $col.Bad
        return $false
    }
    $gameLabel.Text = 'Game closed: ready'
    $gameLabel.ForeColor = $col.Good
    return $true
}

function Invalidate-Plan {
    $script:plan = $null
    $btnApply.Enabled = $false
    foreach ($item in $list.Items) { $item.SubItems[2].Text = '' }
}

function Get-TickedAlts {
    $out = @()
    foreach ($a in $altList.CheckedItems) { $out += [string]$a }
    return $out
}

function Get-TickedFiles {
    $out = @()
    foreach ($item in $list.CheckedItems) { $out += $item.Text }
    return $out
}

function Test-CanTick([string]$kind) {
    return ($kind -eq 'settings' -or $kind -eq 'except' -or $kind -eq 'unknown')
}

function Fill-Characters {
    $charBox.Items.Clear()
    if ($mainBox.SelectedItem) {
        foreach ($c in (Get-MainCharacters $script:inventory ([string]$mainBox.SelectedItem))) { [void]$charBox.Items.Add($c) }
    }
    $saved = $script:choices
    if ($saved -and $saved.baseFrom -and $charBox.Items.Contains($saved.baseFrom)) {
        $charBox.SelectedItem = $saved.baseFrom
    } elseif ($charBox.Items.Count -gt 0) {
        $charBox.SelectedIndex = 0
    }
}

function Fill-Alts {
    $altList.Items.Clear()
    $ticked = @()
    $saved = $script:choices
    if ($saved -and $saved.alts) { $ticked = @($saved.alts) }
    foreach ($a in $script:inventory.Accounts) {
        if ($a -eq [string]$mainBox.SelectedItem) { continue }
        $i = $altList.Items.Add($a)
        if ($ticked -contains $a) { $altList.SetItemChecked($i, $true) }
    }
}

function Load-Folder {
    $script:loading = $true
    try {
        $form.Cursor = $cursorWait
        Log "Reading $($paths.SavedVars) ..."
        $script:inventory = Get-FasInventory $paths.SavedVars
        $form.Cursor = $cursorNormal
        $saved = $script:choices

        $mainBox.Items.Clear()
        foreach ($a in $script:inventory.Accounts) { [void]$mainBox.Items.Add($a) }
        $main = $null
        if ($saved -and $saved.main) { $main = $saved.main }
        if (-not $main) { $main = Get-FasMainFromAddon $script:inventory }
        if ($main -and $mainBox.Items.Contains($main)) { $mainBox.SelectedItem = $main }
        elseif ($mainBox.Items.Count -gt 0) { $mainBox.SelectedIndex = 0 }

        Fill-Alts
        Fill-Characters
        $baseCheck.Checked = [bool]($saved -and $saved.baseGame)

        $list.BeginUpdate()
        $list.Items.Clear()
        $unticked = @()
        $tickedUnknown = @()
        if ($saved) {
            if ($saved.unticked) { $unticked = @($saved.unticked) }
            if ($saved.tickedUnknown) { $tickedUnknown = @($saved.tickedUnknown) }
        }
        $stripe = $false
        foreach ($f in $script:inventory.Files) {
            $kind = Get-FileKind $f
            $item = New-Object System.Windows.Forms.ListViewItem($f.Sv.Name)
            $text = Get-KindText $kind $f
            if ($f.Sv.Error) { $text = "Left alone: $($f.Sv.Error)" }
            [void]$item.SubItems.Add($text)
            [void]$item.SubItems.Add('')
            $item.Tag = $kind
            $item.UseItemStyleForSubItems = $true
            if ($stripe) { $item.BackColor = $col.Stripe } else { $item.BackColor = $col.Void }
            $stripe = -not $stripe
            switch ($kind) {
                'settings' { $item.ForeColor = $col.Text;  $item.Checked = -not ($unticked -contains $f.Sv.Name) }
                'except'   { $item.ForeColor = $col.Text;  $item.Checked = -not ($unticked -contains $f.Sv.Name) }
                'unknown'  { $item.ForeColor = $col.Warn;  $item.Checked = ($tickedUnknown -contains $f.Sv.Name) }
                default    { $item.ForeColor = $col.Muted; $item.Checked = $false }
            }
            [void]$list.Items.Add($item)
        }
        $list.EndUpdate()
    } finally {
        $script:loading = $false
        $form.Cursor = $cursorNormal
    }
    Invalidate-Plan
    Log ("Found {0} saved files and {1} accounts." -f $script:inventory.Files.Count, $script:inventory.Accounts.Count)
}

function Save-Choices {
    $unticked = @(); $tickedUnknown = @()
    foreach ($item in $list.Items) {
        $kind = [string]$item.Tag
        if (($kind -eq 'settings' -or $kind -eq 'except') -and -not $item.Checked) { $unticked += $item.Text }
        if ($kind -eq 'unknown' -and $item.Checked) { $tickedUnknown += $item.Text }
    }
    $base = $null
    if ($charBox.SelectedItem) { $base = [string]$charBox.SelectedItem }
    $script:choices = [pscustomobject]@{
        main = [string]$mainBox.SelectedItem; alts = @(Get-TickedAlts); unticked = $unticked
        tickedUnknown = $tickedUnknown; baseGame = $baseCheck.Checked; baseFrom = $base
    }
    if (-not $script:testing) { Save-FasChoices $paths $script:choices }
}

# ---- what the buttons do ----
function Do-Preview {
    Invalidate-Plan
    $alts = @(Get-TickedAlts)
    if (-not $mainBox.SelectedItem) { Log 'Pick your main account first.'; return }
    if ($alts.Count -eq 0) { Log 'Tick at least one account to copy to.'; return }
    $baseFrom = $null
    if ($baseCheck.Checked -and $charBox.SelectedItem) { $baseFrom = [string]$charBox.SelectedItem }
    $files = @(Get-TickedFiles)
    if ($files.Count -eq 0 -and -not $baseFrom) { Log 'Tick at least one addon, or the chat window, meters and quest tracker box.'; return }

    $form.Cursor = $cursorWait
    # Read the folder again so the preview matches the files as they are right now.
    $script:inventory = Get-FasInventory $paths.SavedVars
    $plan = New-FasPlan $script:inventory @{ Main = [string]$mainBox.SelectedItem; Alts = $alts; Files = $files; BaseGameFrom = $baseFrom }
    $form.Cursor = $cursorNormal
    Save-Choices

    $changed = @{}
    foreach ($p in $plan) { $changed[$p.Name] = $p.Changes.Count }
    foreach ($item in $list.Items) {
        if ($changed.ContainsKey($item.Text)) {
            $n = $changed[$item.Text]
            if ($n -eq 1) { $item.SubItems[2].Text = '1 change' } else { $item.SubItems[2].Text = "$n changes" }
        } elseif ($item.Checked) {
            $item.SubItems[2].Text = 'matches'
        }
    }
    if ($plan.Count -eq 0) {
        Log 'Preview: everything ticked already matches the main. Nothing to do.'
        return
    }
    $fileWord = 'files'
    if ($plan.Count -eq 1) { $fileWord = 'file' }
    Log ("Preview: {0} {1} would change for {2}:" -f $plan.Count, $fileWord, ($alts -join ', '))
    foreach ($p in $plan) {
        $shown = @($p.Changes | Select-Object -First 12)
        $more = $p.Changes.Count - $shown.Count
        $text = $shown -join '; '
        if ($more -gt 0) { $text += "; and $more more" }
        Log ("   {0}: {1}" -f $p.Name, $text)
    }
    $script:plan = $plan
    $btnApply.Enabled = $true
}

function Do-Apply {
    if (-not $script:plan) { return }
    if (-not (Update-GameStatus)) { Log 'Close the game completely first.'; return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ("Change {0} saved files for {1}?`n`nThe whole SavedVariables folder is backed up first, and Restore a backup puts it back." -f $script:plan.Count, (@(Get-TickedAlts) -join ', ')),
        "Fury's Account Sync", [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $form.Cursor = $cursorWait
    $result = Invoke-FasPlan $paths $script:plan { param($m) Log $m }
    $form.Cursor = $cursorNormal
    Invalidate-Plan
    if (-not $result.Ok) { Show-Problem $result.Message } else { Log $result.Message }
    if ($result.Ok) {
        [System.Windows.Forms.MessageBox]::Show("Done. Log in on each account to see it.`n`nBackup: $($result.Backup)", "Fury's Account Sync") | Out-Null
    }
    Load-Folder
}

function Do-Restore {
    if (-not (Update-GameStatus)) { Log 'Close the game completely first.'; return }
    $backups = @(Get-FasBackups $paths)
    if ($backups.Count -eq 0) { Log 'There are no backups yet.'; return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.InitialDirectory = $paths.Backups
    $dlg.Filter = 'Backups (*.zip)|*.zip'
    $dlg.Title = 'Pick the backup to put back'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Put every saved file back the way it was in:`n$([IO.Path]::GetFileName($dlg.FileName))`n`nYour files as they are now are backed up first.",
        "Fury's Account Sync", [System.Windows.Forms.MessageBoxButtons]::OKCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $form.Cursor = $cursorWait
    $now = New-FasBackup $paths ' before restore'
    Log "Backed up the current files to $now"
    try {
        Restore-FasBackup $paths $dlg.FileName
    } catch {
        Log "That backup couldn't be put back ($($_.Exception.Message)). Putting your files back the way they were."
        Restore-FasBackup $paths $now
        throw
    }
    $form.Cursor = $cursorNormal
    Log "Restored $([IO.Path]::GetFileName($dlg.FileName))."
    Load-Folder
}

# ---- events ----
$mainBox.Add_SelectedIndexChanged({
    if ($script:loading) { return }
    Guard { Fill-Alts; Fill-Characters; Invalidate-Plan }
})
$altList.Add_ItemCheck({ if (-not $script:loading) { Guard { Invalidate-Plan } } })
$baseCheck.Add_CheckedChanged({ if (-not $script:loading) { Guard { Invalidate-Plan } } })
$charBox.Add_SelectedIndexChanged({ if (-not $script:loading) { Guard { Invalidate-Plan } } })
$list.Add_ItemCheck({
    param($source, $e)
    if ($script:loading) { return }
    try {
        # Data, skipped and unreadable files can't be ticked.
        if (-not (Test-CanTick ([string]$list.Items[$e.Index].Tag))) {
            $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
            return
        }
        Invalidate-Plan
    } catch {
        $script:problems++
        Log ("Something went wrong: {0}" -f $_.Exception.Message)
    }
})
$btnAllAddons.Add_Click({
    Guard {
        foreach ($item in $list.Items) {
            $k = [string]$item.Tag
            if ($k -eq 'settings' -or $k -eq 'except') { $item.Checked = $true }
        }
    }
})
$btnNoAddons.Add_Click({ Guard { foreach ($item in $list.Items) { $item.Checked = $false } } })
$btnPreview.Add_Click({ Guard { Do-Preview } })
$btnApply.Add_Click({ Guard { Do-Apply } })
$btnRestore.Add_Click({ Guard { Do-Restore } })
$btnFolder.Add_Click({
    Guard {
        if (-not (Test-Path -LiteralPath $paths.Backups)) { New-Item -ItemType Directory -Path $paths.Backups | Out-Null }
        Start-Process explorer.exe -ArgumentList ('"' + $paths.Backups + '"')
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Guard { [void](Update-GameStatus) } })
$timer.Start()

$form.Add_Shown({
    Guard {
        $form.Refresh()
        $form.Activate()
        [void](Update-GameStatus)
        Load-Folder
        Log 'Tick the accounts to copy to and the addons to copy, then press Preview.'
    }
})
$form.Add_FormClosing({ $timer.Stop() })

# ---- self test: load, preview for the first other account, save a log and a picture, close ----
if ($script:testing) {
    $stopper = New-Object System.Windows.Forms.Timer
    $stopper.Interval = 120000
    $stopper.Add_Tick({ $script:problems++; $script:logLines.Add('SELF TEST: took too long, closing'); $form.Close() })
    $stopper.Start()
    $form.Add_Shown({
        try {
            Guard {
                Log ("SELF TEST: main {0}; {1} other accounts; {2} rows; {3} characters on the main" -f `
                    $mainBox.SelectedItem, $altList.Items.Count, $list.Items.Count, $charBox.Items.Count)
                $byKind = @{}
                foreach ($item in $list.Items) { $k = [string]$item.Tag; $byKind[$k] = 1 + [int]$byKind[$k] }
                Log ('SELF TEST: rows by kind: ' + (($byKind.Keys | Sort-Object | ForEach-Object { "$_=$($byKind[$_])" }) -join ', '))
                $tickedBefore = $list.CheckedItems.Count
                # A file that can't be ticked must stay unticked.
                $locked = $null
                foreach ($item in $list.Items) { if (-not (Test-CanTick ([string]$item.Tag))) { $locked = $item; break } }
                if ($locked) {
                    $locked.Checked = $true
                    if ($locked.Checked) { throw "a file that is never copied ($($locked.Text)) could be ticked" }
                }
                if ($altList.Items.Count -eq 0) { throw 'no other account to try' }
                for ($i = 0; $i -lt $altList.Items.Count; $i++) { $altList.SetItemChecked($i, ($i -eq 0)) }
                if ($charBox.Items.Count -gt 0) { $baseCheck.Checked = $true }
                Do-Preview
                $planned = 0
                if ($script:plan) { $planned = @($script:plan).Count }
                Log ("SELF TEST: {0} files ticked; preview for {1}: {2} files would change; Apply button on: {3}" -f `
                    $tickedBefore, $altList.Items[0], $planned, $btnApply.Enabled)
                [System.Windows.Forms.Application]::DoEvents()
                if (-not (Test-Path -LiteralPath $SelfTest)) { New-Item -ItemType Directory -Path $SelfTest | Out-Null }
                $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
                $bmp.Save((Join-Path $SelfTest 'selftest-window.png'), [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                Log 'SELF TEST: picture saved'
            }
        } finally {
            $stopper.Stop()
            $script:logLines.Add("SELF TEST: finished with $($script:problems) problems")
            if (Test-Path -LiteralPath $SelfTest) {
                [System.IO.File]::WriteAllLines((Join-Path $SelfTest 'selftest-log.txt'), $script:logLines)
            }
            $form.Close()
        }
    })
}

[void]$form.ShowDialog()

if ($script:testing) {
    $script:logLines | ForEach-Object { Write-Output $_ }
    if ($script:problems -gt 0) { exit 1 }
    exit 0
}
