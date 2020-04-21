package it.fvaleri.cdc;

import org.apache.camel.Exchange;
import org.apache.camel.TypeConversionException;
import org.apache.camel.support.TypeConverterSupport;
import org.apache.kafka.connect.data.Struct;

public class CustomerConverter extends TypeConverterSupport {

    @Override
    public <T> T convertTo(Class<T> type, Exchange exchange, Object value) throws TypeConversionException {
        Struct struct = (Struct) exchange.getIn().getBody();
        return (T) new Customer(
            struct.getInt64("id"),
            struct.getString("first_name"),
            struct.getString("last_name"),
            struct.getString("email")
        );
    }

}
