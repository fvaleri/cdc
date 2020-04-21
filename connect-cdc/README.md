## Connect CDC process

This is the KafkaConnect distributed mode architecture that we will configure to fit our use case.
```
SourceConnector --> KafkaConnectDM [Worker0JVM(TaskA0, TaskB0, TaskB1),...] --> SinkConnector
                                |
                    Kafka (offsets, config, status)
```

We will run all components on localhost, but ideally each one should run in a different host (physical, VM or container).
Connect workers operate well in containers and in managed environments. Take a look at the [Strimzi](https://strimzi.io)
project if you want to know how to easily operate Kafka and KafkaConnect on Kubernetes platform.

We need a Kafka cluster up and running (3 ZooKeeper + 3 Kafka).
```sh
./run.sh --kafka
# status check
ps -ef | grep "[Q]uorumPeerMain" | wc -l
ps -ef | grep "[K]afka" | wc -l
```

DebeziumPostgresConnector was installed by the previous step, but we also need to
manually install the JmsSinkConnector and our custom SMTs to format the sink output.
```sh
# download JmsSinkConnector from https://www.confluent.io/hub/confluentinc/kafka-connect-jms-sink
mkdir -p /tmp/kafka/plugins/jms-sink-connector
cp -R $FOLDER/lib/*.jar /tmp/kafka/plugins/jms-sink-connector/
mvn dependency:get -Ddest=/tmp/kafka/plugins/jms-sink-connector/ -Dartifact=org.apache.activemq:activemq-all:5.15.4
# compile and deploy custom SMTs as fat JAR
mvn clean package -f ./connect-cdc/pom.xml
cp connect-cdc/target/connect-cdc-1.0.0-SNAPSHOT.jar /tmp/kafka/plugins/jms-sink-connector/
```

Now we can start our 3-nodes KafkaConnect cluster in distributed mode (workers that are configured with matching `group.id`
values automatically discover each other and form a cluster). We use JSON serialization format for all connectors to keep
the configuration simple, but using a binary format like Avro or Protobuf, along with a SchemaRegistry, you can get better
performance and enforce a contract between your services.
```sh
./run.sh --connect
# status check
ps -ef | grep "[C]onnectDistributed" | wc -l
tail -n100 /tmp/kafka/logs/connect.log
/tmp/kafka/bin/kafka-topics.sh --zookeeper localhost:2180 --list
curl localhost:7070/connector-plugins | jq
```

The infrastructure is ready and we can finally configure our CDC pipeline.
```sh
# postgres source task (topic name == serverName.schemaName.tableName)
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/dbz-source.json

# file sink connector tasks
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/json-jms-sink.json
curl -sX POST -H "Content-Type: application/json" localhost:7070/connectors -d @connect-cdc/src/main/connectors/xml-jms-sink.json

# status check
curl -s localhost:7070/connectors | jq
curl -s localhost:7070/connectors/dbz-source/status | jq
```

Produce some more changes and check the queues.
```sh
./run.sh --stream
```

This is the change event produced by Debezium.
```sh
/tmp/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9090 \
    --from-beginning \
    --topic localhost.cdc.customers \
    --max-messages 1 | jq
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
