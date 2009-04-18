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

create or replace function insert_metric(in_timestamp timestamp,
                                         in_measure double precision,
                                         in_hostname text,
                                         in_ds_type datasource_type,
                                         in_plugin text,
                                         in_plugin_instance text,
                                         in_type text,
                                         in_type_name text,
                                         in_type_instance text) returns void as $$
  DECLARE
    host_id integer;
    a_plugin_id integer;
    a_type_id integer;
  BEGIN
    select into host_id id from hostname_dimension where hostname = in_hostname;
    IF NOT FOUND THEN
      insert into hostname_dimension (hostname) values (in_hostname) returning id into host_id;
    END IF;

    IF in_plugin_instance IS NULL THEN
        select into a_plugin_id id from plugin_dimension where plugin = in_plugin and plugin_instance is null;
    ELSE
        select into a_plugin_id id from plugin_dimension where plugin = in_plugin and plugin_instance = in_plugin_instance;
    END IF;

    IF NOT FOUND THEN
       insert into plugin_dimension (plugin, plugin_instance) values (in_plugin, in_plugin_instance) returning id into a_plugin_id;
    END IF;

    IF in_type_instance IS NULL THEN
        select into a_type_id id from type_dimension where type = in_type and type_name = in_type_name and type_instance is null;
    ELSE
        select into a_type_id id from type_dimension where type = in_type and type_name = in_type_name and type_instance = in_type_instance;
    END IF;

    IF NOT FOUND THEN
       insert into type_dimension (type, ds_type, type_name, type_instance) values (in_type, in_ds_type, in_type_name, in_type_instance) returning id into a_type_id;
    END IF;

    insert into metrics (timestamp, measure, hostname_id, plugin_id, type_id) values (in_timestamp, in_measure, host_id, a_plugin_id, a_type_id);
  END;
$$ LANGUAGE plpgsql;

create or replace function get_interval(start_timestamp timestamp, length interval, step text) returns SETOF timestamp as $$
  DECLARE
    v_timestamp timestamp;
    end_timestamp timestamp;
  BEGIN
    v_timestamp := start_timestamp;
    end_timestamp := start_timestamp + length;
    WHILE v_timestamp <= end_timestamp LOOP
      RETURN NEXT v_timestamp;
      v_timestamp := v_timestamp + ('1' || step)::interval;
    END LOOP;
  END;
$$ language plpgsql;

create or replace function create_partition_trigger(parent text,
                                                    start_timestamp timestamp,
                                                    length interval,
                                                    step text,
                                                    format text) returns void as $trigger$
  DECLARE
    v_function text;
    v_body text;
    v_current_date date;
    v_start_date date;
    v_suffix text;
  BEGIN
    v_current_date := date(start_timestamp);
    v_function := 'CREATE OR REPLACE FUNCTION ' || parent || '_insert_trigger() '
                  || 'RETURNS TRIGGER LANGUAGE plpgsql AS $$ '
                  || 'BEGIN ';

    FOR v_start_date in select * from get_interval(start_timestamp, length, step) LOOP
        select trim(to_char(v_start_date, format)) into v_suffix;
        IF v_current_date = v_start_date THEN
           v_body := ' IF ';
        ELSE
           v_body := ' ELSEIF ';
        END IF;
        v_body := v_body || ' NEW.timestamp >= ''' || v_start_date || '''::timestamp and '
                         || ' NEW.timestamp < ''' || v_start_date + ( '1' || step)::interval || '''::timestamp THEN '
                         || ' INSERT INTO ' || parent || '_' || v_suffix 
                         || ' values (NEW.*); ';
        v_function := v_function || v_body;
    END LOOP;
    v_function := v_function || 'ELSE RETURN NEW; END IF; RETURN NULL; END; $$';
    EXECUTE v_function;
  END;
$trigger$ LANGUAGE plpgsql;

create or replace function create_partition_tables(parent text, start_timestamp timestamp, length interval, step text, format text) returns void as $$
  DECLARE
      sql text;
      v_suffix text;
      v_start_date date;
      table_name text;
  BEGIN
      FOR v_start_date in select * from get_interval(start_timestamp, length, step) LOOP
          select trim(to_char(v_start_date, format)) into v_suffix;
          select parent || '_' || v_suffix into table_name;
          select 'create table ' || table_name
                || ' (CHECK (timestamp >= ' || quote_literal(v_start_date)
                || '::timestamp and timestamp < ' || quote_literal(v_start_date + ( '1' || step)::interval)
                || '::timestamp)) INHERITS (' || parent || ');'
                into sql;
           EXECUTE sql;
           EXECUTE 'create index index_' || table_name || '_on_timestamp_hostname_and_plugin_and_type on ' || table_name || ' (timestamp, hostname_id, plugin_id, type_id);';
       END LOOP;
  END;
$$ LANGUAGE plpgsql;

-- if you are using postgres 8.4, which introduced window functions
-- you can use something like this to to create a view on rows that come from
-- COUNTER plugins. Because the real measurement is the difference of
-- the last sample to the next sample, use the lag() function to do that math.
-- This will create a combined view of both COUNTER and GUAGE types.
--
-- WARNING - for large datasets THIS WILL BE SLOW!

-- create view metrics_view as 
--  SELECT timestamp,
--   ((m.measure - lag(m.measure) 
--           over(partition by m.hostname_id, 
--                             p.plugin,
--                             p.plugin_instance,
--                             t.type,
--                             t.type_instance
--                 order by timestamp, m.hostname_id, p.plugin, p.plugin_instance, t.type, t.type_instance))) AS metric,
--  m.hostname_id, 
--  m.plugin_id, 
--  m.type_id
-- FROM metrics m, plugin_dimension p, type_dimension t
-- where m.type_id = t.id
-- and m.plugin_id = p.id
-- and t.ds_type = 'COUNTER'
-- UNION
-- select timestamp, m.measure as metric,
--  m.hostname_id, 
--  m.plugin_id, 
--  m.type_id
-- FROM metrics m, type_dimension t
-- where m.type_id = t.id
-- and t.ds_type = 'GUAGE';
