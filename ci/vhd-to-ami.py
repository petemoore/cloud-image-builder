import boto3
import json
import os
import urllib.request 
from colorama import Style
from dateutil.parser import parse
from time import sleep


# configuration settings
manifest_url = 'https://raw.githubusercontent.com/mozilla-platform-ops/relops-image-builder/master/manifest.json'
aws_region_name = 'us-west-2'
aws_availability_zone = '{}c'.format(aws_region_name)
aws_resource_tags = [
    {
        'Key': 'owner',
        'Value': 'relops-ami-builder'
    },
]

# set up the aws clients & resources
aws_ec2_client = boto3.client('ec2', region_name=aws_region_name)
aws_ec2_resource = boto3.resource('ec2', region_name=aws_region_name)
aws_s3_resource = boto3.resource('s3', region_name=aws_region_name)

# load the relops-image-builder json manifest
for manifest_item in json.loads(urllib.request.urlopen(manifest_url).read().decode()):

    # load each vhd bucket object referred to by the manifest
    aws_bucket_object = aws_s3_resource.Object(manifest_item['vhd']['bucket'], manifest_item['vhd']['key'])
    print('{}/{} ({})'.format(aws_bucket_object.bucket_name, aws_bucket_object.key, aws_bucket_object.last_modified))
    aws_image_name_filter = '{}-*'.format(os.path.splitext(os.path.basename(aws_bucket_object.key))[0])

    # load the list of amis associated with each vhd
    aws_image_list = list(sorted(aws_ec2_resource.images.filter(Owners=['self'], Filters=[{'Name': 'name', 'Values': [aws_image_name_filter]}]), key=lambda x: x.creation_date))
    for aws_image in aws_image_list:
        aws_image_creation_date = parse(aws_image.creation_date)
        print('{}- {} ({}, {}){}'.format((Style.BRIGHT if (aws_image_creation_date > aws_bucket_object.last_modified) else Style.DIM), aws_image.id, aws_image_creation_date, aws_image.name, Style.RESET_ALL))

    # check if we already have at least one ami for each vhd (ensuring that the ami was created after the vhd was last generated by the relops-image-builder ci)
    if any(parse(aws_image.creation_date) > aws_bucket_object.last_modified for aws_image in aws_image_list):
        print('  image creation skipped. ami created on {}, after vhd generation on {}, found.'.format(parse(aws_image_list[-1].creation_date), aws_bucket_object.last_modified))
    else:
        # if we don't already have an ami, we'll create it here.
        print('  image creation triggered. ami created after vhd generation on {}, not found.'.format(aws_bucket_object.last_modified))
        disk_container = {
            'Description': '{} {} ({}) - edition: {}, language: {}, partition: {}, captured: {}'.format(manifest_item['os'], manifest_item['build']['major'], manifest_item['version'], manifest_item['edition'], manifest_item['language'], manifest_item['partition'], aws_bucket_object.last_modified),
            'Format': manifest_item['format'],
            'UserBucket': {
                'S3Bucket':aws_bucket_object.bucket_name,
                'S3Key':aws_bucket_object.key
            }
        }
        # create a snapshot import task and wait for it to complete
        aws_import_snapshot_task_status = aws_ec2_client.import_snapshot(DiskContainer=disk_container)
        aws_import_snapshot_task_complete_or_failed = False
        last_aws_import_snapshot_task_detail = False
        while not aws_import_snapshot_task_complete_or_failed:
            aws_import_snapshot_task_detail = aws_ec2_client.describe_import_snapshot_tasks(ImportTaskIds=[aws_import_snapshot_task_status['ImportTaskId']])['ImportSnapshotTasks'][0]['SnapshotTaskDetail']
            if ((last_aws_import_snapshot_task_detail and ('Progress' in aws_import_snapshot_task_detail) and ((last_aws_import_snapshot_task_detail['Status'] != aws_import_snapshot_task_detail['Status']) or (last_aws_import_snapshot_task_detail['StatusMessage'] != aws_import_snapshot_task_detail['StatusMessage']) or (last_aws_import_snapshot_task_detail['Progress'] < aws_import_snapshot_task_detail['Progress']))) or (last_aws_import_snapshot_task_detail == False)):
                print('  snapshot import task in progress with id: {}, progress: {}%, status: {}; {}'.format(aws_import_snapshot_task_status['ImportTaskId'], aws_import_snapshot_task_detail['Progress'], aws_import_snapshot_task_detail['Status'], aws_import_snapshot_task_detail['StatusMessage']))
            last_aws_import_snapshot_task_detail = aws_import_snapshot_task_detail
            aws_import_snapshot_task_complete_or_failed = aws_import_snapshot_task_detail['Status'] in ['completed', 'deleted'] or aws_import_snapshot_task_detail['StatusMessage'].startswith('ServerError') or aws_import_snapshot_task_detail['StatusMessage'].startswith('ClientError')
            sleep(1)
        aws_import_snapshot_task_detail = aws_ec2_client.describe_import_snapshot_tasks(ImportTaskIds=[aws_import_snapshot_task_status['ImportTaskId']])['ImportSnapshotTasks'][0]['SnapshotTaskDetail']
        if aws_import_snapshot_task_detail['Status'] != 'completed':
            print('  snapshot import failed. status: {}; {}'.format(aws_import_snapshot_task_detail['Status'], aws_import_snapshot_task_detail['StatusMessage']))
        else:
            print('  snapshot import complete. snapshot id: {}, status: {}'.format(aws_import_snapshot_task_detail['SnapshotId'], aws_import_snapshot_task_detail['Status']))
            aws_snapshot = aws_ec2_resource.Snapshot(aws_import_snapshot_task_detail['SnapshotId'])
            while aws_snapshot.state != 'completed':
                print('  waiting for snapshot {} availability. current state: {}'.format(aws_snapshot.snapshot_id, aws_snapshot.state))
                sleep(1)
                aws_snapshot = aws_ec2_resource.Snapshot(aws_import_snapshot_task_detail['SnapshotId'])
            print('  snapshot id: {}, state: {}, progress: {}, size: {}gb'.format(aws_snapshot.snapshot_id, aws_snapshot.state, aws_snapshot.progress, aws_snapshot.volume_size))
            print('    https://{}.console.aws.amazon.com/ec2/v2/home?region={}#Snapshots:visibility=owned-by-me;snapshotId={}'.format(aws_region_name, aws_region_name, aws_snapshot.snapshot_id))

            # tag snapshot
            aws_ec2_client.create_tags(Resources=[aws_snapshot.snapshot_id], Tags=aws_resource_tags)

            # create and tag volume
            create_volume_response = aws_ec2_client.create_volume(AvailabilityZone=aws_availability_zone, Encrypted=False, Size=aws_snapshot.volume_size, SnapshotId=aws_snapshot.snapshot_id, VolumeType='gp2', TagSpecifications=[{'ResourceType': 'volume', 'Tags': aws_resource_tags}])
            print('  volume creation in progress. volume id: {}, state: {}'.format(create_volume_response['VolumeId'], create_volume_response['State']))
            aws_volume = aws_ec2_resource.Volume(create_volume_response['VolumeId'])
            while aws_volume.state != 'available':
                print('  waiting for volume {} availability. current state: {}'.format(aws_volume.id, aws_volume.state))
                sleep(1)
                aws_volume = aws_ec2_resource.Volume(create_volume_response['VolumeId'])
            print('  volume id: {}, state: {}, size: {}gb'.format(aws_volume.id, aws_volume.state, aws_volume.size))
            print('    https://{}.console.aws.amazon.com/ec2/v2/home?region={}#Volumes:volumeId={}'.format(aws_region_name, aws_region_name, aws_volume.id))

            # create and tag instance
            amazon_linux_ami_id = sorted(aws_ec2_resource.images.filter(Owners=['amazon'], Filters=[{'Name': 'description', 'Values': [manifest_item['deployment']['aws']['init_ami_filter']]}]), key=lambda x: x.creation_date)[-1].image_id
            aws_instance = aws_ec2_resource.create_instances(ImageId=amazon_linux_ami_id, InstanceType=manifest_item['deployment']['aws']['instance_type'], KeyName=manifest_item['deployment']['aws']['key_name'], MaxCount=1, MinCount=1, Placement={'AvailabilityZone': aws_availability_zone}, SecurityGroups=manifest_item['deployment']['aws']['security_groups'], TagSpecifications=[{'ResourceType': 'instance', 'Tags': aws_resource_tags}])[0]
            print('  instance id: {}, type: {}, state: {}'.format(aws_instance.id, aws_instance.instance_type, aws_instance.state['Name']))
            print('    https://{}.console.aws.amazon.com/ec2/v2/home?region={}#Instances:instanceId={}'.format(aws_region_name, aws_region_name, aws_instance.id))
            aws_instance_id = aws_instance.id
            while aws_instance.state['Name'] != 'running':
                print('  waiting for instance {} to start. current state: {}'.format(aws_instance.id, aws_instance.state['Name']))
                sleep(1)
                aws_instance = aws_ec2_resource.Instance(aws_instance_id)
            print('  instance id: {}, state: {}'.format(aws_instance.id, aws_instance.state['Name']))
            aws_ec2_client.stop_instances(InstanceIds=[aws_instance_id])
            while aws_instance.state['Name'] != 'stopped':
                print('  waiting for instance {} to stop. current state: {}'.format(aws_instance.id, aws_instance.state['Name']))
                sleep(1)
                aws_instance = aws_ec2_resource.Instance(aws_instance_id)
            print('  instance id: {}, type: {}, state: {} {} {}'.format(aws_instance.id, aws_instance.instance_type, aws_instance.state['Name'], aws_instance.state_reason['Message'], aws_instance.state_transition_reason))
