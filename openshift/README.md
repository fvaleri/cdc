## Cloud-native CDC pipeline

Simple cloud-native CDC pipeline on OpenShift for streaming changes from MySQL (source) to AMQ (sink).

Note that we are using unsecured components that are not suitable for production use.

### Initialization

```sh
API_ENDPOINT="https://api.crc.testing:6443"
ADMIN_NAME="kubeadmin"
ADMIN_PASS="dpDFV-xamBW-kKAk3-Fi6Lg"
NAMESPACE="cdc"
DOWNLOAD_DIR="~/Downloads"
TMP="/tmp/cdc"

# init namespace
rm -rf $TMP && mkdir -p $TMP
oc login -u $ADMIN_NAME -p $ADMIN_PASS $API_ENDPOINT
oc new-project $NAMESPACE
```

### MySQL database (source system)

```sh
# deploy resource
oc create configmap my-mysql-init --from-file=./openshift/mysql/initdb.sql
oc create -f ./openshift/mysql/my-mysql.yaml

# wait for mysql pod to start and init the database
oc exec my-mysql-ss-0 -- sh -c 'mysql -u root < /config/initdb.d/initdb.sql'

# do some changes
oc exec my-mysql-ss-0 -- sh -c 'MYSQL_PWD="cdcadmin" mysql -u cdcadmin cdcdb -e \
    "INSERT INTO customers (first_name, last_name, email) VALUES (\"John\", \"Doe\", \"jdoe@example.com\")"'
oc exec my-mysql-ss-0 -- sh -c 'MYSQL_PWD="cdcadmin" mysql -u cdcadmin cdcdb -e \
    "UPDATE customers SET first_name = \"Jane\" WHERE id = 1"'
oc exec my-mysql-ss-0 -- sh -c 'MYSQL_PWD="cdcadmin" mysql -u cdcadmin cdcdb -e \
    "INSERT INTO customers (first_name, last_name, email) VALUES (\"Chuck\", \"Norris\", \"cnorris@example.com\")"'

# check status
oc exec my-mysql-ss-0 -- sh -c 'MYSQL_PWD="cdcadmin" mysql -u cdcadmin cdcdb -e "SELECT * FROM customers"'
```

### AMQ broker (sink system)

```sh
mkdir $TMP/amq
unzip -qq $DOWNLOAD_DIR/amq-broker-operator-7.8.0-ocp-install-examples.zip -d $TMP/amq
AMQ_DEPLOY="$(find $TMP/amq -name "deploy" -type d)"

# deploy operator
oc create -f $AMQ_DEPLOY/service_account.yaml
oc create -f $AMQ_DEPLOY/role.yaml
oc create -f $AMQ_DEPLOY/role_binding.yaml
oc create -f $AMQ_DEPLOY/crds/broker_activemqartemis_crd.yaml
oc create -f $AMQ_DEPLOY/crds/broker_activemqartemisaddress_crd.yaml
oc create -f $AMQ_DEPLOY/crds/broker_activemqartemisscaledown_crd.yaml
oc create -f $AMQ_DEPLOY/operator.yaml

# deploy resources
oc create -f ./openshift/amq/my-broker.yaml
oc create -f ./openshift/amq/my-address.yaml

# check status
oc get activemqartemises
oc get activemqartemisaddresses
```

### AMQ Streams Kafka

```sh
mkdir $TMP/streams
unzip -qq $DOWNLOAD_DIR/amq-streams-1.6.0-ocp-install-examples.zip -d $TMP/streams
STREAMS_DEPLOY="$(find $TMP/streams -name "install" -type d)"

# deploy operator
sed -i.bk "s/namespace: .*/namespace: $NAMESPACE/g"  $STREAMS_DEPLOY/cluster-operator/*RoleBinding*.yaml
oc create -f $STREAMS_DEPLOY/cluster-operator

# deploy resources
oc create -f ./openshift/streams/my-cluster.yaml

# check status
oc get kafkas
```

### AMQ Streams KafkaConnect

```sh
CONNECT_NAME="my-connect"
CONNECT_IMAGE="registry.redhat.io/amq7/amq-streams-kafka-26-rhel7:1.6.0"
CONNECTORS=(
    "https://repo.maven.apache.org/maven2/io/debezium/debezium-connector-mysql/1.4.0.Final/debezium-connector-mysql-1.4.0.Final-plugin.zip"
    "https://repository.apache.org/content/groups/public/org/apache/camel/kafkaconnector/camel-sjms2-kafka-connector/0.7.0/camel-sjms2-kafka-connector-0.7.0-package.zip"
)

# build custom KafkaConnect image
mkdir -p $TMP/my-connect/plugins
for url in "${CONNECTORS[@]}"; do
    curl -sL $url -o $TMP/my-connect/plugins/file.zip && \
        unzip -qq $TMP/my-connect/plugins/file.zip -d $TMP/my-connect/plugins
done
sleep 2 && rm -rf $TMP/my-connect/plugins/file.zip
echo -e "FROM $CONNECT_IMAGE\nCOPY ./plugins/ /opt/kafka/plugins/\nUSER 1001" > $TMP/my-connect/Dockerfile
oc new-build --binary --name=my-connect -l app=my-connect
oc patch bc my-connect --type json -p '[{"op":"add", "path":"/spec/strategy/dockerStrategy/dockerfilePath", "value":"Dockerfile"}]'
oc start-build my-connect --from-dir=$TMP/my-connect --follow

# deploy resources
sed "s/NAMESPACE/$NAMESPACE/g" ./openshift/streams/my-connect.yaml | oc create -f -
oc create -f ./openshift/streams/connectors/mysql-source.yaml
oc create -f ./openshift/streams/connectors/amq-sink.yaml

# check status
oc describe kafkaconnector mysql-source
oc describe kafkaconnector amq-sink

# check queue's content from the AMQ web console
echo http://$(oc get routes my-broker-wconsj-0-svc-rte -o=jsonpath='{.status.ingress[0].host}{"\n"}')/console
```

### Cleanup

```sh
rm -rf $TMP
oc delete project $NAMESPACE
oc delete crds $(oc get crds | grep activemq | awk '{print $1}')
oc delete crd,sa,clusterrolebinding,clusterrole -l app=strimzi
```
