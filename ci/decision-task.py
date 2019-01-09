import os
import slugid
import taskcluster
from datetime import datetime, timedelta

options = {
  'rootUrl': 'https://taskcluster.net',
  'credentials': {
    'clientId': os.environ.get('TASKCLUSTER_CLIENT_ID'),
    'accessToken': os.environ.get('TASKCLUSTER_ACCESS_TOKEN')
  }
} if 'TASKCLUSTER_CLIENT_ID' in os.environ and 'TASKCLUSTER_ACCESS_TOKEN' in os.environ else {
  'rootUrl': 'http://taskcluster'
}
queue = taskcluster.Queue(options)

tasks = range(1, 3)
for i in tasks:
  taskId = slugid.nice().decode('utf-8')
  payload = {
    'created': '{}Z'.format(datetime.utcnow().isoformat()[:-3]),
    'deadline': '{}Z'.format((datetime.utcnow() + timedelta(days=3)).isoformat()[:-3]),
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'github-worker',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.getenv('TASK_ID', taskId),
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
      'name': 'task {} ({})'.format(i, taskId),
      'description': 'description of task {} ({})'.format(i, taskId),
      'owner': os.getenv('GITHUB_HEAD_USER_EMAIL', 'grenade@mozilla.com'),
      'source': 'https://github.com/mozilla-platform-ops/relops-image-builder/commit/{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    }
  }
  print('creating task {}/{} (https://tools.taskcluster.net/groups/{}/tasks/{})'.format(i, tasks[-1], os.getenv('TASK_ID', taskId), taskId))
  taskStatusResponse = queue.createTask(taskId, payload)
  print(taskStatusResponse)