#!/bin/sh
# Runs once, when the Postgres data volume is first created.
set -e
psql -v ON_ERROR_STOP=1 -U postgres <<SQL
CREATE ROLE synapse LOGIN PASSWORD '${SYNAPSE_DB_PASSWORD}';
CREATE DATABASE synapse OWNER synapse TEMPLATE template0
  ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C';
SQL
