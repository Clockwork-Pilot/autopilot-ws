#!/bin/bash
set -euo pipefail

BASE_IMAGE="${BASE_IMAGE:-autopilot-ws-base}"
IMAGE_TAG="${IMAGE_TAG:-autopilot-ws}"

USER_DOCKERFILE="${1:-}"
[ $# -gt 0 ] && shift

echo "==> Building $BASE_IMAGE from Dockerfile"
docker build -f Dockerfile -t "$BASE_IMAGE" "$@" .

if [ -n "$USER_DOCKERFILE" ]; then
    if [ ! -f "$USER_DOCKERFILE" ]; then
        echo "Error: user Dockerfile not found: $USER_DOCKERFILE" >&2
        exit 1
    fi
    echo "==> Building $IMAGE_TAG from $USER_DOCKERFILE (FROM $BASE_IMAGE)"
    # Pass BASE_IMAGE so the user Dockerfile can resolve `FROM ${BASE_IMAGE}`
    # to the locally built base instead of pulling the published remote.
    # Requires the user Dockerfile to declare `ARG BASE_IMAGE=<default>` above FROM.
    docker build -f "$USER_DOCKERFILE" -t "$IMAGE_TAG" \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" \
        "$@" .
else
    echo "==> No user Dockerfile given — tagging $BASE_IMAGE as $IMAGE_TAG"
    docker tag "$BASE_IMAGE" "$IMAGE_TAG"
fi

echo
echo "==> Images:"
docker images --filter "reference=$BASE_IMAGE" --filter "reference=$IMAGE_TAG"
