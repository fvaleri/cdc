## KafkaConnect on OpenShift

We are going to replicate the same CDC pipeline on OpenShift from scratch, this time using MySQL as the source database.
Note that, for the sake of simplicity, we are using unsecured components that are not suitable for production use.
All these commands can be easily automated with a shell scripts.

## Project setup

```sh
API_ENDPOINT="https://api.crc.testing:6443"
ADMIN_NAME="kubeadmin"
ADMIN_PASS="7z6T5-qmTth-oxaoD-p3xQF"
USER_NAME="developer"
USER_PASS="developer"
PROJECT_NAME="cdc"

# new project
TMP="/tmp/ocp" && rm -rf $TMP && mkdir -p $TMP
oc login -u $ADMIN_NAME -p $ADMIN_PASS $API_ENDPOINT
oc new-project $PROJECT_NAME
oc adm policy add-role-to-user admin $USER_NAME

# RH registry authentication
REG_SECRET="000regauth"
oc create secret docker-registry $REG_SECRET \
    --docker-server="registry.redhat.io" \
    --docker-username="my-user" \
    --docker-password="my-pass"
```

## MySQL setup (source system)

```sh
oc create configmap db-config --from-file=./mysql/my.cnf
oc create configmap db-init --from-file=./mysql/initdb.sql
oc create secret generic db-creds \
    --from-literal=database-name=cdcdb \
    --from-literal=database-user=cdcadmin \
    --from-literal=database-password=cdcadmin \
    --from-literal=database-admin-password=cdcadmin

# resource deploy
oc create -f ./mysql/my-mysql.yaml

# status check
MYSQL_POD=$(oc get pods | grep my-mysql | grep Running | cut -d " " -f1)
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e "SHOW DATABASES"'

# insert some values
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e \
    "INSERT INTO customers (first_name, last_name, email) VALUES (\"John\", \"Doe\", \"jdoe@example.com\")"'
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e "SELECT * FROM customers"'
```

## AMQ Broker setup (sink system)

```sh
mkdir $TMP/amq
unzip -qq /path/to/amq-broker-operator-7.5.0-ocp-install-examples.zip -d $TMP/amq
AMQ_DEPLOY="$(find $TMP/amq -name "deploy" -type d)"

oc create -f $AMQ_DEPLOY/service_account.yaml
oc create -f $AMQ_DEPLOY/role.yaml
oc create -f $AMQ_DEPLOY/role_binding.yaml
oc apply -f $AMQ_DEPLOY/crds
oc create -f $AMQ_DEPLOY/operator.yaml

# registry linking
oc secrets link default $REG_SECRET --for=pull
oc secrets link builder $REG_SECRET --for=pull
oc secrets link deployer $REG_SECRET --for=pull
oc secrets link amq-broker-operator $REG_SECRET --for=pull

# resource deploy
oc create -f ./amq/my-broker.yaml
oc create -f ./amq/my-address.yaml

# status check
oc get activemqartemises
oc get activemqartemisaddresses
```

## AMQ Streams setup 0 (Kafka)

```sh
mkdir $TMP/streams
unzip -qq /path/to/amq-streams-1.4.1-ocp-install-examples.zip -d $TMP/streams
STREAMS_DEPLOY="$(find $TMP/streams -name "install" -type d)"

sed -i -e "s/namespace: .*/namespace: $PROJECT_NAME/g" $STREAMS_DEPLOY/cluster-operator/*RoleBinding*.yaml
oc apply -f $STREAMS_DEPLOY/cluster-operator
oc set env deploy/strimzi-cluster-operator STRIMZI_NAMESPACE=$PROJECT_NAME
oc apply -f $STREAMS_DEPLOY/strimzi-admin
oc adm policy add-cluster-role-to-user strimzi-admin $USER_NAME

# registry linking
oc secrets link builder $REG_SECRET --for=pull
oc secrets link strimzi-cluster-operator $REG_SECRET --for=pull
oc set env deploy/strimzi-cluster-operator STRIMZI_IMAGE_PULL_SECRETS=$REG_SECRET

# resource deploy
oc apply -f ./streams/my-kafka.yaml
oc apply -f ./streams/my-topic.yaml

# status check
oc get kafkas
oc get kafkatopics
```

## AMQ Streams setup 1 (KafkaConnect)

```sh
KAFKA_CLUSTER="my-kafka-cluster"
CONNECTOR_URLS=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-mysql/1.1.1.Final/debezium-connector-mysql-1.1.1.Final-plugin.zip"
    "https://repo1.maven.org/maven2/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/0.2.0/camel-sjms2-kafka-connector-0.2.0-package.zip"
)

CONNECTORS="$TMP/connectors" && mkdir -p $CONNECTORS
for url in "${CONNECTOR_URLS[@]}"; do
    curl -sL $url -o $CONNECTORS/file.zip && unzip -qq $CONNECTORS/file.zip -d $CONNECTORS
done
sleep 2
rm -rf $CONNECTORS/file.zip

# resource deploy
oc create secret generic debezium-config --from-file=./streams/connectors/mysql.properties
oc create secret generic camel-config --from-file=./streams/connectors/amq.properties
oc apply -f ./streams/my-connect-s2i.yaml
# wait for the connect cluster to be up and running
oc start-build my-connect-cluster-connect --from-dir $CONNECTORS

# status check
oc get kafkaconnects2i
oc exec -i $KAFKA_CLUSTER-kafka-0 -c kafka -- bin/kafka-topics.sh --zookeeper localhost:2181 --list

# all running pods up to this point
amq-broker-operator-5d4559677-9ghv5                1/1     Running     0          20m
my-broker-ss-0                                     1/1     Running     0          18m
my-connect-cluster-connect-2-httk9                 1/1     Running     0          2m
my-kafka-cluster-entity-operator-9b59899dd-c4q6h   3/3     Running     0          10m
my-kafka-cluster-kafka-0                           2/2     Running     0          11m
my-kafka-cluster-zookeeper-0                       2/2     Running     0          11m
my-mysql-1-g4j6m                                   1/1     Running     0          26m
strimzi-cluster-operator-588cc9c5d5-sr952          1/1     Running     0          15m

# pipeline config (topic name == serverName.databaseName.tableName)
oc apply -f ./streams/connectors/mysql-source.yaml
oc apply -f ./streams/connectors/amq-sink.yaml

# status check
oc get kafkaconnectors
oc describe kafkaconnector mysql-source
oc describe kafkaconnector amq-sink
CONNECT_POD=$(oc get pods | grep my-connect-cluster | grep Running | cut -d " " -f1)
oc logs $CONNECT_POD
oc exec -i $KAFKA_CLUSTER-kafka-0 -c kafka -- bin/kafka-console-consumer.sh \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 --topic my-mysql.cdcdb.customers --from-beginning
```

## Cleanup

```sh
rm -rf $TMP
oc delete project $PROJECT_NAME
oc delete crd/activemqartemises.broker.amq.io
oc delete crd/activemqartemisaddresses.broker.amq.io
oc delete crd/activemqartemisscaledowns.broker.amq.io
oc delete crd -l app=strimzi
oc delete clusterrolebinding -l app=strimzi
oc delete clusterrole -l app=strimzi
```
