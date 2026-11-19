[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PreviousBuild,
    [Parameter(Mandatory = $true)]
    [string]$PreviousInstaller,
    [Parameter(Mandatory = $true)]
    [string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$CurrentRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$OldRoot = (Resolve-Path -LiteralPath $PreviousBuild).Path
$OldMsi = (Resolve-Path -LiteralPath $PreviousInstaller).Path
$CurrentPayload = Join-Path $CurrentRoot 'windows-x64'
$OldPayload = Join-Path $OldRoot 'windows-x64'
$CurrentRelease = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $CurrentPayload 'RELEASE_INFO.json') | ConvertFrom-Json
$OldRelease = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $OldPayload 'RELEASE_INFO.json') | ConvertFrom-Json
$CurrentMsi = (Resolve-Path -LiteralPath (Join-Path $CurrentRoot "sigils-and-oaths-$($CurrentRelease.version)-windows-x64.msi")).Path
$Engine = Join-Path $Project '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
$Probe = Join-Path $PSScriptRoot 'installer_profile_probe.gd'
$WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
$RawRegistry = 'HKCU:\Software\SigilsAndOaths'
$Menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Sigils and Oaths'
$DataNames = @('campaign_autosave.json','custom_deck.json','settings.cfg')
$PayloadFiles = @('SigilsAndOaths.exe','SigilsAndOaths.pck','RELEASE_INFO.json','LICENSE.txt',
    'licenses/Godot-LICENSE.txt','licenses/Godot-COPYRIGHT.txt')

function Assert-Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-MsiProperty([string]$Package, [string]$Property) {
    $Database = $WindowsInstaller.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$WindowsInstaller,@($Package,0))
    try {
        $Query = 'SELECT `Value` FROM `Property` WHERE `Property` = ''' + $Property + ''''
        $View = $Database.GetType().InvokeMember('OpenView','InvokeMethod',$null,$Database,@($Query))
        try {
            $null = $View.GetType().InvokeMember('Execute','InvokeMethod',$null,$View,$null)
            $Record = $View.GetType().InvokeMember('Fetch','InvokeMethod',$null,$View,$null)
            if ($null -ne $Record) {
                try { $Record.GetType().InvokeMember('StringData','GetProperty',$null,$Record,@(1)) }
                finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Record) }
            }
        } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($View) }
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Database) }
}

function Product-State([string]$ProductCode) {
    [int]$WindowsInstaller.GetType().InvokeMember('ProductState','GetProperty',$null,$WindowsInstaller,@($ProductCode))
}

function Is-UserProductRegistered([string]$ProductCode) {
    # The Installer API also sees unmanaged per-user registrations when
    # Windows stores the metadata outside the conventional Uninstall key.
    $Products = $WindowsInstaller.GetType().InvokeMember('ProductsEx','GetProperty',$null,$WindowsInstaller,@($ProductCode,'',2))
    try { [int]$Products.GetType().InvokeMember('Count','GetProperty',$null,$Products,$null) -eq 1 }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Products) }
}

function Read-InstallPath {
    $Entry = Get-ItemProperty -LiteralPath $RawRegistry -Name 'InstallPath' -ErrorAction SilentlyContinue
    if ($null -ne $Entry) { [IO.Path]::GetFullPath($Entry.InstallPath).TrimEnd('\') }
}

function Invoke-Msi([string]$Action, [string]$Package, [string]$Step, [int]$ExpectedCode = 0, [switch]$UseTestPath) {
    $Log = Join-Path $Evidence "$Step.log"
    $Arguments = @($Action, ('"' + $Package + '"'), '/qn', '/norestart', '/L*V', ('"' + $Log + '"'))
    if ($UseTestPath) { $Arguments += ('INSTALLFOLDER="' + $InstallPath + '"') }
    $Process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    try {
        Assert-Check ($Process.WaitForExit(180000)) "Windows Installer did not finish $Step. See $Log"
        $Process.Refresh()
        Assert-Check ($Process.ExitCode -eq $ExpectedCode) "Windows Installer returned $($Process.ExitCode) during $Step. See $Log"
    } finally { $Process.Dispose() }
}

function Invoke-Profile([scriptblock]$Action) {
    $OriginalAppData = $env:APPDATA
    $OriginalLocalAppData = $env:LOCALAPPDATA
    $OriginalProfile = $env:SIGILS_INSTALL_TEST_PROFILE
    try {
        $env:APPDATA = $Profile
        $env:LOCALAPPDATA = $Profile
        $env:SIGILS_INSTALL_TEST_PROFILE = $Profile
        & $Action
    } finally {
        $env:APPDATA = $OriginalAppData
        $env:LOCALAPPDATA = $OriginalLocalAppData
        $env:SIGILS_INSTALL_TEST_PROFILE = $OriginalProfile
    }
}

function Read-GameProfile([string]$Payload, [string]$Version, [string]$Mode, [string]$Step) {
    $Log = Join-Path $Evidence "$Step.log"
    Invoke-Profile {
        & $Engine --headless --main-pack (Join-Path $Payload 'SigilsAndOaths.pck') --script $Probe --quit-after 800 -- $Mode $Version *> $Log
        $RunCode = $LASTEXITCODE
        Assert-Check ($RunCode -eq 0 -and (Select-String -LiteralPath $Log -Pattern '^INSTALLER PROFILE .+ OK' -Quiet)) "Game data test failed during $Step. See $Log"
        Assert-Check (-not (Select-String -LiteralPath $Log -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)) "Game data test reported errors during $Step. See $Log"
    }
}

function Profile-Fingerprint {
    $Entries = foreach ($Name in $DataNames) {
        $Files = @(Get-ChildItem -LiteralPath $Profile -Recurse -File -Filter $Name)
        Assert-Check ($Files.Count -eq 1) "Expected one isolated $Name"
        (Get-FileHash -LiteralPath $Files[0].FullName -Algorithm SHA256).Hash
    }
    $Entries -join ':'
}

function Verify-Files([string]$Payload) {
    foreach ($Name in $PayloadFiles) {
        $InstalledHash = (Get-FileHash -LiteralPath (Join-Path $InstallPath $Name) -Algorithm SHA256).Hash
        $SourceHash = (Get-FileHash -LiteralPath (Join-Path $Payload $Name) -Algorithm SHA256).Hash
        Assert-Check ($InstalledHash -eq $SourceHash) "Installed data must match the portable build: $Name"
    }
}

function Verify-Installed([string]$ProductCode, [string]$Version, [string]$Payload, [string]$Step) {
    Assert-Check ((Product-State $ProductCode) -eq 5 -and (Read-InstallPath) -eq $InstallPath) 'Product is not installed in the isolated directory.'
    Assert-Check (Is-UserProductRegistered $ProductCode) 'Windows Installer did not register a current-user product.'
    Verify-Files $Payload
    $Links = @(Get-ChildItem -File -Filter '*.lnk' -LiteralPath $Menu)
    Assert-Check ($Links.Count -eq 1) 'Expected exactly one Start Menu shortcut.'
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($Links[0].FullName)
    $Executable = Join-Path $InstallPath 'SigilsAndOaths.exe'
    Assert-Check ($Shortcut.TargetPath -eq $Executable -and $Shortcut.WorkingDirectory.TrimEnd('\') -eq $InstallPath) 'Start Menu shortcut target or working folder differs.'
    $BootLog = Join-Path $Evidence "$Step-native-startup.log"
    Invoke-Profile {
        $Game = Start-Process -FilePath $Executable -WorkingDirectory $Shortcut.WorkingDirectory -WindowStyle Hidden -PassThru `
            -ArgumentList @('--quit-after','100','--log-file',('"' + $BootLog + '"'))
        try {
            if (-not $Game.WaitForExit(45000)) {
                $Game.Kill()
                throw "Installed game did not finish the startup check during $Step."
            }
            $Game.Refresh()
            Assert-Check ($Game.ExitCode -eq 0) "Installed game exited with $($Game.ExitCode)."
        } finally { $Game.Dispose() }
    }
    Assert-Check ((Select-String -LiteralPath $BootLog -Pattern 'OpenGL API' -Quiet) -and
        -not (Select-String -LiteralPath $BootLog -Pattern '^ERROR:|^SCRIPT ERROR:' -Quiet)) "Native launch reported errors during $Step."
    Read-GameProfile $InstallPath $Version 'resume' "$Step-profile"
}

function Verify-Removed([string]$ProductCode) {
    Assert-Check ((Product-State $ProductCode) -ne 5 -and -not (Read-InstallPath) -and
        -not (Is-UserProductRegistered $ProductCode)) 'Uninstall left an installed product or registration.'
    Assert-Check (-not (Test-Path -LiteralPath $Menu)) 'Uninstall left the Start Menu shortcut.'
    foreach ($Name in $PayloadFiles) {
        Assert-Check (-not (Test-Path -LiteralPath (Join-Path $InstallPath $Name))) "Uninstall left $Name"
    }
    Assert-Check ((Test-Path -LiteralPath $Marker) -and (Profile-Fingerprint) -eq $SavedProfile) 'Uninstall touched personal files.'
}

$OldCode = Read-MsiProperty $OldMsi 'ProductCode'
$NewCode = Read-MsiProperty $CurrentMsi 'ProductCode'
$OldUpgrade = Read-MsiProperty $OldMsi 'UpgradeCode'
$NewUpgrade = Read-MsiProperty $CurrentMsi 'UpgradeCode'
Assert-Check ($OldCode -and $NewCode -and $OldCode -ne $NewCode -and $OldUpgrade -eq $NewUpgrade -and
    $NewUpgrade -eq '{9B6B5C43-E52F-4C9B-AC7A-913B6750C4A7}') 'Both packages must be distinct releases of Sigils and Oaths.'
Assert-Check ([int](Read-MsiProperty $CurrentMsi 'ProductLanguage') -eq 2052) 'Expected a Simplified Chinese installer.'
Assert-Check (-not (Read-MsiProperty $CurrentMsi 'ALLUSERS') -and -not (Read-MsiProperty $OldMsi 'ALLUSERS')) 'Expected a current-user installer.'
Assert-Check (-not (Read-InstallPath) -and -not (Test-Path -LiteralPath $Menu) -and (Product-State $OldCode) -ne 5 -and
    (Product-State $NewCode) -ne 5) 'The product is already installed. Use a fresh Windows test account.'
$IsAdmin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Assert-Check (-not $IsAdmin) 'Run this test from a non-elevated PowerShell session.'
$Evidence = (New-Item -ItemType Directory -Path (Join-Path $Project ('.tools/windows-delivery-' + [Guid]::NewGuid().ToString('N')))).FullName
$InstallPath = Join-Path $Evidence (([string][char]0x9A8C + [char]0x6536) + ' Game Folder')
$Profile = (New-Item -ItemType Directory -Path (Join-Path $Evidence 'isolated-appdata')).FullName
$Marker = Join-Path $InstallPath 'player-notes.txt'
Write-Host "Installer test logs: $Evidence"
Read-GameProfile $OldPayload $OldRelease.version 'seed' 'old-portable-profile'
$SavedProfile = Profile-Fingerprint
try {
    Invoke-Msi '/i' $OldMsi 'install-previous' -UseTestPath
    Verify-Installed $OldCode $OldRelease.version $OldPayload 'previous'
    Set-Content -LiteralPath $Marker -Value 'A file created by the player' -Encoding Ascii

    # The upgrade deliberately omits INSTALLFOLDER to exercise previous-path discovery.
    Invoke-Msi '/i' $CurrentMsi 'upgrade'
    Verify-Installed $NewCode $CurrentRelease.version $CurrentPayload 'upgraded'
    Assert-Check ((Product-State $OldCode) -ne 5 -and -not (Is-UserProductRegistered $OldCode)) 'Upgrade left a second installed version.'
    Invoke-Msi '/i' $OldMsi 'reject-downgrade' 1603
    Verify-Files $CurrentPayload
    Assert-Check ((Profile-Fingerprint) -eq $SavedProfile -and (Test-Path -LiteralPath $Marker)) 'Upgrade changed the data or an unrelated file.'

    Invoke-Msi '/x' $CurrentMsi 'uninstall'
    Verify-Removed $NewCode
    Invoke-Msi '/i' $CurrentMsi 'reinstall' -UseTestPath
    Verify-Installed $NewCode $CurrentRelease.version $CurrentPayload 'reinstalled'
    Invoke-Msi '/x' $CurrentMsi 'final-uninstall'
    Verify-Removed $NewCode
} finally {
    # Clean up only the products registered by this run in this exact test directory.
    if ((Read-InstallPath) -eq $InstallPath) {
        if ((Product-State $NewCode) -eq 5) { Invoke-Msi '/x' $CurrentMsi 'cleanup-current' }
        if ((Product-State $OldCode) -eq 5) { Invoke-Msi '/x' $OldMsi 'cleanup-previous' }
    }
}
[pscustomobject]@{
    previous=$OldRelease.version; current=$CurrentRelease.version; non_elevated=$true; language='zh-CN'
    fresh_install=$true; native_starts=3; installed_files_per_check=$PayloadFiles.Count; start_menu=$true
    upgraded_in_place=$true; downgrade_blocked=$true; uninstalled=$true; reinstalled=$true
    preserved_profile_files=$DataNames; retired_product_removed=$true; unrelated_file_preserved=$true
    status='passed'
} | ConvertTo-Json
