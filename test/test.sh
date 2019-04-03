#!/usr/bin/env bash
set -euo pipefail

export YB_PG_FALLBACK_SYSTEM_USER_NAME=$USER
export YB_DISABLE_CALLHOME=1

yb_data_dirs=(
  "$HOME/yugabyte-data"
)

cleanup() {
  local exit_code=$?
  for yb_data_dir in "${yb_data_dirs[@]}"; do
    if [[ -d $yb_data_dir ]]; then
      find "$yb_data_dir" \
        -name "*.out" -or \
        -name "*.err" -or \
        \( -name "*.log" -and -not -wholename "*/tablet-*/*.log" \) | while read log_path; do

        echo "------------------------------------------------------------------------------------"
        echo "$log_path"
        echo "------------------------------------------------------------------------------------"
        echo
        cat "$log_path"
        echo

      done
    fi
  done
  exit "$exit_code"
}

trap cleanup EXIT
bin/yb-ctl --install-if-needed create
