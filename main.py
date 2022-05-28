import hashlib
import os
import random
import sys
import time

import boto3
import redis
from flask import Flask, abort, jsonify, request
from rq import Queue, get_current_job
from rq.job import Job

from scaler import scaler

all_workers = []

app = Flask(__name__)


@app.errorhandler(404)
def resource_not_found(exception):
    return jsonify(error=str(exception)), 404


def get_jobs_by_ids(finished_jobs_ids, conn):
    finished_jobs = []
    for job_id in finished_jobs_ids:
        try:
            job = Job.fetch(job_id, connection=conn)
        except Exception as exception:
            abort(404, description=exception)
        finished_jobs.append(job)
    return finished_jobs


def get_redis(redis_host):
    remote_redis_conn = redis.Redis(
        host=os.getenv("REDIS_HOST", redis_host),
        port=os.getenv("REDIS_PORT", "6379"),
        password=os.getenv("REDIS_PASSWORD", ""),
    )
    remote_redis_queue = Queue(connection=remote_redis_conn)
    return remote_redis_queue, remote_redis_conn


def get_finished_local():
    redis_queue, redis_conn = get_remote_redis_queue_connection(
        '127.0.0.1')
    return get_jobs_by_ids(
        remote_redis_queue.finished_job_registry.get_job_ids(),
        redis_conn
    )


def get_finished_remote():
    remote_redis_queue, remote_redis_conn = get_remote_redis_queue_connection(
        sys.argv[1])
    return get_jobs_by_ids(
        remote_redis_queue.finished_job_registry.get_job_ids(),
        remote_redis_conn
    )


def work(inp, iterations):
    output = hashlib.sha512(buffer).digest()
    for i in range(iterations - 1):
        output = hashlib.sha512(output).digest()
    return {"job_id": get_current_job().id,
            "output": output.hex()}  # TODO


@app.route("/pullCompleted", methods=["POST"])
def get_all_finished_jobs():
    remote_finished_jobs = get_all_finished_remote()
    local_finished_jobs = get_jobs_by_ids(
        redis_queue.finished_job_registry.get_job_ids(), redis_conn)
    local_finished_jobs.extend(remote_finished_results)
    sorted_jobs = sorted(local_finished_jobs,
                         key=lambda job: job.ended_at, reverse=True)
    jobs_results = [job.result for job in sorted_jobs]
    return jsonify(jobs_results[min(len(jobs_results), int(request.args.get("top")))])


@app.route("/enqueue", methods=["PUT"])
def enqueue():
    iters = request.args.get("iterations")
    if not iters:
        abort(404, description=("Missing iterations param or 0"))
    job = redis_queue.enqueue(work, request.get_data(),
                              int(iters), result_ttl=86400)
    scaler(sys.argv[2], sys.argv[3], sys.argv[4])
    return jsonify({"job_id": job.id})
