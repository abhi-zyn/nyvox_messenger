-- ============================================================================
-- Nyvox — Supabase database schema
-- Run this in: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Privacy model (Session-inspired):
--   * Identity = a keypair generated on the device. Your Account ID is derived
--     from your public key — no phone number or email is ever stored.
--   * The server stores ONLY ciphertext + nonces. Plaintext never leaves devices.
--   * Row Level Security (RLS) ensures users can only read rows that belong
--     to conversations they are a member of.
--   * device_auth links anonymous auth sessions to an Account ID, so restoring
--     your recovery phrase on a new device brings back the same identity.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. PROFILES — one row per identity, keyed by Account ID ("vc" + hex pubkey)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  account_id    text primary key,
  display_name  text not null default 'Anonymous',
  public_key    text not null,                 -- X25519 public key (hex)
  avatar_emoji  text not null default '🕶️',
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. DEVICE AUTH — maps each anonymous Supabase auth session to an Account ID
-- ---------------------------------------------------------------------------
create table if not exists public.device_auth (
  auth_uid    uuid primary key references auth.users (id) on delete cascade,
  account_id  text not null references public.profiles (account_id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists device_auth_account_idx on public.device_auth (account_id);

-- ---------------------------------------------------------------------------
-- 3. CONVERSATIONS + MEMBERS
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id          uuid primary key default gen_random_uuid(),
  is_group    boolean not null default false,
  title       text,                            -- groups only; DMs stay untitled
  created_at  timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  account_id      text not null references public.profiles (account_id) on delete cascade,
  joined_at       timestamptz not null default now(),
  primary key (conversation_id, account_id)
);

-- ---------------------------------------------------------------------------
-- 4. MESSAGES — ciphertext/nonce are base64; expires_at = disappearing timer
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references public.conversations (id) on delete cascade,
  sender_account_id text not null references public.profiles (account_id) on delete cascade,
  ciphertext        text not null,             -- AES-GCM ciphertext + MAC (base64)
  nonce             text not null,             -- AES-GCM nonce (base64)
  created_at        timestamptz not null default now(),
  expires_at        timestamptz,               -- null = keep forever
  read_at           timestamptz
);

create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at);

create index if not exists messages_expires_idx
  on public.messages (expires_at) where expires_at is not null;

-- ---------------------------------------------------------------------------
-- 5. HELPER: Account ID of the currently signed-in device
-- ---------------------------------------------------------------------------
create or replace function public.current_account_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select account_id from public.device_auth where auth_uid = auth.uid() limit 1
$$;

-- ---------------------------------------------------------------------------
-- 5b. HELPER: is the current caller a member of a conversation?
--     SECURITY DEFINER so it bypasses RLS on conversation_members. Policies
--     MUST use this instead of subquerying conversation_members directly — a
--     policy that references its own table causes infinite recursion (42P17).
--     Returns only a boolean scoped to the current caller, so it leaks nothing.
-- ---------------------------------------------------------------------------
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation_id
      and account_id = (select public.current_account_id())
  )
$$;

-- ---------------------------------------------------------------------------
-- 6. HELPER: create a 1-to-1 conversation atomically (or return existing one)
--    SECURITY DEFINER lets it insert members for both sides in one call.
-- ---------------------------------------------------------------------------
create or replace function public.create_dm_conversation(other_account_id text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me text := public.current_account_id();
  existing_id uuid;
  new_id uuid;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  -- Reuse an existing DM between the two identities if there is one.
  select cm1.conversation_id into existing_id
  from conversation_members cm1
  join conversation_members cm2
    on cm1.conversation_id = cm2.conversation_id
  join conversations c on c.id = cm1.conversation_id
  where cm1.account_id = me
    and cm2.account_id = other_account_id
    and c.is_group = false
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  insert into conversations (is_group) values (false) returning id into new_id;
  insert into conversation_members (conversation_id, account_id) values
    (new_id, me),
    (new_id, other_account_id);
  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. HELPER: find a profile by Account ID (for adding contacts)
-- ---------------------------------------------------------------------------
create or replace function public.lookup_profile_by_account_id(p_account_id text)
returns table (account_id text, display_name text, public_key text, avatar_emoji text)
language sql
stable
security definer
set search_path = public
as $$
  select account_id, display_name, public_key, avatar_emoji
  from profiles
  where account_id = lower(trim(p_account_id))
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
alter table public.profiles             enable row level security;
alter table public.device_auth          enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

-- Profiles: any signed-in user may read profiles (needed to render chats and
-- exchange public keys). Anyone signed in may claim an unclaimed Account ID
-- once; afterwards only its linked devices may update it.
create policy "profiles readable by authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "claim profile once"
  on public.profiles for insert
  to authenticated
  with check (true);

create policy "linked devices update profile"
  on public.profiles for update
  to authenticated
  using (account_id = (select public.current_account_id()))
  with check (account_id = (select public.current_account_id()));

-- Device links: you may register your own device session, see devices linked
-- to your own identity, and re-link your own device (upsert retry path).
create policy "register own device"
  on public.device_auth for insert
  to authenticated
  with check (auth_uid = auth.uid());

create policy "read own device links"
  on public.device_auth for select
  to authenticated
  using (
    auth_uid = auth.uid()
    or account_id = (select public.current_account_id())
  );

create policy "update own device link"
  on public.device_auth for update
  to authenticated
  using (auth_uid = auth.uid())
  with check (auth_uid = auth.uid());

-- Conversations: visible only to members (via the recursion-safe helper).
create policy "members can read conversation"
  on public.conversations for select
  to authenticated
  using (public.is_conversation_member(id));

create policy "members can read membership"
  on public.conversation_members for select
  to authenticated
  using (public.is_conversation_member(conversation_id));

-- Messages: only conversation members can read; you send as your own identity.
create policy "members can read messages"
  on public.messages for select
  to authenticated
  using (public.is_conversation_member(conversation_id));

create policy "members can send messages"
  on public.messages for insert
  to authenticated
  with check (
    sender_account_id = (select public.current_account_id())
    and public.is_conversation_member(conversation_id)
  );

create policy "members can update read receipt"
  on public.messages for update
  to authenticated
  using (public.is_conversation_member(conversation_id));

create policy "members can delete messages"
  on public.messages for delete
  to authenticated
  using (public.is_conversation_member(conversation_id));

-- ---------------------------------------------------------------------------
-- 9. REALTIME — enable so clients get instant message delivery
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;

-- ---------------------------------------------------------------------------
-- 10. OPTIONAL: automatically purge expired (disappearing) messages.
--     Requires pg_cron: Dashboard → Database → Extensions → enable pg_cron,
--     then uncomment and run the block below.
-- ---------------------------------------------------------------------------
-- select cron.schedule(
--   'purge-expired-messages',
--   '* * * * *',
--   $$delete from public.messages where expires_at is not null and expires_at < now()$$
-- );
