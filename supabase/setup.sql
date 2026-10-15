-- Expense tracker for May: database setup.
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
--
-- Access model: there are no logins. Each "wallet" is opened by a long secret key
-- that lives only in the personal link. The database stores just the SHA-256 hash
-- of that key. The tables are closed to the public API; every read and write goes
-- through the functions below, which check the key first.

-- ---------- tables ----------
create table if not exists public.wallets (
  id          uuid primary key default gen_random_uuid(),
  key_hash    text not null unique,
  label       text not null,
  settings    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

-- one row per wallet per month; items is a map of expense id -> expense
create table if not exists public.months (
  wallet_id   uuid not null references public.wallets(id) on delete cascade,
  month       text not null check (month ~ '^m[0-9]{4}-[0-9]{2}$'),
  items       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  primary key (wallet_id, month)
);

alter table public.wallets enable row level security;
alter table public.months  enable row level security;
-- No policies on purpose: the public API cannot read or write these tables directly.
revoke all on public.wallets, public.months from anon, authenticated;

-- ---------- the two wallets: May's, and one for testing ----------
insert into public.wallets (key_hash, label) values
  ('36aa0a9c1274056e9cdcb60aaa73d8f0038d793e1565f121e0b4eed9e3ada8c2', 'may'),
  ('43100b10fb6fa94d241c2b81c15e46b1dac8e92c97bde56ab350be9b987fc2f6', 'test')
on conflict (key_hash) do nothing;

-- ---------- functions the app calls ----------
create or replace function public.wallet_id_for(p_key text)
returns uuid language sql stable security definer set search_path = '' as $$
  select w.id from public.wallets w
  where w.key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex');
$$;
revoke execute on function public.wallet_id_for(text) from public, anon, authenticated;

-- Load settings and the requested months.
create or replace function public.wallet_load(p_key text, p_months text[])
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  wid uuid := public.wallet_id_for(p_key);
  result jsonb;
begin
  if wid is null then raise exception 'unknown wallet' using errcode = '28000'; end if;
  if coalesce(array_length(p_months, 1), 0) > 36 then raise exception 'too many months' using errcode = '22023'; end if;
  select jsonb_build_object(
    'settings', w.settings,
    'months', coalesce((
      select jsonb_object_agg(m.month, m.items)
      from public.months m
      where m.wallet_id = wid and m.month = any(p_months)
    ), '{}'::jsonb)
  ) into result
  from public.wallets w where w.id = wid;
  return result;
end;
$$;

-- Add or replace one expense.
create or replace function public.wallet_put(p_key text, p_month text, p_id text, p_item jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare wid uuid := public.wallet_id_for(p_key);
begin
  if wid is null then raise exception 'unknown wallet' using errcode = '28000'; end if;
  if p_month !~ '^m[0-9]{4}-[0-9]{2}$' or p_id !~ '^[A-Za-z0-9_-]{1,40}$'
     or jsonb_typeof(p_item) <> 'object' or length(p_item::text) > 2000 then
    raise exception 'invalid expense' using errcode = '22023';
  end if;
  insert into public.months as m (wallet_id, month, items, updated_at)
  values (wid, p_month, jsonb_build_object(p_id, p_item), now())
  on conflict (wallet_id, month)
  do update set items = m.items || jsonb_build_object(p_id, p_item), updated_at = now();
end;
$$;

-- Remove one expense.
create or replace function public.wallet_delete(p_key text, p_month text, p_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare wid uuid := public.wallet_id_for(p_key);
begin
  if wid is null then raise exception 'unknown wallet' using errcode = '28000'; end if;
  update public.months set items = items - p_id, updated_at = now()
  where wallet_id = wid and month = p_month;
end;
$$;

-- Save settings (the categories and their colours).
create or replace function public.wallet_save_settings(p_key text, p_settings jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare wid uuid := public.wallet_id_for(p_key);
begin
  if wid is null then raise exception 'unknown wallet' using errcode = '28000'; end if;
  if jsonb_typeof(p_settings) <> 'object' or length(p_settings::text) > 20000 then
    raise exception 'invalid settings' using errcode = '22023';
  end if;
  update public.wallets set settings = p_settings where id = wid;
end;
$$;

-- Daily keep-alive: a real read, so the free project never counts as inactive.
create or replace function public.ping()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.wallets;
$$;

grant execute on function public.wallet_load(text, text[]) to anon;
grant execute on function public.wallet_put(text, text, text, jsonb) to anon;
grant execute on function public.wallet_delete(text, text, text) to anon;
grant execute on function public.wallet_save_settings(text, jsonb) to anon;
grant execute on function public.ping() to anon;
