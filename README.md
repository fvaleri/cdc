# CDC with Camel and Debezium

Change Data Capture (CDC) is a well-established software design pattern for a system that monitors and captures data changes, so that other software can respond to those events. Using a log-based CDC engine like [Debezium](https://debezium.io) we can easily build data pipelines to bridge traditional data stores and new event-driven architectures (EDA). Debezium captures data changes directly from the internal data store's write ahead log (WAL).

The main advantages of a log-based CDC process over a poll-based one are:

- **Low overhead**: near real-time reaction to data changes avoids increased CPU load due to frequent polling.
- **No lost changes**: using a poll loop you may miss intermediary changes (updates, deletes) between two runs.
- **No data model impact**: no need for timestamp columns to determine the last update of data.

There are two main approaches for building CDC pipelines with Debezium:

1. **Code-driven** using plain Camel routes with no Kafka dependency.
2. **Configuration-driven** using a KafkaConnect cluster with its connectors.

While KafkaConnect provides some Connectors for zero or low coding integrations, Camel's extensive collection of Components (300+) allows you to connect to all kinds of external systems. Thanks to a new sub-project called CamelKafkaConnector they can also be used as Connectors.

## Pipeline implementations

Enable TX log access and start Postgres external source system.

```
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

```
./run.sh artemis

# status check
ps -ef | grep "[A]rtemis" | wc -l

# login: admin/admin
open http://localhost:8161/console
```

The requirement is to stream all customer changes from a source table to XML and JSON sink queues:

- [Camel CDC pipeline (code-driven)](./camel-cdc)
- [Connect CDC pipeline (configuration-driven)](./connect-cdc)

Bonus: the same Connect pipeline can also be deployed on OpenShift: 

- [Cloud-native CDC pipeline (OpenShift)](./openshift)

## Final considerations

Both CDC approaches are valid but, depending on your experience, you may find one of them more convenient. No matter what technology you use, the CDC process must run as single thread to maintain ordering. Since Debezium records the log offset asynchronously, any final consumer of these changes must be idempotent.

If you already have a Kafka cluster, two implicit benefits of using KafkaConnect in distributed mode are that you have a fault tolerant CDC process, and you can easily rebuild the application state if needed. One thing to be aware of is that Debezium offers better performance because it reads changes directly from the internal transaction log, but there is no standard for it, so an implementation change may require a rewrite of the corresponding plugin. This also means that every data source has its own procedure to enable access to its transaction log.

Connectors configuration allows you to transform message payload by using Single Message Transformations (SMTs). They can be chained and extended with custom implementations, but they are actually designed for simple modifications and long chains of SMTs are hard to maintain and reason about. Moreover, transformations are synchronous and applied on each message, so you can really slow down the streaming pipeline with heavy processing or external service calls.

In cases where you need to do heavy processing, split, enrich, aggregate records or call external services, you should use a stream processing layer between Connectors such as Kafka Streams or plain Camel. Just remember that Kafka Streams creates internal topics, and you are forced to put transformed data back into Kafka (data duplication), while this is just an option using Camel.
