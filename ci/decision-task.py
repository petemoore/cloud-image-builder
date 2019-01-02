#import asyncio
import os
import slugid
import taskcluster
#import taskcluster.aio

options = {
  'rootUrl': 'https://taskcluster'
}
queue = taskcluster.Queue(options)
#loop = asyncio.get_event_loop()
#session = taskcluster.aio.createSession(loop=loop)
#asyncQueue = taskcluster.aio.Queue(options, session=session)

for i in range(0, 2):
  taskId=slugid.nice()
  payload = {
    'provisionerId': 'aws-provisioner-v1',
    'workerType': 'github-worker',
    'schedulerId': 'taskcluster-github',
    'taskGroupId': os.environ.get('TASK_ID'),
    #'dependencies': [
    #  os.environ.get('TASK_ID')
    #],
    'routes': [
      'index.project.releng.relops-image-builder.v1.revision.{}'.format(os.environ.get('GITHUB_HEAD_SHA'))
    ],
    'scopes': [
      'generic-worker:os-group:aws-provisioner-v1/relops-image-builder/Administrators',
      'generic-worker:run-as-administrator:aws-provisioner-v1/relops-image-builder'
    ],
    'payload': {
      'maxRunTime': 30,
      'image': 'grenade/opencloudconfig',
      'command': [
        'echo',
        '"i am task {}"'.format(taskId)
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
  taskCreateResult = queue.createTask(taskId, payload)
  #await asyncQueue.createTask(taskId=taskId, payload=payload)

#await asyncQueue.listTaskGroup(taskGroupId='value') # -> result