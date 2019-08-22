$SysDir = @($Env:ProgramFiles, ${Env:ProgramFiles(x86)}, $Env:windir)
function script:Get-Modules-Paths {
    param(
        [string[]]$Excludes
    )
    $AllPaths = ($Env:PSModulePath).Split(";")
    if ($null -eq $Excludes -or $Excludes.Length -eq 0) {
        return $AllPaths
    }
    $ExcludesLower = $Excludes | ForEach-Object { $_.ToLower() }
    return $AllPaths | Where-Object { 
        $full = $_.ToLower()
        $matches = $ExcludesLower | Where-Object { 
            $prefix = $_
            $full.StartsWith($prefix) 
        }
        return $matches.Length -eq 0
    }
}
$paths = Get-Modules-Paths -Excludes $SysDir
function script:Add-Module-Files {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Functions
    )
    if ($null -eq $paths -or $paths.Length -eq 0) {
        $SysDirStr = Join-String -InputObject $SysDir -Separator ";"
        Write-Host "没有找到合适的模块路径, 请检查系统环境变量%PSModulePath%是否有指定[", $SysDirStr, "]以外的目录" -ForegroundColor Red
        Write-Host "如果没有, 请自行添加一个用以存储新安装的模块文件" -ForegroundColor Red
        Write-Host "%PSModulePath%", ":", $Env:PSModulePath
        return
    }
    $path = $paths
    if ($paths.GetType().IsArray) {
        $path = $paths[0]
    }
    if ((Test-Path -Path $path) -eq $false) {
        New-Item -Path $path -ItemType directory -Force
    }
    $dir = Join-Path -Path $path -ChildPath $Name
    $fullName = Join-Path -Path $dir -ChildPath "$Name.psm1"
    $manifest = Join-Path -Path $dir -ChildPath "$Name.psd1"
    if ((Test-Path -Path $dir) -eq $false) {
        New-Item -Path $dir -ItemType directory -Force | Out-Null
    }
    Write-Host "使用", $path, "作为模块安装目录"
    Copy-Item -Path $FilePath -Destination $fullName | Out-Null
    # Out-File -InputObject $Content -FilePath $fullName
    New-ModuleManifest -Path $manifest -RootModule "$Name.psm1" -FunctionsToExport $Functions
}
function script:Remove-Module-Files {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )
    if ($paths.Length -eq 0) {
        return
    }
    $path = $paths
    if ($paths.GetType().IsArray) {
        $path = $paths[0]
    }
    $dir = Join-Path -Path $path -ChildPath $Name
    $fullName = Join-Path -Path $dir -ChildPath "$Name.psm1"
    $manifest = Join-Path -Path $dir -ChildPath "$Name.psd1"
    if (Test-Path -Path $fullName) {
        Remove-Item $fullName -Force | Out-Null
    }
    if (Test-Path -Path $manifest) {
        Remove-Item -Path $manifest | Out-Null
    }
    Remove-Item -Path $dir -Recurse -Force | Out-Null
}
function Find-Module {
    [CmdletBinding(DefaultParameterSetName = "Name")]
    [OutputType([boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )
    $results = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
    return ($results.Length -gt 0)
}
function Add-Module {
    [OutputType([boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Functions
    )
    if (Find-Module $Name) {
        Write-Host "模块", $Name, "已存在" -ForegroundColor Red
        return $false
    }
    Add-Module-Files $Name $FilePath $Functions
    if (Find-Module $Name) {
        Write-Host "模块", $Name, "添加成功" -ForegroundColor Green
        Write-Host "使用方式："
        Write-Host "Import-Module -Name", $Name
        return $true
    }
    return $false
}
function Remove-Module {
    [CmdletBinding(
        DefaultParameterSetName = "Name",
        SupportsShouldProcess = $true)]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )
    if ((Find-Module $Name) -eq $false) {
        Write-Host "模块", $Name, "不存在" -ForegroundColor Red
        return $true
    }
    Remove-Module-Files $Name
    if (Find-Module $Name) {
        Write-Host "删除失败,模块", $Name, "依然存在" -ForegroundColor Red
        return $false
    }
    return $true
}
function Repair-Module {
    [OutputType([boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath,

        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Functions
    )
    PROCESS {
        if (Find-Module $Name) {
            Remove-Module-Files $Name
        }
        if (Find-Module $Name) {
            Write-Host "删除失败,模块", $Name, "依然存在" -ForegroundColor Red
            return $false
        }
        Add-Module-Files $Name $FilePath $Functions
        if (Find-Module $Name) {
            Write-Host "模块", $Name, "添加成功" -ForegroundColor Green
            return $true
        }
        return $false
    }
}
Export-ModuleMember -Function Add-Module, Remove-Module, Repair-Module, Find-Module