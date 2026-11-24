# Fury's Account Sync - Windows tool, engine
# Reads and writes ESO SavedVariables files. Used by FurysAccountSync.ps1 (the window).
#
# Safety rules built in here:
#   - Files are read and written byte for byte (Latin-1), so text in any language survives untouched.
#   - A file is only edited if reading it and writing it back unchanged gives exactly the same bytes.
#   - Every written file is read back and checked. Any failure restores the whole folder from the backup.
#   - Only the chosen alt accounts' sections change. The main account's own sections are never written.

$ErrorActionPreference = 'Stop'

if (-not ('FuryAS.Node' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

namespace FuryAS
{
    // One value in a SavedVariables file: a table (ordered keys) or a plain value kept as its raw text.
    public class Node
    {
        public bool IsTable;
        public string Raw;                         // plain values: exactly as written in the file
        public List<string> Keys;                  // tables: raw key text, e.g. "\"@Furyous\"" or "12"
        public List<Node> Values;

        public static Node NewTable()
        {
            Node n = new Node();
            n.IsTable = true;
            n.Keys = new List<string>();
            n.Values = new List<Node>();
            return n;
        }

        public int IndexOf(string key)
        {
            if (!IsTable) return -1;
            for (int i = 0; i < Keys.Count; i++) if (Keys[i] == key) return i;
            return -1;
        }

        public Node Get(string key)
        {
            int i = IndexOf(key);
            return i < 0 ? null : Values[i];
        }

        public void Set(string key, Node value)
        {
            int i = IndexOf(key);
            if (i < 0) { Keys.Add(key); Values.Add(value); }
            else Values[i] = value;
        }

        public void Remove(string key)
        {
            int i = IndexOf(key);
            if (i >= 0) { Keys.RemoveAt(i); Values.RemoveAt(i); }
        }

        public Node Clone()
        {
            Node n = new Node();
            n.IsTable = IsTable;
            n.Raw = Raw;
            if (IsTable)
            {
                n.Keys = new List<string>(Keys);
                n.Values = new List<Node>(Values.Count);
                foreach (Node v in Values) n.Values.Add(v.Clone());
            }
            return n;
        }

        public string ToText()
        {
            StringBuilder sb = new StringBuilder();
            Sv.Write(sb, this, 0, "\n");
            return sb.ToString();
        }
    }

    // A whole file: one or more "Name =" assignments.
    public class SvFile
    {
        public List<string> Names = new List<string>();
        public List<Node> Roots = new List<Node>();
        public string Newline = "\n";             // the game writes Windows line endings
        public bool Compact;                      // the file is written with no spaces or line breaks at all
        public string Between = "";               // compact files: what stands between two assignments
        public string Tail = "";                  // compact files: what follows the last assignment

        public Node Get(string name)
        {
            int i = Names.IndexOf(name);
            return i < 0 ? null : Roots[i];
        }
    }

    public static class Sv
    {
        // ---------------- reading ----------------
        class Reader
        {
            public string T; public int P;
            public Reader(string t) { T = t; P = 0; }

            public void Ws()
            {
                while (P < T.Length && (T[P] == ' ' || T[P] == '\t' || T[P] == '\r' || T[P] == '\n')) P++;
            }

            public bool AtEnd() { Ws(); return P >= T.Length; }

            public char Peek() { Ws(); if (P >= T.Length) throw Fail("unexpected end of file"); return T[P]; }

            public void Expect(char c)
            {
                if (Peek() != c) throw Fail("expected '" + c + "'");
                P++;
            }

            public Exception Fail(string what)
            {
                int line = 1;
                for (int i = 0; i < P && i < T.Length; i++) if (T[i] == '\n') line++;
                return new FormatException(what + " on line " + line);
            }

            public string Word()
            {
                Ws();
                int s = P;
                while (P < T.Length && (char.IsLetterOrDigit(T[P]) || T[P] == '_')) P++;
                if (P == s) throw Fail("expected a name");
                return T.Substring(s, P - s);
            }

            public string StringLit()
            {
                Ws();
                int s = P;
                if (T[P] != '"') throw Fail("expected a string");
                P++;
                while (P < T.Length && T[P] != '"')
                {
                    if (T[P] == '\\') P++;
                    P++;
                }
                if (P >= T.Length) throw Fail("unterminated string");
                P++;
                return T.Substring(s, P - s);
            }

            public string Atom()
            {
                Ws();
                int s = P;
                while (P < T.Length)
                {
                    char c = T[P];
                    if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\r' || c == '\n') break;
                    P++;
                }
                if (P == s) throw Fail("expected a value");
                return T.Substring(s, P - s);
            }

            public Node Value()
            {
                char c = Peek();
                if (c == '{') return Table();
                Node n = new Node();
                n.Raw = (c == '"') ? StringLit() : Atom();
                return n;
            }

            public Node Table()
            {
                Expect('{');
                Node t = Node.NewTable();
                while (true)
                {
                    char c = Peek();
                    if (c == '}') { P++; return t; }
                    Expect('[');
                    string key = (Peek() == '"') ? StringLit() : Atom();
                    Expect(']');
                    Expect('=');
                    Node v = Value();
                    t.Keys.Add(key);
                    t.Values.Add(v);
                    if (Peek() == ',') P++;
                }
            }
        }

        public static SvFile Parse(string text)
        {
            Reader r = new Reader(text);
            SvFile f = new SvFile();
            if (text.Contains("\r\n")) f.Newline = "\r\n";
            // Newer game versions save these files with no spaces or line breaks at all: Name={["k"]=1,}
            int endOfLast = -1;
            while (!r.AtEnd())
            {
                if (endOfLast >= 0 && f.Names.Count == 1) f.Between = text.Substring(endOfLast, r.P - endOfLast);
                string name = r.Word();
                if (f.Names.Count == 0 && r.P + 1 < text.Length && text[r.P] == '=' && text[r.P + 1] == '{') f.Compact = true;
                r.Expect('=');
                f.Names.Add(name);
                f.Roots.Add(r.Value());
                endOfLast = r.P;
            }
            if (endOfLast >= 0) f.Tail = text.Substring(endOfLast);
            return f;
        }

        // ---------------- writing (the game's own layout) ----------------
        public static void Write(StringBuilder sb, Node n, int indent, string nl)
        {
            if (!n.IsTable) { sb.Append(n.Raw); return; }
            sb.Append(nl).Append(' ', indent).Append('{');
            for (int i = 0; i < n.Keys.Count; i++)
            {
                sb.Append(nl).Append(' ', indent + 4).Append('[').Append(n.Keys[i]).Append("] = ");
                Write(sb, n.Values[i], indent + 4, nl);
                sb.Append(',');
            }
            sb.Append(nl).Append(' ', indent).Append('}');
        }

        public static void WriteCompact(StringBuilder sb, Node n)
        {
            if (!n.IsTable) { sb.Append(n.Raw); return; }
            sb.Append('{');
            for (int i = 0; i < n.Keys.Count; i++)
            {
                sb.Append('[').Append(n.Keys[i]).Append("]=");
                WriteCompact(sb, n.Values[i]);
                sb.Append(',');
            }
            sb.Append('}');
        }

        public static string Serialize(SvFile f)
        {
            StringBuilder sb = new StringBuilder();
            if (f.Compact)
            {
                for (int i = 0; i < f.Names.Count; i++)
                {
                    if (i > 0) sb.Append(f.Between);
                    sb.Append(f.Names[i]).Append('=');
                    WriteCompact(sb, f.Roots[i]);
                }
                sb.Append(f.Tail);
                return sb.ToString();
            }
            for (int i = 0; i < f.Names.Count; i++)
            {
                sb.Append(f.Names[i]).Append(" =");
                Write(sb, f.Roots[i], 0, f.Newline);
                sb.Append(f.Newline);
            }
            return sb.ToString();
        }

        public static bool Same(Node a, Node b)
        {
            if (a == null || b == null) return a == b;
            return a.ToText() == b.ToText();
        }
    }
}
'@
}

$script:Latin1 = [System.Text.Encoding]::GetEncoding(28591)

# ---------------------------------------------------------------------------------------------
# Where things are
# ---------------------------------------------------------------------------------------------
function Get-FasPaths {
    param([string]$Live)
    if (-not $Live) {
        $Live = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Elder Scrolls Online\live'
    }
    [pscustomobject]@{
        Live       = $Live
        SavedVars  = Join-Path $Live 'SavedVariables'
        Backups    = Join-Path (Split-Path $Live -Parent) "Fury's Account Sync Backups"
        Choices    = Join-Path (Split-Path $Live -Parent) "Fury's Account Sync choices.json"
    }
}

function Test-GameRunning {
    $running = Get-Process -Name 'eso64', 'eso' -ErrorAction SilentlyContinue
    return [bool]$running
}

# ---------------------------------------------------------------------------------------------
# What each addon's saved file holds. Keyed by the saved variable's name inside the file.
#   settings : copy the main's account-wide section to each alt
#   except   : same, but these parts stay as each alt has them (stats, logs, history, caches)
#   data     : never copied (inventories, knowledge, history, guild data)
#   own      : this tool or something it replaces
# Anything not listed is "unknown" and skipped unless you tick it. The addon's Rules.lua holds the same list.
# ---------------------------------------------------------------------------------------------
$script:Rules = @{
    'AddonSelectorSavedVars'                        = @{ kind = 'settings' }
    'AdvancedFilters_Settings'                      = @{ kind = 'settings' }
    'ArchiveHelperSavedVars'                        = @{ kind = 'settings' }
    'AsquartOsseinCageHelperSavedVariables'         = @{ kind = 'settings' }
    'AutoBindVariables'                             = @{ kind = 'settings' }
    'AutoCategorySavedVars'                         = @{ kind = 'settings' }
    'AutoCatRules'                                  = @{ kind = 'settings' }
    'AutoInviteSettings'                            = @{ kind = 'settings' }
    'AutoRecruitSavedVars'                          = @{ kind = 'settings' }
    'BanditsCompanions_SavedVars'                   = @{ kind = 'settings' }
    'BSCHTKASaved'                                  = @{ kind = 'settings' }
    'BUI_VARS'                                      = @{ kind = 'settings' }
    'CombatInsightsSavedVariables'                  = @{ kind = 'settings' }
    'CombatMetrics_Save'                            = @{ kind = 'settings' }
    'CombatMetronomeSavedVars'                      = @{ kind = 'settings' }
    'CrutchAlertsSavedVariables'                    = @{ kind = 'settings' }
    'DDPositions_Mirror_SavedVars'                  = @{ kind = 'settings' }
    'DDPositions_SavedVars'                         = @{ kind = 'settings' }
    'dolgubonslazysetcraftersavedvars'              = @{ kind = 'settings' }
    'DryzlerElderGeekNetTauntSavedVariables'        = @{ kind = 'settings' }
    'FancyActionBarSV'                              = @{ kind = 'settings' }
    'GroupFinderPlus_SavedVariables'                = @{ kind = 'settings' }
    'GroupManager_Data'                             = @{ kind = 'settings' }
    'HodorReflexesSavedVars'                        = @{ kind = 'settings' }
    'HowToCloudrestVariables'                       = @{ kind = 'settings' }
    'HowToKyneVariables'                            = @{ kind = 'settings' }
    'HowToSunspireVariables'                        = @{ kind = 'settings' }
    'ILeadListVars'                                 = @{ kind = 'settings' }
    'InsatiableHungerBlocker_SV'                    = @{ kind = 'settings' }
    'LBooks_SavedVariables'                         = @{ kind = 'settings' }
    'LibCustomIconsSV'                              = @{ kind = 'settings' }
    'LibScrollableMenu_SavedVars'                   = @{ kind = 'settings' }
    'LPNSavedVars'                                  = @{ kind = 'settings' }
    'MeterskullSettings'                            = @{ kind = 'settings' }
    'MP_SavedGlobal'                                = @{ kind = 'settings' }
    'NowhereVaultSecretSeekerSavedVars'             = @{ kind = 'settings' }
    'OSIStore'                                      = @{ kind = 'settings' }
    'OsseinCageHelperSavedVariables'                = @{ kind = 'settings' }
    'PerfectPixel'                                  = @{ kind = 'settings' }
    'PerfectWeaveSV'                                = @{ kind = 'settings' }
    'PersonalAssistant_SavedVariables'              = @{ kind = 'settings' }
    'PersonalAssistantBanking_SavedVariables'       = @{ kind = 'settings' }
    'PersonalAssistantConsume_SavedVariables'       = @{ kind = 'settings' }
    'PersonalAssistantIntegration_SavedVariables'   = @{ kind = 'settings' }
    'PersonalAssistantJunk_SavedVariables'          = @{ kind = 'settings' }
    'PersonalAssistantLoot_SavedVariables'          = @{ kind = 'settings' }
    'PersonalAssistantRepair_SavedVariables'        = @{ kind = 'settings' }
    'PersonalAssistantWorker_SavedVariables'        = @{ kind = 'settings' }
    'PotionMaker_Data'                              = @{ kind = 'settings' }
    'PowerfulAssaultTrackerSavedVars'               = @{ kind = 'settings' }
    'QcellDreadsailReefHelperSavedVariables'        = @{ kind = 'settings' }
    'QcellRockgroveHelperSavedVariables'            = @{ kind = 'settings' }
    'QuestMap_SavedVariables'                       = @{ kind = 'settings' }
    'RDLVars'                                       = @{ kind = 'settings' }
    'ResistOMeterSettings'                          = @{ kind = 'settings' }
    'RNVars'                                        = @{ kind = 'settings' }
    'SanitysEdgeHelperSavedVariables'               = @{ kind = 'settings' }
    'StudsGroupFinderTweaksVars'                    = @{ kind = 'settings' }
    'SurveyZoneListSavedVariables'                  = @{ kind = 'settings' }
    'Untaunted_Save'                                = @{ kind = 'settings' }
    'WhoPulledVariables'                            = @{ kind = 'settings' }
    'WritWorthyVars'                                = @{ kind = 'settings' }

    'BeamMeUp_SV'                                   = @{ kind = 'except'; keep = @('portCounterPerZone', 'lastPortedZones', 'savedGold', 'initialTimeStamp', 'houseFurnitureCount_LII', 'lastofflineReminder') }
    'CSPSSavedVariables'                            = @{ kind = 'except'; keep = @('charData') }
    'DolgubonsWritCrafterSavedVars'                 = @{ kind = 'except'; keep = @('rewards', 'craftLog', 'writLocations', 'skipItemQuests', 'totalCraftsCount') }
    'EzStalking_SavedVars'                          = @{ kind = 'except'; keep = @('log') }
    'MagicCarpetSavedVars'                          = @{ kind = 'except'; keep = @('EarnedTrophies', 'LastOogyBoogy') }
    'MagicSorter'                                   = @{ kind = 'except'; keep = @('Data') }
    'PCHAT_OPTS'                                    = @{ kind = 'except'; keep = @('LineStrings', 'history') }
    'PortToFriendsHouseVars'                        = @{ kind = 'except'; keep = @('myHousesFavorites') }
    'ResearchAssistant_Settings_Server'             = @{ kind = 'except'; keep = @('acquiredTraits', 'blacksmithCharacter', 'clothierCharacter', 'leatherworkerCharacter', 'weaponsmithCharacter', 'woodworkingCharacter', 'jewelryCraftingCharacter') }
    'SkillLinesSavedVars'                           = @{ kind = 'except'; keep = @('NA Megaserver', 'EU Megaserver') }
    'TamrielTradeCentreVars'                        = @{ kind = 'except'; keep = @('NAData', 'EUData') }
    'USPF_Settings'                                 = @{ kind = 'except'; keep = @('ptsData', 'charInfo') }
    'WizardsWardrobeSV'                             = @{ kind = 'except'; keep = @('accountWideStorage') }
    'XLGearBankerSavedVariables'                    = @{ kind = 'except'; keep = @('gearSetList', 'pages', 'displayingSet', 'displayingPage') }

    'ArmoryStyleManagerData'                        = @{ kind = 'data' }
    'AutomateSavedVars'                             = @{ kind = 'data' }
    'AwesomeGuildStore_Data'                        = @{ kind = 'data' }
    'BUI_REPORTS'                                   = @{ kind = 'data' }
    'CombatInsightsFightDataSV'                     = @{ kind = 'data' }
    'CombatMetricsFightData'                        = @{ kind = 'data' }
    'CraftStore_Account'                            = @{ kind = 'data' }
    'CraftStore_Character'                          = @{ kind = 'data' }
    'DecoTrackSavedVars'                            = @{ kind = 'data' }
    'DSSTSavedVariables'                            = @{ kind = 'data' }
    'EssentialHousingCommunitySavedVars'            = @{ kind = 'data' }
    'FCOItemSaver_Settings'                         = @{ kind = 'data'; why = 'item markers and settings are stored together' }
    'FurnitureCatalogue_Settings'                   = @{ kind = 'data' }
    'FuryCT_SV'                                     = @{ kind = 'data' }
    'FuryGMT_SV'                                    = @{ kind = 'data'; why = 'guild data and settings are stored together' }
    'FuryGTT_SV'                                    = @{ kind = 'data' }
    'FurysGuildCrier_SV'                            = @{ kind = 'data' }
    'FurysInventoryLedger_SV'                       = @{ kind = 'data' }
    'Harvest_SavedVars'                             = @{ kind = 'data' }
    'IIFA_DATABASE'                                 = @{ kind = 'data' }
    'LeoAltholicSavedVariables'                     = @{ kind = 'data' }
    'LibCharacterKnowledgeData'                     = @{ kind = 'data' }
    'LibCustomNamesSV'                              = @{ kind = 'data' }
    'LibDebugLoggerLog'                             = @{ kind = 'data' }
    'LibDebugLoggerSettings'                        = @{ kind = 'data' }
    'LibHistoire_GuildHistoryCache'                 = @{ kind = 'data' }
    'LibHistoire_Settings'                          = @{ kind = 'data' }
    'MP_ChestData'                                  = @{ kind = 'data' }
    'MP_ThievesTrove'                               = @{ kind = 'data' }
    'PithkaSavedVariables'                          = @{ kind = 'data' }
    'SUPERSTAR'                                     = @{ kind = 'data' }
    'WPamA_SV_Debug'                                = @{ kind = 'data' }
    'WPamA_SV_Main'                                 = @{ kind = 'data' }
    'ZO_InternalIngame_SavedVariables'              = @{ kind = 'data' }

    'AccountSettings_SV'                            = @{ kind = 'own'; why = 'Synced Account Settings, which this replaces' }
    'FurysAccountSync_SV'                           = @{ kind = 'own' }
    'ZO_Ingame_SavedVariables'                      = @{ kind = 'own'; why = 'base game: use the chat and window option' }
    'ZO_Pregame_SavedVariables'                     = @{ kind = 'own' }
}

# Per-character parts of the base game's saved file that make up the chat and window layout.
$script:BaseGameCharacterParts = @('"Chat"', '"PerformanceMeters"', '"ZO_HUDTracker_Manager"')

function Get-Rule([string]$varName) {
    if ($script:Rules.ContainsKey($varName)) { return $script:Rules[$varName] }
    return @{ kind = 'unknown' }
}

function Q([string]$s) { return '"' + $s + '"' }
function UnQ([string]$s) { if ($s.Length -ge 2 -and $s[0] -eq '"') { return $s.Substring(1, $s.Length - 2) } return $s }

# ---------------------------------------------------------------------------------------------
# Reading files
# ---------------------------------------------------------------------------------------------
function Read-SvFile([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = $script:Latin1.GetString($bytes)
    $result = [pscustomobject]@{ Path = $path; Name = [IO.Path]::GetFileName($path); Text = $text; File = $null; Error = $null }
    try {
        $f = [FuryAS.Sv]::Parse($text)
        if ([FuryAS.Sv]::Serialize($f) -ne $text) {
            $result.Error = 'its layout is unusual, so it is left alone'
        } else {
            $result.File = $f
        }
    } catch {
        $result.Error = "it can't be read ($($_.Exception.Message))"
    }
    return $result
}

# The accounts on this PC, spelled the way the game spells them. The base game's own saved file
# lists every account that has logged in here. Addons also keep "@name" keys in places that aren't
# account sections (lists of names, lowercase copies), so those are never used to find accounts.
function Get-FasAccounts($files) {
    $found = New-Object System.Collections.Generic.HashSet[string]
    $zo = $files | Where-Object { $_.Name -eq 'ZO_Ingame.lua' -and $_.File } | Select-Object -First 1
    if ($zo) {
        $root = $zo.File.Get('ZO_Ingame_SavedVariables')
        if ($root -and $root.IsTable) {
            foreach ($profile in $root.Values) {
                if (-not $profile.IsTable) { continue }
                for ($k = 0; $k -lt $profile.Keys.Count; $k++) {
                    if ($profile.Keys[$k].StartsWith('"@') -and $profile.Values[$k].IsTable) { [void]$found.Add((UnQ $profile.Keys[$k])) }
                }
            }
        }
    }
    if ($found.Count -eq 0) {
        # No base game file: take the accounts that have a real account-wide section in any addon's file.
        foreach ($sv in $files) {
            if (-not $sv.File) { continue }
            foreach ($root in $sv.File.Roots) {
                if (-not $root.IsTable) { continue }
                foreach ($profile in $root.Values) {
                    if (-not $profile.IsTable) { continue }
                    for ($k = 0; $k -lt $profile.Keys.Count; $k++) {
                        $node = $profile.Values[$k]
                        if ($profile.Keys[$k].StartsWith('"@') -and $node.IsTable -and $node.IndexOf('"$AccountWide"') -ge 0) {
                            [void]$found.Add((UnQ $profile.Keys[$k]))
                        }
                    }
                }
            }
        }
    }
    return @($found | Sort-Object)
}

# How one saved variable is laid out: which of the known accounts have a section in it, and whether
# any of them has an account-wide part (the part this tool copies).
function Get-AccountMap($root, $accounts) {
    $map = @{ Accounts = @{}; Wide = $false; PerCharacter = $false }
    if (-not $root -or -not $root.IsTable) { return $map }
    foreach ($profile in $root.Values) {
        if (-not $profile.IsTable) { continue }
        foreach ($acct in $accounts) {
            $node = $profile.Get((Q $acct))
            if (-not $node -or -not $node.IsTable) { continue }
            $map.Accounts[$acct] = $true
            for ($k = 0; $k -lt $node.Keys.Count; $k++) {
                if (-not $node.Values[$k].IsTable) { continue }
                if ($node.Keys[$k] -eq '"$AccountWide"') { $map.Wide = $true } else { $map.PerCharacter = $true }
            }
        }
    }
    return $map
}

# Scans the folder: every file, every saved variable in it, its rule and the accounts on this PC.
function Get-FasInventory([string]$savedVars) {
    $read = @()
    foreach ($fi in Get-ChildItem -LiteralPath $savedVars -Filter '*.lua' -File | Sort-Object Name) {
        $read += Read-SvFile $fi.FullName
    }
    $accounts = @(Get-FasAccounts $read)
    $files = @()
    foreach ($sv in $read) {
        $vars = @()
        if ($sv.File) {
            for ($i = 0; $i -lt $sv.File.Names.Count; $i++) {
                $name = $sv.File.Names[$i]
                $map = Get-AccountMap $sv.File.Roots[$i] $accounts
                $vars += [pscustomobject]@{
                    Name         = $name
                    Rule         = (Get-Rule $name)
                    PerAccount   = ($map.Accounts.Count -gt 0)
                    Wide         = $map.Wide
                    PerCharacter = $map.PerCharacter
                }
            }
        }
        $files += [pscustomobject]@{ Sv = $sv; Vars = $vars }
    }
    return [pscustomobject]@{ Files = $files; Accounts = $accounts }
}

# How a file shows in the list. A file can hold several saved variables: settings ones are copied,
# data ones in the same file are always left alone. Only variables with an account-wide part can be
# copied, so a file that keeps everything per character is shown as that.
function Get-FileKind($fileEntry) {
    if ($fileEntry.Sv.Error) { return 'cant' }
    $vars = @($fileEntry.Vars)
    if ($vars.Count -eq 0) { return 'empty' }
    $kinds = @($vars | Where-Object { $_.Wide } | ForEach-Object { $_.Rule.kind })
    $allKinds = @($vars | ForEach-Object { $_.Rule.kind })
    if ($kinds -contains 'settings' -or $kinds -contains 'except') {
        if ($kinds -contains 'except' -or $allKinds -contains 'data' -or $allKinds -contains 'unknown') { return 'except' }
        return 'settings'
    }
    if ($allKinds -contains 'own') { return 'own' }
    if ($allKinds -contains 'data') { return 'data' }
    if ($kinds -contains 'unknown') { return 'unknown' }
    if (@($vars | Where-Object { $_.PerCharacter }).Count -gt 0) { return 'perchar' }
    return 'shared'
}

function Get-KindText([string]$kind, $fileEntry = $null) {
    $text = switch ($kind) {
        'settings' { 'Settings: copied' }
        'except'   { 'Settings: copied (its stats, logs and data stay)' }
        'data'     { 'Data: never copied' }
        'own'      { 'Skipped' }
        'shared'   { 'Already shared by every account' }
        'perchar'  { 'Kept per character: not copied' }
        'unknown'  { 'Unknown: skipped unless ticked' }
        'cant'     { "Can't be read: left alone" }
        default    { 'Nothing to copy' }
    }
    if ($fileEntry -and ($kind -eq 'data' -or $kind -eq 'own')) {
        $why = @($fileEntry.Vars | Where-Object { $_.Rule.why } | ForEach-Object { $_.Rule.why }) | Select-Object -First 1
        if ($why) { $text = "$text ($why)" }
    }
    return $text
}

# Characters the main account has in the base game's file (for the chat and window option).
function Get-MainCharacters($inventory, [string]$main) {
    $zo = $inventory.Files | Where-Object { $_.Sv.Name -eq 'ZO_Ingame.lua' -and $_.Sv.File } | Select-Object -First 1
    if (-not $zo) { return @() }
    $root = $zo.Sv.File.Get('ZO_Ingame_SavedVariables')
    $profile = $root.Get('"Default"')
    if (-not $profile) { return @() }
    $acct = $profile.Get((Q $main))
    if (-not $acct) { return @() }
    return @($acct.Keys | Where-Object { $_ -ne '"$AccountWide"' } | ForEach-Object { UnQ $_ } | Sort-Object)
}

# ---------------------------------------------------------------------------------------------
# Planning: works on in-memory copies only. Nothing is written here.
# ---------------------------------------------------------------------------------------------
# $options: @{ Main = '@x'; Alts = @('@y'); Files = @('BeamMeUp.lua', ...); BaseGameFrom = 'Char Name' or $null }
# Returns one entry per file that would change: Name, Path, NewText, Changes (list of strings).
function New-FasPlan($inventory, $options) {
    $plan = @()
    $mainKey = Q $options.Main
    foreach ($entry in $inventory.Files) {
        $sv = $entry.Sv
        if (-not $sv.File) { continue }
        $wanted = $options.Files -contains $sv.Name
        $isBase = ($sv.Name -eq 'ZO_Ingame.lua') -and $options.BaseGameFrom
        if (-not $wanted -and -not $isBase) { continue }

        $fileKind = Get-FileKind $entry
        $work = [FuryAS.Sv]::Parse($sv.Text)     # a fresh copy to change
        $changes = New-Object System.Collections.Generic.List[string]

        for ($i = 0; $i -lt $work.Names.Count; $i++) {
            $varName = $work.Names[$i]
            $root = $work.Roots[$i]
            if (-not $root.IsTable) { continue }

            if ($isBase -and $varName -eq 'ZO_Ingame_SavedVariables') {
                $profile = $root.Get('"Default"')
                if (-not $profile) { continue }
                $mainAcct = $profile.Get($mainKey)
                $fromChar = if ($mainAcct) { $mainAcct.Get((Q $options.BaseGameFrom)) } else { $null }
                if (-not $fromChar) { continue }
                foreach ($alt in $options.Alts) {
                    $altAcct = $profile.Get((Q $alt))
                    if (-not $altAcct) { continue }
                    for ($c = 0; $c -lt $altAcct.Keys.Count; $c++) {
                        $charKey = $altAcct.Keys[$c]
                        if ($charKey -eq '"$AccountWide"') { continue }
                        $charNode = $altAcct.Values[$c]
                        if (-not $charNode.IsTable) { continue }
                        foreach ($part in $script:BaseGameCharacterParts) {
                            $src = $fromChar.Get($part)
                            if (-not $src) { continue }
                            if (-not [FuryAS.Sv]::Same($src, $charNode.Get($part))) {
                                $charNode.Set($part, $src.Clone())
                                $changes.Add("$alt / $(UnQ $charKey): $(UnQ $part)")
                            }
                        }
                    }
                }
                continue
            }

            if (-not $wanted) { continue }
            $rule = Get-Rule $varName
            if ($rule.kind -eq 'data' -or $rule.kind -eq 'own') { continue }
            if ($rule.kind -eq 'unknown' -and $fileKind -ne 'unknown') { continue }
            $keep = @()
            if ($rule.keep) { $keep = @($rule.keep | ForEach-Object { Q $_ }) }

            for ($p = 0; $p -lt $root.Keys.Count; $p++) {
                $profile = $root.Values[$p]
                if (-not $profile.IsTable) { continue }
                $mainAcct = $profile.Get($mainKey)
                if (-not $mainAcct -or -not $mainAcct.IsTable) { continue }
                $mainWide = $mainAcct.Get('"$AccountWide"')
                if (-not $mainWide -or -not $mainWide.IsTable) { continue }

                foreach ($alt in $options.Alts) {
                    $altKey = Q $alt
                    $altAcct = $profile.Get($altKey)
                    $created = $false
                    if (-not $altAcct) {
                        $altAcct = [FuryAS.Node]::NewTable()
                        $profile.Set($altKey, $altAcct)
                        $created = $true
                    }
                    $altWide = $altAcct.Get('"$AccountWide"')
                    $newWide = $mainWide.Clone()
                    foreach ($k in $keep) {
                        $mine = if ($altWide -and $altWide.IsTable) { $altWide.Get($k) } else { $null }
                        if ($mine) { $newWide.Set($k, $mine.Clone()) } else { $newWide.Remove($k) }
                    }
                    if ([FuryAS.Sv]::Same($newWide, $altWide)) {
                        if ($created) { $profile.Remove($altKey) }
                        continue
                    }
                    $diff = 0
                    foreach ($k in $newWide.Keys) {
                        $old = if ($altWide -and $altWide.IsTable) { $altWide.Get($k) } else { $null }
                        if (-not [FuryAS.Sv]::Same($newWide.Get($k), $old)) { $diff++ }
                    }
                    if ($altWide -and $altWide.IsTable) {
                        foreach ($k in $altWide.Keys) { if ($newWide.IndexOf($k) -lt 0) { $diff++ } }
                    }
                    $altAcct.Set('"$AccountWide"', $newWide)
                    $note = if ($created) { 'added' } elseif ($diff -eq 1) { '1 part changed' } else { "$diff parts changed" }
                    $label = if ($work.Names.Count -gt 1) { "$alt, $varName" } else { $alt }
                    $changes.Add("${label}: $note")
                }
            }
        }

        if ($changes.Count -gt 0) {
            $plan += [pscustomobject]@{
                Name    = $sv.Name
                Path    = $sv.Path
                OldText = $sv.Text
                NewText = [FuryAS.Sv]::Serialize($work)
                Changes = $changes
            }
        }
    }
    return ,$plan
}

# ---------------------------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------------------------
function New-FasBackup($paths, [string]$label = '') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $paths.Backups)) { New-Item -ItemType Directory -Path $paths.Backups | Out-Null }
    $stamp = Get-Date -Format 'yyyy-MM-dd HHmmss'
    $name = "SavedVariables $stamp$label.zip"
    $zip = Join-Path $paths.Backups $name
    [System.IO.Compression.ZipFile]::CreateFromDirectory($paths.SavedVars, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    # keep the newest 10
    Get-ChildItem -LiteralPath $paths.Backups -Filter 'SavedVariables *.zip' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10 | Remove-Item -Force
    return $zip
}

function Get-FasBackups($paths) {
    if (-not (Test-Path -LiteralPath $paths.Backups)) { return @() }
    return @(Get-ChildItem -LiteralPath $paths.Backups -Filter 'SavedVariables *.zip' | Sort-Object LastWriteTime -Descending)
}

function Restore-FasBackup($paths, [string]$zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $archive.Entries) {
            if (-not $e.Name) { continue }
            $dest = Join-Path $paths.SavedVars $e.FullName
            $dir = Split-Path $dest -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        }
    } finally {
        $archive.Dispose()
    }
}

# ---------------------------------------------------------------------------------------------
# Applying a plan
# ---------------------------------------------------------------------------------------------
# Returns @{ Ok = $true/$false; Backup = path; Message = text }
# The parameter names here must not match any variable of the window script: $onMessage calls back into
# it, and PowerShell would hand that code this function's variables instead of its own.
function Invoke-FasPlan($paths, $plan, [scriptblock]$onMessage) {
    if (Test-GameRunning) { return @{ Ok = $false; Message = 'The game is running. Close it completely, then try again.' } }
    if (-not $plan -or $plan.Count -eq 0) { return @{ Ok = $false; Message = 'Nothing to change.' } }

    # Refuse if any file changed since the preview was made.
    foreach ($item in $plan) {
        $now = $script:Latin1.GetString([System.IO.File]::ReadAllBytes($item.Path))
        if ($now -ne $item.OldText) {
            return @{ Ok = $false; Message = "$($item.Name) changed since the preview. Press Preview again." }
        }
    }

    $backup = New-FasBackup $paths
    & $onMessage "Backed up the SavedVariables folder to $backup"

    $written = @()
    try {
        foreach ($item in $plan) {
            # Check the new text reads back cleanly before it goes anywhere near the real file.
            $check = [FuryAS.Sv]::Parse($item.NewText)
            if ([FuryAS.Sv]::Serialize($check) -ne $item.NewText) { throw "$($item.Name) didn't check out before writing" }

            $tmp = $item.Path + '.fas-new'
            [System.IO.File]::WriteAllBytes($tmp, $script:Latin1.GetBytes($item.NewText))
            Move-Item -LiteralPath $tmp -Destination $item.Path -Force
            $written += $item

            $back = $script:Latin1.GetString([System.IO.File]::ReadAllBytes($item.Path))
            if ($back -ne $item.NewText) { throw "$($item.Name) didn't read back the same after writing" }
            & $onMessage "Wrote $($item.Name)"
        }
    } catch {
        & $onMessage "Problem: $($_.Exception.Message). Putting every file back from the backup."
        Restore-FasBackup $paths $backup
        return @{ Ok = $false; Backup = $backup; Message = "Nothing was changed: $($_.Exception.Message). Everything was restored from the backup." }
    }
    return @{ Ok = $true; Backup = $backup; Message = "Done. $($written.Count) files updated. Backup: $backup" }
}

# ---------------------------------------------------------------------------------------------
# Remembered choices (which addons are ticked, main, alts)
# ---------------------------------------------------------------------------------------------
function Read-FasChoices($paths) {
    if (Test-Path -LiteralPath $paths.Choices) {
        try { return Get-Content -LiteralPath $paths.Choices -Raw | ConvertFrom-Json } catch { }
    }
    return $null
}

function Save-FasChoices($paths, $choices) {
    $choices | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $paths.Choices -Encoding UTF8
}

# The main account the in-game addon was told about, if any.
function Get-FasMainFromAddon($inventory) {
    $f = $inventory.Files | Where-Object { $_.Sv.Name -eq 'FurysAccountSync.lua' -and $_.Sv.File } | Select-Object -First 1
    if (-not $f) { return $null }
    $root = $f.Sv.File.Get('FurysAccountSync_SV')
    if (-not $root) { return $null }
    $main = $root.Get('"main"')
    if ($main -and -not $main.IsTable) { return UnQ $main.Raw }
    return $null
}
