# 定义目标目录（当前脚本所在目录，即项目根目录）
$destDir = Get-Location

# 定义需要查找的 APK 文件名及其对应的目标名称
# 根据你的要求，移除了架构中的 'v'
$mapping = @{
    "app-arm64-v8a-release.apk"   = "Giantesswaltz_APP+arm64-8a.apk"
    "app-armeabi-v7a-release.apk" = "Giantesswaltz_APP+armeabi-7a.apk"
    "app-x86_64-release.apk"      = "Giantesswaltz_APP+x86_64.apk"
    "app-debug.apk"               = "Giantesswaltz_APP+debug.apk"
}

Write-Host "正在扫描 Flutter APK 文件..." -ForegroundColor Cyan

# 在当前目录下递归搜索 build 文件夹中的 apk
Get-ChildItem -Path $destDir -Filter "*.apk" -Recurse | ForEach-Object {
    $fileName = $_.Name
    
    if ($mapping.ContainsKey($fileName)) {
        $newName = $mapping[$fileName]
        $targetPath = Join-Path -Path $destDir -ChildPath $newName
        
        Write-Host "发现文件: $($_.FullName)" -ForegroundColor Gray
        Write-Host "正在移动并重命名为: $newName" -ForegroundColor Green
        
        # 强制移动并覆盖目标
        Move-Item -Path $_.FullName -Destination $targetPath -Force
    }
}

Write-Host "完成！APK 已整理至项目根目录。" -ForegroundColor Yellow