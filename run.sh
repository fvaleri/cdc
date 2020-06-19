#!/bin/sh
set -e

TMP="/tmp/cdc"

ARTEMIS_HOME="$TMP/artemis"
ARTEMIS_URL="https://archive.apache.org/dist/activemq/activemq-artemis/2.13.0/apache-artemis-2.13.0-bin.tar.gz"

KAFKA_HOME="$TMP/kafka"
KAFKA_URL="https://archive.apache.org/dist/kafka/2.5.0/kafka_2.12-2.5.0.tgz"

CONNECT_URL="http://localhost:7070"
CONNECTOR_URLS=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/1.2.0.Final/debezium-connector-postgres-1.2.0.Final-plugin.zip"
    "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/0.3.0/camel-sjms2-kafka-connector-0.3.0-package.zip"
)

create_db() {
    echo "Postgres provisioning"
    psql template1 -f ./external/initdb.sql
    echo "Done"
}

stream_changes() {
    watch -n1 "psql cdcdb -U cdcadmin -c \
        \"INSERT INTO cdc.customers (first_name, last_name, email) \
        VALUES (md5(random()::text), md5(random()::text), md5(random()::text)||'@example.com')\""
}

query_table() {
    psql cdcdb -U cdcadmin -c "SELECT * FROM cdc.customers"
}

start_artemis() {
    echo "Artemis provisioning"
    rm -rf $ARTEMIS_HOME && mkdir -p $ARTEMIS_HOME
    curl -sL $ARTEMIS_URL | tar xz -C $ARTEMIS_HOME --strip-components 1
    $ARTEMIS_HOME/bin/artemis create $ARTEMIS_HOME/instance --name instance --user admin --password admin --require-login
    $ARTEMIS_HOME/instance/bin/artemis-service start
    sleep 5
    $ARTEMIS_HOME/instance/bin/artemis queue create --user admin --password admin --name CustomersJSON --auto-create-address --anycast --durable --silent
    $ARTEMIS_HOME/instance/bin/artemis queue create --user admin --password admin --name CustomersXML --auto-create-address --anycast --durable --silent
    echo "Done"
}

start_kafka() {
    echo "Kafka provisioning"
    rm -rf $KAFKA_HOME && mkdir -p $KAFKA_HOME
    curl -sL $KAFKA_URL | tar xz -C $KAFKA_HOME --strip-components 1

    # zookeeper cluster
    for node in {0,1,2}; do
        eval "echo \"$(<./external/templates/zookeeper.properties)\"" >$KAFKA_HOME/config/zookeeper-$node.properties
        mkdir -p $KAFKA_HOME/zookeeper-$node
        echo "$node" > $KAFKA_HOME/zookeeper-$node/myid
        $KAFKA_HOME/bin/zookeeper-server-start.sh -daemon $KAFKA_HOME/config/zookeeper-$node.properties
    done

    # kafka cluster
    sleep 5
    for node in {0,1,2}; do
        eval "echo \"$(<./external/templates/kafka.properties)\"" >$KAFKA_HOME/config/kafka-$node.properties
        mkdir -p $KAFKA_HOME/kafka-$node
        $KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/kafka-$node.properties
    done
    echo "Done"
}

start_connect() {
    echo "Connect provisioning"
    local connectors="$TMP/connectors" && mkdir -p $connectors
    for url in "${CONNECTOR_URLS[@]}"; do
        curl -sL $url -o $connectors/file.zip && unzip -qq $connectors/file.zip -d $connectors
    done
    sleep 2
    rm -rf $connectors/file.zip

    # custom SMTs as fat JAR
    mvn clean package -f ./connect-cdc/pom.xml
    cp ./connect-cdc/target/connect-cdc-*.jar $connectors

    # connect cluster
    for node in {0,1,2}; do
        eval "echo \"$(<./external/templates/connect.properties)\"" >$KAFKA_HOME/config/connect-$node.properties
        $KAFKA_HOME/bin/connect-distributed.sh -daemon $KAFKA_HOME/config/connect-$node.properties
    done
    echo "Done"
}

stop_cleanup() {
    echo "Stopping all processes"
    ps -ef | grep 'ConnectDistributed' | grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | grep 'Kafka' | grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | grep 'QuorumPeerMain' | grep -v grep | awk '{print $2}' | xargs kill -9
    ps -ef | grep 'Artemis' | grep -v grep | awk '{print $2}' | xargs kill -9
    rm -rf $TMP /tmp/offset.dat
    echo "Done"
}

USAGE="
Usage: ./$(basename $0) [OPTIONS]

Options:
  -d, --database        Create the database (Postgres must be up)
  -s, --stream          Produce a stream of changes (Ctrl+C to stop)
  -q, --query           Query table's content
  -a, --artemis         Start Artemis broker
  -k, --kafka           Start Kafka cluster
  -c, --connect         Start KafkaConnect cluster
  -x, --stop            Stop all and cleanup
"
case "$1" in
    -d|--database) create_db;;
    -s|--stream) stream_changes;;
    -q|--query) query_table;;
    -a|--artemis) start_artemis;;
    -k|--kafka) start_kafka;;
    -c|--connect) start_connect;;
    -x|--stop) stop_cleanup;;
    *) echo "$USAGE";;
esac
