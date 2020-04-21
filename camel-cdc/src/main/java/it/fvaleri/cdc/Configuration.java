package it.fvaleri.cdc;

import java.io.File;

import org.apache.camel.BindToRegistry;
import org.apache.camel.Exchange;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Configuration {

    @BindToRegistry
    public CdcSetup cdc() {
        return new CdcSetup();
    }

    public static final class CdcSetup {
        private static final Logger LOG = LoggerFactory.getLogger(CdcSetup.class);

        public String offsetPath(final Exchange exchange) throws Exception {
            String offsetPath = System.getenv("OFFSET_PATH");
            if (offsetPath != null) {
                if (LOG.isDebugEnabled()) {
                    LOG.debug("Using offsetPath from env: {}", offsetPath);
                }
            } else {
                offsetPath = "/tmp";
            }
            new File(offsetPath).mkdirs();
            return offsetPath;
        }
    }

}
