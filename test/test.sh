#!/usr/bin/env bash

set -euo pipefail

export YB_PG_FALLBACK_SYSTEM_USER_NAME=$USER
export YB_DISABLE_CALLHOME=1

log() {
  echo >&2 "[$( date +%Y-%m-%dT%H:%M:%S] ) $*"
}

start_cluster_run_tests() {
  root_dir=$1
  "$root_dir"/yb-ctl $flag_data_dir start
  "$root_dir"/yb-ctl $flag_data_dir add_node
  "$root_dir"/yb-ctl $flag_data_dir stop_node 1
  "$root_dir"/yb-ctl $flag_data_dir start_node 1
  "$root_dir"/yb-ctl $flag_data_dir stop
}

yb_data_dirs=(
  "/tmp/yugabyte-data"
)

flag_data_dir=(
  "--data_dir ${yb_data_dirs[0]}"
)

log_heading() {
  (
    echo
    echo "----------------------------------------------------------------------------------------"
    echo "$@"
    echo "----------------------------------------------------------------------------------------"
    echo
  ) >&2
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log "^^^ SEE THE ERROR MESSAGE ABOVE ^^^"
    log_heading "Dumping all the log files below:"
  fi
  for yb_data_dir in "${yb_data_dirs[@]}"; do
    if [[ -d $yb_data_dir ]]; then
      find "$yb_data_dir" \
        -name "*.out" -or \
        -name "*.err" -or \
        \( -name "*.log" -and -not -wholename "*/tablet-*/*.log" \) |
      while read log_path; do
        log_heading "$log_path"
        cat "$log_path" >&2
      done
    fi
  done
  log_heading "End of dumping various logs"
  if [[ $exit_code -ne 0 ]]; then
    echo "Scroll up past the various logs to where it says 'SEE THE ERROR MESSAGE'."
  fi
  exit "$exit_code"
}

log "OSTYPE: $OSTYPE"
log "USER: $USER"
log "TRAVIS: ${TRAVIS:-undefined}"

if [[ ${TRAVIS:-} != "true" || $OSTYPE != darwin* ]]; then
  # We don't run pycodestyle on macOS on Travis CI.
  pycodestyle --config=pycodestyle.conf bin/yb-ctl
fi

trap cleanup EXIT

bin/yb-ctl $flag_data_dir --install-if-needed create
bin/yb-ctl $flag_data_dir stop
start_cluster_run_tests "bin"

log "Testing putting this version of yb-ctl inside the installation directory"
installation_dir=$( ls -td "$HOME/yugabyte-db/yugabyte-"* | head -1 )
log "YugaByte DB was automatically installed into directory: $installation_dir"
(
  set -x
  cp bin/yb-ctl "$installation_dir"
  start_cluster_run_tests "$installation_dir"
)

log "Pretending we've just built the code and are running yb-ctl from the bin directory in the code"
yb_src_root=$HOME/yugabyte-db-src-root
submodule_bin_dir=$yb_src_root/submodules/yugabyte-installation/bin
mkdir -p "$submodule_bin_dir"
cp bin/yb-ctl "$submodule_bin_dir"
mkdir -p "$yb_src_root/build"
yb_build_root=$yb_src_root/build/latest
cp -R "$installation_dir" "$yb_build_root"

if [[ $OSTYPE == linux* ]]; then
  "$yb_build_root/bin/post_install.sh"
fi
(
  set -x
  "$submodule_bin_dir/yb-ctl" start
  "$submodule_bin_dir/yb-ctl" stop
)

log_heading "TESTS SUCCEEDED"
