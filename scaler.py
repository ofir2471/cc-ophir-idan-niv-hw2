import random
import sys
import time

import boto3

from main import get_redis

all_workers = []


def terminate_instance(instance_id):
    boto3.client("ec2", region_name="eu-west-1").terminate_instances(
        InstanceId=[instance_id]
    )


def launch_instance(key_name, security_group_ids, ip):
    return boto3.client("ec2", region_name="eu-west-1").run_instances(
        ImageId="ami-00e7df8df28dfa791",
        MinCount=1,
        MaxCount=1,
        InstanceType="t2.micro",
        KeyName=key_name,
        SecurityGroupIds=[security_group_ids],
        UserData=f"""
        #!/bin/bash
        sleep 10
        sudo apt-get update
        sudo apt-get install python3-pip -y
        sudo apt-get install python3-flask -y
        sudo apt update
        sudo apt install python3-rq -y
        sudo apt-get install python3-flask -y
        cd /home/ubuntu
        git clone https://github.com/ofir2471/cc-ophir-idan-niv-hw2
        rq worker --url redis://{ip}:6379
        """
    )["Instances"][0]["InstanceId"]


def scaler(key_name, security_group_ids, ip):
    redis_queue, _ = get_redis('127.0.0.1')
    jobs = len(redis_queue.jobs)
    workers = len(all_workers)
    if (workers == 0 and jobs > 0) or (workers != 0 and jobs / workers > 10):
        all_workers.append(create_worker_instance(
            key_name, security_group_ids, ip))
    elif workers > 1 and jobs / workers <= 1:
        terminate_instance(all_workers.pop(0))
