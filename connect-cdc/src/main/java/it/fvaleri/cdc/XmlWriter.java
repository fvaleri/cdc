package it.fvaleri.cdc;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.transforms.Transformation;
import org.json.JSONObject;
import org.json.XML;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class XmlWriter<R extends ConnectRecord<R>> implements Transformation<R> {

    private static final Logger LOG = LoggerFactory.getLogger(XmlWriter.class);

    public XmlWriter() {
    }

    @Override
    public void configure(Map<String, ?> configs) {
    }

    @Override
    public R apply(R record) {
        LOG.debug("Input record: {}", record.value());
        // extract final value and convert
        JSONObject value = new JSONObject(record.value().toString());
        String op = (String) value.getString("op");
        LOG.debug("Operation: {}", op);
        if (op != null && "cru".contains(op)) {
            JSONObject after = value.getJSONObject("after");
            String newValue = XML.toString(after, "customer");
            return record.newRecord(
                record.topic(), record.kafkaPartition(),
                null, null,
                Schema.STRING_SCHEMA, newValue,
                record.timestamp());
        } else {
            return null;
        }
    }

    @Override
    public ConfigDef config() {
        return new ConfigDef();
    }

    @Override
    public void close() {
    }

}
