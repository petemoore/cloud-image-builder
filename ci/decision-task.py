import os
import slugid
import taskcluster
from datetime import datetime, timedelta

queue = taskcluster.Queue({
  'rootUrl': 'https://taskcluster'
})

tasks = range(1, 3)
for i in tasks:
  taskId = slugid.nice()
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'github-worker',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
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
        'echo {}'.format(taskId)
      ],
      'features': {
        'taskclusterProxy': True
      },
      'metadata': {
        'name': 'task {} ({})'.format(i, taskId),
        'description': 'description of task {} ({})'.format(i, taskId),
        'owner': os.environ.get('GITHUB_HEAD_USER_EMAIL'),
        'source': 'https://github.com/mozilla-platform-ops/relops-image-builder/commit/{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
      }
    }
  }
  print('creating task {}/{} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(i, tasks[-1], os.environ.get('TASK_ID'), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)