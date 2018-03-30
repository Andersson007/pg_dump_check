#!/bin/bash
# pg_dump_check.sh - Script restores pg dump on a standalone Postgres server
# and sends mail notification with time and cluster size statistics
#
# Author: Andrey Klychkov aaklychkov@mail.ru
# Licence: Copyleft free software
# Version: 1.0
# Date: 30-03-2018
#
# Requirements: standalone postgresql-server,
# bash, psql, pg_restore, mailx,
# run it as the 'postgres' user
#
# IMPORTANT: dump directories must be done in the 'directory' format
# and its names must be similar as 'YYYYMMDD_$DUMP_SUFFIX',
# also you should previously copy a database schema
# from your production database cluster to a recovering server
# to prevent pg_restore errors related with global objects
# like 'role "somerole" does not exist', etc 
#
# Usage: set up desired settings -> test -> add to the crontab
#
# This script have automatic rotated log files
#
# Notification's content example:
# -------------------------------
#   my-test-srv.local: pg_restore of /tmp/backup/20180329_test has been done:
#   dump_size=49M, exec_time=00:00:19, cluster_size=6.3G
#


################################
#   PARAMETERS AND VARIABLES   #
################################

# Common params:
VERSION="1.0"
HOSTNAME=$(hostname)
DATE=$(date +%Y%m%d)

# Main params:
PGBIN="/usr/pgsql-9.6/bin"
PGDATA="/var/lib/pgsql/9.6/data"
RESTOR_HOSTNAME="test125"  # You want to restore a dump
    # on this host (current hostname).
    # It must be accorded $HOSTNAME,
    # if not, exit. For prevent a disaster
    # of removing a work database
DUMP_DIR="/tmp/backup/"  # Dir that keeps dump directories
DUMP_SUFFIX="_test_db"   # Suffix of a dump directories
RECOVER_DB="test_db"     # DB name that needs to be restored
RECOVER_JOBS=1           # Number of restoring processes
PGLOG_DIR="${PGDATA}/pg_log"  # Postgresql server log dir

# Logging params:
LOG_DIR="/tmp/pg_check_log/"
LOG_PREF="pgdump_check.log_"
LOG="${LOG_DIR}/${LOG_PREF}${DATE}"
LOG_KEEP=7

# Mail params:
SEND_MAIL=1  # Set it up to 1 for sending
RECEPIENT="testmail@local"
MAIL_SBJ="${HOSTNAME}: pgdump_check.sh status"


######################
#   FUNCTION BLOCK   #
######################

function send_mail() {
    if [ ${SEND_MAIL} -eq 1 ]; then
        echo "${HOSTNAME}: $1" | mailx -s ${MAIL_SBJ} ${RECEPIENT} 2>> ${LOG}
    fi
}


function get_now_time() {
    echo $(date +%Y.%m.%d_%H:%M:%S)
}


function write_to_log() {
    echo "$(get_now_time) $1: $2" >> ${LOG}
}


function check_dir() {
    err=0
    if [ ! -d "$1" ]; then
        msg="the dir $1 does not exist. Exit"
        err=1

    elif [ ! -r "$1" ]; then
        msg="the right to read is missing. Exit"
        err=1
    fi

    if [ "${err}" -eq 1 ]; then
        write_to_log "ERROR" ${msg}
        send_mail "Error, ${msg}"
        exit 1
    fi
}


#################
#   MAIN BLOCK  #
#################

# Check that all paths exist:
check_dir ${PGDATA}
check_dir ${PGLOG_DIR}
check_dir ${DUMP_DIR}
check_dir ${LOG_DIR}


# Mark start of a job in a logfile:
write_to_log "INFO" "=Start a dump check for the ${RECOVER_DB}="

# To prevent of dropping database on a work cluster,
# $RESTORE_HOSTNAME and HOSTNAME must be the same host:
if [ "${RESTOR_HOSTNAME}" != "${HOSTNAME}" ]; then
    msg="You're trying to restore db on ${HOSTNAME}. Are you sure that it's the right server?"
    write_to_log "WARNING" "${msg}"
    send_mail "${msg}"
    exit 1
fi

# Postgres must be running:
ps aux | grep postgres | grep -v grep &> /dev/null
if [ $? -ne 0 ]; then
    msg="Postgres is not running on the host. Exit"
    write_to_log "ERROR" "${msg}"
    send_mail "${msg}"
    exit 1
fi

# If a recovered database exist, exit:
${PGBIN}/psgl ${RECOVER_DB} -c "SELECT now()" &>/dev/null
if [ $? -eq 0 ]; then
    msg="database ${RECOVER_DB} exist or this check's been impossible. Exit"
    write_to_log "ERROR" "${msg}"
    send_mail "${msg}"
    exit 1
fi

msg="${RECOVER_DB} does not exist, begin recovery"
write_to_log "INFO" "${msg}"

# Get the most recent dump dir:
dump=$(ls -d1 ${DUMP_DIR}/*${DUMP_SUFFIX}* | sort -n | tail -n 1 2>/dev/null)
if [ -z "${dump}" ]; then
    msg="a dump with the ${DUMP_SUFFIX} suffix does not exist. Exit"
    write_to_log "ERROR" "${msg}"
    send_mail "${msg}"
    exit 1
fi

write_to_log "INFO" "the most recent dump is ${dump}"

# Some stat:
start_date=$(date +%s)
dump_size=$(du -hs ${dump} | tr '[:blank:]' ' ' | cut -f1 -d' ')
write_to_log "INFO" "dump size is ${dump_size}"

# Restore a datebase:
${PGBIN}/pg_restore -F d ${dump} -j ${RECOVER_JOBS} -C -d postgres 2>> ${LOG}
if [ $? -ne 0 ]; then
    msg="pg_restore of ${dump} failed. See ${LOG} for more info"
    write_to_log "ERROR" "${msg}"
    send_mail "${msg}"
    exit 1
fi

# Check postgres logs for errors:
errors=$(grep -r "ERROR\|FATAL\|PANIC" ${PGLOG_DIR} | grep -v -i "autovacuum")
if [ "${errors}" != "" ]; then
    msg="errors was found after recovery\n\n${errors}"
    write_to_log "WARNING" "${msg}"
    send_mail "${msg}"
fi

# Stat again:
end_date=$(date +%s)
exec_time=$(date -u -d "0 ${end_date} seconds - ${start_date} seconds" +"%H:%M:%S")
cluster_size=$(du -hs ${PGDATA} | tr '[:blank:]' ' ' | cut -f1 -d' ')

# Generate the main stat report:
msg="pg_restore of ${dump} has been done: "\
"dump_dize=${dump_size}, exec_time=${exec_time}, cluster_size=${cluster_size}"
write_to_log "INFO" "${msg}"

# Send the report:
send_mail "${msg}"

# Drop database:
${PGBIN}/psql -t -c "DROP DATABASE ${RECOVER_DB};" 1> /dev/null 2>> ${LOG}
if [ $? -ne 0 ]; then
    msg="dropping of ${RECOVER_DB} failed. See ${LOG} for more info"
    write_to_log "ERROR" "${msg}"
    send_mail "${msg}"
    exit 1
else
    write_to_log "INFO" "database has been dropped"
fi

write_to_log "INFO" "=Recovery is done="

# Remove old logs:
ls -1 ${LOG_DIR}/${LOG_PREF}* | sort -n | head -n-${LOG_KEEP} |\
while read line; do
	rm -rf ${line}
done

exit 0
