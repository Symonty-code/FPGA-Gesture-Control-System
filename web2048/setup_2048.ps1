$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$gameDir = Join-Path $workspaceRoot "2048-fpga-game"

Write-Host "FPGA 2048 setup"
Write-Host "Source integration files: $PSScriptRoot"
Write-Host "Game directory: $gameDir"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is not available in PATH."
}

if (-not (Test-Path $gameDir)) {
    Write-Host "Cloning original 2048 source..."
    git clone https://github.com/gabrielecirulli/2048.git $gameDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
} else {
    Write-Host "Existing 2048-fpga-game directory found; reusing it."
}

$jsDir = Join-Path $gameDir "js"
if (-not (Test-Path $jsDir)) {
    throw "The target does not look like the original 2048 source: js directory is missing."
}

$integrationFiles = @(
    "fpga_game_extension.js",
    "application_fpga.js",
    "fpga_serial_controller.js"
)

foreach ($name in $integrationFiles) {
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path $source)) { throw "Missing integration file: $source" }
    Copy-Item $source (Join-Path $jsDir $name) -Force
    Write-Host "Copied $name"
}

$indexPath = Join-Path $gameDir "index.html"
$html = Get-Content $indexPath -Raw

$oldBootstrap = '<script src="js/application.js"></script>'
$newBootstrap = @'
  <script src="js/fpga_game_extension.js"></script>
  <script src="js/application_fpga.js"></script>
  <script src="js/fpga_serial_controller.js"></script>
'@

if ($html.Contains($oldBootstrap)) {
    $html = $html.Replace($oldBootstrap, $newBootstrap.Trim())
    Set-Content -Path $indexPath -Value $html -Encoding UTF8
    Write-Host "Patched index.html for FPGA control."
} elseif ($html.Contains('js/application_fpga.js')) {
    Write-Host "index.html is already patched for FPGA control."
} else {
    throw "Could not find the original application.js bootstrap in index.html."
}

# Apply a persistent CSS patch directly to the cloned game's stylesheet.
# This is more reliable than depending only on dynamically injected styles.
$cssPath = Join-Path $gameDir "style\main.css"
if (-not (Test-Path $cssPath)) {
    throw "Could not find style/main.css in the cloned 2048 source."
}

$cssMarker = "/* FPGA2048_CENTER_PATCH */"
$css = Get-Content $cssPath -Raw
if (-not $css.Contains($cssMarker)) {
    $centerPatch = @'

/* FPGA2048_CENTER_PATCH */
@media screen and (min-width: 521px) {
  body {
    margin-left: 0 !important;
    margin-right: 0 !important;
  }

  body > .container {
    width: 500px !important;
    max-width: 500px !important;
    margin-left: auto !important;
    margin-right: auto !important;
  }

  body > .container .game-container {
    margin-left: auto !important;
    margin-right: auto !important;
  }
}
'@
    Add-Content -Path $cssPath -Value $centerPatch -Encoding UTF8
    Write-Host "Patched style/main.css for centered desktop layout."
} else {
    Write-Host "style/main.css is already patched for centered desktop layout."
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "Next:"
Write-Host "  cd `"$gameDir`""
Write-Host "  py -m http.server 8000"
Write-Host "Then open http://localhost:8000 in a Chromium-based desktop browser and click Connect FPGA."
