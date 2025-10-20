# 设置脚本在出错时停止
$ErrorActionPreference = "Stop"

# -------------------------
# PowerShell 版本检查与自动安装（确保运行在 PowerShell 7+）
function Restart-InPwsh7IfNeeded {
    $CurrentMajor = $PSVersionTable.PSVersion.Major
    if ($CurrentMajor -ge 7) { return $false }

    Write-Host "⚠️ 当前会话为 PowerShell 小于 7，检测系统中是否已安装 PowerShell 7+..." -ForegroundColor Yellow

    # 尝试从 PATH 查找 pwsh
    $pwshPath = $null
    $installedMajor = 0
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) {
        $pwshPath = $pwshCmd.Source
        try { $installedMajor = & "$pwshPath" -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null | ForEach-Object { [int]$_ } } catch { $installedMajor = 0 }
    }

    # 如果 PATH 未找到，再检查常见目录
    if (-not $pwshPath) {
        $possible = @(
            "$env:ProgramFiles\PowerShell\7\pwsh.exe",
            "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe",
            "$env:ProgramFiles(x86)\PowerShell\7\pwsh.exe"
        )
        foreach ($p in $possible) {
            if (Test-Path $p) {
                try { $ver = & "$p" -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null | ForEach-Object { [int]$_ } } catch { $ver = 0 }
                if ($ver -and $ver -gt 0) { $pwshPath = $p; $installedMajor = $ver; break }
            }
        }
    }

    # 如果找到了 7+，就用它重新启动脚本
    if ($installedMajor -ge 7 -and $pwshPath) {
        Write-Host "✅ 系统已安装 PowerShell $installedMajor，使用 $pwshPath 重新运行脚本。" -ForegroundColor Green

        # 解析脚本路径：优先使用 $PSCommandPath（PowerShell 3+），回退到 MyInvocation
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }

        $argsFromInvocation = @()
        if ($MyInvocation.UnboundArguments) {
            foreach ($item in $MyInvocation.UnboundArguments) {
                if ($item -ne $null -and $item -ne '') { $argsFromInvocation += [string]$item }
            }
        }
        $baseArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit')
        $argList = $baseArgs + @('-File', $scriptPath) + $argsFromInvocation
        $argList = @($argList) | Where-Object { $_ -ne $null -and $_ -ne '' }
        Start-Process -FilePath $pwshPath -ArgumentList $argList -Verb RunAs
        return $true
    }
    else {
        Write-Host "⚠️ 未找到 PowerShell 7，可手动安装后重试。" -ForegroundColor Yellow
        return $false
    }
}

# 如果需要安装并重启，则退出当前进程（新进程将接手）
if (Restart-InPwsh7IfNeeded) {
    Write-Host "Exiting current process to allow PowerShell 7+ to handle the rest..." -ForegroundColor Cyan
    exit 0
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$msg,
        [string]$color = "White"
    )
    Write-Host $msg -ForegroundColor $color
}



Write-Log "`n⚙️ 安装 Volta ..." "Cyan"

# --------------------------
# 检查环境变量 VOLTA_FEATURE_PNPM
# --------------------------
$val = [System.Environment]::GetEnvironmentVariable("VOLTA_FEATURE_PNPM", "Machine")
if (-not $val) {
    $val = [System.Environment]::GetEnvironmentVariable("VOLTA_FEATURE_PNPM", "User")
}

if ($val -eq "1") {
    Write-Log "✅ VOLTA_FEATURE_PNPM 已设置，跳过" "Green"
}
else {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if ($isAdmin) {
        [System.Environment]::SetEnvironmentVariable("VOLTA_FEATURE_PNPM", "1", "Machine")
        Write-Log "✅ 已设置系统级别的环境变量 VOLTA_FEATURE_PNPM = 1" "Green"
    }
    else {
        [System.Environment]::SetEnvironmentVariable("VOLTA_FEATURE_PNPM", "1", "User")
        Write-Log "⚠️ 未以管理员身份运行，已设置用户级别的环境变量 VOLTA_FEATURE_PNPM = 1" "Yellow"
    }
}




# ==========================
# ==========================
# 在安装 Volta 之前：使用 winget 检查并安装 Git 与 Visual Studio Code（如未安装）
# 该步骤为幂等：先检测是否存在命令，再决定是否调用 winget 安装。需要管理员权限时会尝试提升权限。
# ==========================

Write-Log "`n⚙️ 检查并安装 Git 与 Visual Studio Code（通过 winget）..." "Cyan"

# Helper: 使用 winget 安装包，自动接受协议并在非管理员时尝试提升
function Ensure-WingetInstall {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $false)][string]$DisplayName = $PackageId
    )

    $installCmd = "winget install $PackageId --accept-source-agreements --accept-package-agreements -e"
    Write-Log "🔧 使用 winget 安装 $DisplayName..." "Cyan"
    Invoke-Expression $installCmd
    if ($LASTEXITCODE -ne 0) { Write-Log "❌ 使用 winget 安装 $DisplayName 失败（ExitCode=$LASTEXITCODE）。" "Red" }
    else { Write-Log "✅ 已通过 winget 安装 $DisplayName 成功。" "Green" }
}
# 首先尝试检测 'code' 命令或常见安装注册表；若未找到则使用 winget
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Log "✅ Visual Studio Code (code) 命令可用，跳过" "Green"
}
else {
    # 额外检查常见安装目录（便于用户通过安装程序安装但未将 code 加入 PATH 的情况）
    $vscodeFound = $false
    $possiblePaths = @(
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles(x86)\Microsoft VS Code\Code.exe",
        "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
    )
    foreach ($p in $possiblePaths) { if (Test-Path $p) { $vscodeFound = $true; break } }

    if ($vscodeFound) {
        Write-Log "✅ 已找到 Visual Studio Code 安装，但 'code' 命令不可用。请手动在 VS Code 中启用 'Shell Command: Install 'code' command in PATH' 或重新登录会话。" "Yellow"
    }
    else {
        Write-Log "⚠️ 未检测到 Visual Studio Code，尝试使用 winget 安装 VS Code..." "Yellow"
        Ensure-WingetInstall -PackageId 'Microsoft.VisualStudioCode' -DisplayName 'Visual Studio Code'
        # 刷新 PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
}

# ==========================
if (!(Get-Command volta -ErrorAction SilentlyContinue)) {
    Write-Log "⚠️ Volta 未安装，尝试使用 winget 安装 Volta..." "Yellow"
    winget install Volta.Volta --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✅ 已通过 winget 安装 Volta 成功" "Green"

        # 尝试刷新 PATH 环境变量，使 volta 立即可用
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")

        # 检查 volta 是否立即可用
        if (!(Get-Command volta -ErrorAction SilentlyContinue)) {
            Write-Log "⚠️ volta 暂不可用，可能需要重新打开终端。继续尝试执行安装..." "Yellow"
        }
    }
    else {
        Write-Log "❌ 使用 winget 安装 Volta 失败，请手动检查。" "Red"
    }
}
else {
    Write-Log "✅ Volta 已安装，跳过" "Green"
}

# ==========================
# 使用 Volta 安装 NodeJS 和 pnpm
# ==========================
Write-Log "`n⚙️ 安装 NodeJS 和 pnpm ..." "Cyan"

$nodeInstalled = volta list node | Select-String "default" -ErrorAction SilentlyContinue
if ($nodeInstalled) {
    Write-Log "✅ NodeJS 已安装，跳过" "Green"
}
else {
    volta install node
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✅ NodeJS 已通过 Volta 安装成功" "Green"
    }
    else {
        Write-Log "❌ 使用 Volta 安装 NodeJS 失败，请手动检查 Volta 日志或终端输出。" "Red"
    }
}

$pnpmInstalled = volta list pnpm | Select-String "default" -ErrorAction SilentlyContinue
if ($pnpmInstalled) {
    Write-Log "✅ pnpm 已安装，跳过" "Green"
}
else {
    volta install pnpm
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✅ pnpm 已通过 Volta 安装成功" "Green"
    }
    else {
        Write-Log "❌ 使用 Volta 安装 pnpm 失败，请手动检查 Volta 日志或终端输出。" "Red"
    }
}

Write-Log "`n🎉 所有步骤完成！" "Green"
Write-Log "请重新打开终端以应用环境变量。" "Yellow"

# -------------------------
# 可选软件安装（通过 winget，交互式选择）
# 支持：通过环境变量 WEB_ENV_SETUP_INSTALL_OPTIONAL=1 跳过交互并自动安装所有可选软件
# -------------------------
Write-Log "`n⚙️ 可选软件安装（Snipaste, Chrome, Firefox, QQ, 微信）..." "Cyan"

# 是否以环境变量自动全部安装（绕过交互）
$autoInstallAll = $env:WEB_ENV_SETUP_INSTALL_OPTIONAL -eq '1'

$optionalPkgs = @(
    @{ Id = 'liule.Snipaste'; Name = 'Snipaste';  },
    @{ Id = 'Google.Chrome'; Name = 'Google Chrome'; },
    @{ Id = 'Mozilla.Firefox'; Name = 'Mozilla Firefox'; },
    @{ Id = 'Tencent.QQ'; Name = 'QQ'; },
    @{ Id = 'Tencent.WeChat'; Name = 'WeChat'; }
    )

function Show-MultiSelect {
    param(
        [Parameter(Mandatory = $true)][string[]]$Options,
        [string]$Title = "请选择（上下键切换，空格选择，回车确认，Esc 取消）"
    )

    $selected = @()
    for ($i = 0; $i -lt $Options.Count; $i++) { $selected += $false }
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
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $vk = $key.VirtualKeyCode
        $ch = $key.Character

        # 兼容不同主机对回车/ESC的编码：CR(13)、LF(10)、ESC(27)
        if ($vk -eq 13 -or $ch -eq "`r" -or $ch -eq "`n") { break }
        if ($vk -eq 27 -or ([int][char]$ch) -eq 27) { $selected = @(); break }

        switch ($vk) {
            38 { if ($cursor -gt 0) { $cursor-- } else { $cursor = $Options.Count - 1 }; RenderAll } # Up
            40 { if ($cursor -lt $Options.Count - 1) { $cursor++ } else { $cursor = 0 }; RenderAll } # Down
            32 { $selected[$cursor] = -not $selected[$cursor]; RenderAll }                            # Space
            default {
                # 某些主机 Space 可能表现为字符而非 VK；再做一次字符判断
                if ($ch -eq ' ') { $selected[$cursor] = -not $selected[$cursor]; RenderAll }
            }
        }
    }

    $result = @()
    for ($i = 0; $i -lt $Options.Count; $i++) { if ($selected[$i]) { $result += $i } }
    Write-Host ""
    return $result
}

$names = $optionalPkgs | ForEach-Object { $_.Name }
$sel = $null
$sel = Show-MultiSelect -Options $names -Title "请选择要安装的可选软件（空格切换，回车确认）："
$selCount = $sel.Count

if ($null -eq $sel -or $selCount -eq 0) {
    Write-Log "ℹ️ 未选择任何可选软件，跳过安装。" "Yellow"
}
else {
    Write-Log "ℹ️ 开始安装选中软件..." "Yellow"
    foreach ($i in $sel) {
        $pkg = $optionalPkgs[$i]
        # 再次检测路径
        $found = winget list --id $pkg.Id | Select-String $pkg.Id
        if ($found) { Write-Log "✅ 检测到 $($pkg.Name) 已安装，跳过安装。" "Green"; continue }
        Write-Log "⚠️ 使用 winget 安装 $($pkg.Name)..." "Yellow"
        Ensure-WingetInstall -PackageId $pkg.Id -DisplayName $pkg.Name
    }
}

# 刷新 PATH（尝试让新安装的应用生效）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

if ($global:WebEnvLog) {
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
    Write-Host "日志已保存到：$global:WebEnvLog" -ForegroundColor Cyan
}
