## KafkaConnect on OpenShift

We are going to replicate the same KafkaConnect CDC pipeline on OpenShift, this time using MySQL as source database.
Note that, for the sake of simplicity, we are using unsecured components that are not suitable for production use.

## Project setup

```sh
API_ENDPOINT="https://api.crc.testing:6443"
ADMIN_NAME="kubeadmin"
ADMIN_PASS="8rynV-SeYLc-h8Ij7-YPYcz"
USER_NAME="developer"
USER_PASS="developer"
PROJECT_NAME="cdc"

# new project
TMP="/tmp/ocp" && rm -rf $TMP && mkdir -p $TMP
oc login -u $ADMIN_NAME -p $ADMIN_PASS $API_ENDPOINT
oc new-project $PROJECT_NAME
oc adm policy add-role-to-user admin $USER_NAME

# RH registry authentication
REG_SECRET="registry-secret"
oc create secret docker-registry $REG_SECRET \
    --docker-server="registry.redhat.io" \
    --docker-username="my-user" \
    --docker-password="my-pass"
oc secrets link default $REG_SECRET --for=pull
oc secrets link builder $REG_SECRET --for=pull
oc secrets link deployer $REG_SECRET --for=pull
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

# resources deploy
oc create -f ./mysql/my-mysql.yaml

# status check
MYSQL_POD=$(oc get pods | grep my-mysql | grep Running | cut -d " " -f1)
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e "SELECT * FROM customers"'

# do some changes
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e \
    "INSERT INTO customers (first_name, last_name, email) VALUES (\"John\", \"Doe\", \"jdoe@example.com\")"'
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e \
    "UPDATE customers SET first_name = \"Jane\" WHERE id = 1"'
oc exec -i $MYSQL_POD -- /bin/sh -c 'MYSQL_PWD="cdcadmin" $MYSQL_PREFIX/bin/mysql -u cdcadmin cdcdb -e \
    "INSERT INTO customers (first_name, last_name, email) VALUES (\"Chuck\", \"Norris\", \"cnorris@example.com\")"'
```

## AMQ Broker setup (sink system)

```sh
mkdir $TMP/amq
unzip -qq /path/to/amq-broker-operator-7.7.0-ocp-install-examples.zip -d $TMP/amq
AMQ_DEPLOY="$(find $TMP/amq -name "deploy" -type d)"

# operator deploy
oc create -f $AMQ_DEPLOY/service_account.yaml
oc create -f $AMQ_DEPLOY/role.yaml
oc create -f $AMQ_DEPLOY/role_binding.yaml
sed -i -e "s/v2alpha1/v2alpha2/g" $AMQ_DEPLOY/crds/broker_v2alpha1_activemqartemis_crd.yaml
sed -i -e "s/v2alpha1/v2alpha2/g" $AMQ_DEPLOY/crds/broker_v2alpha1_activemqartemisaddress_crd.yaml
oc apply -f $AMQ_DEPLOY/crds
oc secrets link amq-broker-operator $REG_SECRET --for=pull
oc create -f $AMQ_DEPLOY/operator.yaml

# resources deploy
oc create -f ./amq/my-broker.yaml

# create the address only when the broker pod is running
oc create -f ./amq/my-address.yaml

# status check
oc get activemqartemises
oc get activemqartemisaddresses
```

## AMQ Streams setup 0 (Kafka)

```sh
mkdir $TMP/streams
unzip -qq /path/to/amq-streams-1.5.0-ocp-install-examples.zip -d $TMP/streams
STREAMS_DEPLOY="$(find $TMP/streams -name "install" -type d)"

# operator deploy
sed -i -e "s/namespace: .*/namespace: $PROJECT_NAME/g" $STREAMS_DEPLOY/cluster-operator/*RoleBinding*.yaml
oc apply -f $STREAMS_DEPLOY/cluster-operator
oc set env deploy/strimzi-cluster-operator STRIMZI_NAMESPACE=$PROJECT_NAME
oc secrets link builder $REG_SECRET --for=pull
oc secrets link strimzi-cluster-operator $REG_SECRET --for=pull
oc set env deploy/strimzi-cluster-operator STRIMZI_IMAGE_PULL_SECRETS=$REG_SECRET
oc apply -f $STREAMS_DEPLOY/strimzi-admin
oc adm policy add-cluster-role-to-user strimzi-admin $USER_NAME

# resources deploy
oc apply -f ./streams/my-kafka.yaml

# status check
oc get kafkas
```

## AMQ Streams setup 1 (KafkaConnect)

```sh
KAFKA_CLUSTER="my-kafka-cluster"
CONNECTOR_URLS=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-mysql/1.2.0.Final/debezium-connector-mysql-1.2.0.Final-plugin.zip"
    "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/0.3.0/camel-sjms2-kafka-connector-0.3.0-package.zip"
)

CONNECTORS="$TMP/connectors" && mkdir -p $CONNECTORS
for url in "${CONNECTOR_URLS[@]}"; do
    curl -sL $url -o $CONNECTORS/file.zip && unzip -qq $CONNECTORS/file.zip -d $CONNECTORS
done
sleep 2
rm -rf $CONNECTORS/file.zip

# resources deploy
oc create secret generic debezium-config --from-file=./streams/connectors/mysql.properties
oc create secret generic camel-config --from-file=./streams/connectors/amq.properties
oc apply -f ./streams/my-connect-s2i.yaml

# start the build only when connect cluster is running
oc start-build my-connect-cluster-connect --from-dir $CONNECTORS --follow

# status check
oc get kafkaconnects2i

# all running pods up to this point
amq-broker-operator-5d4559677-dpzf5                 1/1     Running     0          21m
my-broker-ss-0                                      1/1     Running     0          19m
my-connect-cluster-connect-2-xr58q                  1/1     Running     0          6m28s
my-kafka-cluster-entity-operator-56c9868474-kfdx2   3/3     Running     1          14m
my-kafka-cluster-kafka-0                            2/2     Running     0          14m
my-kafka-cluster-zookeeper-0                        1/1     Running     0          15m
my-mysql-1-vmbbw                                    1/1     Running     0          25m
strimzi-cluster-operator-666fcd8b96-q8thc           1/1     Running     0          15m

# pipeline config (topic name == serverName.databaseName.tableName)
oc apply -f ./streams/connectors/mysql-source.yaml
oc apply -f ./streams/connectors/amq-sink.yaml

# status check
oc get kafkaconnectors
oc describe kafkaconnector mysql-source
oc describe kafkaconnector amq-sink

CONNECT_POD=$(oc get pods | grep my-connect-cluster | grep Running | cut -d " " -f1)
oc logs $CONNECT_POD

oc get kafkatopics
oc exec -i $KAFKA_CLUSTER-kafka-0 -c kafka -- bin/kafka-console-consumer.sh \
    --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092 --topic my-mysql.cdcdb.customers --from-beginning

# open the AMQ web console to check queue's content
echo http://$(oc get routes my-broker-wconsj-0-svc-rte -o=jsonpath='{.status.ingress[0].host}{"\n"}')/console
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
