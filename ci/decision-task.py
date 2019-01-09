import os
import slugid
import taskcluster
from datetime import datetime, timedelta

queue = taskcluster.Queue({'rootUrl': os.getenv('TASKCLUSTER_ROOT_URL', 'https://taskcluster')})
taskIds = [slugid.nice().decode('utf-8') for i in range(1, 3)]
for taskId in taskIds:
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'github-worker',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.getenv('TASK_ID', taskIds[0]),
    'routes': [
      'project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    #'scopes': [
    #  'generic-worker:os-group:aws-provisioner-v1/relops-image-builder/Administrators',
    #  'generic-worker:run-as-administrator:aws-provisioner-v1/relops-image-builder'
    #],
    'payload': {
      'maxRunTime': 30,
      'image': 'grenade/opencloudconfig',
      'command': [
        '/bin/bash',
        '--login',
        '-c',
        'echo {}'.format(taskId)
      ],
      'features': {
        'taskclusterProxy': True
      }
    },
    'metadata': {
      'name': 'task {}'.format(taskId),
      'description': 'description of task {}'.format(taskId),
      'owner': os.getenv('GITHUB_HEAD_USER_EMAIL', 'grenade@mozilla.com'),
      'source': 'https://github.com/mozilla-platform-ops/relops-image-builder/commit/{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(taskId, os.getenv('TASK_ID', taskIds[0]), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)