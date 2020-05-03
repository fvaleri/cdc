package it.fvaleri.cdc;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.transforms.Transformation;
import org.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class JsonWriter<R extends ConnectRecord<R>> implements Transformation<R> {

    private static final Logger LOG = LoggerFactory.getLogger(JsonWriter.class);

    public JsonWriter() {
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
            JSONObject newValue = value.getJSONObject("after");
            return record.newRecord(
                record.topic(), record.kafkaPartition(),
                null, null,
                Schema.STRING_SCHEMA, newValue.toString(),
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
