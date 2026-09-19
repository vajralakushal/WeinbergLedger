# The Weinberg Theory Group Ledger

A small, self-hosted catalog for a **shared physical library** — it tracks which
book each member owns, who has currently borrowed it, and where it lives on the
shelves, with a full **audit trail** (who changed what, from where, and when).
Accounts are required to edit anything; anyone can still browse the catalog and
the audit trail without one.

- **Backend:** Ruby on Rails (API-only), data in a single **SQLite** file
  (`library.db`). JSON API on port `3000`.
- **Frontend:** React + [Vite](https://vite.dev/) single-page app. Self-hosted
  fonts and dithered art — **no runtime network dependency** for the UI.
- **External calls:** only OpenLibrary, and only when someone uses the optional
  ISBN/identifier auto-fill or cover thumbnails. Everything else works offline.

---

## Table of contents

1. [Architecture](#architecture)
2. [Repository layout](#repository-layout)
3. [Accounts & permissions](#accounts--permissions)
4. [Prerequisites](#prerequisites)
5. [Setup](#setup)
6. [Running in development (locally)](#running-in-development)
7. [Tests](#tests)
8. [Database & data](#database--data)
9. [Building for production](#building-for-production)
10. [Deploying](#deploying)
    - [The one deployment invariant](#the-one-deployment-invariant-same-origin)
    - [Secrets: the Rails master key](#secrets-the-rails-master-key)
    - [Serving the built app (3 options)](#serving-the-built-app)
    - [Local Mac mini](#deploy-a-local-mac-mini-primary-target)
    - [Linux server](#deploy-b-linux-server-systemd--caddy)
    - [Windows](#deploy-c-windows)
    - [Cloudflare (remote access)](#deploy-d-cloudflare-tunnel-remote-access)
11. [Configuration reference](#configuration-reference)
12. [Maintenance & backups](#maintenance--backups)
13. [Troubleshooting](#troubleshooting)

---

## Architecture

```
                         ┌──────────────────────────────┐
   browser  ── /api/* ──▶│  Rails API (backend/)  :3000  │──▶ library.db (SQLite)
      │                  │  JSON API + auth + audit log  │──▶ img/ (cover cache)
      │                  └──────────────────────────────┘
      │                            ▲
      └── / , /assets, /fonts ─────┘   (static frontend, built to frontend/dist)
```

- In **development**, the Vite dev server (`:5173`) serves the UI and **proxies**
  `/api/*` to Rails (`:3000`). See `frontend/vite.config.js`.
- In **production**, there is no dev server. You build the UI to
  `frontend/dist/` and serve those static files **on the same origin** as the
  API (see [the deployment invariant](#the-one-deployment-invariant-same-origin)).

The frontend always calls the API with **relative** URLs (`/api/...`), so it has
no idea what host/port it is on — which is exactly what makes it portable.

---

## Repository layout

```
WeinbergLedger/
├── backend/                # Rails API app (routes, auth, admin, ~all logic)
│   ├── app/{models,controllers,services}/
│   ├── config/database.yml # dev/production point at ../library.db
│   ├── db/migrate/
│   └── test/
├── library.db              # SQLite database (ships with the catalog)
├── img/                     # cached book covers (created on demand)
├── frontend/
│   ├── index.html
│   ├── vite.config.js      # dev proxy /api -> :3000, Vitest config
│   ├── package.json
│   ├── public/fonts/       # self-hosted woff2 (Space Grotesk / Space Mono)
│   └── src/
│       ├── App.jsx, BookModal.jsx, AddBookModal.jsx, AuditLog.jsx
│       ├── LoginModal.jsx, SignupView.jsx, ChangePasswordModal.jsx
│       ├── UserMenu.jsx, UsersDashboard.jsx (admin)
│       ├── api.js          # bearer-token header helper
│       ├── *.css
│       ├── assets/         # generated dither PNGs
│       └── *.test.jsx      # frontend tests (Vitest + Testing Library)
└── README.md
```

---

## Accounts & permissions

Browsing (search, the audit log, book history, cover thumbnails) never
requires an account. **Editing anything requires logging in.**

**Registering:** click "Log In" → "Sign Up". The form asks for first name,
last name, username, password, and a quiz question ("What is the speed of
light, in God-given units?" — answer `1`) as a lightweight bot filter.
Registrations land in a `PENDING` state until an admin approves them; the
account is auto-removed if it's denied, or if it sits unapproved for more
than 24 hours (this also reclaims its randomly-assigned 4-digit user ID).
Registration attempts are also IP-rate-limited (5/hour) via `rack-attack`.

**Regular users** (once approved) can:
- Check books in/out (edit the Borrower field) and edit Location
- Add, bulk-import, and remove books
- Change their own password

**Admins** can additionally:
- Approve or deny pending registrations, from the **Users Dashboard**
  (top-right username menu → *Users Dashboard*)
- Delete a user — optionally reassigning that user's `OWNER`/`BORROWER` text
  on existing books to someone else first, so deleting an account doesn't
  leave orphaned name text behind
- Reset a user's password to a random one-time value (shown once, to relay
  to them) — this also forces a password change on their next login
- Promote another user to admin

Every edit still writes an `AUDIT_LOG` row, same as before — the `EDITOR` is
now the logged-in account's name rather than a free-text field, so it can't
be spoofed.

---

## Prerequisites

| Tool        | Version              | Needed for                                  |
|-------------|----------------------|---------------------------------------------|
| **Ruby**    | 3.2+                 | running the Rails API server                |
| **Bundler** | 2.x (`gem install bundler`) | installing Ruby gems                 |
| **Node.js** | 20.19+ (LTS 22 recommended) | building / developing the frontend  |
| **npm**     | 10+ (ships with Node)| frontend dependencies                       |

> **Node is only needed to build or develop the frontend.** A production server
> that just serves the pre-built `frontend/dist/` does **not** need Node.

### Installing the toolchain per OS

**macOS** (Homebrew):
```bash
brew install rbenv node
rbenv install 3.2.7 && rbenv global 3.2.7
gem install bundler rails
```

**Linux** (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y build-essential libsqlite3-dev
# Ruby via rbenv (recommended) or: sudo apt install ruby-full
# Node 22 via NodeSource:
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
gem install bundler rails
```

**Windows**:
- Install Ruby+Devkit from [RubyInstaller](https://rubyinstaller.org/) (run
  `ridk install` and pick the MSYS2 toolchain when prompted).
- Install Node LTS from [nodejs.org](https://nodejs.org/).

---

## Setup

```bash
git clone https://github.com/vajralakushal/WeinbergLedger.git WeinbergLedger
cd WeinbergLedger

# 1) Backend gems
cd backend && bundle install && cd ..

# 2) Frontend packages
cd frontend && npm install && cd ..
```

`backend/db/migrate/` includes migrations for the `USERS`/`SESSIONS` tables
(and an idempotent one for the original `LIBRARY`/`AUDIT_LOG` tables, so a
fresh, book-less database still bootstraps). Run them once after cloning:

```bash
cd backend && bin/rails db:migrate && cd ..
```

Against the committed `library.db`, this only adds the new `USERS`/`SESSIONS`
tables — none of the existing book/audit data is touched.

---

## Running in development

Open **two terminals**.

**Terminal 1 — API server:**
```bash
cd backend
bin/rails server
# => listening on http://0.0.0.0:3000
```

**Terminal 2 — frontend dev server:**
```bash
cd frontend
npm run dev
# => open the printed URL, e.g. http://localhost:5173
```

Use the app at the **Vite URL** (`:5173`). It proxies API calls to `:3000`
automatically, so both must be running.

To register the first admin (there's no UI for this on purpose — the very
first account has to be promoted out-of-band), sign up through the app, then:
```bash
cd backend
bin/rails runner 'User.find_by(username: "yourusername").update!(admin_status: true, approval_status: "APPROVED")'
```

---

## Tests

```bash
cd backend && bin/rails test     # Ruby: Minitest, ~70 tests
cd frontend && npm test          # JS: Vitest + Testing Library
```

Backend tests run against an isolated `backend/storage/test.sqlite3` — they
never touch the real `library.db`. `DISABLE_OPENLIBRARY=1` is set
automatically in the test environment, so the suite never makes real network
calls.

---

## Database & data

- The catalog lives in **`library.db`** (committed, so a fresh clone already has
  the books). SQLite runs in **WAL mode**, so you may also see `library.db-wal`
  and `library.db-shm` next to it — that's normal.
- `backend/config/database.yml` points the Rails `development` and
  `production` environments at this same file (one directory up from
  `backend/`), overridable via `LIBRARY_DB` — exactly like the old Sinatra
  app's `DB_PATH`. No data migration is needed when pulling this branch.
- Every edit / add / remove records an `AUDIT_LOG` row: who (name), where
  (IP), what changed (old → new), and when. Browse it in the UI under
  **View audit log**.

**Schema** (for reference / creating a fresh empty DB — see
`backend/db/migrate/` for the source of truth):
```sql
CREATE TABLE LIBRARY (
  ID            INTEGER PRIMARY KEY,
  OWNER         INTEGER NOT NULL,   -- stores the owner's name (legacy INTEGER-typed column, holds text)
  BORROWER      TEXT,
  LOCATION      TEXT,
  TITLE         TEXT NOT NULL,
  CREATOR       TEXT,
  PUBLISHER     TEXT,
  SERIES        TEXT,
  SUBJECT       TEXT,
  CREATION_DATE TEXT,
  IDENTIFIER    TEXT                 -- e.g. "LC : ...; ISBN : ...; OCLC : (OCoLC)..."
);

CREATE TABLE AUDIT_LOG (
  ID        INTEGER PRIMARY KEY AUTOINCREMENT,
  BOOK_ID   INTEGER NOT NULL,
  FIELD     TEXT    NOT NULL,
  OLD_VALUE TEXT,
  NEW_VALUE TEXT,
  EDITOR    TEXT    NOT NULL,
  IP        TEXT,
  TIMESTAMP TEXT    NOT NULL
);

CREATE TABLE USERS (
  user_id               INTEGER PRIMARY KEY, -- random 4-digit id, assigned on signup
  admin_status          BOOLEAN NOT NULL DEFAULT 0,
  first_name            TEXT    NOT NULL,
  last_name             TEXT    NOT NULL,
  username              TEXT    NOT NULL UNIQUE,
  password_digest       TEXT    NOT NULL,    -- bcrypt hash (has_secure_password)
  approval_status       TEXT    NOT NULL DEFAULT 'PENDING', -- PENDING | APPROVED | DENIED
  must_change_password  BOOLEAN NOT NULL DEFAULT 0,
  created_at, updated_at DATETIME NOT NULL
);

CREATE TABLE SESSIONS (               -- one row per logged-in bearer token
  id                     INTEGER PRIMARY KEY,
  user_id                INTEGER NOT NULL,
  token_digest           TEXT    NOT NULL UNIQUE, -- SHA-256 of the token; the raw token is never stored
  expires_at             DATETIME NOT NULL,
  created_at, updated_at DATETIME NOT NULL
);
```

**Importing books:** use the **Add book** dialog in the UI (requires login):
- *Single book* — type an ISBN/LCCN/OCLC and **Look up** to auto-fill fields
  (all still editable), or fill them by hand.
- *Bulk CSV* — paste or upload CSV with the columns
  `Owner, Borrower, Shelf, DD, Title, Creator, Publisher, Edition, Series, Notes, Subject, Creation Date, Identifier`.
  Each row needs a Title, an Owner, and an ISBN or LC identifier (a missing ISBN
  is looked up online when possible; otherwise the row is reported as skipped.

---

## Building for production

```bash
cd frontend
npm run build      # outputs static files to frontend/dist/
```

`frontend/dist/` is a fully static bundle (HTML/CSS/JS + `fonts/` + inlined
dither art). Serve it as described below.

---

## Deploying

### The one deployment invariant: same origin

The frontend calls the API at **relative** paths (`/api/...`). So in production
the static files **and** the API must be reachable under **one hostname/origin**.
Concretely, requests to `https://your-host/api/...` must reach Rails, and
everything else must serve `frontend/dist/`. Every recipe below achieves that.

(You *can* split them across origins, but then you must proxy `/api` to the
backend yourself — the app has no configurable API base by design.)

### Secrets: the Rails master key

Unlike the old Sinatra app, Rails needs a secret (`secret_key_base`) to boot
in production — it's what signs/encrypts sessions and the credentials file.
`bundle exec rails new` generated `backend/config/master.key` locally; it is
**deliberately gitignored** (it's a secret, same category as a private key —
never commit it). To deploy:

- Copy `backend/config/master.key` to the production machine out-of-band
  (`scp`, a password manager, etc. — **not** via git), so it ends up at
  `backend/config/master.key` there too, **or**
- Set the `RAILS_MASTER_KEY` environment variable to its contents instead
  (no file needed) — the way most PaaS/systemd/Docker setups prefer.

Without one of these, `bin/rails server -e production` will fail to boot.

Also note: Rails defaults to **forcing HTTPS** in production
(`config.force_ssl`). That's correct once you're behind a domain + TLS (Caddy,
a load balancer, Cloudflare), but it will redirect-loop a **plain-HTTP LAN**
deployment with nothing terminating TLS in front of it. Set `FORCE_SSL=0` in
that case (see [Deploy A](#deploy-a-local-mac-mini-primary-target)).

### Serving the built app

Pick one of these. **Option A** and **B** are the usual choices.

#### Option A — Reverse proxy (Caddy) — recommended, no code changes
[Caddy](https://caddyserver.com/) is a tiny single binary (macOS/Linux/Windows)
with automatic HTTPS. Point it at `frontend/dist/` and forward `/api`:

```caddyfile
# Caddyfile   (use a real domain for auto-HTTPS, or ":8080" for LAN/tunnel)
your-host.example.com {
    encode gzip
    handle /api/* {
        reverse_proxy localhost:3000
    }
    handle {
        root * /srv/WeinbergLedger/frontend/dist
        try_files {path} /index.html
        file_server
    }
}
```
Run Rails (`bin/rails server -e production`) and Caddy (`caddy run`) side by side.

#### Option B — Let Rails serve the frontend (single process, no extra software)
`backend/public/` is Rails' static-file root. Symlink (or copy) the built
frontend into it, so Rails serves `frontend/dist/` for everything that isn't
an `/api/*` route:

```bash
ln -s ../../frontend/dist/* backend/public/
```
Then `bin/rails server -e production` (from `backend/`) serves the whole app
on `:3000`. Simplest for a scrappy single-box deployment. (Put a reverse
proxy in front only if you want HTTPS/compression.)

#### Option C — nginx
```nginx
server {
    listen 80;
    server_name your-host.example.com;
    root /srv/WeinbergLedger/frontend/dist;

    location /api/ { proxy_pass http://127.0.0.1:3000; }
    location /     { try_files $uri /index.html; }
}
```

---

### Deploy A: Local Mac mini (primary target)

Access over the LAN from any machine in the office.

1. Clone, `cd backend && bundle install && bin/rails db:migrate`, and
   `cd frontend && npm run build`.
2. Choose a serving option above. For LAN-only, **Option B** (Rails serves
   `dist/`) is simplest — the app is then at `http://<mac-mini-ip>:3000`.
3. Since there's no TLS on a bare LAN deployment, set `FORCE_SSL=0` (see
   [Secrets](#secrets-the-rails-master-key)) — otherwise Rails will redirect
   every request to `https://`, which nothing is listening on.
4. Keep it running across logins/reboots with a **LaunchAgent**. Create
   `~/Library/LaunchAgents/com.weinberg.ledger.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key><string>com.weinberg.ledger</string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/bash</string>
       <string>-lc</string>
       <string>cd /Users/YOU/WeinbergLedger/backend && exec bin/rails server -e production</string>
     </array>
     <key>EnvironmentVariables</key>
     <dict>
       <key>PORT</key><string>3000</string>
       <key>FORCE_SSL</key><string>0</string>
       <key>RAILS_MASTER_KEY</key><string>PASTE_THE_MASTER_KEY_HERE</string>
     </dict>
     <key>RunAtLoad</key><true/>
     <key>KeepAlive</key><true/>
     <key>StandardOutPath</key><string>/tmp/weinberg-ledger.log</string>
     <key>StandardErrorPath</key><string>/tmp/weinberg-ledger.err</string>
   </dict>
   </plist>
   ```
   ```bash
   launchctl load ~/Library/LaunchAgents/com.weinberg.ledger.plist
   # (bash -lc so rbenv's Ruby is on PATH; adjust the path to your checkout)
   ```
5. Find the Mac mini's IP (`ipconfig getifaddr en0`) and share
   `http://<that-ip>:3000` with the group. macOS may prompt to allow incoming
   connections the first time — allow it.

> **Firewall:** this exposes the app to your local network only. For access from
> outside the office, use [Cloudflare Tunnel](#deploy-d-cloudflare-tunnel-remote-access)
> rather than opening router ports (and drop `FORCE_SSL=0`, since Cloudflare
> terminates real TLS in front of the tunnel).

---

### Deploy B: Linux server (systemd + Caddy)

1. Clone to `/srv/WeinbergLedger`, `cd backend && bundle install && bin/rails db:migrate`,
   `cd ../frontend && npm run build`.
2. Run the API under **systemd** — `/etc/systemd/system/weinberg-ledger.service`:

   ```ini
   [Unit]
   Description=Weinberg Ledger API
   After=network.target

   [Service]
   WorkingDirectory=/srv/WeinbergLedger/backend
   Environment=PORT=3000
   Environment=RAILS_ENV=production
   Environment=RAILS_MASTER_KEY=PASTE_THE_MASTER_KEY_HERE
   ExecStart=/usr/bin/env bin/rails server
   Restart=always
   User=www-data

   [Install]
   WantedBy=multi-user.target
   ```
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now weinberg-ledger
   ```
   (If Ruby is installed via rbenv, use the full path to its Ruby/gem shims in
   `ExecStart`, e.g. `/home/USER/.rbenv/shims/bundle exec rails server`.)
3. Put **Caddy** in front (Option A) for static files + HTTPS — with a real
   domain behind Caddy, leave `FORCE_SSL` unset (defaults to on).

---

### Deploy C: Windows

1. Install Ruby+Devkit and Node (see [Prerequisites](#prerequisites)).
2. `cd backend && bundle install && bin\rails db:migrate`.
3. `cd frontend && npm run build`.
4. Serve with **Caddy for Windows** (Option A) or use **Option B** and run
   `bin\rails server -e production` (set `FORCE_SSL=0` if there's no TLS in
   front of it). To keep it running as a service, use
   [NSSM](https://nssm.cc/) to wrap the `rails server` command.
5. The `SIGUSR2/SIGUSR1/SIGHUP not implemented` messages Puma prints on Windows
   are harmless — those are POSIX-only restart signals.

---

### Deploy D: Cloudflare Tunnel (remote access)

**Why a tunnel and not Workers/Pages?** This backend is a long-running Ruby
process that writes to a local SQLite file and caches cover images on disk. It
is **not** serverless-compatible, so it can't run on Cloudflare Workers or as a
Pages Function. The clean way to put it on the internet (with HTTPS, no open
router ports) is to run the app on your box and expose it through a
**Cloudflare Tunnel**.

1. Run the app locally so it's reachable at one origin, e.g. Caddy or Rails on
   `http://localhost:8080` (Option A/B). Cloudflare terminates real TLS in
   front of the tunnel, so leave `FORCE_SSL` unset here (default on).
2. Install `cloudflared` and authenticate:
   ```bash
   brew install cloudflared          # macOS; see docs for Linux/Windows
   cloudflared tunnel login
   cloudflared tunnel create weinberg-ledger
   cloudflared tunnel route dns weinberg-ledger ledger.example.com
   ```
3. `~/.cloudflared/config.yml`:
   ```yaml
   tunnel: <TUNNEL-UUID>
   credentials-file: /Users/YOU/.cloudflared/<TUNNEL-UUID>.json
   ingress:
     - hostname: ledger.example.com
       service: http://localhost:8080   # whatever serves dist + /api
     - service: http_status:404
   ```
4. Run it (and `cloudflared service install` to keep it up):
   ```bash
   cloudflared tunnel run weinberg-ledger
   ```

The tunnel must point at the **single same-origin server** (the thing serving
both `dist/` and `/api`), not directly at the API — otherwise the static files
won't be served. Put Cloudflare Access in front of the hostname if you want to
restrict who can reach it.

---

## Configuration reference

All configuration is via environment variables (none are required in
development — defaults shown; `RAILS_MASTER_KEY` is required in production,
see [Secrets](#secrets-the-rails-master-key)).

| Variable              | Default            | Purpose                                                                 |
|------------------------|--------------------|-------------------------------------------------------------------------|
| `PORT`                 | `3000`             | Port the API server binds (on `0.0.0.0`).                               |
| `LIBRARY_DB`           | `../library.db`    | Path to the SQLite database file (relative to `backend/`).              |
| `LIBRARY_IMG_DIR`      | `../img`           | Directory where fetched cover images are cached.                        |
| `DISABLE_OPENLIBRARY`  | *(unset)*          | `1` = skip OpenLibrary (offline; lookups report "not found"). `error` = force the error path. Used by the test suite; handy for fully offline installs. |
| `FORCE_SSL`            | `true` (production only) | `0` to disable Rails' forced HTTPS redirect — needed for a plain-HTTP LAN deployment with no reverse-proxy TLS in front of it. |
| `RAILS_MASTER_KEY`     | *(none)*           | Production secret; alternative to committing/copying `backend/config/master.key`. |

Example (offline install on a box with no internet):
```bash
DISABLE_OPENLIBRARY=1 PORT=8080 bin/rails server
```

---

## Maintenance & backups

- **Back up the data** = back up `library.db`. Because of WAL mode, the safe way
  to snapshot a live DB is:
  ```bash
  sqlite3 library.db ".backup 'backup-$(date +%F).db'"
  ```
  (Copying the file while the server runs can miss un-checkpointed WAL data;
  `.backup` is consistent.)
- The audit log grows over time inside `AUDIT_LOG`. It's small (one row per
  edit) and worth keeping — it's the accountability record.
- Cover images in `img/` are just a cache; safe to delete (they'll refetch).
- `USERS`/`SESSIONS` are in the same `library.db` file, so the same backup
  covers accounts too. A user's session(s) are revoked immediately by
  deleting their row(s) from `SESSIONS` (logging out does this automatically).

---

## Troubleshooting

**`Address already in use ... port 3000 (Errno::EADDRINUSE)`**
Another copy of the server is already running. Find and stop it:
```bash
lsof -ti tcp:3000 | xargs kill        # macOS/Linux
# Windows:  netstat -ano | findstr :3000    then    taskkill /PID <pid> /F
```

**`Missing encryption key to decrypt file with... ActiveSupport::MessageEncryptor::InvalidMessage`**
Rails can't find `backend/config/master.key` and `RAILS_MASTER_KEY` isn't
set. See [Secrets](#secrets-the-rails-master-key) — this file is
intentionally not committed to git.

**The app keeps redirecting to `https://` and the page never loads**
You're on a plain-HTTP LAN/local deployment with Rails' default
`force_ssl` still on. Set `FORCE_SSL=0` (see
[Deploy A](#deploy-a-local-mac-mini-primary-target)).

**`Migrations are pending` / schema errors on boot**
Run `cd backend && bin/rails db:migrate`. Safe to run repeatedly — the
`LIBRARY`/`AUDIT_LOG` migration is a no-op if those tables already exist.

**ISBN lookup returns `503` "temporarily unavailable"**
The server couldn't reach OpenLibrary. It retries automatically; try again, or
enter the book's details manually. On **Windows**, a persistent 503 is usually a
missing TLS CA bundle — verify with:
```
ruby -e "require 'net/http'; u=URI('https://openlibrary.org/api/books?bibkeys=ISBN:9781470418847&format=json&jscmd=data'); p Net::HTTP.start(u.host,u.port,use_ssl:true){|h| h.get(u.request_uri)}.code"
```
If that raises `OpenSSL::SSL::SSLError`, download <https://curl.se/ca/cacert.pem>
and set `SSL_CERT_FILE` to its path (e.g. `setx SSL_CERT_FILE C:\Ruby\ssl\cacert.pem`),
then restart. (Reinstalling Ruby via RubyInstaller's `ridk install` also fixes it.)

**ISBN lookup returns `404`**
That identifier genuinely isn't in OpenLibrary — try a different one (ISBN vs
LCCN vs OCLC) or add the book manually. Bare numbers work; catalog decorations
like `(OCoLC)…` or a trailing `(alk. paper)` will not match.

**"Database is locked" on save**
Two processes are writing at once. Make sure only one server instance is running
against a given `library.db`.

**Frontend loads but API calls fail in production**
You're almost certainly not serving on the [same origin](#the-one-deployment-invariant-same-origin).
Confirm that `https://your-host/api/whoami` returns JSON from the same hostname
that serves the page.

**Can't log in / "You must be logged in" on every request**
The bearer token is stored in the browser's `localStorage`; clearing site
data logs you out. If a token looks valid but requests still 401, the
session may have expired (30-day TTL) or been revoked (e.g. an admin
deleted the account) — log in again.

**Registered but stuck on "pending"**
An admin needs to approve the account from the Users Dashboard. Registrations
left unapproved for more than 24 hours are automatically removed (this is by
design, to reclaim unused 4-digit user IDs) — sign up again if that happens.
