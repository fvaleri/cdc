package it.fvaleri.cdc;

import static org.apache.kafka.connect.transforms.util.Requirements.requireMap;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.transforms.Transformation;

import java.util.Map;

public class JsonWriter<R extends ConnectRecord<R>> implements Transformation<R> {

    public JsonWriter() {
    }

    @Override
    public void configure(Map<String, ?> configs) {
    }

    @Override
    public R apply(R record) {
        // schemaless transformation (Map instead of Struct)
        final Map<String, Object> value = requireMap(record.value(), JsonWriter.class.getName());
        String op = (String) value.get("op");
        if ("cru".contains(op)) {
            Map<String, Object> newValue = (Map<String, Object>) value.get("after");
            return record.newRecord(record.topic(), record.kafkaPartition(), null, null, null, newValue, record.timestamp());
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
