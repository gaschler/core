#!/bin/bash
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

ROBOT_NAME=${1:-robot-sim}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${DIR}/common.sh
source ${DIR}/include-config.sh

set -euxo pipefail

gcloud --project=$GCP_PROJECT_ID compute instances create ${ROBOT_NAME} \
  --zone=$GCP_ZONE \
  --image-family ubuntu-1604-lts \
  --image-project ubuntu-os-cloud \
  --boot-disk-size=200GB \
  --machine-type=n1-standard-4 \
  --scopes=cloud-platform
gcloud --project=$GCP_PROJECT_ID compute instances add-tags ${ROBOT_NAME}  \
  --tags=kokoro-ssh

ROBOT_HOSTNAME=${ROBOT_NAME}.${GCP_ZONE}.${GCP_PROJECT_ID}

function run_on_robot_sim() {
  ssh -o "StrictHostKeyChecking=no" robco@$ROBOT_HOSTNAME "$@"
}

until gcloud --project $GCP_PROJECT_ID compute ssh robco@${ROBOT_NAME} --zone=$GCP_ZONE  --command "uptime"; do
  sleep 1
done

gcloud --project $GCP_PROJECT_ID compute config-ssh

cat ./src/bootstrap/robot/install_k8s_on_robot.sh | run_on_robot_sim bash

set +x
echo
echo "Your VM is ready. Try connecting with:"
echo " ssh -o StrictHostKeyChecking=no robco@$ROBOT_HOSTNAME"
