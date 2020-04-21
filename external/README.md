## External systems setup

Start Postgres database (the procedure depends on your specific OS).

We use a simple script to create and initialize the database.
This script can balso e used to query the table and produce a stream of changes.
```sh
./run.sh
./run.sh --database
./run.sh --query
./run.sh --stream
```

Enable Postgres internal transaction log access (required by Debezium).
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

Start Artemis broker and open the [web console](http://localhost:8161/console) to check messages.
```sh
./run.sh --artemis
```
