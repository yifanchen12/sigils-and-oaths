[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BuildDirectory,
    [string]$OutputDirectory,
    [string]$WixPath = (Join-Path $PSScriptRoot '../.tools/wix-5.0.2/wix.exe'),
    [string]$UiExtensionPath = (Join-Path $PSScriptRoot '../.tools/wix-5.0.2/ui-extension/wixext5/WixToolset.UI.wixext.dll')
)

$ErrorActionPreference = 'Stop'
$BuildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$SourceRoot = Join-Path $BuildRoot 'windows-x64'
$OutputRoot = if ($OutputDirectory) { (Resolve-Path -LiteralPath $OutputDirectory).Path } else { $BuildRoot }
$Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $SourceRoot 'RELEASE_INFO.json') | ConvertFrom-Json
if ($Manifest.platform -ne 'windows-x64' -or $Manifest.source_dirty -ne $false -or $Manifest.smoke_test -ne 'packaged-executable-headless-startup' -or
    $Manifest.version -notmatch '^([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z.-]+)?$') {
    throw 'Supply a verified Windows build created by tools/build_release.ps1.'
}
$ProductVersion = [version]$Matches[1]
if ($ProductVersion.Major -gt 255 -or $ProductVersion.Minor -gt 255 -or $ProductVersion.Build -gt 65535) {
    throw 'This version exceeds the Windows Installer version limits.'
}
foreach ($Name in @('SigilsAndOaths.exe', 'SigilsAndOaths.pck')) {
    $File = Get-Item -LiteralPath (Join-Path $SourceRoot $Name)
    $Expected = @($Manifest.payload | Where-Object file -eq $Name)
    if ($Expected.Count -ne 1 -or $Expected[0].bytes -ne $File.Length -or
        (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash -ne $Expected[0].sha256) {
        throw "Windows release data does not match the manifest: $Name"
    }
}
$Compiler = (Resolve-Path -LiteralPath $WixPath).Path
$UiExtension = (Resolve-Path -LiteralPath $UiExtensionPath).Path
$WixVersion = (& $Compiler --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $WixVersion -notmatch '^5\.0\.2(\+|$)') {
    throw 'This installer has been built and tested with WiX 5.0.2.'
}
$FileName = "sigils-and-oaths-$($Manifest.version)-windows-x64.msi"
$Destination = Join-Path $OutputRoot $FileName
if (Test-Path -LiteralPath $Destination) { throw "An installer already exists: $Destination" }
$LogPath = Join-Path $OutputRoot "installer-$($Manifest.version)-build.log"
$ScratchName = '.installer-' + [Guid]::NewGuid().ToString('N')
$Scratch = (New-Item -ItemType Directory -Path (Join-Path $OutputRoot $ScratchName)).FullName
try {
    $License = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $SourceRoot 'LICENSE.txt')
    $LicenseLines = foreach ($Line in ($License -split '\r?\n')) {
        foreach ($Character in $Line.ToCharArray()) {
            switch ($Character) {
                '\' { '\\' }
                '{' { '\{' }
                '}' { '\}' }
                default {
                    $Code = [int]$Character
                    if ($Code -gt 127) {
                        if ($Code -gt 32767) { $Code -= 65536 }
                        "\u$Code?"
                    } else { [string]$Character }
                }
            }
        }
        '\par ' + [Environment]::NewLine
    }
    $LicenseRtf = Join-Path $Scratch 'license.rtf'
    Set-Content -LiteralPath $LicenseRtf -Encoding Ascii -Value ('{\rtf1\ansi\uc1\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs20 ' + ($LicenseLines -join '') + '}')
    $GameIcon = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../assets/art/lantern-windows.ico')).Path
    $TemporaryMsi = Join-Path $Scratch $FileName
    & $Compiler build -nologo -arch x64 -culture zh-CN -ext $UiExtension -pdbtype none `
        -d "ProductVersion=$ProductVersion" -d "GamePayload=$SourceRoot" -d "GameIcon=$GameIcon" `
        -d "LicenseRtf=$LicenseRtf" -o $TemporaryMsi (Join-Path $PSScriptRoot 'windows_installer.wxs') *> $LogPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $TemporaryMsi)) {
        throw "Windows Installer build failed. See $LogPath"
    }
    [IO.File]::Move($TemporaryMsi, $Destination)
} finally {
    $Resolved = (Resolve-Path -LiteralPath $Scratch).Path
    if ((Split-Path -Parent $Resolved) -eq $OutputRoot -and (Split-Path -Leaf $Resolved) -eq $ScratchName) {
        Remove-Item -LiteralPath $Resolved -Recurse -Force
    }
}
[pscustomobject]@{
    path=$Destination; version=$Manifest.version; product_version="$ProductVersion"; compiler=$WixVersion
    bytes=(Get-Item -LiteralPath $Destination).Length
    sha256=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json
