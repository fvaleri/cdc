package it.fvaleri.cdc;

import javax.jms.ConnectionFactory;
import org.apache.activemq.artemis.jms.client.ActiveMQConnectionFactory;
import org.apache.camel.LoggingLevel;
import org.apache.camel.Predicate;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.component.debezium.DebeziumConstants;
import org.apache.camel.component.jackson.JacksonDataFormat;
import org.apache.camel.component.jms.JmsComponent;
import org.apache.camel.model.dataformat.JaxbDataFormat;
import org.apache.camel.spi.PropertiesComponent;
import org.apache.kafka.connect.data.Struct;
import io.debezium.data.Envelope;

public final class Routes extends RouteBuilder {

    private static final String DATABASE_READER =
        "debezium-postgres:{{database.hostname}}?"
        + "databaseHostname={{database.hostname}}"
        + "&databasePort={{database.port}}"
        + "&databaseUser={{database.user}}"
        + "&databasePassword={{database.password}}"
        + "&databaseDbname={{database.dbname}}"
        + "&databaseServerName={{database.hostname}}"
        + "&schemaWhitelist={{database.schema}}"
        + "&tableWhitelist={{database.schema}}.customers"
        + "&offsetStorageFileName=/tmp/offset.dat"
        + "&offsetFlushIntervalMs=10000"
        + "&pluginName=pgoutput";
    private static final String XML_WRITER = "direct:xml-writer";
    private static final String JSON_WRITER = "direct:json-writer";

    @Override
    public void configure() throws Exception {
        typeConverterSetup();
        jmsComponentSetup();

        final Predicate isCreateOrUpdateEvent =
            header(DebeziumConstants.HEADER_OPERATION).in(
                constant(Envelope.Operation.CREATE.code()),
                constant(Envelope.Operation.READ.code()),
                constant(Envelope.Operation.UPDATE.code()));

        from(DATABASE_READER)
            .routeId(Routes.class.getName() + ".DatabaseReader")
            .log(LoggingLevel.DEBUG, "Incoming message \nBODY: ${body} \nHEADERS: ${headers}")
            .filter(isCreateOrUpdateEvent)
                .convertBodyTo(Customer.class)
                .multicast().streaming().parallelProcessing()
                    .stopOnException().to(XML_WRITER, JSON_WRITER)
                .end()
            .end();

        from(JSON_WRITER)
            .routeId(Routes.class.getName() + ".JsonWriter")
            .marshal(jacksonDataFormat())
            .log(LoggingLevel.DEBUG, "JSON format: ${body}")
            .convertBodyTo(String.class)
            .to("jms:queue:CustomersJSON?disableReplyTo=true");

        from(XML_WRITER)
            .routeId(Routes.class.getName() + ".XmlWriter")
            .marshal(jaxbDataFormat())
            .log(LoggingLevel.DEBUG, "XML format: ${body}")
            .convertBodyTo(String.class)
            .to("jms:queue:CustomersXML?disableReplyTo=true");
    }

    private JacksonDataFormat jacksonDataFormat() {
        final JacksonDataFormat jacksonDataFormat = new JacksonDataFormat();
        return jacksonDataFormat;
    }

    private JaxbDataFormat jaxbDataFormat() {
        final JaxbDataFormat jaxbDataFormat = new JaxbDataFormat();
        jaxbDataFormat.setContextPath(Routes.class.getPackage().getName());
        jaxbDataFormat.setPrettyPrint("false");
        jaxbDataFormat.setFragment("true");
        return jaxbDataFormat;
    }

    private void typeConverterSetup() {
        getContext().getTypeConverterRegistry()
            .addTypeConverter(Customer.class, Struct.class, new CustomerConverter());
    }

    private void jmsComponentSetup() {
        final PropertiesComponent prop = getContext().getPropertiesComponent();
        final ConnectionFactory connectionFactory = new ActiveMQConnectionFactory(prop.resolveProperty("broker.url").get());
        final JmsComponent jmsComponent = JmsComponent.jmsComponentAutoAcknowledge(connectionFactory);
        jmsComponent.setUsername(prop.resolveProperty("broker.user").get());
        jmsComponent.setPassword(prop.resolveProperty("broker.password").get());
        getContext().addComponent("jms", jmsComponent);
    }

}
