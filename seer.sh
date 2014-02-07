#!/usr/bin/env sh
################################################################################
# Name         seer.sh 
# Version      0.1 (2014 February 2)
# Description  For developers who work with Oracle databases, Seer is a shell
#              script for UNIX machines that calls SQL*Plus with parameters
#              given at the prompt.
# Author       @jliverse
#
# Copyright 2014 Joseph Liversedge
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Usage:
# ./seer.sh myscript.sql
# ./seer.sh -h localhost -p 1521 -s orcl -u myusername -w mypassword "select * from TAB"

VERSION=0.1

HOST=localhost
PORT=1521
SID=${ORACLE_SID:orcl}
SERVICE_NAME=
USER=
PASS=

# Show usage and options for the script.
################################################################################
function run_usage() {

  local icon=
  # Use Emoji on the Mac
  if [ $TERM_PROGRAM == 'Apple_Terminal' ] ; then
    icon="🔮  "
  fi

  # If we have something that looks like an ANSI-friendly
  # terminal, set a few color variables.
  local purple=
  local white=
  local none=
  case $TERM in
    *xterm*|rxvt*)
      tput sgr0
      purple='\033[1;35m'
      white='\033[1;37m'
      none='\033[0m'
      ;;
  esac
  
  local script=`basename "$0"`

  # Read some multi-line usage text into the variable 'usage'.
  IFS='' read -r -d '' usage <<EOF
${icon}${purple}Seer ${VERSION}${none}, a SQL*Plus convenience script for Oracle.
  
${white}Usage:${none} ${script} [options...] <filename>
       ${script} [options...] <SQL statement>
       
${white}Options:${none}
  -u, --user USER       set the login user to USER
      --password PASS   set the login password to USER
      --pass PASS
  -w, --expect-password wait for the password to be entered interactively
  
  -h, --host HOST       set the Oracle hostname to HOST     (default: localhost)
  -p, --post POST       set the Oracle port to PORT         (default: 1521)
  -s, --sid SID         set the Oracle SID to SID           (default: orcl)
  -n, --service NAME    set the Oracle service name to NAME

  -v, --verbose         print additional output

${white}Examples:${none}
   ${script} "desc TAB"
   ${script} my-sql-script.sql
   ${script} -w -u myusername my-sql-script.sql
   ${script} -h localhost -p 1521 -s orcl -u myusername --password mypassword "select * from TAB"

EOF
  echo "${usage}"
}

# Construct the SQL*Plus connection string.
################################################################################
function connection_string() {
  if [ -n "$SERVICE_NAME" ]; then
    echo "(description=(address_list=(address=(protocol=tcp)(host=$HOST)(port=$PORT)))(connect_data=(service_name=$SERVICE_NAME)))"
  else
    echo "(description=(address_list=(address=(protocol=tcp)(host=$HOST)(port=$PORT)))(connect_data=(sid=$SID)))"
  fi
}

# Call SQL*Plus with the given connection details and handle any arguments.
################################################################################
run_sqlplus() {

  echo
  
  local login="/"
  local command="sqlplus -L"
  if [[ -n "${USER}" && -n "${PASS}" ]]; then
    login="$USER/$PASS"
    command="sqlplus -S"
  elif [ -n "$USER" ]; then
    login="$USER"
  fi

  if [ -n "$SID" ]; then
    export ORACLE_SID="$SID"
  fi
  
  local connection=$(connection_string)
  local filename=$1
  # If the first argument is a file, assume we're executing a script.
  if [ -e "$filename" ]; then
    # We could have arguments passed into the script, so pop the file name.
    shift

    # Run sqlplus with the connection information and the SQL script.
    if [ $VERBOSE ]; then
      echo "${command} \"${login}@${connection}\" \"@${filename}\" $@"
    fi
    exit | $command "${login}@${connection}" "@${filename}" $@
  else
    # Create a temporary file to store our preferred formatting just before the
    # SQL statements. We could run this inline, but we need to be able to type
    # in a password if not provided as a command-line option.
    local pid=$$
    local temp_filename="$TMPDIR/seer-`date '+%Y%m%d-%H%M'`-${pid}.sql"

    mkdir -p ${TMPDIR} && cat > "$temp_filename" <<EOF
set sqlprompt '' trimspool on truncate on wrap off tab off
set numformat 99999999999999
set linesize 32767
set pagesize 50000
set timing on
$@;
exit
EOF

    # Run sqlplus with the connection information and the temporary SQL script.
    if [ $VERBOSE ]; then
      echo "${command} \"${login}@${connection}\" \"@${temp_filename}\""
    fi
    $command "${login}@${connection}" "@${temp_filename}"
    
    # Remove the file we created.
    rm "$temp_filename"
  fi
}

# Handle the parsed arguments.
################################################################################
function run_script() {
  # Check that we have at least one script argument.
  if [ ! $1 ]; then
    run_usage
    exit 1
  else
    run_sqlplus "$@"
  fi
} 

# The main function parses command-line options before running the script.
################################################################################
function main() {

  # Parse command-line arguments.
  # Credit: http://stackoverflow.com/questions/192249/
  local args=()
  while [[ $# > 0 ]]; do
    local key="$1"
    shift
    case $key in
    -h|--host)
      HOST="$1"
      shift
      ;;
    -p|--port)
      PORT="$1"
      shift
      ;;
    -u|--user)
      USER="$1"
      shift
      ;;
    --password|--pass)
      PASS="$1"
      shift
      ;;
    -w|--expect-password)
      read -r -p "Enter password: " PASS
      ;;
    -n|--service)
      SERVICE_NAME="$1"
      shift
      ;;
    -s|--sid)
      SID="$1"
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      ;;
    *)
      args[${#args[*]}]="${key}"
      ;;
    esac
  done

  # Handle the collected arguments.
  run_script "${args[@]}"
}

set -o noglob
main $@
