param (
  [string] $target_worker_type,
  [string] $source_org = 'mozilla-platform-ops',
  [string] $source_repo = 'relops-image-builder',
  [string] $source_ref = 'master',
  [string] $ec2_key_pair = 'mozilla-taskcluster-worker-relops-image-builder',
  [string[]] $ec2_security_groups = @('ssh-only', 'rdp-only')
)

foreach ($env_var in (Get-ChildItem -Path 'Env:')) {
  Write-Host -object ('{0}: {1}' -f $env_var.Name, $env_var.Value) -ForegroundColor DarkGray
}

$worker_type_map = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/worker-type-map.json?{3}' -f $source_org, $source_repo, $source_ref, [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
$manifest = (Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/{0}/{1}/{2}/manifest.json?{3}' -f $source_org, $source_repo, $source_ref, [Guid]::NewGuid()) -UseBasicParsing | ConvertFrom-Json)
$config = @($manifest | Where-Object {
  $_.os -eq 'Windows' -and
  $_.build.major -eq $worker_type_map."$target_worker_type".build.major -and
  $_.build.release -eq $worker_type_map."$target_worker_type".build.release -and
  $_.build.build -eq $worker_type_map."$target_worker_type".build.build -and
  $_.version -eq $worker_type_map."$target_worker_type".version -and
  $_.edition -eq $worker_type_map."$target_worker_type".edition -and
  $_.language -eq $worker_type_map."$target_worker_type".language -and
  $_.architecture -eq $worker_type_map."$target_worker_type".architecture
})[0]

if (-not $config) {
  throw [System.ArgumentOutOfRangeException] ('failed to determine configuration for Windows build: {0}.{1}.{2}, version: {3}, edition: {4}, language: {5}, architecture: {6}' -f $worker_type_map."$target_worker_type".build.major, $worker_type_map."$target_worker_type".build.release, $worker_type_map."$target_worker_type".build.build, $worker_type_map."$target_worker_type".version, $worker_type_map."$target_worker_type".edition, $worker_type_map."$target_worker_type".language, $worker_type_map."$target_worker_type".architecture)
}

$image_capture_date = ((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss.fff'))
$image_description = ('{0} {1} ({2}) - edition: {3}, language: {4}, partition: {5}, captured: {6}, ref {7}' -f $config.os, $config.build.major, $config.version, $config.edition, $config.language, $config.partition, $image_capture_date, $source_ref)

$aws_region = 'us-west-2'
$aws_availability_zone = ('{0}c' -f $aws_region)

$cwi_url = ('https://raw.githubusercontent.com/{0}/{1}/{2}/Convert-WindowsImage.ps1' -f $source_org, $source_repo, $source_ref)
$work_dir = (Resolve-Path -Path '.\').Path
$cwi_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($cwi_url)))
$ua_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.unattend)))
$iso_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.iso.key)))
$vhd_path = (Join-Path -Path $work_dir -ChildPath ([System.IO.Path]::GetFileName($config.vhd.key)))

Write-Host -object ('work_dir: {0}' -f $work_dir) -ForegroundColor DarkGray
Write-Host -object ('iso_path: {0}' -f $iso_path) -ForegroundColor DarkGray

Set-ExecutionPolicy RemoteSigned

# install aws powershell module if not installed
if (-not (Get-Module -ListAvailable -Name 'AWSPowerShell' -ErrorAction 'SilentlyContinue')) {
  try {
    Install-Module -Name 'AWSPowerShell'
    Write-Host -object 'installed powershell module: AWSPowerShell' -ForegroundColor White
  } catch {
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
  }
} else {
  Write-Host -object 'detected powershell module: AWSPowerShell' -ForegroundColor DarkGray
}
# install nuget package provider if not installed
$nugetPackageProvider = (Get-PackageProvider -Name 'NuGet' -ErrorAction 'SilentlyContinue')
if ((-not ($nugetPackageProvider)) -or ($nugetPackageProvider.Version -lt 2.8.5.201)) {
  try {
    Install-PackageProvider -Name 'NuGet' -MinimumVersion 2.8.5.201 -Force
    Write-Host -object 'installed package provider: NuGet' -ForegroundColor White
  } catch {
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
  }
} else {
  Write-Host -object ('detected package provider: NuGet {0}' -f $nugetPackageProvider.Version) -ForegroundColor DarkGray
}
if (-not (Get-Command 'Copy-S3Object' -ErrorAction 'SilentlyContinue')) {
  Write-Host -object ('required powershell function: Copy-S3Object is missing. aborting...') -ForegroundColor Red
  exit
}

$vhd_key = $(if ($source_ref.Length -eq 40) { ($config.vhd.key.Replace('vhd/', ('vhd/{0}/' -f $source_ref.SubString(0, 7)))) } else { $config.vhd.key })
if (-not (Get-S3Object -BucketName $config.vhd.bucket -Key $vhd_key -Region $aws_region)) {

  # download the iso file if not on the local filesystem
  if (-not (Test-Path -Path $iso_path -ErrorAction 'SilentlyContinue')) {
    Write-Host -object ('downloading {0} from bucket {1} with key {2}' -f $iso_path, $config.iso.bucket, $config.iso.key) -ForegroundColor White
    Copy-S3Object -BucketName $config.iso.bucket -Key $config.iso.key -LocalFile $iso_path -Region $aws_region
    if  (Test-Path -Path $iso_path -ErrorAction 'SilentlyContinue') {
      Write-Host -object ('downloaded {0} from bucket {1} with key {2}' -f $iso_path, $config.iso.bucket, $config.iso.key) -ForegroundColor White
    } else {
      Write-Host -object ('failed to download {0} from bucket {1} with key {2}. aborting...' -f $iso_path, $config.iso.bucket, $config.iso.key) -ForegroundColor Red
      exit
    }
  } else {
    Write-Host -object ('iso detected at: {0}' -f $iso_path) -ForegroundColor DarkGray
  }

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

  # delete the unattend file if it exists
  if (Test-Path -Path $ua_path -ErrorAction SilentlyContinue) {
    Remove-Item -Path $ua_path -Force
  }
  # download the unattend file
  try {
    (New-Object Net.WebClient).DownloadFile($config.unattend.Replace('mozilla-platform-ops/relops-image-builder/master', ('{0}/{1}/{2}' -f $source_org, $source_repo, $source_ref)), $ua_path)
    Write-Host -object ('downloaded {0} to {1}' -f $config.unattend.Replace('mozilla-platform-ops/relops-image-builder/master', ('{0}/{1}/{2}' -f $source_org, $source_repo, $source_ref)), $ua_path) -ForegroundColor White
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
      Write-Host -object ('downloading {0} from bucket {1} with key {2}' -f $local_path, $driver.bucket, $driver.key) -ForegroundColor White
      Copy-S3Object -BucketName $driver.bucket -Key $driver.key -LocalFile $local_path -Region $(if ($driver.region) { $driver.region } else { $aws_region })
      if (Test-Path -Path $local_path -ErrorAction SilentlyContinue) {
        Write-Host -object ('downloaded {0} from bucket {1} with key {2}' -f (Resolve-Path -Path $local_path), $driver.bucket, $driver.key) -ForegroundColor White
      } else {
        Write-Host -object ('failed to download {0} from bucket {1} with key {2}' -f $local_path, $driver.bucket, $driver.key) -ForegroundColor Red
        exit
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
    $disableWindowsService = $(if ($config.service -and $config.service.disable -and $config.service.disable.Length) { $config.service.disable } else { @() })
    if ($drivers.length) {
      if ($config.architecture.Contains('arm')) {
        Convert-WindowsImage -verbose:$true -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $(if ($config.wimindex) { $config.wimindex } else { $config.edition }) -UnattendPath (Resolve-Path -Path $ua_path).Path -Driver $drivers -RemoteDesktopEnable:$true -DisableWindowsService $disableWindowsService -DisableNotificationCenter:($config.build.major -eq 10) -BCDBoot ('{0}\System32\bcdboot.exe' -f $env:SystemRoot)
      } else {
        Convert-WindowsImage -verbose:$true -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $(if ($config.wimindex) { $config.wimindex } else { $config.edition }) -UnattendPath (Resolve-Path -Path $ua_path).Path -Driver $drivers -RemoteDesktopEnable:$true -DisableWindowsService $disableWindowsService -DisableNotificationCenter:($config.build.major -eq 10)
      }
    } else {
      if ($config.architecture.Contains('arm')) {
        Convert-WindowsImage -verbose:$true -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $(if ($config.wimindex) { $config.wimindex } else { $config.edition }) -UnattendPath (Resolve-Path -Path $ua_path).Path -RemoteDesktopEnable:$true -DisableWindowsService $disableWindowsService -DisableNotificationCenter:($config.build.major -eq 10) -BCDBoot ('{0}\System32\bcdboot.exe' -f $env:SystemRoot)
      } else {
        Convert-WindowsImage -verbose:$true -SourcePath $iso_path -VhdPath $vhd_path -VhdFormat $config.format -VhdPartitionStyle $config.partition -Edition $(if ($config.wimindex) { $config.wimindex } else { $config.edition }) -UnattendPath (Resolve-Path -Path $ua_path).Path -RemoteDesktopEnable:$true -DisableWindowsService $disableWindowsService -DisableNotificationCenter:($config.build.major -eq 10)
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
          Write-Host -object ('downloading {0} from bucket {1} with key {2}' -f $local_path, $package.bucket, $package.key) -ForegroundColor White
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

  # upload the vhd(x) file
  try {
    Write-S3Object -BucketName $config.vhd.bucket -File $vhd_path -Key $vhd_key
    Write-Host -object ('uploaded {0} to bucket {1} with key {2}' -f $vhd_path, $config.vhd.bucket, $vhd_key) -ForegroundColor White
  } catch {
    Write-Host -object ('failed to upload {0} to bucket {1}' -f $config.vhd.bucket, $vhd_key) -ForegroundColor Red
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
  }
} else {
  Write-Host -object ('vhd exists in bucket {0} with key {1}. skipping vhd creation.' -f $config.vhd.bucket, $vhd_key) -ForegroundColor White
}

# import the vhd as an ec2 snapshot
try {
  $import_task_status = @(Import-EC2Snapshot -DiskContainer_Format $config.format -DiskContainer_S3Bucket $config.vhd.bucket -DiskContainer_S3Key $vhd_key -Description $image_description)[0]
  Write-Host -object ('snapshot import task in progress with id: {0}, progress: {1}%, status: {2}; {3}' -f $import_task_status.ImportTaskId, $import_task_status.SnapshotTaskDetail.Progress,  $import_task_status.SnapshotTaskDetail.Status, $import_task_status.SnapshotTaskDetail.StatusMessage) -ForegroundColor White
} catch {
  Write-Host -object ('failed to create snapshot import task for image {0} in bucket {1}' -f $vhd_key, $config.vhd.bucket) -ForegroundColor Red
  if ($_.Exception.InnerException) {
    Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
  }
  Write-Host -object $_.Exception.Message -ForegroundColor Red
  throw
}

# wait for snapshot import completion
while (($import_task_status.SnapshotTaskDetail.Status -ne 'completed') -and ($import_task_status.SnapshotTaskDetail.Status -ne 'deleted') -and (-not $import_task_status.SnapshotTaskDetail.StatusMessage.StartsWith('ServerError')) -and (-not $import_task_status.SnapshotTaskDetail.StatusMessage.StartsWith('ClientError'))) {
  try {
    $last_status = $import_task_status
    $import_task_status = @(Get-EC2ImportSnapshotTask -ImportTaskId $last_status.ImportTaskId)[0]
    if ($import_task_status.SnapshotTaskDetail.Progress) {
      Write-Progress -Activity 'EC2 Import Snapshot' -Status ('{0}% {1} {2}' -f $import_task_status.SnapshotTaskDetail.Progress, $import_task_status.SnapshotTaskDetail.Status, $import_task_status.SnapshotTaskDetail.StatusMessage) -PercentComplete $import_task_status.SnapshotTaskDetail.Progress
    }
    if (($import_task_status.SnapshotTaskDetail.Status -ne $last_status.SnapshotTaskDetail.Status) -or ($import_task_status.SnapshotTaskDetail.StatusMessage -ne $last_status.SnapshotTaskDetail.StatusMessage)) {
      Write-Host -object ('snapshot import task in progress with id: {0}, progress: {1}%, status: {2}; {3}' -f $import_task_status.ImportTaskId, $import_task_status.SnapshotTaskDetail.Progress,  $import_task_status.SnapshotTaskDetail.Status, $import_task_status.SnapshotTaskDetail.StatusMessage) -ForegroundColor White
    }
  } catch [System.InvalidOperationException] {
    Write-Host -object ('failed to determine snapshot import task status for import task {0}. {1}' -f $last_status.ImportTaskId, $_.Exception.Message) -ForegroundColor DarkYellow
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
  }
  Start-Sleep -Milliseconds 500
}
Write-Progress -Activity 'EC2 Import Snapshot' -Completed
if ($import_task_status.SnapshotTaskDetail.Status -ne 'completed') {
  Write-Host -object ('snapshot import failed. status: {0}; {1}' -f $import_task_status.SnapshotTaskDetail.Status, $import_task_status.SnapshotTaskDetail.StatusMessage) -ForegroundColor Red
  Write-Host -object ($import_task_status.SnapshotTaskDetail | Format-List | Out-String) -ForegroundColor Red
} else {
  Write-Host -object ('snapshot import complete. snapshot id: {0}, status: {1}; {2}' -f $import_task_status.SnapshotTaskDetail.SnapshotId, $import_task_status.SnapshotTaskDetail.Status, $import_task_status.SnapshotTaskDetail.StatusMessage) -ForegroundColor White
  Write-Host -object ($import_task_status.SnapshotTaskDetail | Format-List | Out-String) -ForegroundColor DarkGray

  $snapshots = @(Get-EC2Snapshot -Filter (New-Object -TypeName Amazon.EC2.Model.Filter -ArgumentList @('description', @(('Created by AWS-VMImport service for {0}' -f $import_task_status.ImportTaskId)))))
  Write-Host -object ('{0} snapshot{1} extracted from {2}' -f  $snapshots.length, $(if ($snapshots.length -gt 1) { 's' } else { '' }), $config.format) -ForegroundColor White
  Write-Host -object ($snapshots | Format-Table | Out-String) -ForegroundColor DarkGray

  # create an ec2 volume for each snapshot
  $volumes = @()
  foreach ($snapshot in $snapshots) {
    $snapshot = (Get-EC2Snapshot -SnapshotId $snapshot.SnapshotId)
    while ($snapshot.State -ne 'completed') {
      Write-Host -object 'waiting for snapshot availability' -ForegroundColor DarkGray
      Start-Sleep -Seconds 1
      $snapshot = (Get-EC2Snapshot -SnapshotId $snapshot.SnapshotId)
    }
    Write-Host -object ('snapshot id: {0}, state: {1}, progress: {2}, size: {3}gb' -f $snapshot.SnapshotId, $snapshot.State, $snapshot.Progress, $snapshot.VolumeSize) -ForegroundColor White
    $volume = (New-EC2Volume -SnapshotId $snapshot.SnapshotId -Size $snapshot.VolumeSize -AvailabilityZone $aws_availability_zone -VolumeType 'gp2' -Encrypted $false)
    Write-Host -object ('volume creation in progress. volume id: {0}, state: {1}' -f  $volume.VolumeId, $volume.State) -ForegroundColor White

    # wait for volume creation to complete
    while ($volume.State -ne 'available') {
      $last_volume_state = $volume.State
      $volume = (Get-EC2Volume -VolumeId $volume.VolumeId)
      if ($last_volume_state -ne $volume.State) {
        Write-Host -object ('volume creation in progress. volume id: {0}, state: {1}' -f $volume.VolumeId, $volume.State) -ForegroundColor White
      }
      Start-Sleep -Milliseconds 500
    }
    $volumes += $volume
    Write-Host -object ($volume | Format-List | Out-String) -ForegroundColor DarkGray
  }
  $volume_zero = $volumes[0].VolumeId

  # create a new ec2 linux instance instantiated with a pre-existing ami
  $amazon_linux_ami_id = (Get-EC2Image -Owner 'amazon' -Filter @((New-Object -TypeName Amazon.EC2.Model.Filter -ArgumentList @('description', @(($worker_type_map."$target_worker_type".ami_description))))))[0].ImageId
  $instance = (New-EC2Instance -ImageId $amazon_linux_ami_id -AvailabilityZone $aws_availability_zone -MinCount 1 -MaxCount 1 -InstanceType $worker_type_map."$target_worker_type".instance_type -KeyName $ec2_key_pair -SecurityGroup $ec2_security_groups).Instances[0]
  $instance_id = $instance.InstanceId
  Write-Host -object ('instance {0} created with ami {1}' -f  $instance_id, $amazon_linux_ami_id) -ForegroundColor White
  while ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -ne 'running') {
    Write-Host -object 'waiting for instance to start' -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
  }
  $device_zero = (Get-EC2Instance -InstanceId $instance_id).Instances[0].BlockDeviceMappings[0].DeviceName
  Stop-EC2Instance -InstanceId $instance_id -ForceStop
  while ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -ne 'stopped') {
    Write-Host -object 'waiting for instance to stop' -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
  }

  # detach and delete volumes and associated snapshots
  foreach ($block_device_mapping in (Get-EC2Instance -InstanceId $instance_id).Instances[0].BlockDeviceMappings) {
    try {
      $detach_volume = (Dismount-EC2Volume -InstanceId $instance_id -Device $block_device_mapping.DeviceName -VolumeId $block_device_mapping.Ebs.VolumeId -ForceDismount:$true)
      Write-Host -object $detach_volume -ForegroundColor DarkGray
      Write-Host -object ('detached volume {0} from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor White
    } catch {
      Write-Host -object ('failed to detach volume {0} from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor Red
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
      exit
    }
    while ((Get-EC2Volume -VolumeId $block_device_mapping.Ebs.VolumeId).State -ne 'available') {
      Write-Host -object ('waiting for volume {0} to detach from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor DarkGray
      Start-Sleep -Milliseconds 500
    }
    Remove-EC2Volume -VolumeId $block_device_mapping.Ebs.VolumeId -PassThru -Force
  }

  # attach volume from vhd import (todo: handle attachment of multiple volumes)
  try {
    $attach_volume = (Add-EC2Volume -InstanceId $instance_id -VolumeId $volume_zero -Device $device_zero -Force)
    Write-Host -object $attach_volume -ForegroundColor DarkGray
    Write-Host -object ('attached volume {0} to {1}{2}' -f $volume_zero, $instance_id, $device_zero) -ForegroundColor White
  } catch {
    Write-Host -object ('failed to attach volume {0} to {1}{2}' -f  $volume_zero, $instance_id, $device_zero) -ForegroundColor Red
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
    throw
  }

  # set DeleteOnTermination to true for all attached volumes
  try {
    $block_device_mapping_specifications = @()
    foreach ($block_device_mapping in (Get-EC2Instance -InstanceId $instance_id).Instances[0].BlockDeviceMappings) {
      $block_device_mapping_specifications += (New-Object Amazon.EC2.Model.InstanceBlockDeviceMappingSpecification -Property @{ DeviceName = $block_device_mapping.DeviceName; Ebs = New-Object Amazon.EC2.Model.EbsInstanceBlockDeviceSpecification -Property @{ DeleteOnTermination = $true; VolumeId = $block_device_mapping.Ebs.VolumeId } })
    }
    Edit-EC2InstanceAttribute -InstanceId $instance_id -BlockDeviceMapping $block_device_mapping_specifications
    Write-Host -object 'DeleteOnTermination set to true for attached volumes' -ForegroundColor White
  } catch {
    Write-Host -object 'failed to set DeleteOnTermination for attached volumes' -ForegroundColor Red
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
  }

  try {
    Edit-EC2InstanceAttribute -InstanceId $instance_id -EnaSupport $true
    Write-Host -object ('enabled ena support attribute on instance {0}' -f $instance_id) -ForegroundColor DarkGray
  } catch {
    if ($_.Exception.InnerException) {
      Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
    }
    Write-Host -object $_.Exception.Message -ForegroundColor Red
  }

  Start-EC2Instance -InstanceId $instance_id
  $screenshot_folder_path = (Join-Path -Path $work_dir -ChildPath 'public\screenshot')
  New-Item -ItemType Directory -Force -Path $screenshot_folder_path
  $last_screenshot_time = ((Get-Date).AddSeconds(-60).ToUniversalTime())
  $last_screenshot_size = 0
  $last_instance_state = ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name)
  $stopwatch =  [System.Diagnostics.Stopwatch]::StartNew()
  while (((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -ne 'stopped') -and ($stopwatch.Elapsed.TotalMinutes -lt 180)) {
    if ($last_screenshot_size > 60kb) {
      $screenshot_frequency = 3
    } else {
      $screenshot_frequency = 30
    }
    if ($last_screenshot_time -le (Get-Date).ToUniversalTime().AddSeconds(0 - $screenshot_frequency)) {
      try {
        $new_screenshot_time = ((Get-Date).ToUniversalTime())
        $screenshot_path = ('{0}\{1}-{2}.jpg' -f $screenshot_folder_path, $instance_id, $new_screenshot_time.ToString("yyyyMMddHHmmss"))
        [io.file]::WriteAllBytes($screenshot_path, [convert]::FromBase64String((Get-EC2ConsoleScreenshot -InstanceId $instance_id -ErrorAction Stop).ImageData))
        $last_screenshot_time = $new_screenshot_time
        $last_screenshot_size = (Get-Item -Path $screenshot_path).length
        Write-Host -object ('{0:n1}kb screenshot saved to {1}' -f ($last_screenshot_size/1kb), (Resolve-Path -Path $screenshot_path).Path) -ForegroundColor DarkGray
      } catch {
        $last_screenshot_time = ((Get-Date).ToUniversalTime())
        $last_screenshot_size = 0
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
      }
    }
    $new_instance_state = ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name)
    if ($new_instance_state -ne $last_instance_state) {
      Write-Host -object ('instance {0} state change detected. previous state: {1}, current state: {2}' -f $instance_id, $last_instance_state, $new_instance_state) -ForegroundColor White
      $last_instance_state = $new_instance_state
    }
    Start-Sleep -Seconds 1
  }
  if ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -eq 'running') {
    Write-Host -object ('instance failed to stop in {0:n1} minutes. forcing stop...' -f $stopwatch.Elapsed.TotalMinutes) -ForegroundColor Cyan
    Stop-EC2Instance -InstanceId $instance_id -ForceStop
    while ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -ne 'stopped') {
      Write-Host -object 'waiting for instance to stop' -ForegroundColor DarkCyan
      Start-Sleep -Seconds 5
    }
    $local_instance_id = ((New-Object Net.WebClient).DownloadString('http://169.254.169.254/latest/meta-data/instance-id'))
    $local_devices = @([char[]]([char]'f'..[char]'z')|%{('xvd{0}' -f $_)})
    # detach previous debug volumes
    foreach ($local_block_device_mapping in (Get-EC2Instance -InstanceId $local_instance_id).Instances[0].BlockDeviceMappings) {
      if ($local_devices.Contains($local_block_device_mapping.DeviceName)) {
        try {
          $detach_volume = (Dismount-EC2Volume -InstanceId $local_instance_id -Device $local_block_device_mapping.DeviceName -VolumeId $local_block_device_mapping.Ebs.VolumeId -ForceDismount:$true)
          Write-Host -object $detach_volume -ForegroundColor DarkCyan
          Write-Host -object ('detached volume {0} from {1}{2}' -f  $local_block_device_mapping.Ebs.VolumeId, $local_instance_id, $local_block_device_mapping.DeviceName) -ForegroundColor Cyan
        } catch {
          Write-Host -object ('failed to detach volume {0} from {1}{2}' -f  $local_block_device_mapping.Ebs.VolumeId, $local_instance_id, $local_block_device_mapping.DeviceName) -ForegroundColor Red
          if ($_.Exception.InnerException) {
            Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
          }
          Write-Host -object $_.Exception.Message -ForegroundColor Red
          exit
        }
        while ((Get-EC2Volume -VolumeId $local_block_device_mapping.Ebs.VolumeId).State -ne 'available') {
          Write-Host -object ('waiting for volume {0} to detach from {1}{2}' -f  $local_block_device_mapping.Ebs.VolumeId, $local_instance_id, $local_block_device_mapping.DeviceName) -ForegroundColor DarkCyan
          Start-Sleep -Milliseconds 500
        }
      }
    }
    $i = 0
    foreach ($block_device_mapping in (Get-EC2Instance -InstanceId $instance_id).Instances[0].BlockDeviceMappings) {
      try {
        $detach_volume = (Dismount-EC2Volume -InstanceId $instance_id -Device $block_device_mapping.DeviceName -VolumeId $block_device_mapping.Ebs.VolumeId -ForceDismount:$true)
        Write-Host -object $detach_volume -ForegroundColor DarkCyan
        Write-Host -object ('detached volume {0} from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor Cyan
      } catch {
        Write-Host -object ('failed to detach volume {0} from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor Red
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
        exit
      }
      while ((Get-EC2Volume -VolumeId $block_device_mapping.Ebs.VolumeId).State -ne 'available') {
        Write-Host -object ('waiting for volume {0} to detach from {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $instance_id, $block_device_mapping.DeviceName) -ForegroundColor DarkCyan
        Start-Sleep -Milliseconds 500
      }
      # attach volume to current instance for access to logs
      try {
        $attach_volume = (Add-EC2Volume -InstanceId $local_instance_id -VolumeId $block_device_mapping.Ebs.VolumeId -Device $local_devices[$i] -Force)
        Write-Host -object $attach_volume -ForegroundColor DarkCyan
        Write-Host -object ('attached volume {0} to {1}{2}' -f $block_device_mapping.Ebs.VolumeId, $local_instance_id, $local_devices[$i]) -ForegroundColor Cyan
      } catch {
        Write-Host -object ('failed to attach volume {0} to {1}{2}' -f  $block_device_mapping.Ebs.VolumeId, $local_instance_id, $local_devices[$i]) -ForegroundColor Red
        if ($_.Exception.InnerException) {
          Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
        }
        Write-Host -object $_.Exception.Message -ForegroundColor Red
        throw
      }
      $i++
    }
  } elseif ((Get-EC2Instance -InstanceId $instance_id).Instances[0].State.Name -eq 'stopped') {
    try {
      $ami_id = (New-EC2Image -InstanceId $instance_id -Name ('{0}-{1}-{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($config.vhd.key), $(if ($source_ref.Length -eq 40) { $source_ref.SubString(0, 7) } else { $source_ref }), $image_capture_date) -Description $image_description)
      Write-Host -object ('ami {0} created from instance {1}' -f $ami_id, $instance_id) -ForegroundColor Green
    } catch {
      Write-Host -object ('failed to create ami from instance {0}' -f  $instance_id) -ForegroundColor Red
      if ($_.Exception.InnerException) {
        Write-Host -object $_.Exception.InnerException.Message -ForegroundColor DarkYellow
      }
      Write-Host -object $_.Exception.Message -ForegroundColor Red
      throw
    }
  }
  # todo:
  # - delete instances, snapshots and volumes created during vhd import
}