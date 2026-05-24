#!/usr/bin/env bash

set -euo pipefail

# Strict checks for required environment variables
for var in FTP_USERNAME FTP_SERVER FTP_PASSWORD FTP_PORT DIR_TO_DELETE; do
  if [ -z "${!var-}" ]; then
    echo "Error: $var environment variable not set."
    exit 2
  fi
done

echo "Using DIR_TO_DELETE: $DIR_TO_DELETE"

# Set SSHPASS environment variable for sshpass (more secure than -p flag)
export SSHPASS="$FTP_PASSWORD"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Guard: test cd to remote dir, exit if it fails
if [ -n "${DIR_TO_DELETE-}" ] && [ "$DIR_TO_DELETE" != "." ]; then
  echo "Checking remote directory existence: $DIR_TO_DELETE"
  sftp_guard_output="$tmpdir/sftp_guard_check.txt"
  printf '%s\n' "cd $DIR_TO_DELETE" 'bye' | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$sftp_guard_output" 2>&1
  sftp_guard_exit_code=$?
  if grep -q "No such file or directory" "$sftp_guard_output"; then
    echo "SFTP exit code for guard: $sftp_guard_exit_code"
    echo "Error: Remote directory does not exist $DIR_TO_DELETE"
    cat "$sftp_guard_output"
    exit 0
  fi
fi

batch="$tmpdir/delete_batch.txt"

build_delete_commands() {
  local path="$1"
  local safe_name
  safe_name=$(printf '%s' "$path" | tr '/' '_')
  local ls_out="$tmpdir/ls_${safe_name}.txt"

  printf '%s\n' "cd $path" "ls -l" "bye" \
    | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" \
    > "$ls_out" 2>&1

  echo "SFTP ls output for $path:"
  cat "$ls_out"

  local files dirs
  files=$(awk '/^-/{print $NF}' "$ls_out")
  dirs=$(awk '/^d/ && $NF != "." && $NF != ".." {print $NF}' "$ls_out")

  for f in $files; do
    echo "rm $path/$f" >> "$batch"
  done

  for d in $dirs; do
    build_delete_commands "$path/$d"
  done

  echo "rmdir $path" >> "$batch"
}

build_delete_commands "$DIR_TO_DELETE"

if [ -s "$batch" ]; then
  delete_output="$tmpdir/delete_output.txt"
  (cat "$batch"; echo "bye") | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$delete_output" 2>&1
  echo "SFTP delete output for $DIR_TO_DELETE:"
  cat "$delete_output"
  if grep -qi "Failure" "$delete_output"; then
    echo "Error: SFTP delete reported a failure for $DIR_TO_DELETE"
    exit 1
  fi
  echo "Remote directory cleaned up."
else
  echo "No files or directories to delete in $DIR_TO_DELETE."
fi
