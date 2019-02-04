#!/usr/bin/env bash
#
# Copyright 2019 The Google Cloud Robotics Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script can be run just like the regular dep tool. It copies the Go
# code to a shadow repo against dep can operate as usual and copies the
# resulting Gopkg.toml and Gopkg.lock files to this directory.
# It then stages the changed dependenies in the bazel WORKSPACE for manual cleanup.

set -e

CURRENT_DIR=$(pwd)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export GOPATH=${DIR}/../.gopath
# We create the shadow repo one dir up because the dep tool falsely tries to
# truncate the GOPATH we provide after the first /go/ dir it sees.
SHADOW_REPO="${DIR}/../.gopath/src/cloud-robotics.googlesource.com/cloud-robotics"
DEP="${GOPATH}/bin/dep"

if ! type ${DEP} >/dev/null; then
  go get github.com/golang/dep/...
fi

mkdir -p ${SHADOW_REPO}

for d in {cmd,pkg,tests}; do
  rm -rf "${SHADOW_REPO}/$d"
done
cp -r ${DIR}/{cmd,pkg,tests} ${SHADOW_REPO}
cp ${DIR}/Gopkg.* ${SHADOW_REPO}

function finalize {
  cp ${SHADOW_REPO}/Gopkg.{lock,toml} ${DIR}
  cd ${CURRENT_DIR}

  bazel run //:gazelle -- update-repos -from_file "${DIR}/Gopkg.lock"
  echo "Dependencies in bazel WORKSPACE updated."
  echo "Edit the WORKSPACE file to restore proper ordering."
  echo "The repository 'com_github_golang_protobuf' is likely included erroneously and needs to be removed"
}

trap finalize EXIT
cd ${SHADOW_REPO}

${DEP} "$@"
