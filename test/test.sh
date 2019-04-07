#!/usr/bin/env bash

set -euo pipefail

export YB_PG_FALLBACK_SYSTEM_USER_NAME=$USER
export YB_DISABLE_CALLHOME=1

log() {
  echo >&2 "[$( date +%Y-%m-%dT%H:%M:%S] ) $*"
}

yb_data_dirs=(
  "$HOME/yugabyte-data"
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

if [[ $OSTYPE == darwin* ]]; then
  pip install --user requirements.txt
fi

trap cleanup EXIT

bin/yb-ctl --install-if-needed create
bin/yb-ctl stop
bin/yb-ctl start
bin/yb-ctl stop

log "Testing putting this version of yb-ctl inside the installation directory"
installation_dir=$( ls -td "$HOME/yugabyte-db/yugabyte-"* | head -1 )
log "YugaByte DB was automatically installed into directory: $installation_dir"
(
  set -x
  cp bin/yb-ctl "$installation_dir"
  "$installation_dir/yb-ctl" start
  "$installation_dir/yb-ctl" stop
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
