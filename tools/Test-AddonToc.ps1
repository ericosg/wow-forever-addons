# Validates every *.toc under -Path. Exit code 1 on any ERROR.
#   - TOC base name equals folder name (suffixes like _Forever/_Camelot/_Mainline allowed)
#   - every listed file exists, with the exact on-disk case
#   - listed .xml files are well-formed
#   - '## Interface:' includes the target interface number, '## Title:' is present
#   - SavedVariables are prefixed with the addon name (warning)
#   - .lua files on disk that the TOC never mentions (warning)
param(
    [Parameter(Mandatory)][string]$Path,
    [int]$Interface = 16001,
    [switch]$SkipLibs
)
$ErrorActionPreference = 'Stop'
$script:errors = 0
function Write-Problem([string]$Level, [string]$Message) {
    if ($Level -eq 'ERROR') { $script:errors++ }
    Write-Output ('{0,-5} {1}' -f $Level, $Message)
}

function Get-ExactCaseStatus([string]$Root, [string]$Relative) {
    # Walk each path segment and compare it with the real directory entry name.
    $current = $Root
    foreach ($segment in ($Relative -split '[\\/]')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        $entry = Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1
        if (-not $entry) { return 'missing' }
        if ($entry.Name -cne $segment) { return 'case:' + $entry.Name }
        $current = $entry.FullName
    }
    return 'ok'
}

$suffixes = '[-_](Mainline|Standard|Classic|Vanilla|TBC|BCC|Wrath|WOTLKC|Cata|Mists|Camelot|Forever)$'
$tocFiles = Get-ChildItem -Path $Path -Recurse -Filter *.toc -File
if ($SkipLibs) { $tocFiles = $tocFiles | Where-Object { $_.FullName -notmatch '[\\/]Libs?[\\/]' } }

foreach ($toc in $tocFiles) {
    $dir = $toc.Directory.FullName
    $folder = $toc.Directory.Name
    $base = $toc.BaseName -replace $suffixes, ''
    if ($base -cne $folder) { Write-Problem ERROR "$($toc.FullName): TOC base name '$base' must equal folder name '$folder'" }

    $bytes = [System.IO.File]::ReadAllBytes($toc.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Problem WARN "$($toc.Name): starts with a UTF-8 BOM; save as UTF-8 without BOM"
    }

    $meta = @{}
    $listed = New-Object System.Collections.Generic.List[string]
    $lineNo = 0
    foreach ($raw in [System.IO.File]::ReadAllLines($toc.FullName, [System.Text.Encoding]::UTF8)) {
        $lineNo++
        $line = $raw.Trim().TrimStart([char]0xFEFF)
        if ($line -eq '') { continue }
        if ($line -match '^##\s*([^:]+?)\s*:\s*(.*)$') { $meta[$Matches[1]] = $Matches[2]; continue }
        if ($line.StartsWith('#')) { continue }
        $file = ($line -replace '\s*\[[^\]]*\]', '').Trim()     # strip inline [AllowLoadGameType ...] directives
        if ($line -match '\[(Family|Game|TextLocale)\]') { Write-Problem WARN "$($toc.Name):$lineNo uses a TOC variable, not checked: $line"; continue }
        $listed.Add($file.Replace('/', '\').ToLowerInvariant())
        $status = Get-ExactCaseStatus $dir $file
        if ($status -eq 'missing') {
            Write-Problem ERROR "$($toc.Name):${lineNo}: listed file not found: $file"
            continue
        }
        if ($status -like 'case:*') {
            Write-Problem ERROR "$($toc.Name):${lineNo}: case mismatch in '$file' (on disk: '$($status.Substring(5))'). Loads on Windows, breaks on case-sensitive systems and in CI"
        }
        if ($file -match '\.xml$') {
            try { $xml = New-Object System.Xml.XmlDocument; $xml.Load((Join-Path $dir $file)) }
            catch { Write-Problem ERROR "$($toc.Name):${lineNo}: $file is not well-formed XML: $($_.Exception.Message)" }
        }
    }

    foreach ($required in 'Interface', 'Title') {
        if (-not $meta.ContainsKey($required)) { Write-Problem ERROR "$($toc.Name): missing '## ${required}:'" }
    }
    if ($meta['Interface'] -and (($meta['Interface'] -split '\s*,\s*') -notcontains "$Interface")) {
        Write-Problem ERROR "$($toc.Name): '## Interface: $($meta['Interface'])' does not include $Interface (addon is flagged out of date)"
    }
    foreach ($key in 'SavedVariables', 'SavedVariablesPerCharacter') {
        if (-not $meta[$key]) { continue }
        foreach ($sv in ($meta[$key] -split '\s*,\s*')) {
            if ($sv -and -not $sv.StartsWith($base)) { Write-Problem WARN "$($toc.Name): $key '$sv' is not prefixed with the addon name '$base'" }
        }
    }
    foreach ($lua in Get-ChildItem -LiteralPath $dir -Recurse -Filter *.lua -File) {
        $rel = $lua.FullName.Substring($dir.Length + 1)
        if ($rel -match '^(Libs?|\.release|tests?|spec)[\\/]') { continue }
        if (-not $listed.Contains($rel.ToLowerInvariant())) {
            Write-Problem WARN "$($toc.Name): $rel is on disk but not listed in this TOC (loaded from XML or another TOC, or dead)"
        }
    }
    Write-Output "checked $($toc.FullName)"
}
if ($script:errors) { Write-Output "$($script:errors) error(s)"; exit 1 }
Write-Output 'TOC check passed'
