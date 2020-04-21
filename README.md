# CDC experiment

This is an experiment for testing two approaches of doing Change Data Capture (CDC) with [Debezium](https://debezium.io).
A CDC process implements an end-to-end pipeline for change streaming from a data source to one or more data sinks.
The main advantages comparing to a simple poll-based or query-based process are:

- *All changes captured*: polling may miss intermediary data changes (updates, deletes) between two runs of the poll loop.
- *Low overhead*: the engine react to data changes in near real-time, avoiding increased CPU load due to frequent polling.
- *No data model impact*: you don't need timestamp columns to determine the last update of data.

The 1st approach is configuration-driven and runs on top of
[KafkaConnect streaming integration platform](https://kafka.apache.org/documentation/#connect).
The 2nd approach is code-driven and it is implemented with [Camel integration framework](https://camel.apache.org),
recently optimized for cloud-native environments.

Why KafkaConnect? Because it is based on *Kafka*, the open source streaming data platform powering some of the most
successful event-driven architectures out there (i.e. Linkedin: 7 trillion messages/day, Netflix: 6 Petabytes/day).
It includes a collection of configurable source/sink *Connectors* for zero or low coding integrations.

Why Camel? Because it includes a rich DSL to declaratively create integration pipelines based on the well-known
enterprise integration patterns (EIPs) and a rich set of *Components* for connecting to almost all external systems
(now you can also use most of them as Connectors thanks to a new sub-projct called CamelKafkaConnect).

## Use case

We want to focus on the technology, so the use case is relatively simple, but includes both routing and transformation logic.
The requirement is to stream all new customers from a source table to XML and JSON sink queues.
```
                                     |---> (xml-sink-queue)
(source-table) ---> [cdc-process] ---|
                                     |---> (json-sink-queue)
```

## Implementations

No matter what technology you use, the CDC process must run as a single thread to maintain ordering.
Since Debezium records the log offset asyncronously, any final consumer of these changes must be idempotent.

Important change event properties: `lsn` (offset) is the log sequence number that tracks the position in the database
WAL (write ahead log), `txId` represents the identifier of the server transaction which caused the event, `ts_ms`
represents the number of microseconds since Unix Epoch as the server time at which the transaction was committed.

- [PostgreSQL setup (prerequisite)](./resources/postgres.md)
- [Artemis setup (prerequisite)](./resources/artemis.md)
- [KafkaConnect CDC pipeline](./resources/connect.md)
- [Camel CDC pipeline](./resources/camel.md)

## Considerations

Both CDC solutions are perfectly valid but, depending on your experience, you may find one of them more convenient.
If you already have a Kafka cluster, an implicit benefit of using KafkaConnect is that it stores the whole change log
in a topic, so that you can easily rebuild the application state if needed.

Another benefit of running on top of KafkaConnect in  distributed mode is that you have a fault tolerant CDC process.
It is possible to achieve the same by running the Camel process as
[clustered singleton service](https://www.nicolaferraro.me/2017/10/17/creating-clustered-singleton-services-on-kubernetes).
on top of Kubernetes.

One thing to be aware of is that Debezium offers better performance because of the access to the internal transaction log,
but there is no standard for it, so a change to the database implementation may require a rewrite of the corresponding plugin.
This also means that every data source has its own procedure to enable access to its internal log.

KafkaConnect single message transformations (SMTs) can be chained (sort of unix pipeline) and extended with custom implementations,
but they are actually designed for simple modifications. Long chains of SMT (transformation stages) are hard to maintain and reason
about. Moreover, remember that tranformations are syncronous and applied at each message, so you can really slowdown the streaming
pipeline with heavy processing or external service calls.

In cases where you need to do heavy processing, split, enrich, aggregate records or call external services, you should use a stream
processing layer between Connectors such as Kafka Streams or Camel. Remember that Kafka Streams creates internal topics and you are
forced to put transformed data back into some Kafka topic (data duplication), while this is just an option using Camel.
