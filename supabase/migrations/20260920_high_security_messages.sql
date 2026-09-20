-- Per-chat High Security mode. Secure messages are hidden from the sender
-- immediately and permanently deleted after the recipient leaves the chat.
alter table public.conversations
  add column if not exists high_security boolean not null default false;

alter table public.messages
  add column if not exists high_security boolean not null default false;

create index if not exists messages_high_security_conversation_idx
  on public.messages (conversation_id, high_security)
  where high_security = true;