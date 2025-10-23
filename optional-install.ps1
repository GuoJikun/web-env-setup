# ===============================
# 可选软件安装脚本（winget）
# 支持交互选择 + 智能安装目录
# ===============================

# 停止出错时继续执行
$ErrorActionPreference = "Stop"

# 允许 Ctrl+C 被当作输入处理
[Console]::TreatControlCAsInput = $true

# 处理 Ctrl+C 中断
trap {
    Write-Log "脚本被中断，正在退出..." "Yellow"
    exit
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$msg,
        [string]$color = "White"
    )
    Write-Host $msg -ForegroundColor $color
}

# ---------------------------------------
# 可选软件列表
# ---------------------------------------
Write-Log "`n⚙️ 可选软件安装（Snipaste, Chrome, Firefox, QQ, 微信）..." "Cyan"

$installBasePath = "D:\Software"

$optionalPkgs = @(
    @{ Id = 'liule.Snipaste'; Name = 'Snipaste'; },
    @{ Id = 'Google.Chrome'; Name = 'Google Chrome'; },
    @{ Id = 'Mozilla.Firefox'; Name = 'Mozilla Firefox'; },
    @{ Id = 'Tencent.QQ'; Name = 'QQ'; },
    @{ Id = 'Tencent.WeChat'; Name = 'WeChat'; },
    @{ Id = 'agalwood.Motrix'; Name = 'Motrix'; },
    @{ Id = 'iQIYI.iQIYI'; Name = '爱奇艺'; },
    @{ Id = 'Tencent.TencentVideo'; Name = '腾讯视频'; },
    @{ Id = 'Youku.Youku'; Name = '优酷'; },
    @{ Id = 'NetEase.CloudMusic'; Name = '网易云音乐'; },
    @{ Id = 'Tencent.Foxmail'; Name = 'Foxmail'; }
)

# ---------------------------------------
# 多选交互选择器
# ---------------------------------------
function Show-MultiSelect {
    param(
        [Parameter(Mandatory = $true)][string[]]$Options,
        [string]$Title = "请选择（上下键切换，空格选择，回车确认，Esc 取消）"
    )

    $selected = @($false) * $Options.Count
    $cursor = 0

    function RenderAll {
        Clear-Host
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $mark = if ($selected[$i]) { '[√]' } else { '[ ]' }
            if ($i -eq $cursor) { Write-Host "> $mark $($Options[$i])" -ForegroundColor Cyan } else { Write-Host "  $mark $($Options[$i])" }
        }
    }

    RenderAll
    while ($true) {
        $key = [Console]::ReadKey($true)
        
        # 检查 Ctrl+C
        if ($key.KeyChar -eq [char]3) {
            Write-Log "Ctrl+C 按下，正在退出..." "Yellow"
            exit
        }
        
        $vk = $key.Key
        $ch = $key.KeyChar

        if ($vk -eq [System.ConsoleKey]::Enter) { break }
        if ($vk -eq [System.ConsoleKey]::Escape) { $selected = @(); break }

        switch ($vk) {
            ([System.ConsoleKey]::UpArrow) { if ($cursor -gt 0) { $cursor-- } else { $cursor = $Options.Count - 1 }; RenderAll }
            ([System.ConsoleKey]::DownArrow) { if ($cursor -lt $Options.Count - 1) { $cursor++ } else { $cursor = 0 }; RenderAll }
            ([System.ConsoleKey]::Spacebar) { $selected[$cursor] = -not $selected[$cursor]; RenderAll }
            default { if ($ch -eq ' ') { $selected[$cursor] = -not $selected[$cursor]; RenderAll } }
        }
    }

    $result = @()
    for ($i = 0; $i -lt $Options.Count; $i++) { if ($selected[$i]) { $result += $i } }
    Write-Host ""
    return $result
}

# ---------------------------------------
# 获取安装器类型
# ---------------------------------------
function Get-InstallerType {
    param([string]$PackageId)
    $info = winget show --id $PackageId --exact 2>$null
    if ($info) {
        $match = $info | Select-String -Pattern 'Installer\s+Type:\s+(.+)' | Select-Object -First 1
        if ($match) { return $match.Matches.Groups[1].Value.Trim() }
    }
    return $null
}

# ---------------------------------------
# 根据安装器类型生成 override 参数
# ---------------------------------------
function Get-OverrideForInstaller {
    param(
        [string]$installerType,
        [string]$name
    )

    $path = Join-Path $installBasePath $name
    switch -Regex ($installerType) {
        'inno' { return "/DIR=$path" }
        'nsis' { return "/D=$path" }
        'nullsoft' { return "/D=$path" }
        'msi' { return "INSTALLDIR=$path" }
        default { return $null }
    }
}

# ---------------------------------------
# 安装函数（带 override 支持）
# ---------------------------------------
function WingetInstall {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [string]$ExtraArgs = ""
    )

    Write-Log "🚀 正在安装 $DisplayName ..." "Cyan"

    $wingetArgs = @(
        "install",
        "--id", $PackageId,
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent"
    )

    if ($ExtraArgs -and $ExtraArgs.Trim() -ne "") {
        $wingetArgs += $ExtraArgs
    }

    Write-Log "📦 执行命令：winget $($wingetArgs -join ' ')" "Gray"

    try {
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            Write-Log "✅ $DisplayName 安装完成。" "Green"
        }
        else {
            Write-Log "❌ $DisplayName 安装失败（退出码：$($process.ExitCode)）。" "Red"
        }
    }
    catch {
        Write-Log "💥 安装 $DisplayName 时发生异常：$($_.Exception.Message)" "Red"
    }
}

# ---------------------------------------
# 主执行逻辑
# ---------------------------------------
$names = $optionalPkgs | ForEach-Object { $_.Name }
$sel = Show-MultiSelect -Options $names -Title "请选择要安装的软件（上下键切换，空格选择，回车确认，Esc/Ctrl+C 取消）："

if ($null -eq $sel -or $sel.Count -eq 0) {
    Write-Log "ℹ️ 未选择任何可选软件，跳过安装。" "Yellow"
    return
}

Write-Log "ℹ️ 开始安装选中软件..." "Yellow"

foreach ($i in $sel) {
    $pkg = $optionalPkgs[$i]
    $pkgId = $pkg.Id
    $pkgName = $pkg.Name

    # 检测是否已安装
    $found = winget list --id $pkgId | Select-String $pkgId
    if ($found) {
        Write-Log "✅ 检测到 $pkgName 已安装，跳过安装。" "Green"
        continue
    }

    # 检测安装器类型
    Write-Log "`n🔍 获取 $pkgName 安装器类型..." "Cyan"
    $type = Get-InstallerType -PackageId $pkgId
    if ($type) {
        Write-Log "🧩 检测到安装器类型：$type" "Gray"
    }
    else {
        Write-Log "⚠️ 无法检测安装器类型，使用默认安装方式。" "Yellow"
    }

    # 生成 override 参数
    $override = Get-OverrideForInstaller -installerType $type -name $pkgName
    if ($override) {
        Write-Log "⚙️ 使用 --override 参数安装至 $installBasePath\$pkgName" "Yellow"
        WingetInstall -PackageId $pkgId -DisplayName $pkgName -ExtraArgs "--override `"$override`""
    }
    else {
        Write-Log "⚙️ 使用默认安装参数安装 $pkgName" "Yellow"
        WingetInstall -PackageId $pkgId -DisplayName $pkgName
    }
}

Write-Log "`n🎉 所有选中软件处理完成！" "Green"
