#!/bin/bash -e
set -o pipefail

NAME=$1

SCRIPT_PATH=$(cd $(dirname $0); pwd)

cd ${SCRIPT_PATH}

if [[ -z "$NAME" ]]; then
  echo "please specify name"
  exit 1
fi

hugo new posts/${NAME}/index.md

