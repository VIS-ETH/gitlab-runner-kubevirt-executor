#!/bin/bash

set -euo pipefail

_vm_name() {
  printf 'runner-%s-project-%d-pipeline-%d-job-%d\n' "${CUSTOM_ENV_CI_RUNNER_SHORT_TOKEN}" "${CUSTOM_ENV_CI_PROJECT_ID}" "${CUSTOM_ENV_CI_PIPELINE_IID}" "${CUSTOM_ENV_CI_JOB_ID}"
}

config() {
  cat <<EOS
{
  "builds_dir": "/builds/${CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID}/${CUSTOM_ENV_CI_PROJECT_PATH_SLUG}",
  "cache_dir": "/cache/${CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID}/${CUSTOM_ENV_CI_PROJECT_PATH_SLUG}",
  "builds_dir_is_shared": false,
  "hostname": "$(_vm_name)",
  "driver": {
    "name": "kubevirt driver",
    "version": "v0.0.1"
  },
  "job_env" : {},
  "shell": "bash"
}
EOS
}

prepare() {
  kubectl create -f - <<EOF
kind: VirtualMachine
metadata:
  name: $(_vm_name)

EOF
}

run() {
  kubectl exec <"${1}"
}

cleanup() {

}

case "${1:-}" in
config)
  config
  ;;
prepare)
  prepare
  ;;
run)
  run "${2}" "${3}"
  ;;
cleanup)
  cleanup
  ;;
*)
  echo "Error invalid command ${1:-}"
  exit 1
  ;;
esac
