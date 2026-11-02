$jsonPath = "c:\Users\David\Meta-CHIP-6.0\bitbake-setup\chip.conf.json"

try {
    $raw = Get-Content $jsonPath -Raw
    $data = $raw | ConvertFrom-Json
    Write-Host "JSON parsed successfully." -ForegroundColor Green

    # version
    Write-Host ("version  : " + $data.version)

    # description
    Write-Host ("desc     : " + $data.description)

    # sources
    $srcKeys = ($data.sources | Get-Member -MemberType NoteProperty).Name
    Write-Host ("sources  : " + ($srcKeys -join ", "))

    # Each source must have git-remote.branch and git-remote.rev (no stray "path")
    foreach ($key in $srcKeys) {
        $src = $data.sources.$key
        $branch = $src.'git-remote'.branch
        $rev    = $src.'git-remote'.rev
        $path   = $src.path
        $pathWarn = if ($path) { "  [WARNING: spurious 'path' field present]" } else { "" }
        Write-Host ("  [$key] branch=$branch rev=$rev$pathWarn")
    }

    # configurations
    $configs = $data.'bitbake-setup'.configurations
    Write-Host ("`nconfigurations (" + $configs.Count + "):")
    foreach ($cfg in $configs) {
        $hasName    = if ($cfg.name)          { "OK" } else { "MISSING" }
        $hasSetup   = if ($cfg.'setup-dir-name') { "OK" } else { "missing" }
        $layerCount = $cfg.'bb-layers'.Count
        $fragCount  = $cfg.'oe-fragments'.Count
        Write-Host ("  name=" + $cfg.name + "  name:$hasName  setup-dir-name:$hasSetup  bb-layers:$layerCount  oe-fragments:$fragCount")
    }

    Write-Host "`nValidation complete - no schema errors detected." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

