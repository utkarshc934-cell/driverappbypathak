create table if not exists public.driver_dashboard_state (
  id boolean primary key default true check (id is true),
  raw_data jsonb not null check (jsonb_typeof(raw_data) = 'array'),
  source_name text not null default 'Supabase shared dataset',
  revision bigint not null default 1 check (revision >= 1),
  updated_at timestamptz not null default now()
);

alter table public.driver_dashboard_state enable row level security;

drop policy if exists "Authenticated users can read dashboard state"
  on public.driver_dashboard_state;
create policy "Authenticated users can read dashboard state"
  on public.driver_dashboard_state
  for select
  to authenticated
  using (auth.uid() is not null);

revoke all on public.driver_dashboard_state from anon, authenticated;
grant select on public.driver_dashboard_state to authenticated;
grant usage on schema public to authenticated;

create or replace function public.assert_driver_dashboard_data(p_raw_data jsonb)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  row_count bigint;
  unique_key_count bigint;
begin
  if p_raw_data is null or jsonb_typeof(p_raw_data) <> 'array' then
    raise exception 'raw_data must be a JSON array';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_raw_data) as item(value)
    where jsonb_typeof(value) <> 'array'
       or case
            when jsonb_typeof(value) = 'array' then jsonb_array_length(value) < 11
            else true
          end
       or nullif(btrim(value ->> 1), '') is null
       or nullif(btrim(value ->> 2), '') is null
  ) then
    raise exception 'Every row must contain 11 columns, a period, and a branch code';
  end if;

  select count(*),
         count(distinct (btrim(value ->> 1), btrim(value ->> 2)))
    into row_count, unique_key_count
    from jsonb_array_elements(p_raw_data) as item(value);

  if row_count <> unique_key_count then
    raise exception 'Duplicate Period + Branch Code keys are not allowed';
  end if;
end;
$$;

revoke all on function public.assert_driver_dashboard_data(jsonb) from public, anon, authenticated;

create or replace function public.ensure_driver_dashboard_state(
  p_raw_data jsonb,
  p_source_name text
)
returns setof public.driver_dashboard_state
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  perform public.assert_driver_dashboard_data(p_raw_data);

  insert into public.driver_dashboard_state (id, raw_data, source_name)
  values (true, p_raw_data, coalesce(nullif(btrim(p_source_name), ''), 'Supabase shared dataset'))
  on conflict (id) do nothing;

  return query
    select *
    from public.driver_dashboard_state
    where id is true;
end;
$$;

create or replace function public.save_driver_dashboard_state(
  p_expected_revision bigint,
  p_raw_data jsonb,
  p_source_name text
)
returns setof public.driver_dashboard_state
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'A valid expected revision is required';
  end if;

  perform public.assert_driver_dashboard_data(p_raw_data);

  return query
    update public.driver_dashboard_state
       set raw_data = p_raw_data,
           source_name = coalesce(nullif(btrim(p_source_name), ''), 'Supabase shared dataset'),
           revision = revision + 1,
           updated_at = clock_timestamp()
     where id is true
       and revision = p_expected_revision
    returning *;
end;
$$;

revoke all on function public.ensure_driver_dashboard_state(jsonb, text) from public, anon;
revoke all on function public.save_driver_dashboard_state(bigint, jsonb, text) from public, anon;
grant execute on function public.ensure_driver_dashboard_state(jsonb, text) to authenticated;
grant execute on function public.save_driver_dashboard_state(bigint, jsonb, text) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'driver_dashboard_state'
  ) then
    alter publication supabase_realtime
      add table public.driver_dashboard_state;
  end if;
end;
$$;
