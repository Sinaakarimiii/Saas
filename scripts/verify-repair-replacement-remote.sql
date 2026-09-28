\set ON_ERROR_STOP on
\set shipment_method post
\set damage_loop false
\ir fixtures/replacement-remote-scenario.sql
\set shipment_method courier
\ir fixtures/replacement-remote-scenario.sql
\set damage_loop true
\ir fixtures/replacement-remote-scenario.sql
