#!/bin/bash

script_name=$(basename ${0##*/} .sh)
temp_dir=$(mktemp -d)

for nxlog_config in nxlog-win10.conf nxlog-win2012.conf nxlog-win2016.conf nxlog-win2019.conf; do
  if curl -s -o ${temp_dir}/${nxlog_config} https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/config/${nxlog_config} && [[ "$(stat -c%s ${temp_dir}/${nxlog_config})" != "15" ]]; then
    echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 2)downloaded $(stat -c%s ${temp_dir}/${nxlog_config}) bytes from https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/config/${nxlog_config}$(tput sgr0)"

    if gsutil cp ${temp_dir}/${nxlog_config} gs://windows-ami-builder/config/${nxlog_config}; then
      echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 2)${temp_dir}/${nxlog_config} uploaded to gs://windows-ami-builder/config/${nxlog_config}$(tput sgr0)"
    else
      echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 1)failed to upload ${temp_dir}/${nxlog_config} to gs://windows-ami-builder/config/${nxlog_config}$(tput sgr0)"
    fi
    if aws s3 cp ${temp_dir}/${nxlog_config} s3://windows-ami-builder/config/${nxlog_config} --profile windows-ami-builder; then
      echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 2)${temp_dir}/${nxlog_config} uploaded to s3://windows-ami-builder/config/${nxlog_config}$(tput sgr0)"
    else
      echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 1)failed to upload ${temp_dir}/${nxlog_config} to s3://windows-ami-builder/config/${nxlog_config}$(tput sgr0)"
    fi
  else
    echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")] $(tput setaf 1)failed to download https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/config/${nxlog_config}$(tput sgr0)"
  fi
done
