#!/bin/sh
set -e

ARTEMIS_URL="https://downloads.apache.org/activemq/activemq-artemis/2.11.0/apache-artemis-2.11.0-bin.tar.gz"
ARTEMIS_HOME="/tmp/artemis"

KAFKA_URL="https://downloads.apache.org/kafka/2.5.0/kafka_2.12-2.5.0.tgz"
KAFKA_HOME="/tmp/kafka"
DEBEZIUM_URL="https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/1.1.0.Final/debezium-connector-postgres-1.1.0.Final-plugin.tar.gz"
PLUGINS_HOME="$KAFKA_HOME/plugins"
CONNECT_URL="http://localhost:7070"

create_db() {
    echo "Database provisioning"
    createdb -T template0 -E UTF8 --lc-collate=en_US --lc-ctype=en_US cdcdb;
    psql cdcdb -f ./external/schema.sql
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
    echo "Broker provisioning"
    rm -rf $ARTEMIS_HOME && mkdir -p $ARTEMIS_HOME
    curl -s $ARTEMIS_URL | tar xz -C $ARTEMIS_HOME --strip-components 1
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
    curl -s $KAFKA_URL | tar xz -C $KAFKA_HOME --strip-components 1

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

    # debezium postgres connector
    mkdir -p $PLUGINS_HOME
    curl -s $DEBEZIUM_URL | tar xz -C $PLUGINS_HOME
    echo "Done"
}

start_connect() {
    echo "Connect provisioning"
    for node in {0,1,2}; do
        eval "echo \"$(<./external/templates/connect.properties)\"" >$KAFKA_HOME/config/connect-$node.properties
        $KAFKA_HOME/bin/connect-distributed.sh -daemon $KAFKA_HOME/config/connect-$node.properties
    done
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
"
case $1 in
    -d|--database) create_db;;
    -s|--stream) stream_changes;;
    -q|--query) query_table;;
    -a|--artemis) start_artemis;;
    -k|--kafka) start_kafka;;
    -c|--connect) start_connect;;
    *) echo "$USAGE"
esac
