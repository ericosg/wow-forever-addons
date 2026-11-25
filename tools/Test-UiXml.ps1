# Validates addon XML against Blizzard's UI.xsd (from the forever branch of wow-ui-source).
param([Parameter(Mandatory)][string]$Xsd, [Parameter(Mandatory)][string[]]$Path)
$ErrorActionPreference = 'Stop'
$schemas = New-Object System.Xml.Schema.XmlSchemaSet
[void]$schemas.Add('http://www.blizzard.com/wow/ui/', (Resolve-Path $Xsd).Path)
$schemas.Compile()
$failed = 0
foreach ($file in Get-ChildItem -Path $Path -Recurse -Filter *.xml -File) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.Schemas = $schemas
    $settings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
    $script:problems = @()
    $settings.add_ValidationEventHandler({ param($s, $e)
        $script:problems += ('{0}({1},{2}): {3}: {4}' -f $file.FullName, $e.Exception.LineNumber, $e.Exception.LinePosition, $e.Severity, $e.Message) })
    try {
        $reader = [System.Xml.XmlReader]::Create($file.FullName, $settings)
        try { while ($reader.Read()) { } } finally { $reader.Close() }
    } catch [System.Xml.XmlException] {
        $script:problems += ('{0}({1},{2}): NotWellFormed: {3}' -f $file.FullName, $_.Exception.LineNumber, $_.Exception.LinePosition, $_.Exception.Message)
    }
    if ($script:problems.Count) { $failed++; $script:problems | ForEach-Object { Write-Output $_ } }
    else { Write-Output ('OK  {0}' -f $file.FullName) }
}
if ($failed) { exit 1 }
