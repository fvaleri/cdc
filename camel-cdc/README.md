## Camel CDC process

This is our Camel CDC pipeline designed using EIPs.
```
                                                                       |--> [format-converter] --> (xml-queue)
(postgres-db) --> [dbz-endpoint] --> [type-converter]--> [multicast] --|
                                                                       |--> [format-converter] --> (json-queue)
```

We use the *Debezium PostgreSQL Component* as the endpoint which creates an event-driven consumer.
This is a wrapper around Debezium embedded engine which enables CDC without the need to maintain Kafka clusters.

Compile and run the application.
```sh
mvn clean compile exec:java -f ./camel-cdc/pom.xml
```

Produce some more changes and check queues.
```sh
./run.sh --stream
```

This is the Exchange produced by Debezium.
```sh
# body
Struct{
    id=46,
    first_name=500f5c4ad014caeaa6b196c268988e36,
    last_name=9d074202a43901ed716d13c447a27d5a,
    email=5b0c660d172b426e584c4ce92224d79b@example.com
}
# headers
{
    CamelDebeziumBefore=null,
    CamelDebeziumIdentifier=localhost.cdc.customers,
    CamelDebeziumKey=Struct{id=46},
    CamelDebeziumOperation=c,
    CamelDebeziumSourceMetadata={
        schema=cdc,
        xmin=null,
        connector=postgresql,
        lsn=39610552,
        name=localhost,
        txId=2091,
        version=1.1.0.Final,
        ts_ms=1587226799511,
        snapshot=false,
        db=cdcdb,
        table=customers
    },
    CamelDebeziumTimestamp=1587226809390
}
```
