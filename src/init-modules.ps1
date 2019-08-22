
$modulesDir = Join-Path -Path (Get-Location).Path -ChildPath "modules"
function Find-Command {
    param([string]$Name)
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}
if (-not (Find-Command Repair-Module)) {
    # Write-Host "没有找到Repair-Module命令,所以我抛异常了"
    $Name = "Module-Manager.psm1"
    $manager = Join-Path -Path $modulesDir -ChildPath $Name
    if ((Test-Path -Path $manager) -eq $false) {
        Write-Host "Module-Manager模块不存在" -ForegroundColor Red
        Write-Host "请确保", $modulesDir, "下存在文件", $Name -ForegroundColor Red
        return
    }
    # Write-Host $manager
    Import-Module -Name $manager
}
if (-not (Find-Command Repair-Module)) {
    Write-Host "Module-Manager模块不完整, 缺少Repair-Module命令, 无法完成初始化" -ForegroundColor Red
    return
}
function Install-Module {
    param(
        [string] $FilePath
    )
    $Path = Join-Path -Path $modulesDir -ChildPath $FilePath
    $module = Get-Module -Name $Path -ListAvailable
    $exports = $module.ExportedCommands.Values
    $groups = $exports | Group-Object -Property CommandType
    $Functions = $groups.Group | ForEach-Object { $_.Name }
    $Name = $module.Name
    # Write-Host $FilePath
    Repair-Module -Name $Name -FilePath $Path -Functions $Functions | Out-Null
}
if ((Test-Path $modulesDir) -eq $false) {
    Write-Host "modules目录不存在" -ForegroundColor Red
    return
}
$modules = Get-ChildItem -Path $modulesDir -Filter *.psm1
$modules | ForEach-Object { 
    Install-Module -FilePath $_.Name
}
Write-Host "模块初始化安装完成..." -ForegroundColor Green