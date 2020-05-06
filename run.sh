#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $(uname -s) == "Darwin" ]]; then
  shopt -s expand_aliases
  alias echo="gecho"; alias dirname="gdirname"; alias grep="ggrep"; alias readlink="greadlink"
  alias tar="gtar"; alias sed="gsed"; alias sort="gsort"; alias date="gdate"; alias wc="gwc"
fi
BASE="" && pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" >/dev/null \
  && { BASE=$PWD; popd >/dev/null; } && readonly BASE
readonly TMP="/tmp/cdc" && mkdir -p $TMP

error() {
  echo "$@" 1>&2
  exit 1
}

db_init() {
  psql template1 -f $BASE/initdb.sql
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
  local artemis_home="$TMP/artemis"
  local artemis_url="https://archive.apache.org/dist/activemq/activemq-artemis/$version/apache-artemis-$version-bin.tar.gz"
  mkdir -p $artemis_home
  curl -sL $artemis_url | tar xz -C $artemis_home --strip-components 1
  $artemis_home/bin/artemis create $artemis_home/instance --name instance --user admin --password admin --require-login
  $artemis_home/instance/bin/artemis-service start
  sleep 5
  $artemis_home/instance/bin/artemis queue create --user admin --password admin --name CustomersJSON --auto-create-address --anycast --durable --silent
  $artemis_home/instance/bin/artemis queue create --user admin --password admin --name CustomersXML --auto-create-address --anycast --durable --silent
}

kafka() {
  local version="2.7.0"
  local kafka_url="https://archive.apache.org/dist/kafka/$version/kafka_2.13-$version.tgz"
  local kafka_home="$TMP/kafka" && mkdir -p $kafka_home
  export KAFKA_HOME="$kafka_home"
  curl -sL $kafka_url | tar xz -C $kafka_home --strip-components 1
  
  # zookeeper cluster
  for node in {0,1,2}; do
    eval "echo \"$(<"$BASE"/connect-cdc/config/templates/zookeeper.properties)\"" >$kafka_home/config/zookeeper-$node.properties
    mkdir -p $kafka_home/data/zookeeper-$node
    echo "$node" > $kafka_home/data/zookeeper-$node/myid
    $kafka_home/bin/zookeeper-server-start.sh -daemon $kafka_home/config/zookeeper-$node.properties
  done
  
  # kafka cluster
  sleep 5
  for node in {0,1,2}; do
    eval "echo \"$(<"$BASE"/connect-cdc/config/templates/kafka.properties)\"" >$kafka_home/config/kafka-$node.properties
    mkdir -p $kafka_home/data/kafka-$node
    $kafka_home/bin/kafka-server-start.sh -daemon $kafka_home/config/kafka-$node.properties
  done
}

connect() {
  local version_dbz="1.4.0.Final"
  local version_kck="0.7.0"
  local kafka_home="$TMP/kafka"
  export KAFKA_HOME=$kafka_home
  local connect_plugins=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-postgres/$version_dbz/debezium-connector-postgres-$version_dbz-plugin.zip"
    "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/$version_kck/camel-sjms2-kafka-connector-$version_kck-package.zip"
  )
  local plugins="$TMP/plugins" && mkdir -p $plugins
  for url in "${connect_plugins[@]}"; do
    curl -sL $url -o $TMP/file.zip && unzip -qqo $TMP/file.zip -d $plugins
  done
  # my SMT fat JAR
  mvn clean package -f $BASE/connect-cdc/my-smt/pom.xml
  cp $BASE/connect-cdc/my-smt/target/my-smt-*.jar $plugins
  # connect cluster
  for node in {0,1,2}; do
    eval "echo \"$(<"$BASE"/connect-cdc/config/templates/connect.properties)\"" >$kafka_home/config/connect-$node.properties
    $kafka_home/bin/connect-distributed.sh -daemon $kafka_home/config/connect-$node.properties
  done
}

stop() {
  ps -ef | grep "[C]onnectDistributed" | grep -v grep | awk '{print $2}' | xargs kill -9 &>/dev/null ||true
  ps -ef | grep "[k]afka.Kafka" | grep -v grep | awk '{print $2}' | xargs kill -9 &>/dev/null ||true
  ps -ef | grep "[q]uorum.QuorumPeerMain" | grep -v grep | awk '{print $2}' | xargs kill -9 &>/dev/null ||true
  ps -ef | grep '[A]rtemis' | grep -v grep | awk '{print $2}' | xargs kill -9 &>/dev/null ||true
}

readonly USAGE="
Usage: $0 [command]

Commands:
  db_init    Initialize database
  db_query   Query test table
  db_stream  Insert some data
  artemis    Start Artemis broker
  kafka      Start Kafka cluster
  connect    Start Connect cluster
  stop       Stop all
"
readonly COMMAND="${1-}"
if [[ -z "$COMMAND" ]]; then
  error "$USAGE"
else
  if (declare -F "$COMMAND" >/dev/null); then
    "$COMMAND"
  fi
fi
