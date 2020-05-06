## External systems setup

Enable transaction log access and start Postgres.
```sh
# postgresql.conf: configure replication slot
wal_level = logical
max_wal_senders = 1
max_replication_slots = 1
# pg_hba.conf: allow localhost replication to user
local   cdcdb       cdcadmin                                trust
host    cdcdb       cdcadmin        127.0.0.1/32            trust
host    cdcdb       cdcadmin        ::1/128                 trust
```

There is a simple script to create and initialize the database.
This script can also be used to query the table and produce a stream of changes.
```sh
./run.sh --database
./run.sh --query
./run.sh --stream
```

Then, start Artemis broker and open the [web console](http://localhost:8161/console) (login: admin/admin).
```sh
./run.sh --artemis
# check status
ps -ef | grep "[A]rtemis" | wc -l
```
