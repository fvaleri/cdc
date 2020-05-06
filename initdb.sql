DROP DATABASE IF EXISTS cdcdb;
DROP ROLE IF EXISTS cdcadmin;

CREATE DATABASE cdcdb WITH TEMPLATE template0 ENCODING UTF8 LC_CTYPE en_US;
\connect cdcdb;

CREATE USER cdcadmin WITH ENCRYPTED PASSWORD 'cdcadmin';

CREATE SCHEMA cdc AUTHORIZATION cdcadmin;
CREATE TABLE cdc.customers (
    id BIGSERIAL NOT NULL PRIMARY KEY,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE
);

GRANT ALL PRIVILEGES ON DATABASE cdcdb to cdcadmin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cdc TO cdcadmin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA cdc TO cdcadmin;

--required by debezium
SELECT pg_create_logical_replication_slot('debezium', 'pgoutput');
CREATE PUBLICATION dbz_publication FOR ALL TABLES WITH (publish = 'insert,update,delete');
ALTER ROLE cdcadmin WITH REPLICATION;
ALTER TABLE cdc.customers REPLICA IDENTITY FULL;
