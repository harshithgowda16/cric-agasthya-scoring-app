#!/usr/bin/env bash
# bootstrap-01.sh - CloudLabs Custom Script Extension for
# nedbank-messaging-eventing-junior (Messaging & Eventing -- Messaging Fundamentals)
#
# Idempotent: safe to re-run. Every step logs to /var/log/nedbank-bootstrap.log.
# Usage: bootstrap-01.sh <DeploymentID>
#
# What this seeds (read Exercise-01/02/03/05 for the full brief):
#   Module 1 (IBM MQ)              -- mqsim, a queue-depth CLI + producer/consumer over Redis lists.
#                                      Seeded fault: mq_consumer.py has no error handling, so the
#                                      first malformed message crashes it and PAYMENTS.IN backs up.
#   Module 2 (Apache Kafka + KSQL) -- kafkasim, a lag/pending CLI + producer/consumer over Redis Streams.
#                                      Seeded fault: kafka_consumer.py never XACKs, so lag grows forever
#                                      while the process (and its logs) look perfectly healthy.
#   Module 3 (Elastic + Logstash)  -- elksim, a JSON-lines log index + search CLI, fed by logstash_sim.py.
#                                      Seeded fault: logstash_sim.py's parser has the timestamp/service/level
#                                      field order wrong, so ERROR-level entries are never classified as ERROR.
#   Module 5 (Python)              -- msgctl.py, an aggregated health-status CLI over all of the above.
#                                      Seeded fault: compute_overall() always returns HEALTHY.
#   Modules 4/6/7 (Ansible, OpenShift/Kubernetes, Git & CI/CD) are question-only -- no bootstrap
#   seeding needed for those; their exhibits are static reference material in the Lab Guide pages.

set -uo pipefail

DEPLOYMENT_ID=${1:-unknown}
LOG=/var/log/nedbank-bootstrap.log
BASE=/opt/nedbank-msg

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG"; }

log "=== bootstrap-01.sh starting, DeploymentID=$DEPLOYMENT_ID ==="

log "--- step 1: apt packages (redis-server, python3, jq, curl) ---"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >>"$LOG" 2>&1
apt-get install -y redis-server python3 python3-pip jq curl >>"$LOG" 2>&1
systemctl enable redis-server >>"$LOG" 2>&1
systemctl restart redis-server >>"$LOG" 2>&1

log "--- step 2: python redis client ---"
pip3 install --break-system-packages redis >>"$LOG" 2>&1

log "--- step 3: lay down StarterCode under $BASE ---"
mkdir -p "$BASE"/{mqsim,kafkasim,elksim/indices,python}
mkdir -p /var/log/nedbank-msg

log "writing /opt/nedbank-msg/mqsim/mqsim.py"
mkdir -p $(dirname /opt/nedbank-msg/mqsim/mqsim.py)
cat > /opt/nedbank-msg/mqsim/mqsim.py << 'MQSIM_PY'
#!/usr/bin/env python3
"""mqsim - lightweight IBM-MQ-style queue CLI backed by real Redis lists.

Presents MQ-style semantics (named queues, PUT, GET, queue DEPTH) on top of a
real, running Redis instance so validators and candidates can query genuine
state (not a canned/static value).
"""
import sys
import json
import redis

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379


def r():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def cmd_put(queue, message):
    r().lpush(f"mq:{queue}", message)


def cmd_depth(queue):
    print(r().llen(f"mq:{queue}"))


def cmd_browse(queue, n=10):
    items = r().lrange(f"mq:{queue}", 0, n - 1)
    for i in items:
        print(i)


def main():
    if len(sys.argv) < 2:
        print("usage: mqsim.py put|depth|browse ...", file=sys.stderr)
        sys.exit(2)
    op = sys.argv[1]
    if op == "put":
        cmd_put(sys.argv[2], sys.argv[3])
    elif op == "depth":
        cmd_depth(sys.argv[2])
    elif op == "browse":
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        cmd_browse(sys.argv[2], n)
    else:
        print(f"unknown op: {op}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
MQSIM_PY
chmod 755 /opt/nedbank-msg/mqsim/mqsim.py

log "writing /opt/nedbank-msg/mqsim/mq_producer.py"
mkdir -p $(dirname /opt/nedbank-msg/mqsim/mq_producer.py)
cat > /opt/nedbank-msg/mqsim/mq_producer.py << 'MQ_PRODUCER_PY'
#!/usr/bin/env python3
"""mq_producer - continuously PUTs payment messages onto PAYMENTS.IN.

Every 7th message is deliberately malformed (not valid JSON) to model the
kind of poison message a real IBM MQ payments queue occasionally receives
from an upstream system (truncated payload, bad encoding, etc). This is the
seeded fault input for Module 1 -- it is not itself the bug, the bug is in
how mq_consumer.py handles it.
"""
import time
import json
import random
import itertools
import redis

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379
QUEUE = "PAYMENTS.IN"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def make_message(i):
    return json.dumps({
        "order_id": f"ORD-{1000 + i}",
        "amount": round(random.uniform(10, 5000), 2),
        "currency": "ZAR",
        "event": "payment.submitted",
    })


def main():
    for i in itertools.count(1):
        if i % 7 == 0:
            # seeded poison message: truncated / invalid JSON
            payload = '{"order_id": "ORD-%d", "amount": 4' % (1000 + i)
        else:
            payload = make_message(i)
        r.lpush(f"mq:{QUEUE}", payload)
        time.sleep(3)


if __name__ == "__main__":
    main()
MQ_PRODUCER_PY
chmod 755 /opt/nedbank-msg/mqsim/mq_producer.py

log "writing /opt/nedbank-msg/mqsim/mq_consumer.py"
mkdir -p $(dirname /opt/nedbank-msg/mqsim/mq_consumer.py)
cat > /opt/nedbank-msg/mqsim/mq_consumer.py << 'MQ_CONSUMER_PY'
#!/usr/bin/env python3
"""mq_consumer - drains PAYMENTS.IN, parses each message, and forwards bad
messages to PAYMENTS.DLQ.

*** SEEDED BUG (candidate fixes this file) ***
json.loads() is called with no exception handling at all. The first poison
message from mq_producer.py raises an uncaught ValueError, which kills this
process. Because systemd does not restart this unit (Restart=no, by design,
so the crash is visible in `systemctl status` rather than being silently
retried away), PAYMENTS.IN then backs up forever -- a stalled consumer,
exactly as described in the assignment sheet. The candidate must edit this
file to catch the parse error, forward the raw bad message to PAYMENTS.DLQ,
and keep looping, then restart the service.
"""
import json
import time
import logging
import redis

logging.basicConfig(
    filename="/var/log/nedbank-msg/mq_consumer.log",
    level=logging.INFO,
    format="%(asctime)sZ %(name)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("mq_consumer")

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379
IN_QUEUE = "PAYMENTS.IN"
DLQ_QUEUE = "PAYMENTS.DLQ"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def main():
    log.info("mq_consumer starting, watching mq:%s", IN_QUEUE)
    while True:
        item = r.brpop(f"mq:{IN_QUEUE}", timeout=5)
        if item is None:
            continue
        _, raw = item
        msg = json.loads(raw)  # <-- no error handling: crashes on poison messages
        log.info("processed order_id=%s amount=%s", msg["order_id"], msg["amount"])


if __name__ == "__main__":
    main()
MQ_CONSUMER_PY
chmod 755 /opt/nedbank-msg/mqsim/mq_consumer.py

log "writing /opt/nedbank-msg/kafkasim/kafkasim.py"
mkdir -p $(dirname /opt/nedbank-msg/kafkasim/kafkasim.py)
cat > /opt/nedbank-msg/kafkasim/kafkasim.py << 'KAFKASIM_PY'
#!/usr/bin/env python3
"""kafkasim - lightweight Kafka/KSQL-style CLI backed by real Redis Streams.

Topics are Redis streams; consumer groups are real Redis consumer groups
(XGROUP/XREADGROUP/XACK), so "lag" below is a genuine Pending Entries List
count, not a canned number.
"""
import sys
import redis

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379


def r():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def cmd_lag(topic, group):
    try:
        summary = r().xpending(topic, group)
    except redis.exceptions.ResponseError:
        print(0)
        return
    # xpending summary dict has 'pending' = count of unacked (pending) entries
    print(summary["pending"] if summary and summary.get("pending") else 0)


def cmd_len(topic):
    print(r().xlen(topic))


def cmd_groups(topic):
    for g in r().xinfo_groups(topic):
        print(g["name"], "pending=", g["pending"])


def main():
    if len(sys.argv) < 2:
        print("usage: kafkasim.py lag|len|groups ...", file=sys.stderr)
        sys.exit(2)
    op = sys.argv[1]
    if op == "lag":
        cmd_lag(sys.argv[2], sys.argv[3])
    elif op == "len":
        cmd_len(sys.argv[2])
    elif op == "groups":
        cmd_groups(sys.argv[2])
    else:
        print(f"unknown op: {op}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
KAFKASIM_PY
chmod 755 /opt/nedbank-msg/kafkasim/kafkasim.py

log "writing /opt/nedbank-msg/kafkasim/kafka_producer.py"
mkdir -p $(dirname /opt/nedbank-msg/kafkasim/kafka_producer.py)
cat > /opt/nedbank-msg/kafkasim/kafka_producer.py << 'KAFKA_PRODUCER_PY'
#!/usr/bin/env python3
"""kafka_producer - XADDs payment events onto the payments.events stream and
ensures the cg-payments consumer group exists.
"""
import time
import random
import itertools
import redis

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379
STREAM = "payments.events"
GROUP = "cg-payments"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def ensure_group():
    try:
        r.xgroup_create(STREAM, GROUP, id="0", mkstream=True)
    except redis.exceptions.ResponseError as e:
        if "BUSYGROUP" not in str(e):
            raise


def main():
    ensure_group()
    for i in itertools.count(1):
        r.xadd(STREAM, {
            "order_id": f"ORD-{2000 + i}",
            "amount": str(round(random.uniform(10, 5000), 2)),
            "event": "payment.settled",
        })
        time.sleep(2)


if __name__ == "__main__":
    main()
KAFKA_PRODUCER_PY
chmod 755 /opt/nedbank-msg/kafkasim/kafka_producer.py

log "writing /opt/nedbank-msg/kafkasim/kafka_consumer.py"
mkdir -p $(dirname /opt/nedbank-msg/kafkasim/kafka_consumer.py)
cat > /opt/nedbank-msg/kafkasim/kafka_consumer.py << 'KAFKA_CONSUMER_PY'
#!/usr/bin/env python3
"""kafka_consumer - reads payment events from the cg-payments consumer group.

*** SEEDED BUG (candidate fixes this file) ***
This process reads and genuinely processes every message (it logs
"processed order_id=..." for each one, so it *looks* healthy and active in
`systemctl status` / the service logs) but it never XACKs. Every message
therefore stays in the group's Pending Entries List forever, so consumer
lag climbs without bound even though the consumer is alive and working --
a "silent" stalled consumer, distinct from Module 1's crash-and-stop
symptom, and a very common real Kafka production incident (candidate must
notice via kafkasim lag / XPENDING, not via the logs looking broken). Fix:
add the XACK call after a message has been handled.
"""
import time
import logging
import redis

logging.basicConfig(
    filename="/var/log/nedbank-msg/kafka_consumer.log",
    level=logging.INFO,
    format="%(asctime)sZ %(name)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("kafka_consumer")

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379
STREAM = "payments.events"
GROUP = "cg-payments"
CONSUMER = "kafka-consumer-1"

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def ensure_group():
    try:
        r.xgroup_create(STREAM, GROUP, id="0", mkstream=True)
    except redis.exceptions.ResponseError as e:
        if "BUSYGROUP" not in str(e):
            raise


def main():
    ensure_group()
    log.info("kafka_consumer starting, group=%s stream=%s", GROUP, STREAM)
    while True:
        resp = r.xreadgroup(GROUP, CONSUMER, {STREAM: ">"}, count=1, block=5000)
        if not resp:
            continue
        for _stream, entries in resp:
            for entry_id, fields in entries:
                log.info("processed order_id=%s amount=%s", fields.get("order_id"), fields.get("amount"))
                # BUG: no r.xack(STREAM, GROUP, entry_id) call here -- the
                # message is left pending forever.


if __name__ == "__main__":
    main()
KAFKA_CONSUMER_PY
chmod 755 /opt/nedbank-msg/kafkasim/kafka_consumer.py

log "writing /opt/nedbank-msg/elksim/logstash_sim.py"
mkdir -p $(dirname /opt/nedbank-msg/elksim/logstash_sim.py)
cat > /opt/nedbank-msg/elksim/logstash_sim.py << 'LOGSTASH_SIM_PY'
#!/usr/bin/env python3
"""logstash_sim - tails the mqsim/kafkasim service logs and ships structured
JSON documents into a real append-only index file (elksim's "Elasticsearch").

Source log line format (written by mq_consumer.py / kafka_consumer.py via
Python logging, see their logging.basicConfig format strings):

    2026-08-29T10:00:00 mq_consumer INFO processed order_id=ORD-1000 amount=42.10

i.e. TIMESTAMP SERVICE LEVEL MESSAGE...

*** SEEDED BUG (candidate fixes this file) ***
PARSE_RE below assumes the field order TIMESTAMP LEVEL SERVICE MESSAGE
(level before service) which does NOT match the real log format above, so
group(2) is captured into "level" but actually contains the *service name*
(e.g. "mq_consumer"/"kafka_consumer") -- every shipped document ends up with
level == the service name, and nothing is ever indexed as level == "ERROR"
even when the source logs contain real ERROR lines. The candidate must fix
the field order in this regex so level reflects the true INFO/ERROR/WARNING
token, then restart the shipper and let it reprocess.
"""
import glob
import json
import os
import re
import time

LOG_DIR = "/var/log/nedbank-msg"
INDEX_DIR = "/opt/nedbank-msg/elksim/indices"
INDEX_FILE = os.path.join(INDEX_DIR, "app-logs.jsonl")
STATE_FILE = "/opt/nedbank-msg/elksim/.shipper_state.json"

# BUG: field order is wrong -- should be (timestamp)(service)(level)(message)
PARSE_RE = re.compile(
    r"^(?P<timestamp>\S+)\s+(?P<level>\S+)\s+(?P<service>\S+)\s+(?P<message>.*)$"
)


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


def main():
    os.makedirs(INDEX_DIR, exist_ok=True)
    state = load_state()
    while True:
        for path in sorted(glob.glob(os.path.join(LOG_DIR, "*.log"))):
            offset = state.get(path, 0)
            with open(path) as f:
                f.seek(offset)
                lines = f.readlines()
                new_offset = f.tell()
            if lines:
                with open(INDEX_FILE, "a") as idx:
                    for line in lines:
                        line = line.rstrip("\n")
                        if not line:
                            continue
                        m = PARSE_RE.match(line)
                        if not m:
                            continue
                        doc = m.groupdict()
                        idx.write(json.dumps(doc) + "\n")
                state[path] = new_offset
        save_state(state)
        time.sleep(3)


if __name__ == "__main__":
    main()
LOGSTASH_SIM_PY
chmod 755 /opt/nedbank-msg/elksim/logstash_sim.py

log "writing /opt/nedbank-msg/elksim/elksim.py"
mkdir -p $(dirname /opt/nedbank-msg/elksim/elksim.py)
cat > /opt/nedbank-msg/elksim/elksim.py << 'ELKSIM_PY'
#!/usr/bin/env python3
"""elksim - lightweight Elasticsearch-style search CLI over the real
app-logs.jsonl index built by logstash_sim.py.
"""
import sys
import json
import argparse

INDEX_FILE = "/opt/nedbank-msg/elksim/indices/app-logs.jsonl"


def load_docs():
    docs = []
    try:
        with open(INDEX_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    docs.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except FileNotFoundError:
        pass
    return docs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", default="app-logs")
    ap.add_argument("--level")
    ap.add_argument("--service")
    ap.add_argument("--count", action="store_true")
    args = ap.parse_args()

    docs = load_docs()
    if args.level:
        docs = [d for d in docs if d.get("level") == args.level]
    if args.service:
        docs = [d for d in docs if d.get("service") == args.service]

    if args.count:
        print(len(docs))
    else:
        for d in docs:
            print(json.dumps(d))


if __name__ == "__main__":
    main()
ELKSIM_PY
chmod 755 /opt/nedbank-msg/elksim/elksim.py

log "writing /opt/nedbank-msg/python/msgctl.py"
mkdir -p $(dirname /opt/nedbank-msg/python/msgctl.py)
cat > /opt/nedbank-msg/python/msgctl.py << 'MSGCTL_PY'
#!/usr/bin/env python3
"""msgctl - aggregated health-status CLI across the messaging stack.

Reports queue depth (mqsim), consumer lag (kafkasim), and error-log volume
(elksim) as a single JSON status document, with an overall HEALTHY/DEGRADED
verdict a dashboard or on-call runbook could alert on.

*** SEEDED BUG (candidate fixes this file) ***
`overall` is computed by compute_overall() below, but the condition there is
written so it evaluates truthy in every real situation (see the comment in
that function) -- the CLI always reports "HEALTHY" no matter how deep the
queues are or how large lag/errors get. The candidate must fix
compute_overall() so it actually reflects the DEGRADED thresholds documented
in the module page (mq_in_depth > 5, or kafka_lag > 5, or elk_error_count > 0).
"""
import json
import subprocess

MQ_IN = "PAYMENTS.IN"
MQ_DLQ = "PAYMENTS.DLQ"
KAFKA_STREAM = "payments.events"
KAFKA_GROUP = "cg-payments"

MQSIM = "/opt/nedbank-msg/mqsim/mqsim.py"
KAFKASIM = "/opt/nedbank-msg/kafkasim/kafkasim.py"
ELKSIM = "/opt/nedbank-msg/elksim/elksim.py"


def run(cmd):
    out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return out.stdout.strip()


def compute_overall(mq_in_depth, mq_dlq_depth, kafka_lag, elk_error_count):
    # BUG: "or True" makes this condition always true, so the branch below
    # always reports HEALTHY regardless of the real depth/lag/error values.
    if mq_in_depth >= 0 or True:
        return "HEALTHY"
    return "DEGRADED"


def main():
    mq_in_depth = int(run(["python3", MQSIM, "depth", MQ_IN]))
    mq_dlq_depth = int(run(["python3", MQSIM, "depth", MQ_DLQ]))
    kafka_lag = int(run(["python3", KAFKASIM, "lag", KAFKA_STREAM, KAFKA_GROUP]))
    elk_error_count = int(run(["python3", ELKSIM, "--level", "ERROR", "--count"]))

    overall = compute_overall(mq_in_depth, mq_dlq_depth, kafka_lag, elk_error_count)

    status = {
        "mq_in_depth": mq_in_depth,
        "mq_dlq_depth": mq_dlq_depth,
        "kafka_lag": kafka_lag,
        "elk_error_count": elk_error_count,
        "overall": overall,
    }
    print(json.dumps(status))


if __name__ == "__main__":
    main()
MSGCTL_PY
chmod 755 /opt/nedbank-msg/python/msgctl.py

log "writing /etc/systemd/system/nb-mq-producer.service"
mkdir -p $(dirname /etc/systemd/system/nb-mq-producer.service)
cat > /etc/systemd/system/nb-mq-producer.service << 'SYSTEMD_MQ_PRODUCER'
[Unit]
Description=Nedbank mqsim - payments producer (IBM MQ simulator, Module 1)
After=redis-server.service
Requires=redis-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/nedbank-msg/mqsim/mq_producer.py
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD_MQ_PRODUCER

log "writing /etc/systemd/system/nb-mq-consumer.service"
mkdir -p $(dirname /etc/systemd/system/nb-mq-consumer.service)
cat > /etc/systemd/system/nb-mq-consumer.service << 'SYSTEMD_MQ_CONSUMER'
[Unit]
Description=Nedbank mqsim - payments consumer (IBM MQ simulator, Module 1)
After=redis-server.service nb-mq-producer.service
Requires=redis-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/nedbank-msg/mqsim/mq_consumer.py
# Restart intentionally left off: a crashed consumer must stay down and
# visibly "stalled" (systemctl status = failed) until the candidate fixes
# the code and restarts the service themselves. Auto-restart would silently
# paper over the seeded fault instead of surfacing it.
Restart=no
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD_MQ_CONSUMER

log "writing /etc/systemd/system/nb-kafka-producer.service"
mkdir -p $(dirname /etc/systemd/system/nb-kafka-producer.service)
cat > /etc/systemd/system/nb-kafka-producer.service << 'SYSTEMD_KAFKA_PRODUCER'
[Unit]
Description=Nedbank kafkasim - payments.events producer (Kafka/KSQL simulator, Module 2)
After=redis-server.service
Requires=redis-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/nedbank-msg/kafkasim/kafka_producer.py
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD_KAFKA_PRODUCER

log "writing /etc/systemd/system/nb-kafka-consumer.service"
mkdir -p $(dirname /etc/systemd/system/nb-kafka-consumer.service)
cat > /etc/systemd/system/nb-kafka-consumer.service << 'SYSTEMD_KAFKA_CONSUMER'
[Unit]
Description=Nedbank kafkasim - cg-payments consumer (Kafka/KSQL simulator, Module 2)
After=redis-server.service nb-kafka-producer.service
Requires=redis-server.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/nedbank-msg/kafkasim/kafka_consumer.py
# This unit stays "active (running)" even while the seeded bug is present --
# that is the point of the exercise: the process never crashes, so
# `systemctl status` alone will NOT reveal the fault. The candidate has to
# read lag/pending metrics (kafkasim lag ...) to find it.
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD_KAFKA_CONSUMER

log "writing /etc/systemd/system/nb-elk-shipper.service"
mkdir -p $(dirname /etc/systemd/system/nb-elk-shipper.service)
cat > /etc/systemd/system/nb-elk-shipper.service << 'SYSTEMD_ELK_SHIPPER'
[Unit]
Description=Nedbank elksim - logstash_sim log shipper (Elastic/Logstash simulator, Module 3)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/nedbank-msg/elksim/logstash_sim.py
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SYSTEMD_ELK_SHIPPER


log "--- step 4: install and start systemd units ---"
systemctl daemon-reload >>"$LOG" 2>&1
for svc in nb-mq-producer nb-kafka-producer nb-elk-shipper; do
  systemctl enable "$svc" >>"$LOG" 2>&1
  systemctl restart "$svc" >>"$LOG" 2>&1
done
# nb-mq-consumer and nb-kafka-consumer are enabled but their first start is
# the SEEDED, buggy StarterCode -- that is deliberate, see header comment.
for svc in nb-mq-consumer nb-kafka-consumer; do
  systemctl enable "$svc" >>"$LOG" 2>&1
  systemctl restart "$svc" >>"$LOG" 2>&1
done

log "--- step 5: give the pipeline a little time to generate real activity ---"
sleep 30

log "--- step 6: verification block -- confirm the seeded faults are actually present ---"
VERIFY_OK=1

# Module 1: mq_consumer should have crashed by now (poison message every 7th)
MQ_STATE=$(systemctl is-active nb-mq-consumer 2>&1 || true)
if [ "$MQ_STATE" = "failed" ]; then
  log "VERIFY OK: seeded Module 1 fault present (nb-mq-consumer has crashed, state=$MQ_STATE)"
else
  log "VERIFY FAIL: expected nb-mq-consumer to have crashed on the seeded poison message by now, state=$MQ_STATE"
  VERIFY_OK=0
fi
MQ_DEPTH=$(python3 "$BASE/mqsim/mqsim.py" depth PAYMENTS.IN 2>>"$LOG" || echo 0)
MQ_DEPTH=${MQ_DEPTH:-0}
if [ "$MQ_DEPTH" -ge 1 ] 2>/dev/null; then
  log "VERIFY OK: PAYMENTS.IN is backing up (depth=$MQ_DEPTH)"
else
  log "VERIFY FAIL: expected PAYMENTS.IN depth >= 1, found $MQ_DEPTH"
  VERIFY_OK=0
fi

# Module 2: kafka lag should already be nonzero and the consumer should still be "active"
KAFKA_STATE=$(systemctl is-active nb-kafka-consumer 2>&1 || true)
KAFKA_LAG=$(python3 "$BASE/kafkasim/kafkasim.py" lag payments.events cg-payments 2>>"$LOG" || echo 0)
KAFKA_LAG=${KAFKA_LAG:-0}
if [ "$KAFKA_STATE" = "active" ] && [ "$KAFKA_LAG" -ge 1 ] 2>/dev/null; then
  log "VERIFY OK: seeded Module 2 fault present (consumer active=$KAFKA_STATE but lag=$KAFKA_LAG)"
else
  log "VERIFY FAIL: expected nb-kafka-consumer active with lag >= 1, found active=$KAFKA_STATE lag=$KAFKA_LAG"
  VERIFY_OK=0
fi

# Module 3: elksim should report 0 ERROR docs even once mq_consumer has logged one
if grep -q "ERROR" /var/log/nedbank-msg/mq_consumer.log 2>>"$LOG"; then
  ELK_ERR=$(python3 "$BASE/elksim/elksim.py" --level ERROR --count 2>>"$LOG")
  if [ "${ELK_ERR:-0}" -eq 0 ]; then
    log "VERIFY OK: seeded Module 3 fault present (real ERROR log lines exist but elksim reports 0)"
  else
    log "VERIFY FAIL: expected elksim ERROR count 0 while the fault is unfixed, found $ELK_ERR"
    VERIFY_OK=0
  fi
else
  log "VERIFY INFO: no ERROR line logged by mq_consumer yet within the boot window -- Module 3's fault (wrong field order) is still present in the shipped code regardless."
fi

# Module 5: msgctl should report HEALTHY no matter what
MSGCTL_OUT=$(python3 "$BASE/python/msgctl.py" 2>>"$LOG")
if echo "$MSGCTL_OUT" | grep -q '"overall": "HEALTHY"'; then
  log "VERIFY OK: seeded Module 5 fault present (msgctl reports HEALTHY: $MSGCTL_OUT)"
else
  log "VERIFY FAIL: expected msgctl to report HEALTHY (bugged) at boot, got: $MSGCTL_OUT"
  VERIFY_OK=0
fi

if [ "$VERIFY_OK" -eq 1 ]; then
  log "=== bootstrap-01.sh completed successfully, all seeded faults confirmed present ==="
else
  log "=== bootstrap-01.sh completed WITH WARNINGS -- see VERIFY FAIL lines above ==="
fi
exit 0
