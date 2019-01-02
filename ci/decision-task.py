#import asyncio
import taskcluster
#import taskcluster.aio
import uuid

queue = taskcluster.Queue(options)
#loop = asyncio.get_event_loop()
#session = taskcluster.aio.createSession(loop=loop)
#asyncQueue = taskcluster.aio.Queue(options, session=session)

for i in range(0, 2):
  taskId=uuid.uuid4().hex
  payload = {
    maxRunTime: 30,
    command: [
      'echo',
      '"i am task {}"'.format(taskId)
    ]
  }
  taskCreateResult = queue.createTask(taskId, payload)
  #await asyncQueue.createTask(taskId=taskId, payload=payload)

#await asyncQueue.listTaskGroup(taskGroupId='value') # -> result