-- Schéma de sauvegarde en ligne de Jaay.
-- À exécuter dans l'éditeur SQL de votre projet Supabase.

create table if not exists public.gf_records (
  user_id    uuid        not null default auth.uid(),
  device_id  text        not null,
  tbl        text        not null,
  id         bigint      not null,
  data       jsonb,
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id, tbl, id)
);

create table if not exists public.gf_devices (
  user_id     uuid        not null default auth.uid(),
  device_id   text        not null,
  name        text        not null default '',
  app_version text        not null default '',
  last_sync   timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.gf_records enable row level security;
alter table public.gf_devices enable row level security;

do $$
declare t text;
begin
  foreach t in array array['gf_records', 'gf_devices'] loop
    execute format('create policy %I on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t || '_select', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', t || '_delete', t);
  end loop;
end $$;
