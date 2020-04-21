## [<<](/README.md) Artemis setup

The setup of the Artemis broker is rather simple.
Once installed, the most convenient way to check messages is by using the [web console](http://localhost:8161/console).
```sh
ARTEMIS_BASE="/tmp/cdc/artemis"
ARTEMIS_URL="https://downloads.apache.org/activemq/activemq-artemis/2.11.0/apache-artemis-2.11.0-bin.tar.gz"
ARTEMIS_HOME="$ARTEMIS_BASE/home"

rm -rf $ARTEMIS_BASE && mkdir -p $ARTEMIS_HOME
curl -s $ARTEMIS_URL | tar xz -C $ARTEMIS_HOME --strip-components 1

# create and start a new broker instance
$ARTEMIS_HOME/bin/artemis create $ARTEMIS_BASE/host0 --name host0 --user admin --password admin --require-login
$ARTEMIS_BASE/host0/bin/artemis-service start

# create our queues
$ARTEMIS_BASE/host0/bin/artemis queue create --user admin --password admin --name CustomersJSON --auto-create-address --anycast --durable --silent
$ARTEMIS_BASE/host0/bin/artemis queue create --user admin --password admin --name CustomersXML --auto-create-address --anycast --durable --silent
```
