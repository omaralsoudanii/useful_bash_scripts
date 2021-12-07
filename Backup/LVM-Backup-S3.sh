#!/bin/bash

die() {
  local _ret=$2
  test -n "$_ret" || _ret=1
  test "$_PRINT_HELP" = yes && print_help >&2
  echo "$1" >&2
  exit ${_ret}
}

begins_with_short_option() {
  local first_option all_short_options='pcrbfh'
  first_option="${1:0:1}"
  test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}

_arg_stop_cmd=
_arg_start_cmd=
_arg_snapshot_name=
_arg_snapshot_mount_dir=
_arg_snapshot_cow=
_arg_group_dir=
_arg_data_dir=
_arg_backup_dir=
_arg_backup_file_prefix=
_arg_s3_archive_path=
CURRDATE=$(date +%Y-%m-%d-%H-%M-%S)

print_help() {
  printf '%s\n' "LVM script to generate a snapshot from file system to S3"
  printf '%s\n' "------------------------------------"
  printf '%s\n' "Example usage:"
  printf '%s\n' "./backup.sh --stop-cmd \"service stop mongo\" --start-cmd \"service start mongo\" --snapshot-name \"tmp-backup-snapshot\" --snapshot-mount \"/var/lib/mongodb-snapshot\" --snapshot-cow \"5\" --group-dir \"/dev/vg00\" --data-dir \"mongo-data\" --backup-dir \"/var/lib/mongodb-backup\" --backup-file-prefix \"hawyyiah-mongo-slave01\" --s3-path \"s3://jawabkom-backup/who-spam/\""
  printf '%s\n' "------------------------------------"
  printf '%s\n' "-h, --help: Prints help"
}

parse_commandline() {
  while test $# -gt 0; do
    _key="$1"
    case "$_key" in
    -stopc | --stop-cmd)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_stop_cmd="$2"
      shift
      ;;
    --stop-cmd=*)
      _arg_stop_cmd="${_key##--stop-cmd=}"
      ;;
    -stopc*)
      _arg_stop_cmd="${_key##-stopc}"
      ;;
    -startc | --start-cmd)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_start_cmd="$2"
      shift
      ;;
    --stop-cmd=*)
      _arg_start_cmd="${_key##--start-cmd=}"
      ;;
    -startc*)
      _arg_start_cmd="${_key##-startc}"
      ;;
    --group-dir)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_group_dir="$2"
      shift
      ;;
    --snapshot-name)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_snapshot_name="$2"
      shift
      ;;
    --snapshot-mount)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_snapshot_mount_dir="$2"
      shift
      ;;    
    --snapshot-cow)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_snapshot_cow="$2"
      shift
      ;;
    --data-dir)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_data_dir="$2"
      shift
      ;;
    --backup-dir)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_backup_dir="$2"
      shift
      ;;    
    --backup-file-prefix)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_backup_file_prefix="$2"
      shift
      ;;    
    --s3-path)
      test $# -lt 2 && die "Missing value for the argument '$_key'." 1
      _arg_s3_archive_path="$2"
      shift
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    -h*)
      print_help
      exit 0
      ;;
    *)
      _PRINT_HELP=yes die "FATAL ERROR: Got an unexpected argument '$1'" 1
      ;;
    esac
    shift
  done
}

logCommandLineArgs() {
  echo "[$CURRDATE] Creating new snapshot with:"
  echo "[START_CMD]: $_arg_start_cmd"
  echo "[STOP_CMD]: $_arg_stop_cmd"
  echo "[SNAPSHOT_NAME]: $_arg_snapshot_name"
  echo "[SNAPSHOT_COW]: ${_arg_snapshot_cow}G"
  echo "[SNAPSHOT_MOUNT]: $_arg_snapshot_mount_dir"
  echo "[GROUP_DIR]: $_arg_group_dir"
  echo "[DATA_DIR]: $_arg_data_dir"
  echo "[BACKUP_DIR]: $_arg_backup_dir"
  echo "[FILE_NAME]: ${_arg_backup_file_prefix}-${CURRDATE}.tar"
  echo "[S3_ARCHIVE_PATH]: $_arg_s3_archive_path"
  echo "------------------------------------"
}

startService() {
  echo "Starting Service ..."
  $_arg_start_cmd
}

stopService() {
  echo "Stopping Service ..."
  $_arg_stop_cmd
}

rollbackAction() {
  echo "Backup process failed, rolling back and starting service..."
  $_arg_start_cmd
  exit 2
}

deleteSnapshotIfExists() {
  EXISTS=$(/sbin/lvs | grep -o "$_arg_snapshot_name")
  if [ ! -z $EXISTS ]; then
    echo "Deleting old snapshot $_arg_snapshot_name from group $_arg_group_dir directory..."
    /usr/bin/umount ${_arg_group_dir}/${_arg_snapshot_name}
    /sbin/lvremove -y ${_arg_group_dir}/${_arg_snapshot_name}
  fi
}

createSnapshot() {
  /sbin/lvcreate -L ${_arg_snapshot_cow}G -s -n $_arg_snapshot_name ${_arg_group_dir}/${_arg_data_dir}
  /usr/bin/mount ${_arg_group_dir}/${_arg_snapshot_name} $_arg_snapshot_mount_dir
}

backupFiles() {
  echo "Archiving data directory to ${_arg_backup_dir}/${_arg_backup_file_prefix}-${CURRDATE}.tar"
  cd $_arg_backup_dir
  tar -cf "${_arg_backup_file_prefix}-${CURRDATE}.tar" -C $_arg_snapshot_mount_dir .
}

archiveToS3() {
  echo "Archiving to S3 ..."
  /usr/local/bin/aws s3 cp "${_arg_backup_dir}/${_arg_backup_file_prefix}-${CURRDATE}.tar" ${_arg_s3_archive_path} --storage-class ONEZONE_IA
}

cleanBackupDirectory() {
  echo "Cleaning up backup directoy..."
  cd $_arg_backup_dir
  rm -f ${_arg_backup_file_prefix}*.tar
}

parse_commandline "$@"

logCommandLineArgs
cleanBackupDirectory || exit 2
deleteSnapshotIfExists || exit 2
stopService
createSnapshot || rollbackAction
startService
backupFiles
deleteSnapshotIfExists
archiveToS3
cleanBackupDirectory