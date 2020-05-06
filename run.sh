#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $(uname -s) == "Darwin" ]]; then
    shopt -s expand_aliases
    alias rm="grm"
    alias echo="gecho"
    alias dirname="gdirname"
    alias grep="ggrep"
    alias readlink="greadlink"
    alias tar="gtar"
    alias sed="gsed"
    alias date="gdate"
fi
__TMP="/tmp/cdc" && readonly __TMP && mkdir -p $__TMP
__HOME="" && pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" >/dev/null \
    && { __HOME=$PWD; popd >/dev/null; } && readonly __HOME

__error() {
    echo "$@" 1>&2
    exit 1
}

db_init() {
    psql template1 -f $__HOME/initdb.sql
}

db_query() {
    psql cdcdb -U cdcadmin -c "SELECT * FROM cdc.customers"
}

db_stream() {
    watch -n1 "psql cdcdb -U cdcadmin -c \
        \"INSERT INTO cdc.customers (first_name, last_name, email) \
        VALUES (md5(random()::text), md5(random()::text), md5(random()::text)||'@example.com')\""
}

artemis() {
    local version="2.16.0"
    local artemis_home="$__TMP/artemis"
    local artemis_url="https://archive.apache.org/dist/activemq/activemq-artemis/$version/apache-artemis-$version-bin.tar.gz"
    rm -rf $artemis_home && mkdir -p $artemis_home
    curl -sL $artemis_url | tar xz -C $artemis_home --strip-components 1
    $artemis_home/bin/artemis create $artemis_home/instance --name instance --user admin --password admin --require-login
    $artemis_home/instance/bin/artemis-service start
    sleep 5
    $artemis_home/instance/bin/artemis queue create --user admin --password admin --name CustomersJSON --auto-create-address --anycast --durable --silent
    $artemis_home/instance/bin/artemis queue create --user admin --password admin --name CustomersXML --auto-create-address --anycast --durable --silent
}

kafka() {
    local version="2.7.0"
    local kafka_home="$__TMP/kafka"
    export KAFKA_HOME=$kafka_home
    local kafka_url="https://archive.apache.org/dist/kafka/$version/kafka_2.13-$version.tgz"
    rm -rf $kafka_home && mkdir -p $kafka_home
    curl -sL $kafka_url | tar xz -C $kafka_home --strip-components 1
    # zookeeper cluster
    for node in {0,1,2}; do
        eval "echo \"$(<"$__HOME"/connect-cdc/config/templates/zookeeper.properties)\"" >$kafka_home/config/zookeeper-$node.properties
        mkdir -p $kafka_home/zookeeper-$node
        echo "$node" > $kafka_home/zookeeper-$node/myid
        $kafka_home/bin/zookeeper-server-start.sh -daemon $kafka_home/config/zookeeper-$node.properties
    done
    # kafka cluster
    sleep 5
    for node in {0,1,2}; do
        eval "echo \"$(<"$__HOME"/connect-cdc/config/templates/kafka.properties)\"" >$kafka_home/config/kafka-$node.properties
        mkdir -p $kafka_home/kafka-$node
        $kafka_home/bin/kafka-server-start.sh -daemon $kafka_home/config/kafka-$node.properties
    done
}

connect() {
    local version_dbz="1.4.0.Final"
    local version_kck="0.7.0"
    local kafka_home="$__TMP/kafka"
    export KAFKA_HOME=$kafka_home
    local connect_plugins=(
        "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/$version_dbz/debezium-connector-postgres-$version_dbz-plugin.zip"
        "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/$version_kck/camel-sjms2-kafka-connector-$version_kck-package.zip"
    )
    local plugins="$__TMP/plugins" && mkdir -p $plugins
    for url in "${connect_plugins[@]}"; do
        curl -sL $url -o $plugins/file.zip && unzip -qqo $plugins/file.zip -d $plugins && rm -rf $plugins/file.zip
    done
    # my SMT fat JAR
    mvn clean package -f $__HOME/connect-cdc/my-smt/pom.xml
    cp $__HOME/connect-cdc/my-smt/target/my-smt-*.jar $plugins
    # connect cluster
    for node in {0,1,2}; do
        eval "echo \"$(<"$__HOME"/connect-cdc/config/templates/connect.properties)\"" >$kafka_home/config/connect-$node.properties
        $kafka_home/bin/connect-distributed.sh -daemon $kafka_home/config/connect-$node.properties
    done
}

stop() {
    ps -e | grep "[C]onnectDistributed" | grep -v grep | awk '{print $1}' | xargs kill -9 ||true
    ps -e | grep "[K]afka" | grep -v grep | awk '{print $1}' | xargs kill -9 ||true
    ps -e | grep "[Q]uorumPeerMain" | grep -v grep | awk '{print $1}' | xargs kill -9 ||true
    ps -e | grep '[A]rtemis' | grep -v grep | awk '{print $1}' | xargs kill -9 ||true
    rm -rf $__TMP /tmp/offset.dat
}

readonly USAGE="
Usage: $(basename $0) [commands]

Commands:
  init     Postgres DB init
  query    Query table's content
  stream   Stream changes (Ctrl+C to stop)
  artemis  Start Artemis broker
  kafka    Start Kafka cluster
  connect  Start KafkaConnect cluster
  stop     Stop all processes
"
readonly COMMAND="${1-}"
case "$COMMAND" in
    init)
        db_init
        ;;
    query)
        db_query
        ;;
    stream)
        db_stream
        ;;
    artemis)
        artemis
        ;;
    kafka)
        kafka
        ;;
    connect)
        connect
        ;;
    stop)
        stop
        ;;
    *)
        __error "$USAGE"
esac
