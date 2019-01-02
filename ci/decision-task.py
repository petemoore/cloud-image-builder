import asyncio
import taskcluster
import taskcluster.aio
import uuid

for i in range(0, 2):
  taskId=uuid.uuid4().hex
  payload = {
    maxRunTime: 30,
    command: [
      'echo',
      'i am task {}'.format(taskId)
    ]
  }
  await asyncQueue.createTask(
    taskId=taskId,
    payload=payload
  )

#await asyncQueue.listTaskGroup(taskGroupId='value') # -> result