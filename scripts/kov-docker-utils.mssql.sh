#!/bin/bash
# set -o xtrace

# WE DEPEND ON DICKER BUILKDKIT FEATURES so every docker compose command should be run with
# DOCKER_BUILDKIT=1 docker compose ...
# so is it a good idea to define this once up here???
# DOCKER_BUILDKIT=1

SCRIPTNAME=$(basename "$0")

# we should still handle the case where getting the logs (which may be on stderr as well as stdout)
# fails. Currently the user cannot see the difference between actual alogs and when getting them fails.
function getContainerLogs() {
  local UNIQUE_NAME="$1"
  docker container ls | grep "${UNIQUE_NAME}" | awk '{print $1}' | xargs docker logs 2>&1
}

function echoerr() {
  echo "$@" 1>&2;
}

function generateDockerFileName() {
  local UNIQUE_NAME=$1
  echo "${UNIQUE_NAME}.Dockerfile"
}

function generateDockerComposeFileName() {
  local UNIQUE_NAME=$1
  echo "${UNIQUE_NAME}.docker-compose.yml"
}

################################################################################
# below are the supported commands
################################################################################

# returns string true if up and running and false if not
function isupandrunning() {
  local LOGS=$(getContainerLogs "$UNIQUE_NAME")

  local READY=$(echo "$LOGS" | grep 'SQL Server is now ready for client connections.')

  if [ "$READY" == "" ]; then
    echo false
  else
    echo true
  fi
}

function waituntilupandrunning() {
  if [ $# -ne 1 ]; then
    echo "
  Usage: ./${SCRIPTNAME} <dockerContainerName>
    * dockerContainerName = the name of a docker container based on a mssqldb image

    This script will scan the logs of that container for the line:
      'SQL Server is now ready for client connections. This is an informational message; no user action is required.'
    and if it is found in the logs, we know that the database server is fully initialized
    so out tests can start running.

    This script will keep running until that line has been found in the logs!!!
  "
    exit -1
  fi

  local UNIQUE_NAME="$1"

  echo "Start checking if the mssql server container '$UNIQUE_NAME' is up and running..."

  local READY="false"

  # The solution below with echo $BASHPID and kill was found here: https://superuser.com/a/796002
  # Another post in the same SO issue mentions the 'watch' command, which can be terminated
  # with the -g/--chgexit option when the output of command changes. 'man watch' for more details.
  ( echo "$BASHPID"; docker container ls | grep "${UNIQUE_NAME}" | awk '{print $1}' | xargs docker logs --follow 2>&1 ) | \
  while read LINE ; do
    if [ -z $TPID ]; then
        echoerr "tpid = $LINE"
        TPID=$LINE # the first line is used to store the previous subshell PID
    else
      echo "$LINE"

      # ideally what follows is a function that can be passed to this function
      if [ "$READY" == "false" ] && [[ "$LINE" == *"SQL Server is now ready for client connections."* ]]; then
        READY="true"
      fi

      if [ "$READY" == "true" ]; then
        kill -3 "$TPID"
        echo "READY: $READY"
        break
      fi
    fi
  done

  # | local OK=$(cat)

  echo "The mssql server container '$UNIQUE_NAME' is MOST LIKELY up and running..."

  # if [ "$OK" == "true" ]; then
  #   echo "The mssql server container '$UNIQUE_NAME' is up and running..."
  # else
  #   echo "The mssql server container '$UNIQUE_NAME' is NOT up and running..."
  # fi
}


function start() {
  if [ $# -lt 2 ]; then
    echo "
Usage: ./${SCRIPTNAME} start <unique_name> <port> <OPTIONAL:context>
  * unique_name = the name to use as a base for the various docker related files,
    the docker container etc.
    WATCH OUT: must be LOWERCASE !!!
  * port = the port on localhost where the mssql server will be listening on (example: 1433).
  * [FUTURE, to be implmented] version = a number indicating whether you need a
    mssql 2017 (14.x), 2019 (15.x), 2022 (16.x) instance
  * context = folder where the files are located that are used to initialize the
    database on first start, defaults to '' ('' or empty string means that you only
    want an empty database, and nothing else)
    * We will run any *.sql files, run any executable *.sh scripts, and source any
      non-executable *.sh scripts found in that 'context' directory to initialize the
      database before starting the service for the first time. (for more details check
      https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-linux-ver15&preserve-view=true&pivots=cs1-bash#pullandrun2019)
    * In order to allow you to reuse files inside the context that you also need in
      other places, all symbolic links will be replaced by the actual content before sending
      the build context to docker.

  This script will create the docker-files for a mssql database and start it.
  Some defaults are fixed: the default database is called 'db', and a user called
  SA with password p@ssw0rd can be used to connect to this database.
  Any other users you want to set up must be created through the use of the files in the
  context folder.
"
    exit -1
  fi

  local UNIQUE_NAME="$1"
  local PORT="$2"
  local CONTEXT="$3"

  local DOCKER_FILENAME=$(generateDockerFileName "${UNIQUE_NAME}")
  local DOCKERCOMPOSE_FILENAME=$(generateDockerComposeFileName "${UNIQUE_NAME}")
  local CWD=$(pwd)
  # if we want to get rid of the CWD_RELATIVE_TO_CONTEXT dependency we could also create our own function: https://unix.stackexchange.com/a/85068
  # CWD_RELATIVE_TO_CONTEXT=$(realpath -m --relative-to="${CONTEXT}" "${CWD}" || grealpath -m --relative-to="${CONTEXT}" "${CWD}" || echo "<NOT FOUND>")
  # if [[ "${CWD_RELATIVE_TO_CONTEXT}" == "<NOT FOUND>" ]];then
  #   echo "realpath/grealpath is not installed?"
  #   exit -1
  # fi


  local EXISTING_DOCKER_CONTAINER_NAME=$(docker container ls -a --format '{{.Names}}' | grep "^${UNIQUE_NAME}$")
  local FULLCONTEXT_DIRNAME=''
  # local CWD_RELATIVE_TO_FULLCONTEXT_DIRNAME = '.'

  if [ "${CONTEXT}" == "" ]; then
    echo "No context provided."
    local CWD_RELATIVE_TO_FULLCONTEXT_DIRNAME='.'
  elif [[ "${EXISTING_DOCKER_CONTAINER_NAME}" != "" ]]; then
    echo "Docker container exists, no need to tar and untar the context"
  else
    echo "Docker container does not exist yet, we will tar and untar the context"
    FULLCONTEXT_DIRNAME="/tmp/${DOCKER_FILENAME}_context"
    local CWD_RELATIVE_TO_FULLCONTEXT_DIRNAME=$(realpath -m --relative-to="${FULLCONTEXT_DIRNAME}" "${CWD}" || grealpath -m --relative-to="${FULLCONTEXT_DIRNAME}" "${CWD}" || echo "<NOT FOUND>")
    if [[ "${CWD_RELATIVE_TO_FULLCONTEXT_DIRNAME}" == "<NOT FOUND>" ]];then
      echo "realpath/grealpath is not installed?"
      exit -1
    fi
    (
      cd "${CONTEXT}"
      mkdir -p "${FULLCONTEXT_DIRNAME}"
      tar -ch . | tar -x -f - -C "${FULLCONTEXT_DIRNAME}"
      echo "Here's what the 'context' contains:"
      ls -hal "${FULLCONTEXT_DIRNAME}"
    )
  fi

  pwd
  cat > "${DOCKER_FILENAME}" << ENDOFFILE
FROM mcr.microsoft.com/mssql/server:2019-latest as mssql_stage
$(
  if [ "${CONTEXT}" == "" ]; then
    echo -n ""
  else
    echo -e "  COPY . /docker-entrypoint-initdb.d/"
    echo "RUN ls -hal /docker-entrypoint-initdb.d"
  fi
)
ENDOFFILE

  cat > "${DOCKERCOMPOSE_FILENAME}" << ENDOFFILE
version: "3.9"  # optional since v1.27.0
services:
  mssqldb:
    container_name: "${UNIQUE_NAME}"
    build:$(
    # with command substituion, trailing newlines are removed, so we used a newline in the front instead :(
    if [ "${FULLCONTEXT_DIRNAME}" == "" ]; then
      echo -n "";
    else echo -e "
      context: ${FULLCONTEXT_DIRNAME}";
    fi
)
      dockerfile: "${CWD_RELATIVE_TO_FULLCONTEXT_DIRNAME}/${DOCKER_FILENAME}"
      target: mssql_stage
    # tagged image name when build is specified, or image name used when build is not specified !!!
    image: "${UNIQUE_NAME}"
    hostname: "${UNIQUE_NAME}"
    ports:
      - ${PORT}:1433
    environment:
      ACCEPT_EULA: Y
      # MSSQL_USER: mssql # The mssql user (useful to connect to the database)
      MSSQL_SA_PASSWORD: p@ssw0rd # The mssql password (useful to connect to the database)
      # By default, the password must be at least eight characters long and contain characters
      # from three of the following four sets: uppercase letters, lowercase letters, base-10 digits,
      # and symbols. You can examine the error log by using the docker logs command.
      # MSSQL_DB: mssql # The mssql default database (automatically created at first launch)
ENDOFFILE

  echo "Starting docker compose"

  # less "${DOCKER_FILENAME}"

  # less "${DOCKERCOMPOSE_FILENAME}"

  # read -p "I will start the docker now, PRESS ENTER TO CONTINUE"

  DOCKER_BUILDKIT=1 docker compose -f "${DOCKERCOMPOSE_FILENAME}" --verbose up -d && waituntilupandrunning "${UNIQUE_NAME}"

  local DBEXISTS=$( execsql "${UNIQUE_NAME}" "SELECT 'true' FROM sys.databases where name = 'db'" "true" | head -n 1 )
  # echo "-------- DBEXISTS = $DBEXISTS"
  # in order to mimic the behaviour of postgres, only run sql scripts if the 'db' database doesnotexist yet
  # (so when the srver has not been initialized before)
  if [ "$DBEXISTS" = 'true' ]; then
    echo "Not running docker-entrypoint-initdb.d scripts because the database server has been initialized already"
  else
    # now create a default database
    execsql "${UNIQUE_NAME}" "CREATE DATABASE db;" "true"

    # now execute the init db scripts on the database
    if [ "${CONTEXT}" == "" ]; then
      echo "No context provided so not executing any more sql scripts"
    else
      readarray -t SQLSCRIPTS < <(ls ${CONTEXT}/*.sql)
      for S in "${SQLSCRIPTS[@]}"; do
        echo "Executing sql script file: $S"
        execsql "${UNIQUE_NAME}" "$( cat "$S" )"
      done
    fi
  fi

  # read -p "I will remove the context at ${FULLCONTEXT_DIRNAME} now, PRESS ENTER TO CONTINUE"
  if [ "${FULLCONTEXT_DIRNAME}" != "" ]; then rm -rf "${FULLCONTEXT_DIRNAME}"; fi
}

function stop() {
  echo "Stopping mssqldb docker container"
  local UNIQUE_NAME="$1"
  local DOCKERCOMPOSE_FILENAME="${UNIQUE_NAME}.docker-compose.yml"

  DOCKER_BUILDKIT=1 docker compose -f "${DOCKERCOMPOSE_FILENAME}" stop
}

function cleanup() {
  echo cleanup
  local UNIQUE_NAME="$1"
  local DOCKER_FILENAME=$(generateDockerFileName "${UNIQUE_NAME}")
  local DOCKERCOMPOSE_FILENAME=$(generateDockerComposeFileName "${UNIQUE_NAME}")

  DOCKER_BUILDKIT=1 docker compose -f "${DOCKERCOMPOSE_FILENAME}" down --rmi=all --remove-orphans
  # DOCKER_BUILDKIT=1 docker compose -f "${DOCKERCOMPOSE_FILENAME}" rm;
  # docker images -a | grep "^${UNIQUE_NAME}\s" | awk '{print $3}' | xargs docker image rm -f

  rm "${DOCKER_FILENAME}" "${DOCKERCOMPOSE_FILENAME}"
}

# Given the unique name folowed by the command line arguments to execute
# it will locate the docker container and run the commands for you
#
# This is both a utility function used by execsql and shell,
# and a standalone function to run any command on the container
function exec() {
  # UNIQUE_NAME=$(awk '/mssqldb:/{flag=1} flag && /container_name:/{print $NF;flag=""}'  test.docker-compose.yml)
  local UNIQUE_NAME="$1"
  local COMMAND=( "${@:2}" )

  local EXISTING_DOCKER=$(docker container ls -a --format "{{.Names}}\t{{.Status}}" | grep "^${UNIQUE_NAME}\s")
  local EXISTING_DOCKER_NAME=$(echo ${EXISTING_DOCKER} | awk '{print $1}')
  local EXISTING_DOCKER_EXITED=$(echo ${EXISTING_DOCKER} | grep "\sExited\s")
  local ALL_EXISTING_CONTAINERS=$(docker container ls -a --format "{{.Names}}\t{{.Status}}")
  [[ -z ${ALL_EXISTING_CONTAINERS} ]] && ALL_EXISTING_CONTAINERS="<EMPTY CONTAINER LIST>"

  if [[ "${EXISTING_DOCKER}" ==  "" ]]; then
    echoerr "ERROR We did not find any containers for \"${UNIQUE_NAME}\"."
    echoerr "These are the containers we found on your system:"
    IFS=$'\n'
    for CONTAINER in ${ALL_EXISTING_CONTAINERS[@]}; do
      echoerr "- ${CONTAINER}"
    done
    return -1
  elif [[ ${EXISTING_DOCKER_EXITED} != '' ]]; then
    echoerr "ERROR Found docker container \"${EXISTING_DOCKER_NAME}\" but it is not running."
    echoerr "- ${EXISTING_DOCKER_EXITED}"
    return -1
  fi

  echoerr "Checking if the mssql server container '$EXISTING_DOCKER_NAME' is up and running..."

  if [ $(isupandrunning "${UNIQUE_NAME}") == "true" ]; then
    echoerr "The mssql server container '$EXISTING_DOCKER_NAME' is up and running..."
    echoerr "running command \"${COMMAND}\""
    echoerr docker exec -it ${EXISTING_DOCKER_NAME} "${COMMAND[@]}"
    docker exec -it "${EXISTING_DOCKER_NAME}" "${COMMAND[@]}"
    return $?
  else
    echoerr "ERROR The mssql server container is not up and running! Exiting..."
    return -1
  fi
}

### third argument can be true to indicate that the db database does not exist yet,
### in order to support the initialization
function execsql() {
  local NOTINITIALISED="$3"
  if [ $# -ne 2 -a "$NOTINITIALISED" != "true" ]; then
    echo "
Usage: ./${SCRIPTNAME} <unique_name> <sql_command>
  * unique_name = the unique name for this docker container
  * sql_command = the SQL command you want to run on the mssqldb container

  This script will run the SQL command on the mssqldb container and print the output without headers.
"
    exit -1
  fi

  # UNIQUE_NAME=$(awk '/mssqldb:/{flag=1} flag && /container_name:/{print $NF;flag=""}'  test.docker-compose.yml)
  local UNIQUE_NAME="$1"
  local COMMAND="$2"

  local DBSQLCMDOPTION="$(
    if [ "$NOTINITIALISED" = "true" ]; then
      echo ""
    else
      echo "-d db"
    fi
  )"

  # head -n -2 removes the last 2 lines (empty line + (... rows afftected) )
  # sed command removes \r (output seems to have \r\n line endings)
  exec "${UNIQUE_NAME}" /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P p@ssw0rd $DBSQLCMDOPTION -h -1 -s "	" -W -w 65535 -Q "${COMMAND}" | head -n -2 | sed 's/\r//g'
  return $?
}


function logs() {
  local UNIQUE_NAME="$1"

  getContainerLogs "${UNIQUE_NAME}"
}

function shell() {
  # echo exec $1 '/bin/bash'

  exec $1 /bin/bash
  return $?
}

################################################################################
# THE ACTUAL SCRIPT
################################################################################

COMMAND=$1

if [[ "${COMMAND}" != @(start|stop|execsql|cleanup|logs|shell|exec|waituntilupandrunning) ]]; then
  echo "
Usage: ./${SCRIPTNAME} <COMMAND> <unique_name> ...
  * COMMAND = what to do
    * start: will start a mssql db server running inside a docker container, that will be
      initialized with the contents of the context folder the very first time, or simply start
      the existing container if it already exists.
      The command will only exit when the server is up and ready to receive connections.
    * stop: will stop the mssql db server, but will leave the docker image available for later use
    * cleanup: will cleanup all related docker artifacts and reclaim disk space
    * execsql: will execute some sql on the server and return the results (if any)
    * logs: will send the docker container logs to stdout
    * shell: will start a shell inside the mssql container (can help with debugging initdb scripts)
    * exec: will execute any given command inside the mssql container (used internally by shell and execsql)
    * waituntilupandrunning: checks if the container is ready and listening for connections
  * unique_name = the name used as the basis for the Dockerfiles, the docker container etc.
    If it is not unique you might interfere with other users of the same script, so using your
    git project name could be a viable option.

  Examples:
    * imagine you want to use this in a NodeJS test suite that needs a DB.
      add this to the 'test' script inside package.json:
      \"test\": \"${SCRIPTNAME} start my_project 1433 ./docker/initdb && mocha; ${SCRIPTNAME} stop my_project\"
"
  exit -1
fi

# pass on the next arguments to the relevant function that implments the command
#   cfr. https://stackoverflow.com/a/3816747
$COMMAND "${@:2}"
