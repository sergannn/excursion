-- Realtime needs tables in the publication in addition to a healthy socket.
do $$
declare
  table_record record;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'create publication supabase_realtime';
  end if;

  for table_record in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and not exists (
        select 1
        from pg_publication_tables p
        where p.pubname = 'supabase_realtime'
          and p.schemaname = n.nspname
          and p.tablename = c.relname
      )
    order by c.relname
  loop
    execute format(
      'alter publication supabase_realtime add table %I.%I',
      table_record.schema_name,
      table_record.table_name
    );
  end loop;
end
$$;
