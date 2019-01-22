import os
import slugid
import taskcluster
from datetime import datetime, timedelta

queue = taskcluster.Queue({'rootUrl': os.getenv('TASKCLUSTER_PROXY_URL', os.getenv('TASKCLUSTER_ROOT_URL'))})
for workerType in ['gecko-t-win10-64-alpha', 'gecko-t-win10-64-gpu-a']:
  taskId = slugid.nice().decode('utf-8')
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'relops-image-builder',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
    'routes': [
      'index.project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    'scopes': [
      'generic-worker:os-group:aws-provisioner-v1/relops-image-builder/Administrators',
      'generic-worker:run-as-administrator:aws-provisioner-v1/relops-image-builder'
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
        'powershell -NoProfile -InputFormat None -File .\\relops-image-builder\\build_ami.ps1 {}'.format(workerType)
      ],
      'features': {
        'runAsAdministrator': True,
        'taskclusterProxy': True
      }
    },
    'metadata': {
      'name': 'iso-to-ami {}'.format(workerType),
      'description': 'build windows ami from iso for {}'.format(workerType),
      'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
      'source': '{}/commit/{}'.format(os.environ.get('GITHUB_HEAD_REPO_URL'), os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(taskId, os.environ.get('TASK_ID'), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)