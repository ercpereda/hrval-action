#!/usr/bin/env bash

set -o errexit

DIR=${1}
FILTER=${2-".*"}
IGNORE_VALUES=${3-false}
KUBE_VER=${4-master}
HELM_VER=${5-v2}
HRVAL="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/hrval.sh"
AWS_S3_REPO=${6-false}
AWS_S3_REPO_NAME=${7-""}
AWS_S3_PLUGIN={$8-""}
HELM_REPOS=${9-""} # "elastic=https://helm.elastic.co;emberstack=https://emberstack.github.io/helm-charts"

if [[ ${HELM_VER} == "v2" ]]; then
    helm init --client-only
fi

if [[ ! -z "${HELM_REPOS}" ]]; then
    repo_lines=($(echo ${HELM_REPOS} | tr ";" "\n"))
    for line in "${repo_lines[@]}"
    do
        tmp=($(echo ${line} | tr "=" "\n"))
        repo_name="${tmp[0]}"
        repo_url="${tmp[1]}"

        echo "Adding repo ${repo_name} ${repo_url}"
        if [[ ${HELM_VER} == "v2" ]]; then
            helm repo add ${repo_name} ${repo_url}
        else
            helmv3 repo add ${repo_name} ${repo_url}
        fi
    done
fi

if [[ ${AWS_S3_REPO} == true ]]; then
    helm plugin install ${AWS_S3_PLUGIN}
    helm repo add ${AWS_S3_REPO_NAME} s3:/${AWS_S3_REPO_NAME}/charts
    helm repo update
fi

# If the path provided is actually a file, just run hrval against this one file
if test -f "${DIR}"; then
  ${HRVAL} ${DIR} ${IGNORE_VALUES} ${KUBE_VER} ${HELM_VER}
  exit 0
fi

# If the path provided is not a directory, print error message and exit
if [ ! -d "$DIR" ]; then
  echo "\"${DIR}\" directory not found!"
  exit 1
fi

function isHelmRelease {
  KIND=$(yq r ${1} kind)
  status=$?
  if [ ! $status -eq 0 ]; then
      echo invalid
  elif [[ ${KIND} == "HelmRelease" ]]; then
      echo true
  else
    echo false
  fi
}

# Find yaml files in directory recursively
DIR_PATH=$(echo ${DIR} | sed "s/^\///;s/\/$//")
FILES_TESTED=0
echo "Using filter: ${FILTER}"
for f in `find ${DIR} -type f -name '*.yaml' -or -name '*.yml' | grep "${FILTER}"`; do
  isHR=$(isHelmRelease ${f})
  echo "isHelmRelease: ${isHR}"
  if [[ "${isHR}" == "true" ]]; then
    ${HRVAL} ${f} ${IGNORE_VALUES} ${KUBE_VER} ${HELM_VER}
    FILES_TESTED=$(( FILES_TESTED+1 ))
  elif [[ "${isHR}" == "invalid" ]]; then
    echo "The file ${f} is invalid"
    exit 1
  else
    echo "Ignoring ${f} not a HelmRelease"
  fi
done

# This will set the GitHub actions output 'numFilesTested'
echo "::set-output name=numFilesTested::${FILES_TESTED}"
