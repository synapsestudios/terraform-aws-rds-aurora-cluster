"""Plain HTTP proxy in front of AWS Emulator for the emulator tests.

Every request passes through unchanged, so its SigV4 signature stays valid,
with one exception. A DescribeGlobalClusters call that filters on db-cluster-id
gets an empty list back, which is what AWS returns for a cluster outside a
global cluster. The emulator rejects that filter, and the AWS provider sends it
on every aws_rds_cluster read: https://github.com/aws/aws-emulator/issues/349

Delete this file and the proxy step in run.sh once that issue is fixed.

Usage: proxy.py <listen port> <emulator port> <emulator ca.pem> [call log]
"""

import http.client
import json
import ssl
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_PORT = int(sys.argv[1])
EMULATOR_PORT = int(sys.argv[2])
TLS = ssl.create_default_context(cafile=sys.argv[3])
CALL_LOG = open(sys.argv[4], "a") if len(sys.argv) > 4 else None

EMPTY_GLOBAL_CLUSTERS = (
    b'<DescribeGlobalClustersResponse xmlns="http://rds.amazonaws.com/doc/2014-10-31/">'
    b"<DescribeGlobalClustersResult><GlobalClusters/></DescribeGlobalClustersResult>"
    b"<ResponseMetadata><RequestId>00000000-0000-0000-0000-000000000349</RequestId></ResponseMetadata>"
    b"</DescribeGlobalClustersResponse>"
)
DROPPED_HEADERS = {"transfer-encoding", "connection", "content-length"}


def is_global_cluster_lookup(body):
    return b"Action=DescribeGlobalClusters" in body and b"db-cluster-id" in body


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        answered_here = is_global_cluster_lookup(body)

        if answered_here:
            status, headers, data = 200, [("Content-Type", "text/xml")], EMPTY_GLOBAL_CLUSTERS
        else:
            upstream = http.client.HTTPSConnection("127.0.0.1", EMULATOR_PORT, context=TLS, timeout=120)
            upstream.request(self.command, self.path, body=body, headers=dict(self.headers.items()))
            response = upstream.getresponse()
            status, data = response.status, response.read()
            headers = [(k, v) for k, v in response.getheaders() if k.lower() not in DROPPED_HEADERS]

        if CALL_LOG:
            action = body.split(b"Action=", 1)[1].split(b"&", 1)[0].decode() if b"Action=" in body else ""
            CALL_LOG.write(json.dumps({
                "time": round(time.time(), 3),
                "action": action or self.headers.get("X-Amz-Target", self.path),
                "status": status,
                "answered_by_proxy": answered_here,
            }) + "\n")
            CALL_LOG.flush()

        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_PATCH = handle_any


ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler).serve_forever()
