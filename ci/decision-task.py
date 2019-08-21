import os
import slugid
import taskcluster
from datetime import datetime, timedelta

queue = taskcluster.Queue({'rootUrl': os.getenv('TASKCLUSTER_PROXY_URL', os.getenv('TASKCLUSTER_ROOT_URL'))})
targets = [
  {
    'taskId': slugid.nice().decode('utf-8'),
    'workerType': 'gecko-t-win10-64-alpha',
    'provisioner': 'aws-provisioner-v1',
    'builder': 'relops-image-builder',
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'workerType': 'gecko-t-win10-64-gpu-a',
    'provisioner': 'aws-provisioner-v1',
    'builder': 'relops-image-builder',
    'buildScript': 'build_ami.ps1',
    'name': 'iso-to-ami',
    'decription': 'build ec2 ami from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'workerType': 'gecko-t-win10-64-gamma',
    'provisioner': 'gcp',
    'builder': 'relops-image-builder-gamma',
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  },
  {
    'taskId': slugid.nice().decode('utf-8'),
    'workerType': 'gecko-t-win10-64-gpu-gamma',
    'provisioner': 'gcp',
    'builder': 'relops-image-builder-gamma',
    'buildScript': 'build_vhd.ps1',
    'name': 'iso-to-vhd',
    'decription': 'build gcp vhd from iso'
  }
]
for target in targets:
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': target['provisioner'],
    'workerType': target['builder'],
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
    'routes': [
      'index.project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    'scopes': [
      'generic-worker:os-group:aws-provisioner-v1/relops-image-builder/Administrators',
      'generic-worker:run-as-administrator:aws-provisioner-v1/relops-image-builder',
      'generic-worker:os-group:gcp/relops-image-builder-gamma/Administrators',
      'generic-worker:run-as-administrator:gcp/relops-image-builder-gamma'
    ],
    'payload': {
      'osGroups': [
        'Administrators'
      ],
      'maxRunTime': 3600,
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
      'name': '{} {}'.format(target['name'], target['workerType']),
      'description': '{} for {}'.format(target['decription'], target['workerType']),
      'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
      'source': '{}/commit/{}'.format(os.environ.get('GITHUB_HEAD_REPO_URL'), os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(target['taskId'], os.environ.get('TASK_ID'), target['taskId']))
  taskStatusResponse = queue.createTask(target['taskId'], payload)
  print(taskStatusResponse)

for target in [t for t in targets if t['provisioner'] == 'gcp']:
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
      'name': '{} {} - dependency'.format(target['name'], target['workerType']),
      'description': '{} for {}'.format(target['decription'], target['workerType']),
      'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
      'source': '{}/commit/{}'.format(os.environ.get('GITHUB_HEAD_REPO_URL'), os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(taskId, os.environ.get('TASK_ID'), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)
