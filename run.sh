#!/usr/bin/env bash
set -Eeuo pipefail

RUN_ARTEMIS_VER="2.16.0" && readonly RUN_ARTEMIS_VER
RUN_KAFKA_VER="2.7.0" && readonly RUN_KAFKA_VER
RUN_DEBEZIUM_VER="1.4.0.Final" && readonly RUN_DEBEZIUM_VER
RUN_CAMELKC_VER="0.7.0" && readonly RUN_CAMELKC_VER
RUN_BASE="" && pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" >/dev/null \
  && { RUN_BASE=$PWD; popd >/dev/null; } && readonly RUN_BASE
RUN_TMP="/tmp/cdc" && readonly RUN_TMP

for x in java curl mvn; do
  if ! command -v "$x" &>/dev/null; then
    error "Missing required utility: $x"
  fi
done

mkdir -p $RUN_TMP

error() {
  echo -e "$@" 1>&2 && exit 1
}

db_init() {
  psql template1 -f "$RUN_BASE"/initdb.sql
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
  local artemis_url="https://archive.apache.org/dist/activemq/activemq-artemis/$RUN_ARTEMIS_VER/apache-artemis-$RUN_ARTEMIS_VER-bin.tar.gz"
  local artemis_home="$RUN_TMP/artemis" && mkdir -p "$artemis_home"
  curl -sL "$artemis_url" | tar xz -C "$artemis_home" --strip-components 1
  "$artemis_home"/bin/artemis create "$artemis_home"/servers/server1 --name server1 --user admin --password changeit --require-login
  "$artemis_home"/servers/server1/bin/artemis-service start
  sleep 5
  "$artemis_home"/servers/server1/bin/artemis queue create --user admin --password changeit --name CustomersJSON --auto-create-address --anycast --durable --silent
  "$artemis_home"/servers/server1/bin/artemis queue create --user admin --password changeit --name CustomersXML --auto-create-address --anycast --durable --silent
}

kafka() {
  local kafka_url="https://archive.apache.org/dist/kafka/$RUN_KAFKA_VER/kafka_2.13-$RUN_KAFKA_VER.tgz"
  local kafka_home="$RUN_TMP/kafka" && mkdir -p "$kafka_home"
  curl -sL "$kafka_url" | tar xz -C "$kafka_home" --strip-components 1

  # zookeeper cluster
  for node in {0,1,2}; do
    eval "echo \"$(<"$RUN_BASE"/connect-cdc/config/templates/zookeeper.properties)\"" >"$kafka_home"/config/zookeeper-"$node".properties
    mkdir -p "$kafka_home"/data/zookeeper-"$node"
    echo "$node" > $kafka_home/data/zookeeper-"$node"/myid
    "$kafka_home"/bin/zookeeper-server-start.sh -daemon "$kafka_home"/config/zookeeper-"$node".properties
  done

  # kafka cluster
  sleep 5
  for node in {0,1,2}; do
    eval "echo \"$(<"$RUN_BASE"/connect-cdc/config/templates/kafka.properties)\"" >"$kafka_home"/config/kafka-"$node".properties
    mkdir -p "$kafka_home"/data/kafka-"$node"
    "$kafka_home"/bin/kafka-server-start.sh -daemon "$kafka_home"/config/kafka-"$node".properties
  done
}

connect() {
  local kafka_home="$RUN_TMP/kafka"
  local connect_plugins=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/$RUN_DEBEZIUM_VER/debezium-connector-postgres-$RUN_DEBEZIUM_VER-plugin.zip"
    "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/$RUN_CAMELKC_VER/camel-sjms2-kafka-connector-$RUN_CAMELKC_VER-package.zip"
  )
  local plugins="$RUN_TMP/plugins" && mkdir -p "$plugins"
  for url in "${connect_plugins[@]}"; do
    curl -sL "$url" -o "$RUN_TMP"/file.zip && unzip -qqo "$RUN_TMP"/file.zip -d "$plugins"
  done

  # my SMT fat JAR
  mvn clean package -f "$RUN_BASE"/connect-cdc/my-smt/pom.xml
  cp "$RUN_BASE"/connect-cdc/my-smt/target/my-smt-*.jar "$plugins"

  # connect cluster
  for node in {0,1,2}; do
    eval "echo \"$(<"$RUN_BASE"/connect-cdc/config/templates/connect.properties)\"" >"$kafka_home"/config/connect-"$node".properties
    "$kafka_home"/bin/connect-distributed.sh -daemon "$kafka_home"/config/connect-"$node".properties
  done
}

clean() {
  pkill -9 -f "cli.ConnectDistributed" ||true
  pkill -9 -f "kafka.Kafka" ||true
  pkill -9 -f "quorum.QuorumPeerMain" ||true
  pkill -9 -f "boot.Artemis" ||true
  rm -rf "$RUN_TMP"
}

readonly USAGE="
Usage: $0 [command]

  db_init      Initialize database
  db_query     Query test table
  db_stream    Insert some data
  artemis      Start Artemis broker
  kafka        Start Kafka cluster
  connect      Start Connect cluster
  clean        Kill all and cleanup
"
readonly COMMAND="${1-}"
if [[ -z "$COMMAND" ]]; then
  error "$USAGE"
else
  if (declare -F "$COMMAND" >/dev/null); then
    "$COMMAND"
  fi
fi
