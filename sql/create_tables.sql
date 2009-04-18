--  Written by Bob Cotton <bob.cotton@gmail.com>
--  This is free software; you can redistribute it and/or modify it under
--  the terms of the GNU General Public License as published by the Free
--  Software Foundation; only version 2 of the License is applicable.
drop table metrics cascade;
drop table hostname_dimension cascade;
drop table plugin_dimension cascade;
drop table type_dimension cascade;
drop type datasource_type cascade;

create type datasource_type as ENUM ('GUAGE', 'COUNTER');

create table metrics (id serial primary key,
                      timestamp timestamp,
                      measure double precision default 0,
                      hostname_id integer not null,
                      plugin_id integer not null,
                      type_id integer not null
                      );

create table hostname_dimension (id serial primary key,
                                 hostname varchar(64) not null);

create table plugin_dimension (id serial primary key,
                               plugin varchar(64) not null,
                               plugin_instance varchar(64));

create table type_dimension (id serial primary key,
                             ds_type datasource_type,
                             type varchar(64) not null,
                             type_name varchar(64) not null,
                             type_instance varchar(64));


select create_partition_tables('metrics', now()::timestamp, '6 months'::interval, 'month', 'YYYY_MM');
select create_partition_trigger('metrics', now()::timestamp, '6 months'::interval, 'month', 'YYYY_MM');
CREATE TRIGGER insert_metrics_trigger BEFORE INSERT ON metrics FOR EACH ROW EXECUTE PROCEDURE metrics_insert_trigger();
