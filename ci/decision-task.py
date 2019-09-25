import os
import slugid
import taskcluster
from datetime import datetime, timedelta

queue = taskcluster.Queue({'rootUrl': os.getenv('TASKCLUSTER_PROXY_URL', os.getenv('TASKCLUSTER_ROOT_URL'))})
targets = [
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'ec2',
    'workerType': 'gecko-t-win10-64-alpha',
    'workerPool': 'aws-provisioner-v1',
    'builder': {
      'workerType': 'relops-image-builder',
      'workerPool': 'aws-provisioner-v1'
    },
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'ec2',
    'workerType': 'gecko-t-win10-64-gpu-a',
    'workerPool': 'aws-provisioner-v1',
    'builder': {
      'workerType': 'relops-image-builder',
      'workerPool': 'aws-provisioner-v1'
    },
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'ec2',
    'workerType': 'gecko-1-b-win2012-alpha',
    'workerPool': 'aws-provisioner-v1',
    'builder': {
      'workerType': 'relops-image-builder',
      'workerPool': 'aws-provisioner-v1'
    },
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'ec2',
    'workerType': 'gecko-1-b-win2016-alpha',
    'workerPool': 'aws-provisioner-v1',
    'builder': {
      'workerType': 'relops-image-builder',
      'workerPool': 'aws-provisioner-v1'
    },
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'ec2',
    'workerType': 'gecko-1-b-win2019-alpha',
    'workerPool': 'aws-provisioner-v1',
    'builder': {
      'workerType': 'relops-image-builder',
      'workerPool': 'aws-provisioner-v1'
    },
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'gcp',
    'workerType': 'gecko-t-win10-64-gamma',
    'workerPool': 'gcp',
    'builder': {
      'workerType': 'win2016-gamma',
      'workerPool': 'sandbox-1'
    },
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'gcp',
    'workerType': 'gecko-t-win10-64-gpu-gamma',
    'workerPool': 'gcp',
    'builder': {
      'workerType': 'win2016-gamma',
      'workerPool': 'sandbox-1'
    },
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'gcp',
    'workerType': 'gecko-1-b-win2012-gamma',
    'workerPool': 'gcp',
    'builder': {
      'workerType': 'win2016-gamma',
      'workerPool': 'sandbox-1'
    },
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'gcp',
    'workerType': 'gecko-1-b-win2016-gamma',
    'workerPool': 'gcp',
    'builder': {
      'workerType': 'win2016-gamma',
      'workerPool': 'sandbox-1'
    },
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'provider': 'gcp',
    'workerType': 'gecko-1-b-win2019-gamma',
    'workerPool': 'gcp',
    'builder': {
      'workerType': 'win2016-gamma',
      'workerPool': 'sandbox-1'
    },
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  }
]
for target in targets:
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': target['builder']['workerPool'],
    'workerType': target['builder']['workerType'],
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
    'routes': [
      'index.project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    'scopes': [
      'generic-worker:os-group:{}/{}/Administrators'.format(target['builder']['workerPool'], target['builder']['workerType']),
      'generic-worker:run-as-administrator:{}/{}'.format(target['builder']['workerPool'], target['builder']['workerType'])
    ],
    'payload': {
      'osGroups': [
        'Administrators'
      ],
      'maxRunTime': 3600,
      'artifacts': [
        {
          "name": "public/screenshot",
          "path": "public/screenshot",
          "type": "directory"
        }
      ] if target['provider'] == 'ec2' else [],
      'command': [
        'git clone {} relops-image-builder'.format(os.environ.get('GITHUB_HEAD_REPO_URL')),
        'git --git-dir=.\\relops-image-builder\\.git --work-tree=.\\relops-image-builder config advice.detachedHead false',
        'git --git-dir=.\\relops-image-builder\\.git --work-tree=.\\relops-image-builder checkout {}'.format(os.environ.get('GITHUB_HEAD_SHA')),
        'powershell -NoProfile -InputFormat None -File .\\relops-image-builder\\{} {}'.format(target['buildScript'], target['workerType'])
      ],
      'features': {
        'runAsAdministrator': True,
        'taskclusterProxy': True
      }
    },
    'metadata': {
      'name': '{} :: {} :: {}'.format(target['provider'], target['workerType'], target['name']),
      'description': '{} for {}'.format(target['decription'], target['workerType']),
      'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
      'source': '{}/commit/{}'.format(os.environ.get('GITHUB_HEAD_REPO_URL'), os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(target['taskId'], os.environ.get('TASK_ID'), target['taskId']))
  taskStatusResponse = queue.createTask(target['taskId'], payload)
  print(taskStatusResponse)

for target in [t for t in targets if t['provider'] == 'gcp']:
  taskId = slugid.nice().decode('utf-8')
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'github-worker',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
    'dependencies': [
      target['taskId']
    ],
    'routes': [
      'index.project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    'scopes': [],
    'payload': {
      'image': 'grenade/opencloudconfig',
      'maxRunTime': 3600,
      'command': [
        '/bin/bash',
        '--login',
        '-c',
        'echo "child task of {}"'.format(target['taskId'])
      ],
      'features': {
        'taskclusterProxy': True
      }
    },
    'metadata': {
      'name': '{} :: {} :: vhd-to-gcp-image'.format(target['provider'], target['workerType']),
      'description': 'build gcp image from vhd for {}'.format(target['workerType']),
      'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
      'source': '{}/commit/{}'.format(os.environ.get('GITHUB_HEAD_REPO_URL'), os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(taskId, os.environ.get('TASK_ID'), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)
