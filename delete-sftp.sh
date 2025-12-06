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
# List files and directories (non-recursive)
ls_output="$tmpdir/ls.txt"
printf '%s\n' "cd $DIR_TO_DELETE" "ls -l" "bye" | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$ls_output" 2>&1 || true
echo "SFTP ls output for $DIR_TO_DELETE:"
cat "$ls_output"

files_to_delete=$(awk '/^-/{print $NF}' "$ls_output")
dirs_to_delete=$(awk '/^d/{print $NF}' "$ls_output")

batch="$tmpdir/delete_batch.txt"
for f in $files_to_delete; do
  echo "rm $DIR_TO_DELETE/$f" >> "$batch"
done

for d in $dirs_to_delete; do
  # Guard: test cd to subdirectory, exit loop if it fails
  sub_guard_output="$tmpdir/sftp_sub_guard_check_$d.txt"
  printf '%s\n' "cd $DIR_TO_DELETE/$d" 'bye' | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$sub_guard_output" 2>&1
  sub_guard_exit_code=$?
  if grep -q "No such file or directory" "$sub_guard_output"; then
    echo "SFTP exit code for subdirectory guard: $sub_guard_exit_code"
    echo "Error: Subdirectory does not exist $DIR_TO_DELETE/$d"
    cat "$sub_guard_output"
    continue
  fi
  # List files in subdirectory
  sub_ls="$tmpdir/ls_$d.txt"
  printf '%s\n' "cd $DIR_TO_DELETE/$d" "ls -l" "bye" | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$sub_ls" 2>&1 || true
  echo "SFTP ls output for $DIR_TO_DELETE/$d:"
  cat "$sub_ls"
  sub_files=$(awk '/^-/{print $NF}' "$sub_ls")
  sub_dirs=$(awk '/^d/{print $NF}' "$sub_ls")
  for sf in $sub_files; do
    echo "rm $DIR_TO_DELETE/$d/$sf" >> "$batch"
  done
  # No recursion: only one level deep
  for sd in $sub_dirs; do
    echo "rmdir $DIR_TO_DELETE/$d/$sd" >> "$batch"
  done
  echo "rmdir $DIR_TO_DELETE/$d" >> "$batch"
done

# Always attempt to remove the directory itself at the end
echo "rmdir $DIR_TO_DELETE" >> "$batch"

if [ -s "$batch" ]; then
  delete_output="$tmpdir/delete_output.txt"
  (cat "$batch"; echo "bye") | sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -P "$FTP_PORT" "$FTP_USERNAME@$FTP_SERVER" > "$delete_output" 2>&1
  echo "SFTP delete output for $DIR_TO_DELETE:"
  cat "$delete_output"
  echo "Remote directory cleaned up."
else
  echo "No files or directories to delete in $DIR_TO_DELETE."
fi
