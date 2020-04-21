#!/bin/sh
set -e

create_db() {
    createdb -T template0 -E UTF8 --lc-collate=en_US --lc-ctype=en_US cdcdb;
    psql cdcdb -f ./resources/schema.sql
}

stream_changes() {
    watch -n1 "psql cdcdb -U cdcadmin -c \
        \"INSERT INTO cdc.customers (first_name, last_name, email) \
        VALUES (md5(random()::text), md5(random()::text), md5(random()::text)||'@example.com')\""
}

check_table() {
    psql cdcdb -U cdcadmin -c "SELECT * FROM cdc.customers"
}

case $1 in
    create_db) create_db;;
    stream_changes) stream_changes;;
    check_table) check_table;;
    *) echo "Usage: $0 {create_db|stream_changes|check_table}"
esac
