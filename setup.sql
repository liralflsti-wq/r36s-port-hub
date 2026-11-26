begin;

create table public.support_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.support_admins enable row level security;
revoke all on public.support_admins from public, anon, authenticated;

create function public.support_is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.support_admins where user_id = (select auth.uid())
  )
$$;
revoke all on function public.support_is_admin() from public, anon, authenticated;
grant execute on function public.support_is_admin() to authenticated;

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  console_model text not null check (char_length(btrim(console_model)) between 1 and 100),
  os text not null check (char_length(btrim(os)) between 1 and 100),
  hub_version text not null default '' check (char_length(hub_version) <= 50),
  description text not null check (char_length(btrim(description)) between 1 and 4000),
  attachment_name text,
  attachment_data text,
  progress smallint not null default 0 check (progress between 0 and 100),
  status text generated always as (
    case when progress = 100 then 'resolved' when progress > 0 then 'working' else 'open' end
  ) stored,
  resolution text not null default '' check (char_length(resolution) <= 4000),
  created_at timestamptz not null default now(),
  constraint attachment_pair check (
    (attachment_name is null and attachment_data is null)
    or (attachment_name is not null and attachment_data is not null
      and char_length(attachment_name) between 1 and 180
      and attachment_name ~* '[.](png|jpe?g|webp|txt|log)$'
      and char_length(attachment_data) between 4 and 5592408
      and octet_length(decode(attachment_data, 'base64')) between 1 and 4194304)
  )
);
create index support_tickets_owner_created on public.support_tickets (owner_id, created_at desc);
create index support_tickets_created on public.support_tickets (created_at desc, id);
alter table public.support_tickets enable row level security;
revoke all on public.support_tickets from public, anon, authenticated;
grant select on public.support_tickets to authenticated;
grant insert (title, console_model, os, hub_version, description, attachment_name, attachment_data)
  on public.support_tickets to authenticated;
grant update (progress, resolution) on public.support_tickets to authenticated;

create policy "Autor ou administrador lê chamados" on public.support_tickets
  for select to authenticated using (owner_id = (select auth.uid()) or (select public.support_is_admin()));
create policy "Autor envia chamado" on public.support_tickets
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "Administrador atualiza chamados" on public.support_tickets
  for update to authenticated using ((select public.support_is_admin()))
  with check ((select public.support_is_admin()));

commit;
