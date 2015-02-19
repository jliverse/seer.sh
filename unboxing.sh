#!/usr/bin/env bash
##############################################################################
# Name         unboxing.sh
# Version      0.0 (2014 December 19)
# Description  For webTA developers who work with Oracle databases, ta-dmp.sh
#              is a Bash script for UNIX machines that uses default values when
#              calling the impdp utility for expdp-generated Oracle dump files.
# Author       @jliverse
##############################################################################

VERSION=0.0
DB_USER=
DB_PASS=
DB_DIRECTORY_NAME=
DB_DIRECTORY_PATH=
SCHEMA_NAME=

# If we have something that looks like an ANSI-friendly
# terminal, set a few color variables.
##############################################################################
case $TERM in
  *xterm*|rxvt*)
  tput sgr0
  error='\033[1;31m'
  success='\033[1;32m'
  info='\033[1;33m'
  bold='\033[1m'
  none='\033[0m'
  hidden='\033[8m'
  tint='\033[1;32m' # green
  ;;
esac

# Import the dump file using 'impdp'.
# Arguments: $filename
##############################################################################
function export() {

  local file_name=`basename "${FILENAME}"`
  local schema_name="${DB_USER}"
  if [[ -n "${SCHEMA_NAME}" ]]; then
    schema_name="${SCHEMA_NAME}"
  fi

  # Require a schema name.
  [[ -z "${schema_name}" ]] && die "The ${TYPE} requires a schema name." "You can set the database username with the ${bold}-s${none} or ${bold}--schema${none} option."

  if [[ -n "${DB_USER}" ]]; then
    [[ -z "${DB_PASS}" ]] && die "The ${TYPE} requires a database password." "You can set the database password with the ${bold}-w${none}, ${bold}--expect-password${none} or ${bold}--password${none} option."

    # Check that we have the correct privileges to export a full database over the wire.
    local privileges=`sqlplus -S "/ as sysdba" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
select '' || count(*) from dba_role_privs where lower(granted_role) in ('exp_full_database') and lower(grantee) = lower('${DB_USER}');
EOF`
    if [[ ${privileges} -eq 0 ]]; then
      # Attempt to grant the permission using generic SYSDBA.
      privileges=`sqlplus -S "/ as sysdba" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
grant exp_full_database to ${DB_USER};
select '' || count(*) from dba_role_privs where lower(granted_role) in ('exp_full_database') and lower(grantee) = lower('${DB_USER}');
EOF`
      # If it's still empty, then quit immediately.
      [[ ${privileges} -eq 0 ]] && die "You do not have the required privileges." "The user ${bold}${DB_USER}${none} must have been granted the ${bold}exp_full_database${none} role, e.g.,\nSQL> grant exp_full_database to ${bold}${DB_USER}${none};"
    fi

    # Check that we have the ability to write into the export directory
    local directory_permission=`sqlplus -S "${DB_USER}/${DB_PASS}" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
select '' || count(*) from all_directories where lower(directory_name) = lower('${DB_DIRECTORY_NAME}');
EOF`
    if [[ ${directory_permission} -eq 0 ]]; then
      # Attempt to grant the permission using generic SYSDBA.
      directory_permission=`sqlplus -S "/ as sysdba" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
grant read, write on directory ${DB_DIRECTORY_NAME} to ${DB_USER};
select '' || count(*) from all_directories where lower(directory_name) = lower('${DB_DIRECTORY_NAME}');
EOF`
      [[ ${directory_permission} -eq 0 ]] && die "You do not have the required permissions." "The user ${bold}${DB_USER}${none} must have access to the Oracle directory, e.g.,\nSQL> grant read, write on directory ${bold}${DB_DIRECTORY_NAME}${none} to ${bold}${DB_USER}${none};"
    fi
  fi

  local directory="${DB_DIRECTORY_PATH%/}"

  if [[ $VERBOSE -eq 1 ]]; then
    echo -e "${bold}Schema            ${none}${schema_name}"
    echo -e "${bold}Dump file         ${none}${file_name}"
  fi

  local credentials="/ as sysdba"
  if [[ -n "${DB_USER}" || -n "${DB_PASS}" ]]; then
    credentials="${DB_USER}/${DB_PASS}"
  fi

  # Run the export, e.g., expdp \"SYS@ORCL AS SYSDBA\" ...
  # reuse_dumpfiles="y" \
  local log_file_name="${file_name%%.dmp}-`date '+%Y%m%d-%H%M'`.log"
  local command="expdp \"${credentials}\" \
             directory=\"${DB_DIRECTORY_NAME}\" \
              dumpfile=\"${file_name}\" \
               logfile=\"${log_file_name}\" \
               schemas=\"${schema_name}\" \
               version=\"compatible\""

  if [[ $DRY_RUN -eq 1 ]]; then
    command=`echo "${command}" | sed -e 's/[ ]\+/ /g'`
    echo -e "${bold}Parameters        ${none}${command}"
  else
    echo
    `${command}` || die "There was a problem ${TYPE}ing the file." "The export to ${bold}${FILENAME}${none} did not complete successfully. See ${bold}${directory}/${log_file_name}${none} for details."
    echo -e "${success}Successfully ${TYPE}ed ${bold}${FILENAME}${none}.${none}"
  fi

  if [[ ! -h "${FILENAME}" ]]; then
    ln -s "${directory}/${file_name}" "${FILENAME}" || die "Could not link to the file." "A symbolic link to ${bold}${${directory}}/${file_name}${none} could not be created at ${FILENAME}."
  fi
  exit 0
}

# Import the dump file using 'impdp'.
# Arguments: $filename
##############################################################################
function import() {
  # Test the filename.
  if [[ ! -f "${FILENAME}" ]]; then
    die "Could not open the file." "The file ${bold}${FILENAME}${none} is not a readable file."
  fi

  # Create a symbolic link from the dump file into the Oracle directory's path if it doesn't already exist.
  local file_name=`basename "${FILENAME}"`
  local file_link
  if [[ ! -e "${directory}/${file_name}" ]]; then
    local pid=$$
    file_link="unboxing-import-`date '+%Y%m%d-%H%M'`-${pid}.dmp"
    file_name="${file_link}"

    local file_path=$(resolve_path "${FILENAME}")
    ln -s "${file_path}" "${directory}/${file_name}" || die "Could not link to the file." "A symbolic link to ${bold}${FILENAME}${none} could not be created in ${directory}."
  fi

  # Get the schema from the dump file itself, if not provided.
  if [[ -z "${SCHEMA_NAME}" ]]; then
    echo -e "You can set the schema directly with the ${bold}-s${none} or ${bold}--schema${none} options.${none}"
    echo -e "${info}Attempting to find a match...${none}"
    local sql_file_name="temp-`date '+%Y%m%d-%H%M'`-$$.sql"
    local status=`impdp "'/ as sysdba'" directory="${DB_DIRECTORY_NAME}" dumpfile="${file_name}" TRANSFORM=SEGMENT_ATTRIBUTES:n sqlfile="${sql_file_name}" EXCLUDE=SCHEMA:\"IN \(\'APEX_030200\', \'CTXSYS\', \'FLOWS_FILES\', \'OLAPSYS\', \'ORDDATA\', \'ORDSYS\', \'OUTLN\', \'OWBSYS_AUDIT\', \'OWBSYS\', \'SCOTT\', \'SYS\', \'SYSMAN\', \'SYSTEM\', \'WMSYS\', \'XDB\'\)\" >/dev/null 2>&1`
    [[ status -ne 0 ]] && die "There was a problem ${TYPE}ing the file." "The file ${bold}${file_name}${none} could not be ${TYPE}ed."

    [[ ! -f "${directory}/${sql_file_name}" ]] && die "The ${TYPE} did not generate an output file." "The ${bold}${directory}/${sql_file_name}${none} does not exist."

    SCHEMA_NAME=`grep -oE '"[^"]+"\.".*"' "${directory}/${sql_file_name}" | head -n 1 | sed -e 's/^"\([^"]\+\).*/\1/g'`
    echo -e "The schema name is ${bold}${SCHEMA_NAME}${none}."
    rm "${directory}/${sql_file_name}"
  fi

  if [[ -n "${DB_USER}" ]]; then
    # Require a password if we provide a user.
    [[ -z "${DB_PASS}" ]] && die "The ${TYPE} requires a database password." "You can set the database password with the ${bold}-w${none}, ${bold}--expect-password${none} or ${bold}--password${none} option."

    local directory_permission=`sqlplus -S "${DB_USER}/${DB_PASS}" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
select '' || count(*) from all_directories where lower(directory_name) = lower('${DB_DIRECTORY_NAME}');
EOF`
    if [[ ${directory_permission} -eq 0 ]]; then
      # Attempt to grant the permission using generic SYSDBA.
      directory_permission=`sqlplus -S "/ as sysdba" <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
grant read, write on directory ${DB_DIRECTORY_NAME} to ${DB_USER};
select '' || count(*) from all_directories where lower(directory_name) = lower('${DB_DIRECTORY_NAME}');
EOF`
      [[ ${directory_permission} -eq 0 ]] && die "You do not have the required permissions." "The user ${bold}${DB_USER}${none} must have access to the Oracle directory, e.g.,\nSQL> grant read, write on directory ${bold}${DB_DIRECTORY_NAME}${none} to ${bold}${DB_USER}${none};"
    fi
  fi

  [[ -z "${NEW_SCHEMA_NAME}" ]] && die "The ${TYPE} requires a the target schema name." "You can set the database schema with the ${bold}--new-schema${none} option."

  if [[ $VERBOSE -eq 1 ]]; then
    echo -e "${bold}Source            ${none}${SCHEMA_NAME}"
    echo -e "${bold}Target            ${none}${NEW_SCHEMA_NAME}"
    echo -e "${bold}Dump file         ${none}${file_name}"
  fi

  local credentials="/ as sysdba"
  if [[ -n "${DB_USER}" || -n "${DB_PASS}" ]]; then
    credentials="${DB_USER}/${DB_PASS}"
  fi

  # Run the import.
  ############################################################################
  local log_file_name="${SCHEMA_NAME}-${NEW_SCHEMA_NAME}-`date '+%Y%m%d-%H%M'`.log"
  local command="impdp \"${credentials}\" \
             directory=\"${DB_DIRECTORY_NAME}\" \
              dumpfile=\"${file_name}\" \
               logfile=\"${log_file_name}\" \
               schemas=\"${SCHEMA_NAME}\" \
          remap_schema=\"${SCHEMA_NAME}:${NEW_SCHEMA_NAME}\" \
               content=\"all\" \
             transform=\"OID:N\""

  # If we've run the import with --force, then replace all tables.
  if [[ $FORCE -eq 1 ]]; then
    command="${command} table_exists_action=\"replace\""
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    command=`echo "${command}" | sed -e 's/[ ]\+/ /g'`
    echo -e "${bold}Parameters        ${none}${command}"
  else
    echo
    `${command}` || die "There was a problem ${TYPE}ing the file." "The file ${bold}${FILENAME}${none} did not complete successfully. See ${bold}${directory}/${log_file_name}${none} for details."
    echo -e "${success}Successfully ${TYPE}ed ${bold}${FILENAME}${none}.${none}"
  fi

  # Delete the symbolic link, if any.
  if [[ -h "${directory}/${file_link}" ]]; then
    rm "${directory}/${file_link}"
  fi
  exit 0
}

function die() {
  echo
  if [[ $# -gt 1 ]]; then
    echo -e "${error}${1}${none}"
    echo -e "${2}"
  else
    echo -e "${error}${*}${none}"
  fi
  echo
  exit 1
}

function print_usage() {

  local icon=
  # Use Emoji on the Mac
  if [[ $TERM_PROGRAM='Apple_Terminal' ]]; then
    icon="📦  "
  fi

  local script=`basename "$0"`

  # Read some multi-line usage text into the variable 'usage'.
  IFS='' read -r -d '' usage <<EOF
${icon}${tint}unboxing ${VERSION}${none}, an impdp/expdp convenience script for Oracle.

${bold}Usage:${none} ${script} [options...]
${script} [options...] <SQL statement>

${bold}Options:${none}
-i, --import FILENAME      import the dump file FILENAME
-o, --export FILENAME      export the schema into the dump file FILENAME

-u, --user USER            set the Oracle user to USER
    --password PASS        set the Oracle password to PASS
-w, --expect-password      wait for the password to be entered interactively

-s, --schema NAME          set the schema name of the import to NAME
    --new-schema NAME      set the target schema name remapped from the import
-n, --directory-name NAME  set the Oracle directory name to NAME
-d, --directory-path DIR   set the Oracle directory path to DIR
                           (default: ${DB_DIRECTORY_PATH})

-v, --verbose              print additional output
    --dry-run              show the impdp/expdp arguments only

${bold}Examples:${none}
${script} --export my-new-export.dmp -u dbadmin -w -d /data/oracle_export/
EOF
  echo -e "${usage}"
}

function resolve_path() {
  if [[ -d "$1" ]]; then
    echo "$(CDPATH="" cd -P -- "$1" && pwd -P)"
  elif  [[ -e "$1" ]]; then
    local directory=$(resolve_path "`dirname "$1"`")
    echo "${directory}/`basename "$1"`"
  else
    echo "$1"
  fi
}

function main() {
  local args=()
  while [[ $# -gt 0 ]]; do
    local key="$1"
    shift
    case $key in
      -d|--directory-path)
      DB_DIRECTORY_PATH=$(resolve_path "$1")
      shift
      ;;
      --dry-run)
      DRY_RUN=1
      ;;
      -i|--import)
      IMPORT=1
      TYPE="import"
      FILENAME=$(resolve_path "$1")
      shift
      ;;
      -n|--directory-name)
      DB_DIRECTORY_NAME="$1"
      shift
      ;;
      -o|--export)
      EXPORT=1
      TYPE="export"
      FILENAME=$(resolve_path "$1")
      shift
      ;;
      --password)
      DB_PASS="$1"
      shift
      ;;
      -s|--schema)
      SCHEMA_NAME="$1"
      shift
      ;;
      --new-schema)
      NEW_SCHEMA_NAME="$1"
      shift
      ;;
      -u|--user)
      DB_USER="$1"
      shift
      ;;
      -v|--verbose)
      VERBOSE=1
      ;;
      --force)
      FORCE=1
      ;;
      -w|--expect-password)
      echo -e -n "${bold}Enter password: ${none}${hidden}" && read -r DB_PASS && echo -e "${none}"
      ;;
      *)
      args[${#args[*]}]="${key}"
      ;;
    esac
  done

  # Require either an import or export parameter.
  # local filename=${args[0]}
  # if [[ ${#args[*]} -ne 0 ]]; then
  if [[ -z "${FILENAME}" ]]; then
    print_usage
    exit 1
  fi

  # Test that we can access SQL*Plus and impdp/expdp.
  [[ -z "`command -v sqlplus`" ]] && die "Could not find 'sqlplus'." "Check your environment and verify that the correct ${bold}\$ORACLE_HOME/bin${none} is referenced in ${bold}\$PATH${none}."
  [[ -z "`command -v impdp`" ]] && die "Could not find 'impdp'." "Check your environment and verify that the correct ${bold}\$ORACLE_HOME/bin${none} is referenced in ${bold}\$PATH${none}."
  [[ -z "`command -v expdp`" ]] && die "Could not find 'expdp'." "Check your environment and verify that the correct ${bold}\$ORACLE_HOME/bin${none} is referenced in ${bold}\$PATH${none}."

  # Test the Oracle directory.
  [[ ! -d "${DB_DIRECTORY_PATH}" ]] && die "The ${TYPE} requires the path for a readable Oracle directory." "You can set the directory path with the ${bold}-d${none} or ${bold}--directory-path${none} option."

  local directory="${DB_DIRECTORY_PATH%/}"
  if [[ ! -d "${directory}" ]]; then
    die "Could not find the Oracle ${TYPE} directory." "The directory ${bold}${directory}${none} is not a readable directory. You can set the path with the ${bold}-d${none} or ${bold}--directory-path${none} option."
  fi

  # Get the Oracle directory name from the path if not provided.
  if [[ -z "${DB_DIRECTORY_NAME}" ]]; then
    DB_DIRECTORY_NAME=`sqlplus -S '/ as sysdba' <<EOF
set linesize 32767 pagesize 0 wrap off feedback off
select '' || directory_name
  from all_directories
 where lower(directory_path) = lower('${directory}')
   and rownum < 2;
EOF`
  fi
  [[ -z "${DB_DIRECTORY_NAME}" ]] && die "You must provide the name of the Oracle directory." "You can set the directory name with the ${bold}-n${none} or ${bold}--directory-name${none} option."

  if [[ $VERBOSE -eq 1 ]]; then
    [[ $IMPORT -eq 1 ]] && echo -e "${bold}Import            ${none}${FILENAME}"
    [[ $EXPORT -eq 1 ]] && echo -e "${bold}Export            ${none}${FILENAME}"
    echo -e "${bold}Directory         ${none}${DB_DIRECTORY_NAME} (${directory})"
    echo -e "${bold}Username/Password ${none}${DB_USER}/${DB_PASS}"
  fi

  if [[ $IMPORT -eq 1 ]]; then
    import
  elif [[ $EXPORT -eq 1 ]]; then
    export
  fi
  exit 0
}

set -o noglob
echo
main "$@"
