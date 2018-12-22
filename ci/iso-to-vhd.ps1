
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
Install-AwsPowershellTools
$manifest = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/mozilla-platform-ops/relops_image_builder/master/manifest.json?{0}' -f [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
$cwi_url = 'https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/Convert-WindowsImage.ps1'
$work_dir = (Resolve-Path -Path '.\').Path
$cwi_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($cwi_url)))
$aws_region = 'us-west-2'
$aws_availability_zone = ('{0}c' -f $aws_region)

# download the vhd conversion script
if (Test-Path -Path $cwi_path -ErrorAction 'SilentlyContinue') {
  Remove-Item -Path $cwi_path -Force
}
try {
  (New-Object Net.WebClient).DownloadFile($cwi_url, $cwi_path)
  Write-Host -object ('downloaded {0} to {1}' -f $cwi_url, $cwi_path) -ForegroundColor White
} catch {
  if ($_.Exception.InnerException) {
    Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
  }
  Write-Host -object $_.Exception.Message -ForegroundColor Red
}

foreach ($config in $manifest) {
  if (Get-S3Object -BucketName $config.vhd.bucket -Key $config.vhd.key -Region $aws_region) {
    Write-Host -object ('Skipping {0} {1} ({2} [{3}.{4}]) {5} {6} {7}. VHD detected ()' -f $config.os, $config.build.major, $config.version, $config.build.release, $config.build.build, $config.edition, $config.language, $config.architecture, $config.vhd.key) -ForegroundColor White
  } else {
    Write-Host -object ('Building {0} {1} ({2} [{3}.{4}]) {5} {6} {7}' -f $config.os, $config.build.major, $config.version, $config.build.release, $config.build.build, $config.edition, $config.language, $config.architecture) -ForegroundColor White

    $ua_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.unattend)))
    $iso_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.iso.key)))
    $vhd_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.vhd.key)))

    # download the iso file if not on the local filesystem
    if (-not (Test-Path -Path $iso_path -ErrorAction 'SilentlyContinue')) {
      if (Get-Command 'Copy-S3Object' -ErrorAction 'SilentlyContinue') {
        Copy-S3Object -BucketName $config.iso.bucket -Key $config.iso.key -LocalFile $iso_path -Region $aws_region
      }
      if  (Test-Path -Path $iso_path -ErrorAction 'SilentlyContinue') {
        Write-Host -object ('downloaded {0} from bucket {1} with key {2}' -f $iso_path, $config.iso.bucket, $config.iso.key) -ForegroundColor White
      }
    } else {
      Write-Host -object ('iso detected at: {0}' -f $iso_path) -ForegroundColor DarkGray
    }

    # delete the unattend file if it exists
    if (Test-Path -Path $ua_path -ErrorAction SilentlyContinue) {
      Remove-Item -Path $ua_path -Force
    }
    # download the unattend file
    try {
      (New-Object Net.WebClient).DownloadFile($config.unattend, $ua_path)
      Write-Host -object ('downloaded {0} to {1}' -f $config.unattend, $ua_path) -ForegroundColor White
    } catch {
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
    }

    # download driver files if not on the local filesystem
    $drivers = @()
    foreach ($driver in $config.drivers) {
      $local_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($driver.key)))
      if (Test-Path -Path $local_path -ErrorAction SilentlyContinue) {
        Remove-Item $local_path -Force -Recurse
        Write-Host -object ('deleted: {0}' -f $local_path) -ForegroundColor DarkGray
      }
      try {
        if (Get-Command 'Copy-S3Object' -ErrorAction 'SilentlyContinue') {
          Copy-S3Object -BucketName $driver.bucket -Key $driver.key -LocalFile $local_path -Region $(if ($driver.region) { $driver.region } else { $aws_region })
        }
        if (Test-Path -Path $local_path -ErrorAction SilentlyContinue) {
          Write-Host -object ('downloaded {0} from bucket {1} with key {2}' -f (Resolve-Path -Path $local_path), $driver.bucket, $driver.key) -ForegroundColor White
        } else {
          Write-Host -object ('failed to download {0} from bucket {1} with key {2}' -f $local_path, $driver.bucket, $driver.key) -ForegroundColor Red
        }
      } catch {
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
        throw
      }
      $driver_target = (Join-Path -Path $work_dir -ChildPath $driver.target)
      if (Test-Path -Path $driver_target -ErrorAction SilentlyContinue) {
        Remove-Item $driver_target -Force -Recurse
        Write-Host -object ('deleted: {0}' -f $driver_target) -ForegroundColor DarkGray
      }
      try {
        if ($driver.extract) {
          $ext = [System.IO.Path]::GetExtension($local_path)
          if ($ext -ne '.zip') {
            $local_path_as_zip = $local_path.Remove(($lastIndex = $local_path.LastIndexOf($ext)), $ext.Length).Insert($lastIndex, '.zip')
            Rename-Item -Path $local_path -NewName $local_path_as_zip
            $local_path = $local_path_as_zip
          }
          Expand-Archive -Path $local_path -DestinationPath $driver_target
          Write-Host -object ('extracted {0} to {1}' -f (Resolve-Path -Path $local_path), (Resolve-Path -Path $driver_target)) -ForegroundColor White
          if ($ext -ne '.zip') {
            $local_path_as_ext = $local_path.Remove(($lastIndex = $local_path.LastIndexOf('.zip')), '.zip'.Length).Insert($lastIndex, $ext)
            Rename-Item -Path $local_path -NewName $local_path_as_ext
          }
        } else {
          Copy-Item -Path (Resolve-Path -Path $local_path) -Destination $driver_target
          Write-Host -object ('copied {0} to {1}' -f (Resolve-Path -Path $local_path), (Resolve-Path -Path $driver_target)) -ForegroundColor White
        }
      } catch {
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
        throw
      }
      $drivers += (Resolve-Path -Path (Join-Path -Path $work_dir -ChildPath $driver.inf)).Path
    }

    # delete the vhd(x) file if it exists
    if (Test-Path -Path $vhd_path -ErrorAction SilentlyContinue) {
      Remove-Item -Path $vhd_path -Force
    }
    # create the vhd(x) file
    try {
      . (Join-Path -Path $work_dir -ChildPath 'Convert-WindowsImage.ps1')
      if ($drivers.length) {
        if ($config.architecture.Contains('arm')) {
          Convert-WindowsImage -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $config.edition -UnattendPath (Resolve-Path -Path $ua_path).Path -Driver $drivers -RemoteDesktopEnable:$true -BCDBoot ('{0}\System32\bcdboot.exe' -f $env:SystemRoot)
        } else {
          Convert-WindowsImage -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $config.edition -UnattendPath (Resolve-Path -Path $ua_path).Path -Driver $drivers -RemoteDesktopEnable:$true
        }
      } else {
        if ($config.architecture.Contains('arm')) {
          Convert-WindowsImage -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $config.edition -UnattendPath (Resolve-Path -Path $ua_path).Path -RemoteDesktopEnable:$true -BCDBoot ('{0}\System32\bcdboot.exe' -f $env:SystemRoot)
        } else {
          Convert-WindowsImage -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $config.edition -UnattendPath (Resolve-Path -Path $ua_path).Path -RemoteDesktopEnable:$true
        }
      }
      if (Test-Path -Path $vhd_path -ErrorAction SilentlyContinue) {
        Write-Host -object ('created {0} from {1}' -f $vhd_path, $iso_path) -ForegroundColor White
      } else {
        Write-Host -object ('failed to create {0} from {1}' -f $vhd_path, $iso_path) -ForegroundColor Red
      }
    } catch {
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
      throw
    }

    # mount the vhd and create a temp directory
    $mount_path = (Join-Path -Path $env:SystemDrive -ChildPath ([System.Guid]::NewGuid().Guid))
    New-Item -Path $mount_path -ItemType directory -force
    Mount-WindowsImage -ImagePath $vhd_path -Path $mount_path -Index 1

    # download package files if not on the local filesystem
    foreach ($package in $config.packages) {
      $local_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($package.key)))
      if (-not (Test-Path -Path $local_path -ErrorAction SilentlyContinue)) {
        try {
          if (Get-Command 'Copy-S3Object' -ErrorAction 'SilentlyContinue') {
            Copy-S3Object -BucketName $package.bucket -Key $package.key -LocalFile $local_path -Region $(if ($package.region) { $package.region } else { $aws_region })
          }
          if (Test-Path -Path $local_path -ErrorAction SilentlyContinue) {
            Write-Host -object ('downloaded {0} from bucket {1} with key {2}' -f (Resolve-Path -Path $local_path), $package.bucket, $package.key) -ForegroundColor White
          } else {
            Write-Host -object ('failed to download {0} from bucket {1} with key {2}' -f $local_path, $package.bucket, $package.key) -ForegroundColor Red
          }
        } catch {
          if ($_.Exception.InnerException) {
            Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
          }
          Write-Host -object $_.Exception.Message -ForegroundColor Red
          throw
        }
      } else {
        Write-Host -object ('package file detected at: {0}' -f (Resolve-Path -Path $local_path)) -ForegroundColor DarkGray
      }
      $mount_path_package_target = (Join-Path -Path $mount_path -ChildPath $package.target)
      try {
        if ($package.extract) {
          Expand-Archive -Path $local_path -DestinationPath $mount_path_package_target
          Write-Host -object ('extracted {0} to {1}' -f (Resolve-Path -Path $local_path), (Resolve-Path -Path $mount_path_package_target)) -ForegroundColor White
        } else {
          Copy-Item -Path (Resolve-Path -Path $local_path) -Destination $mount_path_package_target
          Write-Host -object ('copied {0} to {1}' -f (Resolve-Path -Path $local_path), (Resolve-Path -Path $mount_path_package_target)) -ForegroundColor White
        }
      } catch {
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
        throw
      }
    }
    # dismount the vhd, save it and remove the mount point
    try {
      Dismount-WindowsImage -Path $mount_path -Save
      Write-Host -object ('dismount of {0} from {1} complete' -f $vhd_path, $mount_path) -ForegroundColor White
      Remove-Item -Path $mount_path -Force
    } catch {
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
      throw
    }

    # delete the vhd(x) file from the bucket if it exists
    if (Get-S3Object -BucketName $config.vhd.bucket -Key $config.vhd.key -Region $aws_region) {
      try {
        Remove-S3Object -BucketName $config.vhd.bucket -Key $config.vhd.key -Region $aws_region -Force
        Write-Host -object ('removed {0} from bucket {1}' -f $config.vhd.key, $config.vhd.bucket) -ForegroundColor White
      } catch {
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
      }
    }

    # upload the vhd(x) file
    try {
      Write-S3Object -BucketName $config.vhd.bucket -File $vhd_path -Key $config.vhd.key
      Write-Host -object ('uploaded {0} to bucket {1} with key {2}' -f $vhd_path, $config.vhd.bucket, $config.vhd.key) -ForegroundColor White
    } catch {
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
    }
  }
}

Get-S3Object -BucketName 'windows-ami-builder' | Where-Object { $_.Key.StartsWith('vhd/') }