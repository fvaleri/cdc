## [<<](/README.md) Connect CDC process

This is the KafkaConnect distributed mode architecture that we will configure to fit our use case.
```
SourceConnector --> KafkaConnectDM [Worker0JVM(TaskA0, TaskB0, TaskB1),...] --> SinkConnector
                                |
                    Kafka (offsets, config, status)
```

We will run all components on localhost, but ideally each one should run in a different host (physical, VM or container).
Connect workers operate well in containers and in managed environments. Take a look at the [Strimzi CNCF project](https://strimzi.io)
if you want to know how to easily operate Kafka and KafkaConnect on Kubernetes platform.

First define some handy environment variables.
```sh
CONNECT_BASE="/tmp/cdc/connect"
KAFKA_URL="https://downloads.apache.org/kafka/2.5.0/kafka_2.12-2.5.0.tgz"
KAFKA_HOME="$CONNECT_BASE/kafka-home"
DBZ_PLUGIN_URL="https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/1.1.0.Final/debezium-connector-postgres-1.1.0.Final-plugin.tar.gz"
PLUGINS_HOME="$KAFKA_HOME/plugins"
CONNECT_URL="http://localhost:7070"
```

We need a 3-nodes Kafka cluster up and running.
```sh
mkdir -p $KAFKA_HOME
curl -s $KAFKA_URL | tar xz -C $KAFKA_HOME --strip-components 1

# run ZooKeeper 3-nodes cluster
for node in {0,1,2}; do
cat <<EOF > $KAFKA_HOME/config/zookeeper-$node.properties
dataDir=$CONNECT_BASE/zookeeper-$node
clientPort=218$node
maxClientsCnxns=0
4lw.commands.whitelist=stat,dump

timeTick=2000
initLimit=5
syncLimit=2

server.0=localhost:2888:3888
server.1=localhost:2889:3889
server.2=localhost:2890:3890
EOF
mkdir -p $CONNECT_BASE/zookeeper-$node
echo "$node" > $CONNECT_BASE/zookeeper-$node/myid
$KAFKA_HOME/bin/zookeeper-server-start.sh -daemon $KAFKA_HOME/config/zookeeper-$node.properties
done
# status check
ps -ef | grep "[z]ookeeper-..properties" | wc -l
echo stat | ncat localhost 2180

# run Kafka 3-nodes cluster
for node in {0,1,2}; do
cat <<EOF > $KAFKA_HOME/config/kafka-$node.properties
broker.id=$node
listeners=PLAINTEXT://:909$node
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dir=$CONNECT_BASE/kafka-$node
num.partitions=1
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=localhost:2180,localhost:2181,localhost:2182
zookeeper.connection.timeout.ms=6000
group.initial.rebalance.delay.ms=0
EOF
mkdir -p $CONNECT_BASE/kafka-$node
$KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/kafka-$node.properties
done
# status check
ps -ef | grep "[k]afka-..properties" | wc -l
echo dump | ncat localhost 2180
```

We also need to install DebeziumPostgresConnector and JmsSinkConnector plugins.
```sh
# debezium
mkdir -p $PLUGINS_HOME
curl -s $DBZ_PLUGIN_URL | tar xz -C $PLUGINS_HOME
# download jms connector from https://docs.confluent.io/current/connect/kafka-connect-jms/sink/#actvemq-quick-start
mkdir -p $PLUGINS_HOME/jms-sink-connector
mv -R $CONNECTOR_FOLDER/* $PLUGINS_HOME/jms-sink-connector/
mvn dependency:get -Ddest=$PLUGINS_HOME/jms-sink-connector/lib -Dartifact=org.apache.activemq:activemq-all:5.15.4
```

Now we can start our 3-nodes KafkaConnect cluster in distributed mode (workers that are configured with matching `group.id`
values automatically discover each other and form a cluster). We use JSON serialization format for all connectors to keep
the configuration simple, but using a binary format like Avro or Protobuf, along with a SchemaRegistry, you can get better
performance and enforce a contract between your services.
```sh
for node in {0,1,2}; do
cat <<EOF > $KAFKA_HOME/config/connect-$node.properties
bootstrap.servers=localhost:9090,localhost:9091,localhost:9092
key.converter=org.apache.kafka.connect.storage.StringConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable=false
rest.host.name=localhost
rest.port=707$node
plugin.path=$PLUGINS_HOME
group.id=my-connect
config.storage.topic=my-connect-configs
offset.storage.topic=my-connect-offsets
status.storage.topic=my-connect-status
EOF
$KAFKA_HOME/bin/connect-distributed.sh -daemon $KAFKA_HOME/config/connect-$node.properties
done
# status check
ps -ef | grep "[c]onnect-..properties" | wc -l
tail -n100 $KAFKA_HOME/logs/connect.log
$KAFKA_HOME/bin/kafka-topics.sh --zookeeper localhost:2180 --list
curl $CONNECT_URL/connector-plugins | jq
```

The infrastructure is now ready and we can configure our CDC pipeline.
```sh
# postgres source task (topic name = serverName.schemaName.tableName)
curl -sX POST -H "Content-Type: application/json" $CONNECT_URL/connectors -d @connect-cdc/src/main/connectors/dbz-source.json

# compile our custom SMTs and copy the fat JAR to the plugin path
mvn clean package -f connect-cdc/pom.xml
cp connect-cdc/target/connect-cdc-1.0.0-SNAPSHOT.jar $KAFKA_HOME/plugins

# file sink connector tasks
curl -sX POST -H "Content-Type: application/json" $CONNECT_URL/connectors -d @connect-cdc/src/main/connectors/json-jms-sink.json
curl -sX POST -H "Content-Type: application/json" $CONNECT_URL/connectors -d @connect-cdc/src/main/connectors/xml-jms-sink.json

# status check
curl -s $CONNECT_URL/connectors | jq
curl -s $CONNECT_URL/connectors/dbz-source/status | jq
```

This is the change event produced by Debezium:
```sh
$KAFKA_HOME/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9090 \
    --from-beginning \
    --topic localhost.cdc.customers \s
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
