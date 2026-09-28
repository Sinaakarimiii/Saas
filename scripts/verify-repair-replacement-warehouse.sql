\set ON_ERROR_STOP on
\set warehouse_proposal parts_proposed
\set warehouse_outcome parts_received
\ir fixtures/replacement-warehouse-scenario.sql
\set warehouse_proposal refurbish_proposed
\set warehouse_outcome refurbish_received
\ir fixtures/replacement-warehouse-scenario.sql
