## Connect CDC pipeline

This is the KafkaConnect distributed mode architecture that we will configure to fit our use case.

```sh
             _________________________
[PgSQL] ---> | Kafka Connect         | ---> [Artemis]
             | worker0, worker1, ... |
             |_______________________|
                        |
                        |
             --------------------------
             | Kafka Cluster          |
             | offset, config, status |
             |________________________|           
```

We will run all components on localhost, but ideally each one should run in a different host (VM or container).
KafkaConnect workers operate well in containers and in managed environments.

We need a Kafka cluster up and running (3 ZooKeeper + 3 Kafka). This step also download and install all required
Connectors (debezium-connector-postgres, camel-sjms2-kafka-connector) and dependencies.

```sh
./run.sh kafka

# status check
ps -e | grep "[Q]uorumPeerMain" | wc -l
ps -e | grep "[K]afka" | wc -l
```

Now we can start our 3-nodes KafkaConnect cluster in distributed mode (workers that are configured with
matching `group.id` values automatically discover each other and form a cluster).

```sh
./run.sh connect

# status check
ps -e | grep "[C]onnectDistributed" | wc -l
tail -n100 /tmp/run.sh/kafka/logs/connect.log
/tmp/run.sh/kafka/bin/kafka-topics.sh --zookeeper localhost:2180 --list
curl localhost:7070/connector-plugins | jq
```

The infrastructure is ready, and we can finally configure our CDC pipeline.

```sh
# Debezium source task (topic name == serverName.schemaName.tableName)
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/config/connectors/dbz-source.json

# JMS sink tasks (based on SJMS2 component)
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/config/connectors/json-jms-sink.json
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/config/connectors/xml-jms-sink.json

# status check
curl -s localhost:7070/connectors | jq
curl -s localhost:7070/connectors/dbz-source/status | jq
curl -s localhost:7070/connectors/json-jms-sink/status | jq
curl -s localhost:7070/connectors/xml-jms-sink/status | jq
```

Produce some more changes and check the queues.

```sh
./run.sh stream
```

This is the change event created by Debezium connector.

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
