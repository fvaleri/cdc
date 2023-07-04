package it.fvaleri.cdc;

public class Main {
    public static void main(final String[] args) throws Exception {
        final org.apache.camel.main.Main main = new org.apache.camel.main.Main();
        main.configure().addRoutesBuilder(new Routes());
        main.run(args);
    }
}
