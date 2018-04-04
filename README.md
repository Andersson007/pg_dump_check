# pg_dump_check

Script restores a pg dump on a standalone Postgres server and sends mail notification with time and cluster size statistics

Also this script have automatic rotated log files (see the "Logging params" setting block)

Author: Andrey Klychkov aaklychkov@mail.ru

Licence: Copyleft free software

Version: 1.0

Date: 30-03-2018

Requirements: bash, standalone postgresql-server, psql, pg_restore, mailx,
run it as the 'postgres' user

IMPORTANT: dump directories must be done in the 'directory' format and its names must be similar as 'YYYYMMDD_$DUMP_SUFFIX', also you should copy a database schema from your production database cluster to a recovering server to prevent pg_restore errors related with global objects like 'role "somerole" does not exist', etc

Usage: set up desired settings -> test it -> add to the crontab

Notification content example:
```
my-test-srv.local: pg_restore of /tmp/backup/20180329_test has been done:
dump_size=49M, exec_time=00:00:19, cluster_size=6.3G
```
