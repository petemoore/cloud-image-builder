
function Write-Log {
  param (
    [string] $message,
    [string] $severity
  )
  Write-Host -object $message -ForegroundColor @{ 'INFO' = 'White'; 'ERROR' = 'Red'; 'WARN' = 'DarkYellow'; 'DEBUG' = 'DarkGray' }[$severity]
}
function Install-AwsPowershellTools {
  param (
    [hashtable] $packageProviders = @{ 'NuGet' = 2.8.5.208 },
    [string[]] $modules = @('AWSPowerShell')
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    foreach ($packageProviderName in $packageProviders.Keys) {
      $version = $packageProviders.Item($packageProviderName)
      $packageProvider = (Get-PackageProvider -Name $packageProviderName -ForceBootstrap:$true)
      if ((-not ($packageProvider)) -or ($packageProvider.Version -lt $version)) {
        try {
          Install-PackageProvider -Name $packageProviderName -MinimumVersion $version -Force
          Write-Log -message ('{0} :: powershell package provider: {1}, version: {2}, installed.' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $version) -severity 'INFO'
        } catch {
          Write-Log -message ('{0} :: failed to install powershell package provider: {1}, version: {2}. {3}' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $version, $_.Exception.Message) -severity 'ERROR'
        }
      } else {
        Write-Log -message ('{0} :: powershell package provider: {1}, version: {2}, detected.' -f $($MyInvocation.MyCommand.Name), $packageProviderName, $packageProvider.Version) -severity 'DEBUG'
      }
    }
    foreach ($module in $modules) {
      if (Get-Module -ListAvailable -Name $module) {
        Write-Log -message ('{0} :: powershell module: {1}, detected.' -f $($MyInvocation.MyCommand.Name), $module) -severity 'DEBUG'
      } else {
        try {
          Install-Module -Name $module -Force
          Write-Log -message ('{0} :: powershell module: {1}, installed.' -f $($MyInvocation.MyCommand.Name), $module) -severity 'INFO'
        } catch {
          Write-Log -message ('{0} :: failed to install powershell module: {1}. {2}' -f $($MyInvocation.MyCommand.Name), $module, $_.Exception.Message) -severity 'ERROR'
        }
      }
    }
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}


Set-ExecutionPolicy RemoteSigned
$manifest = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/mozilla-platform-ops/relops_image_builder/master/manifest.json?{0}' -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
$cwi_url = 'https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/Convert-WindowsImage.ps1'
$work_dir = (Resolve-Path -Path '.\').Path
$cwi_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($cwi_url)))
$ua_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.unattend)))
$iso_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.iso.key)))
$vhd_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.vhd.key)))

Install-AwsPowershellTools

Get-S3Object -BucketName 'windows-ami-builder'