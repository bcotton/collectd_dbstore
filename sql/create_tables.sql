select create_partition_tables('metrics', now()::timestamp, '6 months'::interval, 'month', 'YYYY_MM');
select create_partition_trigger('metrics', now()::timestamp, '6 months'::interval, 'month', 'YYYY_MM');
CREATE TRIGGER insert_metrics_trigger BEFORE INSERT ON metrics FOR EACH ROW EXECUTE PROCEDURE metrics_insert_trigger();
