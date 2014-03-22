#!/usr/bin/env sh
################################################################################
# Name         seer.sh 
# Version      0.2 (2014 March 4)
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

VERSION=0.2

HOST=localhost
PORT=1521
SID=${ORACLE_SID:orcl}
SERVICE_NAME=
USER=
PASS=
LINESIZE=`tput cols`

# If we have something that looks like an ANSI-friendly
# terminal, set a few color variables.
################################################################################
case $TERM in
  *xterm*|rxvt*)
    tput sgr0
    purple='\033[1;35m'
    white='\033[1;37m'
    none='\033[0m'
    ;;
esac

# Show usage and options for the script.
################################################################################
function run_usage() {

  local icon=
  # Use Emoji on the Mac
  if [ $TERM_PROGRAM='Apple_Terminal' ]; then
    icon="🔮 "
  fi

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

      --width WIDTH     limit the output to WIDTH columns
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

  if ! $(command -v sqlplus >/dev/null 2>&1); then
    echo >&2 "The ${purple}sqlplus${none} command could not be found. Check your environment and verify that ${white}\$ORACLE_HOME/bin${none} is referenced in ${white}\$PATH${none}."
    echo
    exit 1
  fi
  
  local login="/"
  local command="sqlplus -L"
  if [ -n "${USER}" -a -n "${PASS}" ]; then
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
    local temp_directory=".seer"
    local temp_filename="${temp_directory}/seer-`date '+%Y%m%d-%H%M'`-${pid}.sql"

    mkdir -p "$temp_directory" && cat > "$temp_filename" <<EOF
set sqlprompt '' trimspool on truncate on wrap off tab off
set numformat 99999999999999
set linesize ${LINESIZE}
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
  while [ $# -gt 0 ]; do
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
    --width)
      LINESIZE=$1
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