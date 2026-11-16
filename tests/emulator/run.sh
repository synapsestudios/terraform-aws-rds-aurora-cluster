#!/usr/bin/env bash
# Starts AWS Emulator and the proxy, runs the emulator tests, then stops both.
#
# Uses the aws-emulator command when it is on PATH (the Linux package, as in
# CI). Otherwise builds tests/emulator/Dockerfile and runs it in Docker.
#
# Extra arguments go to `terraform test`, for example:
#   tests/emulator/run.sh -filter=tests/emulator/lifecycle.tftest.hcl -verbose
#
# Settings, all optional:
#   EMULATOR_VERSION  emulator release to run in Docker (default 1.0.385)
#   EMULATOR_PORT     port the emulator listens on (default 9297)
#   PROXY_PORT        port the proxy listens on (default 9298)
#   CALL_LOG          file the proxy appends one JSON line per API call to
set -euo pipefail

EMULATOR_VERSION=${EMULATOR_VERSION:-1.0.385}
EMULATOR_PORT=${EMULATOR_PORT:-9297}
PROXY_PORT=${PROXY_PORT:-9298}

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=tests/emulator
cd "$REPO_ROOT"

# The emulator writes its credentials and certificate under $HOME/.aws/emulator.
# A throwaway HOME keeps them away from the real ~/.aws.
EMULATOR_HOME=$(mktemp -d)
EMULATOR_FILES="$EMULATOR_HOME/.aws/emulator/$EMULATOR_PORT"
mkdir -p "$EMULATOR_HOME/.aws/emulator"

CONTAINER=""
EMULATOR_PID=""
PROXY_PID=""
cleanup() {
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
  [ -n "$EMULATOR_PID" ] && kill "$EMULATOR_PID" 2>/dev/null || true
  [ -n "$CONTAINER" ] && docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$EMULATOR_HOME"
}
trap cleanup EXIT

if command -v aws-emulator >/dev/null 2>&1; then
  aws-emulator -v
  HOME="$EMULATOR_HOME" aws-emulator -p "$EMULATOR_PORT" --telemetry off --idle-timeout 3600 >"$EMULATOR_HOME/emulator.log" 2>&1 &
  EMULATOR_PID=$!
else
  docker build -q -t "aws-emulator:$EMULATOR_VERSION" --build-arg "EMULATOR_VERSION=$EMULATOR_VERSION" "$TEST_DIR" >/dev/null
  CONTAINER="aws-emulator-test-$EMULATOR_PORT"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$CONTAINER" --memory=2g --memory-swap=2g \
    -p "127.0.0.1:$EMULATOR_PORT:$EMULATOR_PORT" \
    -e HOME="$EMULATOR_HOME" -v "$EMULATOR_HOME/.aws/emulator:$EMULATOR_HOME/.aws/emulator" \
    "aws-emulator:$EMULATOR_VERSION" -p "$EMULATOR_PORT" --idle-timeout 3600 >/dev/null
  docker run --rm "aws-emulator:$EMULATOR_VERSION" -v
fi

for _ in $(seq 60); do
  curl -sf --cacert "$EMULATOR_FILES/ca.pem" "https://127.0.0.1:$EMULATOR_PORT/__admin/health" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -sf --cacert "$EMULATOR_FILES/ca.pem" "https://127.0.0.1:$EMULATOR_PORT/__admin/health" >/dev/null

python3 -I "$TEST_DIR/proxy.py" "$PROXY_PORT" "$EMULATOR_PORT" "$EMULATOR_FILES/ca.pem" ${CALL_LOG:+"$CALL_LOG"} &
PROXY_PID=$!

# Sign with the emulator's keys only. Real keys in the environment would win
# over the credentials file.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_ENDPOINT_URL
export AWS_SHARED_CREDENTIALS_FILE="$EMULATOR_FILES/emulator_credentials"
export AWS_CONFIG_FILE="$EMULATOR_FILES/config"
export AWS_EC2_METADATA_DISABLED=true

terraform init -input=false -test-directory="$TEST_DIR" >/dev/null
terraform test -test-directory="$TEST_DIR" -var "emulator_endpoint=http://127.0.0.1:$PROXY_PORT" "$@"
