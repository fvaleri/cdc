## [<<](/README.md) Postgres setup

This configuration is required by Debezium and it is specific to *Postgres* (tested on v11).

We use a simple script to create and initialize the source database.
The same script can be used to query the table and produce a stream of changes.
```sh
# create the database
resources/run.sh create_db

# produce a stream of changes (Ctrl+C to stop)
resources/run.sh stream_changes

# check table's content
resources/run.sh check_table
```

Apply the following changes to enable database internal transaction log access.
```sh
# postgresql.conf: configure replication slot
wal_level = logical
max_wal_senders = 1
max_replication_slots = 1
# pg_hba.conf: allow localhost replication to debezium user
local   replication     cdcadmin                            trust
host    replication     cdcadmin    127.0.0.1/32            trust
host    replication     cdcadmin    ::1/128                 trust
# add replication permission to user and enable previous values
psql cdcdb
ALTER ROLE cdcadmin WITH REPLICATION;
ALTER TABLE cdc.customers REPLICA IDENTITY FULL;
# restart Postgres
```
