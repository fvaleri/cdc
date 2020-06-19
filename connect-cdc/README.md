## Connect CDC pipeline

This is the KafkaConnect distributed mode architecture that we will configure to fit our use case.
```
Postgres --> KafkaConnect [Worker0JVM(TaskA0, TaskB0, TaskB1),...] --> Artemis
                                |
                    Kafka (offsets, config, status)
```

We will run all components on localhost, but ideally each one should run in a different host (physical, VM or container).
Connect workers operate well in containers and in managed environments. Take a look at the [Strimzi](https://strimzi.io)
project if you want to know how to easily operate Kafka and KafkaConnect on Kubernetes platform.

We need a Kafka cluster up and running (3 ZooKeeper + 3 Kafka). This step also download and install all required Connectors
(`debezium-connector-postgres`, `camel-sjms2-kafka-connector`) and dependencies.
```sh
./run.sh --kafka
# status check
ps -ef | grep "[Q]uorumPeerMain" | wc -l
ps -ef | grep "[K]afka" | wc -l
```

Now we can start our 3-nodes KafkaConnect cluster in distributed mode (workers that are configured with matching `group.id`
values automatically discover each other and form a cluster).
```sh
./run.sh --connect
# status check
ps -ef | grep "[C]onnectDistributed" | wc -l
tail -n100 /tmp/cdc/kafka/logs/connect.log
/tmp/cdc/kafka/bin/kafka-topics.sh --zookeeper localhost:2180 --list
curl localhost:7070/connector-plugins | jq
```

The infrastructure is ready and we can finally configure our CDC pipeline.
```sh
# debezium source task (topic name == serverName.schemaName.tableName)
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/dbz-source.json

# jms sink tasks (powered by sjms2 component)
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/json-jms-sink.json
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/xml-jms-sink.json

# status check
curl -s localhost:7070/connectors | jq
curl -s localhost:7070/connectors/dbz-source/status | jq
curl -s localhost:7070/connectors/json-jms-sink/status | jq
curl -s localhost:7070/connectors/xml-jms-sink/status | jq
```

Produce some more changes and check the queues.
```sh
./run.sh --stream
```

This is the change event produced by Debezium.
```sh
{
  "payload": {
    "before": null,
    "after": {
      "id": 1,
      "first_name": "7b789a503dc96805dc9f3dabbc97073b",
      "last_name": "8428d131d60d785175954712742994fa",
      "email": "68d0a7ccbd412aa4c1304f335b0edee8@example.com"
    },
    "source": {
      "version": "1.1.0.Final",
      "connector": "postgresql",
      "name": "localhost",
      "ts_ms": 1587303655422,
      "snapshot": "true",
      "db": "cdcdb",
      "schema": "cdc",
      "table": "customers",
      "txId": 2476,
      "lsn": 40512632,
      "xmin": null
    },
    "op": "c",
    "ts_ms": 1587303655424,
    "transaction": null
  }
}
```
