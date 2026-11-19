[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$DownloadTemplates,
    [switch]$WindowsInstaller
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $GodotPath) {
    $GodotPath = Join-Path $ProjectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$EngineVersion = (& $GodotPath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $EngineVersion -ne '4.7.2.stable.official.ed1daf0bf') {
    throw "Expected Godot 4.7.2.stable.official.ed1daf0bf; got $EngineVersion"
}

$TemplateUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
$TemplateHash = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
$ArchivePath = Join-Path $ProjectRoot '.tools/Godot_v4.7.2-stable_export_templates.tpz'
$TemplateDir = Join-Path $ProjectRoot '.tools/godot-templates/4.7.2.stable'
if (-not (Test-Path -LiteralPath $ArchivePath)) {
    if (-not $DownloadTemplates) {
        throw 'Official export templates are missing. Run again with -DownloadTemplates (1.19 GiB download).'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $ArchivePath) | Out-Null
    Invoke-WebRequest -Uri $TemplateUrl -OutFile $ArchivePath -TimeoutSec 900
}
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $TemplateHash) {
    throw 'The template archive SHA256 does not match the official Godot 4.7.2 release. No export was attempted.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path $TemplateDir | Out-Null
$Archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    foreach ($Name in @('version.txt', 'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe', 'windows_debug_x86_64.exe', 'windows_debug_x86_64_console.exe')) {
        $Entry = $Archive.GetEntry("templates/$Name")
        if ($null -eq $Entry) { throw "Template archive has no $Name" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, (Join-Path $TemplateDir $Name), $true)
    }
} finally { $Archive.Dispose() }
if ((Get-Content -LiteralPath (Join-Path $TemplateDir 'version.txt') -Raw).Trim() -ne '4.7.2.stable') {
    throw 'Unexpected template version.'
}

$LicenseCache = Join-Path $ProjectRoot '.tools/godot-licenses'
New-Item -ItemType Directory -Force -Path $LicenseCache | Out-Null
foreach ($Name in @('LICENSE', 'COPYRIGHT')) {
    $LicensePath = Join-Path $LicenseCache "Godot-$Name.txt"
    if (-not (Test-Path -LiteralPath $LicensePath)) {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/$Name.txt" -OutFile $LicensePath -TimeoutSec 60
    }
}

$ProjectText = Get-Content -LiteralPath (Join-Path $ProjectRoot 'project.godot') -Raw
$VersionMatch = [regex]::Match($ProjectText, '(?m)^config/version="([0-9A-Za-z.\-]+)"')
if (-not $VersionMatch.Success) { throw 'Project version is missing or unsafe for a filename.' }
$Version = $VersionMatch.Groups[1].Value
$OutputRoot = Join-Path $ProjectRoot ('build/' + $Version + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$PackageDir = Join-Path $OutputRoot 'windows-x64'
if (Test-Path -LiteralPath $OutputRoot) { throw 'Output directory already exists; retry in a second.' }
New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
$ExportLog = Join-Path $OutputRoot 'export.log'
$Executable = Join-Path $PackageDir 'SigilsAndOaths.exe'
& $GodotPath --headless --path $ProjectRoot --export-release 'Windows Desktop' $Executable *> $ExportLog
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Executable)) {
    throw "Godot export failed. See $ExportLog"
}
$PackPath = Join-Path $PackageDir 'SigilsAndOaths.pck'
if (-not (Test-Path -LiteralPath $PackPath)) { throw 'Export produced no PCK.' }

# Inspect the actual PCK, including runtime JSON loaded outside ResourceLoader.
$AuditScript = Join-Path $OutputRoot 'audit_pack.gd'
$AuditReport = Join-Path $OutputRoot 'pack-audit.json'
$AuditLog = Join-Path $OutputRoot 'pack-audit.log'
@'
extends SceneTree
var entries: Array[String] = []
var problems: Array[String] = []

func walk(path: String) -> void:
    for filename in DirAccess.get_files_at(path):
        entries.append(path.path_join(filename))
    for dirname in DirAccess.get_directories_at(path):
        walk(path.path_join(dirname))

func _initialize() -> void:
    walk("res://")
    entries.sort()
    for path in entries:
        var relative = path.trim_prefix("res://")
        if relative.begins_with("assets/art/model_sources/") or relative.ends_with(".blend"):
            problems.append("editable Blender source should not be in the Windows game pack: " + path)
        if not (relative.begins_with("assets/") or relative.begins_with("data/") or relative.begins_with("scripts/") or relative.begins_with("scenes/") or relative.begins_with(".godot/imported/") or relative.begins_with(".godot/exported/") or relative in ["project.binary", ".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin"]):
            problems.append("unexpected resource: " + path)
    var campaign = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
    if not campaign is Dictionary:
        problems.append("campaign JSON unavailable")
    else:
        for chapter in campaign.chapters:
            if not JSON.parse_string(FileAccess.get_file_as_string(chapter.path)) is Dictionary:
                problems.append("missing chapter: " + chapter.path)
        var requisitions: int = 0
        for setup: Dictionary in campaign.scenarios.values():
            if setup.has("requisition"): requisitions += 1
        if requisitions != 20 or not campaign.scenarios.get("c06_court", {}).get("requisition", {}).get("offers", []).has("dawn_weir"):
            problems.append("campaign requisition data unavailable")
        var bridge = campaign.scenarios.get("c01_bridge", {}).get("story_control", {})
        var channel = campaign.scenarios.get("c14_upstream_channel", {}).get("story_control", {})
        if bridge.get("cells", []).size() != 2 or bridge.get("round_limit", -1) != 0 or channel.get("round_limit", 0) != 25:
            problems.append("campaign difficulty data unavailable")
    var required_resources = ["res://scenes/main.tscn", "res://data/cards.tres", "res://data/decks.tres",
        "res://assets/art/expansion/spells-v1.png", "res://assets/art/expansion/traps-forest-v1.png",
        "res://assets/art/expansion/warfront-units-v1.png", "res://assets/art/expansion/warfront-effects-v1.png",
        "res://assets/art/expansion/afterglow-units-v1.png", "res://assets/art/expansion/afterglow-spells-v1.png",
        "res://assets/art/expansion/afterglow-traps-weather-v1.png",
        "res://assets/art/expansion/tidegate-units-v1.png", "res://assets/art/expansion/tidegate-spells-v1.png",
        "res://assets/art/expansion/tidegate-traps-weather-v1.png",
        "res://assets/art/expansion/levee-watch-v1.png", "res://assets/art/expansion/levee-orders-v1.png", "res://scripts/timed_orders.gd",
        "res://assets/art/expansion/moorings-scouts-v1.png", "res://assets/art/expansion/moorings-veterans-v1.png",
        "res://assets/art/expansion/moorings-works-v1.png", "res://assets/art/expansion/moorings-tides-v1.png",
        "res://assets/art/expansion/pilgrim-marches-v1.png", "res://assets/art/expansion/pilgrim-watch-v1.png",
        "res://assets/art/expansion/pilgrim-wards-v1.png", "res://assets/art/expansion/pilgrim-salvos-v1.png",
        "res://assets/art/expansion/glassroad-company-v1.png", "res://assets/art/expansion/glassroad-edicts-v1.png",
        "res://assets/art/expansion/glassroad-reserves-v1.png", "res://assets/art/expansion/glassroad-ambush-v1.png",
        "res://assets/art/battlefields/rivergate-relief-v1.png",
        "res://assets/art/battlefields/lamplanding-v2.png", "res://assets/art/narrative/return-morning-v1.png",
        "res://assets/art/battlefields/saltlane-v2.png", "res://assets/art/narrative/saltlane-yard-v1.png",
        "res://assets/art/narrative/quartermaster-desk-v1.png", "res://scripts/campaign_requisition.gd",
        "res://assets/art/narrative/chapter-replay-archive-v1.png", "res://scripts/chapter_replay_view.gd",
        "res://assets/art/narrative/campaign-armory-v1.png", "res://scripts/campaign_armory.gd", "res://scripts/campaign_armory_view.gd",
        "res://scripts/campaign_difficulty.gd",
        "res://scripts/settings_dialog.gd", "res://scripts/training.gd", "res://scripts/game_audio.gd", "res://assets/audio/council.ogg",
        "res://assets/audio/battle.ogg", "res://assets/audio/trap.wav", "res://assets/audio/victory.wav"]
    for path in required_resources:
        if not ResourceLoader.exists(path):
            problems.append("missing runtime resource: " + path)
    var catalog = load("res://data/cards.tres")
    var decks = load("res://data/decks.tres")
    if catalog == null or catalog.cards.size() != 249 or catalog.find("thousand_steps").get("cost") != 10 or catalog.find("bridle_break").get("kill_mana") != 2 or not catalog.find("petal_signal").get("combo", {}).get("refresh_move", false):
        problems.append("expansion card data unavailable")
    if catalog != null:
        var glassroad: Array[Dictionary] = catalog.cards.filter(func(card: Dictionary) -> bool: return card.get("set_id", "") == "glassroad")
        var art = load("res://scripts/art_library.gd")
        if glassroad.size() != 48 or catalog.find("all_banner_call").get("recruits", []).size() != 3 or catalog.find("glass_treaty").get("modes", {}).size() != 2:
            problems.append("Glassroad Orders rules unavailable")
        for card: Dictionary in glassroad:
            if art.get_texture(card.id) == null: problems.append("missing Glassroad illustration: " + card.id)
    if decks == null or decks.decks.size() != 23 or decks.find("chalkline_vanguard").get("cards", {}).get("petal_signal", 0) < 1 or decks.find("cairn_watch").get("cards", {}).get("bellglass_cover", 0) < 1 or decks.find("bellfoundry_column").get("cards", {}).get("thousand_steps", 0) < 1 or decks.find("glassroad_reserve").get("cards", {}).get("all_banner_call", 0) != 1:
        problems.append("expansion preset data unavailable")
    var armory = load("res://scripts/campaign_armory.gd")
    if armory == null or armory.unlocked_count(7) != 3 or not armory.validate({"vanguard": "petal_signal", "company": "roadside_muster", "reserve": "glass_treaty"}, 7).is_empty():
        problems.append("campaign armory unavailable")
    var report = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
    report.store_string(JSON.stringify({"count": entries.size(), "entries": entries, "problems": problems, "ok": problems.is_empty()}, "\t"))
    report.close()
    print("PACK_AUDIT count=", entries.size(), " errors=", problems.size())
    quit(0 if problems.is_empty() else 1)
'@ | Set-Content -LiteralPath $AuditScript -Encoding utf8
& $GodotPath --headless --main-pack $PackPath --script $AuditScript --log-file $AuditLog -- $AuditReport *> (Join-Path $OutputRoot 'pack-audit-console.log')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $AuditReport)) { throw "PCK audit failed. See $AuditLog" }
$PackAudit = Get-Content -LiteralPath $AuditReport -Raw | ConvertFrom-Json
if (-not $PackAudit.ok) { throw "PCK contains unexpected or missing resources. See $AuditReport" }

# Run the packaged executable from its own directory, with no source-project path.
$SmokeLog = Join-Path $OutputRoot 'smoke.log'
$Smoke = Start-Process -FilePath $Executable -ArgumentList @('--headless', '--quit-after', '60', '--log-file', ('"' + $SmokeLog + '"')) -WorkingDirectory $PackageDir -WindowStyle Hidden -PassThru
try {
    if (-not $Smoke.WaitForExit(45000)) {
        $Smoke.Kill()
        throw 'Packaged executable did not exit within 45 seconds.'
    }
    $Smoke.Refresh()
    if ($Smoke.ExitCode -ne 0) { throw "Packaged executable exited with $($Smoke.ExitCode)." }
} finally { $Smoke.Dispose() }
if (-not (Test-Path -LiteralPath $SmokeLog)) { throw 'Packaged executable created no smoke-test log.' }
if (Select-String -LiteralPath $SmokeLog -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet) {
    throw "Packaged executable reported errors. See $SmokeLog"
}

Copy-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE') -Destination (Join-Path $PackageDir 'LICENSE.txt')
$LicenseOutput = New-Item -ItemType Directory -Path (Join-Path $PackageDir 'licenses')
Copy-Item -LiteralPath (Join-Path $LicenseCache 'Godot-LICENSE.txt'), (Join-Path $LicenseCache 'Godot-COPYRIGHT.txt') -Destination $LicenseOutput.FullName
$SourceCommit = (& git -C $ProjectRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to determine source commit.' }
$StatusLines = @(& git -C $ProjectRoot status --porcelain --untracked-files=all)
$MaterialChanges = @($StatusLines | Where-Object {
    $_ -and $_ -notmatch '^\?\? (?:scripts/|tests/).+\.gd\.uid$' -and $_ -notmatch '^\?\? docs/screenshots/.+\.png\.import$'
})
$SourceDirty = $MaterialChanges.Count -gt 0
if ($SourceDirty) { throw 'Source has uncommitted material changes; commit or discard them before release export.' }
$Payload = @('SigilsAndOaths.exe', 'SigilsAndOaths.pck') | ForEach-Object {
    $Path = Join-Path $PackageDir $_
    [ordered]@{file=$_; bytes=(Get-Item -LiteralPath $Path).Length; sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
[ordered]@{
    version=$Version; channel='development-preview'; platform='windows-x64';
    engine=$EngineVersion; template_sha256=$TemplateHash; source_commit=$SourceCommit;
    source_dirty=$SourceDirty; built_utc=(Get-Date).ToUniversalTime().ToString('o');
    smoke_test='packaged-executable-headless-startup'; pack_audit_entries=$PackAudit.count; payload=$Payload
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PackageDir 'RELEASE_INFO.json') -Encoding utf8
$ZipPath = Join-Path $OutputRoot "sigils-and-oaths-$Version-windows-x64.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($PackageDir, $ZipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$ZipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Checksums = @("$ZipHash  $([IO.Path]::GetFileName($ZipPath))")
$Result = [ordered]@{
    version=$Version; source_commit=$SourceCommit; source_dirty=$SourceDirty
    archive=$ZipPath; sha256=$ZipHash; bytes=(Get-Item -LiteralPath $ZipPath).Length; smoke='passed'
}
if ($WindowsInstaller) {
    $Result.installer = & (Join-Path $PSScriptRoot 'build_windows_installer.ps1') -BuildDirectory $OutputRoot | ConvertFrom-Json
    $Checksums += "$($Result.installer.sha256)  $([IO.Path]::GetFileName($Result.installer.path))"
}
$Checksums | Set-Content -LiteralPath (Join-Path $OutputRoot 'SHA256SUMS.txt') -Encoding ascii
$Result | ConvertTo-Json -Depth 4
