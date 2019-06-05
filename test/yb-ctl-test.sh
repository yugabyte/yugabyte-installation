#!/usr/bin/env bash

set -euo pipefail

export YB_PG_FALLBACK_SYSTEM_USER_NAME=$USER
export YB_DISABLE_CALLHOME=1

# This will be auto-detected the first time yb-ctl auto-downloads and installs YugaByte DB.
installation_dir=""

log() {
  echo >&2 "[$( date +%Y-%m-%dT%H:%M:%S )] $*"
}

detect_installation_dir() {
  if [[ -z $installation_dir ]]; then
    installation_dir=$( ls -td "$HOME/yugabyte-db/yugabyte-"* | head -1 )
    log "YugaByte DB has been automatically installed into directory: $installation_dir"
  fi
}

verify_ysqlsh() {
  log "Creating a YSQL table and inserting a bit of data"
  (
    set -x
    "$installation_dir"/bin/ysqlsh <<-EOF
create table mytable (k int primary key, v text);
insert into mytable (k, v) values (10, 'myvalueforten');
insert into mytable (k, v) values (20, 'myvaluefortwenty');
EOF
  )
  log "Running a simple select from our YSQL table"
  (
    set -x
    echo "select * from mytable where k = 10; drop table mytable;" | \
      "$installation_dir"/bin/ysqlsh | \
      grep "myvalueforten"
  )
}

start_cluster_run_tests() {
  root_dir=$1
  (
    set -x
    "$root_dir"/yb-ctl "${yb_ctl_args[@]}" start
    verify_ysqlsh
    "$root_dir"/yb-ctl "${yb_ctl_args[@]}" add_node
    verify_ysqlsh
    "$root_dir"/yb-ctl "${yb_ctl_args[@]}" stop_node 1
    verify_ysqlsh
    "$root_dir"/yb-ctl "${yb_ctl_args[@]}" start_node 1
    verify_ysqlsh
    "$root_dir"/yb-ctl "${yb_ctl_args[@]}" stop
  )
}

readonly yb_data_dir="/tmp/yb-ctl-test-data-$( date +%Y-%m-%dT%H_%M_%S )-$RANDOM"

yb_ctl_args=(
  --data_dir "$yb_data_dir"
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
  log_heading "End of dumping various logs"
  if [[ $exit_code -ne 0 ]]; then
    echo "Scroll up past the various logs to where it says 'SEE THE ERROR MESSAGE'."
  fi
  log "Killing yb-master/yb-tserver processes"
  (
    set -x +e
    pkill -f "yb-master --fs_data_dirs $yb_data_dir/" -SIGKILL
    pkill -f "yb-tserver --fs_data_dirs $yb_data_dir/" -SIGKILL
  )
  if ! "$keep_data_dir"; then
    rm -rf "$yb_data_dir"
  else
    log "Keeping data directory around: $yb_data_dir"
  fi
  exit "$exit_code"
}

print_usage() {
  cat <<-EOT
Usage: ${0##*/} [<options>]
Options:
  -h, --help
    Print usage information
  --verbose
    Produce verbose output -- passed down to yb-ctl.
EOT
}

# -------------------------------------------------------------------------------------------------
# Parsing test arguments
# -------------------------------------------------------------------------------------------------

verbose=false
keep_data_dir=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
    ;;
    -v|--verbose)
      verbose=true
    ;;
    -k|--keep-data-dir)
      keep_data_dir=true
    ;;
    *)
      print_usage >&2
      echo >&2
      echo "Invalid option: $1" >&2
      exit 1
  esac
  shift
done

if "$verbose"; then
  yb_ctl_args+=( --verbose )
fi

# -------------------------------------------------------------------------------------------------
# Main test code
# -------------------------------------------------------------------------------------------------

script_dir=$( cd "$( dirname "$0" )" && pwd )
cd "$script_dir"/..

log "OSTYPE: $OSTYPE"
log "USER: $USER"
log "TRAVIS: ${TRAVIS:-undefined}"

if [[ ${TRAVIS:-} != "true" || $OSTYPE != darwin* ]]; then
  # We don't run pycodestyle on macOS on Travis CI.
  pycodestyle --config=pycodestyle.conf bin/yb-ctl
fi

trap cleanup EXIT

(
  set -x
  bin/yb-ctl "${yb_ctl_args[@]}" --install-if-needed create
)

detect_installation_dir
verify_ysqlsh

(
  set -x
  bin/yb-ctl "${yb_ctl_args[@]}" stop
)

start_cluster_run_tests "bin"

log "Testing putting this version of yb-ctl inside the installation directory"
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