# Nyvox 🕶️

A **Session-style private messenger** built with **Flutter + Supabase**.
Send messages, not metadata.

- 🚫 **No phone number, no email** — your Account ID (`vc…`) is your identity, just like a Session ID
- 🔐 **End-to-end encryption** — X25519 key exchange + AES-256-GCM, done on-device; the server only stores ciphertext
- 📝 **12-word recovery phrase** (BIP-39) — restore your identity on any device
- ⏱ **Disappearing messages** — off / 10 min / 1 hour / 1 day / 1 week
- 📷 **Add contacts by Account ID or QR code** — your address book is never uploaded
- ⚡ **Realtime delivery** via Supabase Realtime
- 🆓 **100% free backend** on Supabase's free tier — no servers to run

---

## Architecture

```
┌──────────────────────────┐        TLS         ┌───────────────────────┐
│  Flutter app (device A)  │ ◄────────────────► │   Supabase (free)     │
│  • X25519 keypair        │   ciphertext only  │  • Postgres + RLS     │
│  • AES-GCM encrypts msgs │                    │  • Anonymous auth     │
│  • Keys in secure storage│                    │  • Realtime           │
└──────────────────────────┘                    └───────────────────────┘
           ▲  E2EE: plaintext never leaves devices ▲
┌──────────────────────────┐
│  Flutter app (device B)  │
└──────────────────────────┘
```

**Identity model (Session-style):** the app generates an X25519 keypair from a
BIP-39 recovery phrase. The Account ID is `vc` + hex(public key). Supabase
*anonymous* sign-in is used only as a transport credential for Row Level
Security; `device_auth` links each anonymous session to its Account ID, so
restoring your phrase on a new phone brings back the same identity.

**Encryption:** for each DM, both devices derive the same shared secret via
X25519 (my secret key × your public key). Every message gets a fresh random
AES-GCM nonce. Only `ciphertext` + `nonce` are stored in Postgres.

---

## Setup (≈15 minutes, free)

### 1. Create the free Supabase backend
See [supabase/SETUP.md](supabase/SETUP.md) — in short:
1. Create a free project at [supabase.com](https://supabase.com)
2. Enable **anonymous sign-ins** (Authentication → Providers → Anonymous)
3. Run [`supabase/schema.sql`](supabase/schema.sql) in the SQL editor
4. Copy your **Project URL** and **anon key** (Project Settings → API)

### 2. Run the app
```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

### 3. Try it on two devices (or device + emulator)
- Device A: **Create account** → save the 12 words → share your Account ID from Settings
- Device B: **Create account** → pencil icon → paste A's Account ID → **Message**

---

## Project structure

```
lib/
├── main.dart                       # bootstrap + Supabase init
├── app.dart                        # theme + onboarding/home routing
├── config/supabase_config.dart     # --dart-define credentials
├── models/models.dart              # Profile, ChatMessage, ConversationSummary
├── services/
│   ├── crypto_service.dart         # X25519 + AES-GCM, BIP-39 identity
│   ├── identity_store.dart         # recovery phrase in secure storage
│   ├── auth_service.dart           # anonymous auth + profile/device linking
│   └── chat_service.dart           # conversations, realtime messages, E2EE I/O
├── state/providers.dart            # Riverpod wiring
└── ui/
    ├── theme.dart                  # Session-style dark + privacy green
    ├── onboarding/                 # create / restore / recovery phrase
    ├── home/                       # conversation list
    ├── chat/                       # chat screen + bubbles + disappearing timer
    ├── contacts/                   # add by Account ID / QR scanner
    └── settings/                   # Account ID + QR, phrase reveal, wipe
supabase/
├── schema.sql                      # tables, RLS policies, RPCs, realtime
└── SETUP.md                        # step-by-step Supabase guide
```

---

## Security notes & honest limitations

✅ **What you get**
- No personal identifiers anywhere: no phone, email, name, or contacts upload
- Message content is unreadable to the server, the database, and anyone
  intercepting traffic (E2EE)
- Database access locked down with Row Level Security
- Free, zero-maintenance backend

⚠️ **What this starter does NOT (yet) do — unlike the real Session**
- **No onion routing**: Supabase sees device IP addresses (metadata). For
  Session-level metadata protection you'd add a relay/onion layer or run
  behind a VPN/Tor.
- **No perfect forward secrecy**: one static keypair per identity. A
  double-ratchet (Signal protocol) can be layered on later.
- **Groups**: the schema supports them (`is_group`), but group UI/encryption
  (sender keys) is a next step.
- Disappearing messages are enforced client-side + optional `pg_cron` purge
  (commented in `schema.sql`).

## Roadmap ideas
- 🔁 Signal-style double ratchet (PFS)
- 👥 Closed groups & communities
- 🖼 Encrypted media attachments (AES-GCM → Supabase Storage)
- 🔔 Push notifications via a metadata-free relay
- 🧅 Optional Tor/VPN transport

## Publishing
- Android: `flutter build apk --release` (or `appbundle` for Play Store)
- iOS: `flutter build ipa`
- Keep the **anon key** public-safe (RLS protects data); never ship a
  `service_role` key in the app.
