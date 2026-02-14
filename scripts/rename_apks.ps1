param(
    [string]$Dir = ".\build\app\outputs\flutter-apk"
)

# Resolve directory
$resolved = Resolve-Path -Path $Dir -ErrorAction SilentlyContinue
if (-not $resolved) {
    Write-Error "Directory not found: $Dir"
    exit 1
}
$target = $resolved.Path

Write-Host "Processing APKs in: $target"

# Helper to compute new name
function Get-NewApkName($name) {
    # Remove any trailing .sha1 for analysis
    $plain = $name -replace '\.sha1$', ''
    # Remove leading 'app-'
    $noPrefix = $plain -replace '^app-', ''
    # Remove common build suffixes like -release or -debug
    $noSuffix = $noPrefix -replace '-(release|debug)$', ''
    # Strip trailing .apk if present
    $token = $noSuffix -replace '\.apk$', ''

    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [System.IO.Path]::GetFileNameWithoutExtension($plain)
    }
    return "Giantesswaltz_APP+${token}.apk"
}

# Detect ABI inside an APK by inspecting lib/ entries
function Detect-ApkAbi($apkPath) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
        $entries = $zip.Entries | ForEach-Object { $_.FullName }
        $zip.Dispose()
        if ($entries -match '^lib/armeabi-v7a/') { return 'armeabi-v7a' }
        if ($entries -match '^lib/arm64-v8a/') { return 'arm64-v8a' }
        if ($entries -match '^lib/x86_64/') { return 'x86_64' }
        if ($entries -match '^lib/x86/') { return 'x86' }
        return 'universal'
    }
    catch {
        return 'universal'
    }
}
# Rename .apk files
$apkFiles = Get-ChildItem -Path $target -File -Filter "*.apk" -ErrorAction SilentlyContinue
foreach ($f in $apkFiles) {
    # If already correctly named like Giantesswaltz_APP+<token>.apk, skip
    if ($f.Name -match '^Giantesswaltz_APP\+[^\s]+\.apk$') {
        Write-Host "Skipping already-named file: $($f.Name)"
        continue
    }

    # If name uses prefix but token is empty (e.g., Giantesswaltz_APP+.apk), detect ABI from content
    if ($f.Name -match '^Giantesswaltz_APP\+$') {
        $abi = Detect-ApkAbi $f.FullName
        $newName = "Giantesswaltz_APP+$abi.apk"
    }
    else {
        $newName = Get-NewApkName $f.Name
    }
    $dest = Join-Path $target $newName
    Write-Host "Renaming $($f.Name) -> $newName"
    Move-Item -LiteralPath $f.FullName -Destination $dest -Force
}

# Rename .apk.sha1 files to match renamed apks
$shaFiles = Get-ChildItem -Path $target -File -Filter "*.apk.sha1" -ErrorAction SilentlyContinue
foreach ($f in $shaFiles) {
    # If already correctly named like Giantesswaltz_APP+<token>.apk.sha1, skip
    if ($f.Name -match '^Giantesswaltz_APP\+[^\s]+\.apk\.sha1$') {
        Write-Host "Skipping already-named sha1: $($f.Name)"
        continue
    }

    # If prefix exists but token empty, try to detect from the paired apk
    if ($f.Name -match '^Giantesswaltz_APP\+.*\.apk\.sha1$') {
        # derive corresponding apk file
        $apkCandidate = ($f.Name -replace '\.sha1$', '')
        $apkPath = Join-Path $target $apkCandidate
        if (-not (Test-Path $apkPath)) {
            # fallback: try detect from any Giantesswaltz_APP*.apk
            $apkMatch = Get-ChildItem -Path $target -Filter 'Giantesswaltz_APP+*.apk' | Select-Object -First 1
            if ($apkMatch) { $abi = Detect-ApkAbi $apkMatch.FullName }
            else { $abi = 'universal' }
        }
        else {
            $abi = Detect-ApkAbi $apkPath
        }
        $newApkName = "Giantesswaltz_APP+$abi.apk"
    }
    else {
        $newApkName = Get-NewApkName $f.Name
    }
    $newName = "${newApkName}.sha1"
    $dest = Join-Path $target $newName
    Write-Host "Renaming $($f.Name) -> $newName"
    Move-Item -LiteralPath $f.FullName -Destination $dest -Force
}

Write-Host "Done."