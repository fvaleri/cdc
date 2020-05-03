# CDC with Camel and Debezium

Change Data Capture (CDC) is a well-established software design pattern for a system that monitors and captures
the changes in data, so that other software can respond to those changes.

Using a CDC engine like [Debezium](https://debezium.io) along with [Camel](https://camel.apache.org) integration
framework, we can easily build data pipelines to bridge traditional data stores and new cloud-native event-driven
architectures.

The advantages of CDC comparing to a simple poll-based or query-based process are:

- *All changes captured*: intermediary changes (updates, deletes) between two runs of the poll loop may be missed.
- *Low overhead*: near real-time reaction to data changes avoids increased CPU load due to frequent polling.
- *No data model impact*: timestamp columns to determine the last update of data are not needed.

There are two main aproaches for building a CDC pipeline:

The first approach is *configuration-driven* and runs on top of [KafkaConnect](https://kafka.apache.org/documentation/#connect),
the streaming integration platform based on Kafka. The second approach is *code-driven* and it is purely implemented with Camel
(no Kafka dependency).

While KafkaConnect provides some *Connectors* for zero or low coding integrations, Camel's extensive collection of *Components*
(300+) enables you to connect to all kinds of external systems. The great news is that these Components can now be used as
Connectors thanks to a new sub-project called *CamelKafkaConnect* (will use the SJMS2 as an example).

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

Prerequisites: Postgres 11, OpenJDK 1.8 and Maven 3.5+.

- [External systems setup](./external/README.md)
- [KafkaConnect CDC pipeline](./connect-cdc/README.md)
- [Camel CDC pipeline](./camel-cdc/README.md)

## Considerations

Both CDC solutions are perfectly valid but, depending on your experience, you may find one of them more convenient.
If you already have a Kafka cluster, an implicit benefit of using KafkaConnect is that it stores the whole change log
in a topic, so you can easily rebuild the application state if needed.

Another benefit of running on top of KafkaConnect in  distributed mode is that you have a fault tolerant CDC process.
It is possible to achieve the same by running the Camel process as
[clustered singleton service](https://www.nicolaferraro.me/2017/10/17/creating-clustered-singleton-services-on-kubernetes)
on top of Kubernetes.

One thing to be aware of is that Debezium offers better performance because of the access to the internal transaction log,
but there is no standard for it, so a change to the database implementation may require a rewrite of the corresponding plugin.
This also means that every data source has its own procedure to enable access to its internal log.

KafkaConnect single message transformations (SMTs) can be chained (sort of Unix pipeline) and extended with custom implementations,
but they are actually designed for simple modifications. Long chains of SMTs are hard to maintain and reason about. Moreover, remember
that tranformations are syncronous and applied at each message, so you can really slowdown the streaming pipeline with heavy processing
or external service calls.

In cases where you need to do heavy processing, split, enrich, aggregate records or call external services, you should use a stream
processing layer between Connectors such as Kafka Streams or Camel. Just remember that Kafka Streams creates internal topics and you
are forced to put transformed data back into some Kafka topic (data duplication), while this is just an option using Camel.
