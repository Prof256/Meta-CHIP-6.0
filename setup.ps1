#!/usr/bin/env pwsh
# Next Thing Co. C.H.I.P. Yocto 6.0 Setup Assistant for PowerShell
# Interactive script to configure bitbake-setup, layers, and build profiles

Write-Host @"
============================================================
   C.H.I.P.  $9 Computer - Yocto 6.0 (Wrynose) Assistant
============================================================
"@ -ForegroundColor Cyan

Write-Host "`nSelect Build Profile:" -ForegroundColor Yellow
Write-Host "  [1] Poky + Onboard NAND Flash (UBI) (Recommended)"
Write-Host "      -> Standard Yocto reference distro targeting onboard NAND flash."
Write-Host "  [2] Poky + MicroSD / USB Storage (ext4/wic)"
Write-Host "      -> Standard Yocto reference distro targeting USB or microSD breakout."
Write-Host "  [3] Minimal OpenEmbedded (nodistro) + Onboard NAND Flash (UBI)"
Write-Host "      -> Lightweight distroless build with minimal footprint for NAND."
Write-Host "  [4] Minimal OpenEmbedded (nodistro) + MicroSD / USB Storage"
Write-Host "      -> Lightweight distroless build configured for USB/microSD."

$profileChoice = Read-Host "`nEnter profile choice [1]"
if ([string]::IsNullOrWhiteSpace($profileChoice)) { $profileChoice = "1" }

$nandChoice = "1"
if ($profileChoice -eq "1" -or $profileChoice -eq "3") {
    Write-Host "`nSelect Onboard NAND Flash Type:" -ForegroundColor Yellow
    Write-Host "  [1] Hynix H27UCG8T2ETR (MLC, 16K Page, 2MB PEB) (Recommended) [Standard C.H.I.P. v1.0]"
    Write-Host "  [2] Toshiba TC58NVG1S3HTA00 (SLC, 2K/4K Page, 256KB PEB)"
    $nandChoice = Read-Host "`nEnter NAND choice [1]"
    if ([string]::IsNullOrWhiteSpace($nandChoice)) { $nandChoice = "1" }
}

Write-Host "`nSelect Yocto Release Branch:" -ForegroundColor Yellow
Write-Host "  [1] master / wrynose (Yocto 6.0 Development / Latest) (Recommended)"
Write-Host "  [2] scarthgap (Yocto 5.0 LTS)"
$branchChoice = Read-Host "`nEnter branch choice [1]"
if ([string]::IsNullOrWhiteSpace($branchChoice)) { $branchChoice = "1" }

$rev = if ($branchChoice -eq "2") { "scarthgap" } else { "master" }

$wifiInput = Read-Host "`nEnable Realtek RTL8723BS Wi-Fi and Bluetooth? (Y/n) [Y]"
$enableWifi = $wifiInput -notmatch "^[nN]"

# Profile mapping
switch ($profileChoice) {
    "2" {
        $profileId = "chip-poky-sd-usb"
        $distro    = "poky"
        $storage   = "sd-usb"
        $fragments = @("machine/chip", "distro/poky", "storage/chip-sd-usb")
    }
    "3" {
        $profileId = "chip-nodistro-nand"
        $distro    = "nodistro"
        $storage   = "nand"
        $fragments = @("machine/chip", "storage/chip-nand")
    }
    "4" {
        $profileId = "chip-nodistro-sd-usb"
        $distro    = "nodistro"
        $storage   = "sd-usb"
        $fragments = @("machine/chip", "storage/chip-sd-usb")
    }
    default {
        $profileId = "chip-poky-nand"
        $distro    = "poky"
        $storage   = "nand"
        $fragments = @("machine/chip", "distro/poky", "storage/chip-nand")
    }
}

# Determine bb-layers based on distro choice
if ($distro -eq "poky") {
    $bbLayers = @(
        "openembedded-core/meta",
        "meta-yocto/meta-poky",
        "meta-yocto/meta-yocto-bsp",
        "meta-openembedded/meta-oe",
        "meta-openembedded/meta-python",
        "meta-openembedded/meta-networking",
        "meta-chip"
    )
} else {
    $bbLayers = @(
        "openembedded-core/meta",
        "meta-openembedded/meta-oe",
        "meta-chip"
    )
}

# Helper: build a source entry with branch + rev (schema requires both)
function New-Source($uri, $branch) {
    return [ordered]@{
        "git-remote" = [ordered]@{
            "remotes" = [ordered]@{ "origin" = [ordered]@{ "uri" = $uri } }
            "branch"  = $branch
            "rev"     = $branch
        }
    }
}

# Build sources (nodistro doesn't need meta-yocto)
$sources = [ordered]@{
    "bitbake"           = New-Source "https://git.openembedded.org/bitbake" $rev
    "openembedded-core" = New-Source "https://git.openembedded.org/openembedded-core" $rev
    "meta-openembedded" = New-Source "https://git.openembedded.org/meta-openembedded" $rev
    "meta-chip"         = New-Source "https://github.com/my-chip/meta-chip-6.0" "master"
}
if ($distro -eq "poky") {
    $sources["meta-yocto"] = New-Source "https://git.yoctoproject.org/meta-yocto" $rev
}

# Assemble the bitbake-setup config (schema: version required, no spurious "path" keys)
$setupJson = [ordered]@{
    "version"     = "1.0"
    "description" = "Next Thing Co. C.H.I.P. - $profileId ($rev)"
    "sources"     = $sources
    "bitbake-setup" = [ordered]@{
        "configurations" = @(
            [ordered]@{
                "name"           = $profileId
                "description"    = "Next Thing Co. C.H.I.P. build profile: $profileId"
                "setup-dir-name" = $profileId
                "bb-layers"      = $bbLayers
                "oe-fragments"   = $fragments
            }
        )
    }
}

$repoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repoRoot)) { $repoRoot = (Get-Location).Path }

# Write JSON
$outJsonPath = Join-Path $repoRoot "bitbake-setup\$profileId.json"
New-Item -ItemType Directory -Force -Path (Split-Path $outJsonPath) | Out-Null
$setupJson | ConvertTo-Json -Depth 10 | Out-File -FilePath $outJsonPath -Encoding utf8

# Generate local.conf.sample
$localConfPath = Join-Path $repoRoot "conf\local.conf.sample"
$lines = @(
    "# ================================================================",
    "# C.H.I.P. Configuration Snippet (for conf/local.conf)",
    "# Generated by setup.ps1 - profile: $profileId",
    "# ================================================================",
    'MACHINE = "chip"'
)
if ($distro -eq "poky") { $lines += 'DISTRO = "poky"' }

if ($storage -eq "nand") {
    $lines += 'IMAGE_FSTYPES += " ubi"'
    if ($nandChoice -eq "2") {
        $lines += 'CHIP_NAND_TYPE = "toshiba-slc"'
        $lines += 'CHIP_UBI_PAGE_SIZE = "4096"'
        $lines += 'CHIP_UBI_PEB_SIZE = "262144"'
        $lines += 'CHIP_UBI_LEB_SIZE = "253952"'
        $lines += 'CHIP_UBI_MAX_LEB_CNT = "1000"'
    } else {
        $lines += 'CHIP_NAND_TYPE = "hynix-mlc"'
        $lines += 'CHIP_UBI_PAGE_SIZE = "16384"'
        $lines += 'CHIP_UBI_PEB_SIZE = "2097152"'
        $lines += 'CHIP_UBI_LEB_SIZE = "2064384"'
        $lines += 'CHIP_UBI_MAX_LEB_CNT = "2000"'
    }
} else {
    $lines += 'IMAGE_FSTYPES += " ext4 wic"'
}
if ($enableWifi) {
    $lines += 'MACHINE_EXTRA_RRECOMMENDS += " kernel-module-r8723bs rtl8723bs linux-firmware-rtl8723"'
}
$lines += 'BB_NUMBER_THREADS ?= "${@oe.utils.cpu_count()}"'
$lines += 'PARALLEL_MAKE ?= "-j ${@oe.utils.cpu_count()}"'

$lines | Out-File -FilePath $localConfPath -Encoding utf8

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " Configuration successfully generated!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Profile:  $profileId"
Write-Host "  Branch:   $rev"
Write-Host "  JSON:     $outJsonPath"
Write-Host "  local.conf sample: $localConfPath"
Write-Host ""
Write-Host "Next Steps (on a Linux build host or WSL):" -ForegroundColor Yellow
Write-Host "  pip install bitbake-setup"
Write-Host "  bitbake-setup init $outJsonPath"
Write-Host "  cd $profileId && bitbake chip-image-minimal"
Write-Host "============================================================`n"

