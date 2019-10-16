# relops image builder

[![Task Status](https://github.taskcluster.net/v1/repository/mozilla-platform-ops/relops-image-builder/master/badge.svg)](https://github.taskcluster.net/v1/repository/mozilla-platform-ops/relops-image-builder/master/latest)

This repository hosts a few scripts and ci configurations that enable the automated creation of Amazon EC2 AMIs or Google Cloud images from Windows ISO files.

The automation works by running a powershell script ([build_ami.ps1](https://github.com/mozilla-platform-ops/relops-image-builder/blob/master/build_ami.ps1)) in this repository which executes the following steps:

- download an ISO from the [ISO repository](https://s3.console.aws.amazon.com/s3/buckets/windows-ami-builder/iso/).
- download an [unattend file](https://github.com/mozilla-platform-ops/relops-image-builder/tree/master/unattend) specifying the installation configuration for the Windows install.
- download packages and drivers required by the Windows installer.
- download and run [Convert-WindowsImage.ps1](https://github.com/mozilla-platform-ops/relops_image_builder/blob/master/Convert-WindowsImage.ps1) to create a VHD file from the ISO and inject the downloaded unattend configuration, drivers and packages.
- upload the created vhd file to the [VHD repository](https://s3.console.aws.amazon.com/s3/buckets/windows-ami-builder/vhd/).
- import the VHD file as an ec2 snapshot using the AWS EC2 api.
- create a new EC2 volume from the imported snapshot.
- create a new EC2 instance, detach its volume(s), attach the newly created volume with the imported snapshot of the Windows VHD.
- boot the new EC2 instance and wait for the Windows unattended install to complete and shut down.
- capture an AMI from the newly created instance after the Windows install has completed.
