# CDC with Camel and Debezium

Change Data Capture (CDC) is a well-established software design pattern for a system that monitors and captures data changes, so that other software can respond to those events.
Using a log-based CDC engine like [Debezium](https://debezium.io) we can easily build data pipelines to bridge traditional data stores with Apache Kafka.
Debezium captures data changes directly from the internal data store's write ahead log (WAL).

The main advantages of a log-based CDC process over a poll-based one are:

- Low overhead: near real-time reaction to data changes avoids increased CPU load due to frequent polling.
- No lost changes: using a poll loop you may miss intermediary changes (updates, deletes) between two runs.
- No data model impact: no need for timestamp columns to determine the last update of data.

There are two main approaches for building CDC pipelines with Debezium:

1. Code-driven using plain Apache Camel routes with no Kafka dependency.
2. Configuration-driven using a Kafka Connect cluster with its connectors.

While Kafka Connect provides some connectors for zero or low coding integrations, Camel's extensive collection of components (300+) allows you to connect to all kinds of external systems.
Thanks to a new sub-project called Camel Kafka Connector they can also be used as connectors.

## Pipeline implementations

Enable TX log access and start Postgres external source system.

```sh
# postgresql.conf: configure replication slot with pgoutput decoding pulgin
wal_level = logical
max_wal_senders = 4
max_replication_slots = 4

# pg_hba.conf: allow localhost replication to user
local   cdcdb       cdcadmin                                trust
host    cdcdb       cdcadmin        127.0.0.1/32            trust
host    cdcdb       cdcadmin        ::1/128                 trust

# database init
./run.sh init
./run.sh query
./run.sh stream
```

Start Artemis external sink system.

```sh
./run.sh artemis

# status check
ps -ef | grep "[A]rtemis" | wc -l

# login: admin/admin
open http://localhost:8161/console
```

The requirement is to stream all customer changes from a source table to XML and JSON sink queues:

- [Camel CDC pipeline (code-driven)](./camel-cdc)
- [Connect CDC pipeline (configuration-driven)](./connect-cdc)

Bonus: a similar Kafka Connect pipeline can also be deployed on OpenShift:

- [Cloud-native CDC pipeline (OpenShift)](./openshift)
