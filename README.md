# The Weinberg Theory Group Ledger

A small, self-hosted catalog for a **shared physical library** — it tracks which
book each member owns, who has currently borrowed it, and where it lives on the
shelves, with a full **audit trail** (who changed what, from where, and when).

- **Backend:** Ruby + [Sinatra](https://sinatrarb.com/), data in a single
  **SQLite** file (`library.db`). JSON API on port `4567`.
- **Frontend:** React + [Vite](https://vite.dev/) single-page app. Self-hosted
  fonts and dithered art — **no runtime network dependency** for the UI.
- **External calls:** only OpenLibrary, and only when someone uses the optional
  ISBN/identifier auto-fill or cover thumbnails. Everything else works offline.

---

## Table of contents

1. [Architecture](#architecture)
2. [Repository layout](#repository-layout)
3. [Prerequisites](#prerequisites)
4. [Setup](#setup)
5. [Running in development](#running-in-development)
6. [Tests](#tests)
7. [Database & data](#database--data)
8. [Building for production](#building-for-production)
9. [Deploying](#deploying)
   - [The one deployment invariant](#the-one-deployment-invariant-same-origin)
   - [Serving the built app (3 options)](#serving-the-built-app)
   - [Local Mac mini](#deploy-a-local-mac-mini-primary-target)
   - [Linux server](#deploy-b-linux-server-systemd--caddy)
   - [Windows](#deploy-c-windows)
   - [Cloudflare (remote access)](#deploy-d-cloudflare-tunnel-remote-access)
10. [Configuration reference](#configuration-reference)
11. [Maintenance & backups](#maintenance--backups)
12. [Troubleshooting](#troubleshooting)

---

## Architecture

```
                         ┌──────────────────────────┐
   browser  ── /api/* ──▶│  Sinatra (app.rb)  :4567 │──▶ library.db (SQLite)
      │                  │  JSON API + audit log    │──▶ img/ (cover cache)
      │                  └──────────────────────────┘
      │                            ▲
      └── / , /assets, /fonts ─────┘   (static frontend, built to frontend/dist)
```

- In **development**, the Vite dev server (`:5173`) serves the UI and **proxies**
  `/api/*` to Sinatra (`:4567`). See `frontend/vite.config.js`.
- In **production**, there is no dev server. You build the UI to
  `frontend/dist/` and serve those static files **on the same origin** as the
  API (see [the deployment invariant](#the-one-deployment-invariant-same-origin)).

The frontend always calls the API with **relative** URLs (`/api/...`), so it has
no idea what host/port it is on — which is exactly what makes it portable.

---

## Repository layout

```
WeinbergLedger/
├── app.rb                 # Sinatra API (all routes, ~600 lines)
├── Gemfile / Gemfile.lock # Ruby dependencies
├── library.db             # SQLite database (ships with the catalog)
├── img/                   # cached book covers (created on demand)
├── frontend/
│   ├── index.html
│   ├── vite.config.js     # dev proxy /api -> :4567, Vitest config
│   ├── package.json
│   ├── public/fonts/      # self-hosted woff2 (Space Grotesk / Space Mono)
│   └── src/
│       ├── App.jsx, BookModal.jsx, AddBookModal.jsx, AuditLog.jsx
│       ├── *.css, fonts.css
│       ├── assets/        # generated dither PNGs
│       └── *.test.jsx     # frontend tests (Vitest + Testing Library)
└── README.md
```

---

## Prerequisites

| Tool        | Version              | Needed for                                  |
|-------------|----------------------|---------------------------------------------|
| **Ruby**    | 3.2 – 3.4 (or 4.0)   | running the API server                      |
| **Bundler** | 2.x (`gem install bundler`) | installing Ruby gems                 |
| **Node.js** | 20.19+ (LTS 22 recommended) | building / developing the frontend  |
| **npm**     | 10+ (ships with Node)| frontend dependencies                       |

> **Node is only needed to build or develop the frontend.** A production server
> that just serves the pre-built `frontend/dist/` does **not** need Node.

### Installing the toolchain per OS

**macOS** (Homebrew):
```bash
brew install rbenv node
rbenv install 3.3.3 && rbenv global 3.3.3
gem install bundler
```

**Linux** (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y build-essential libsqlite3-dev
# Ruby via rbenv (recommended) or: sudo apt install ruby-full
# Node 22 via NodeSource:
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
gem install bundler
```

**Windows**:
- Install Ruby+Devkit from [RubyInstaller](https://rubyinstaller.org/) (run
  `ridk install` and pick the MSYS2 toolchain when prompted).
- Install Node LTS from [nodejs.org](https://nodejs.org/).
- See the [Ruby version note](#ruby-version-compatibility) below — newer Ruby on
  Windows needs a couple of extra gem lines.

---

## Setup

```bash
git clone https://github.com/vajralakushal/WeinbergLedger.git WeinbergLedger
cd WeinbergLedger

# 1) Backend gems
bundle install

# 2) Frontend packages
cd frontend
npm install
cd ..
```

### Ruby version compatibility

Ruby **3.4.0** moved several former standard-library files (`csv`, `ostruct`,
`logger`, `base64`) out of the default gems and into *bundled gems*. Under
Bundler they must be declared in the `Gemfile`, or you'll see errors like:

```
cannot load such file -- ostruct (LoadError)
```

- **Ruby 3.2 / 3.3.x** — nothing to do; those files are still default gems.
- **Ruby 3.4+ / 4.0** — add these lines to the `Gemfile`, then `bundle install`:
  ```ruby
  gem 'csv'
  gem 'ostruct'
  gem 'logger'
  gem 'base64'
  ```

> If your team runs a **mix** of Ruby versions across machines, add those lines
> but keep the resulting `Gemfile.lock` change **local** (don't commit it) so a
> lockfile resolved on Ruby 4.0 doesn't break the machine on Ruby 3.2.

---

## Running in development (local)

Open **two terminals**.

**Terminal 1 — API server:**
```bash
bundle exec ruby app.rb
# => listening on http://0.0.0.0:4567
```

**Terminal 2 — frontend dev server:**
```bash
cd frontend
npm run dev
# => open the printed URL, e.g. http://localhost:5173
```

Use the app at the **Vite URL** (`:5173`). It proxies API calls to `:4567`
automatically, so both must be running.

---

## Tests

**Backend** (minitest + rack-test — runs against a throwaway temp DB, never
touches `library.db`, and stays offline):
```bash
bundle exec ruby test/app_test.rb
```

**Frontend** (Vitest + Testing Library):
```bash
cd frontend
npm test          # one-off run
# npx vitest      # watch mode
```

---

## Database & data

- The catalog lives in **`library.db`** (committed, so a fresh clone already has
  the books). SQLite runs in **WAL mode**, so you may also see `library.db-wal`
  and `library.db-shm` next to it — that's normal.
- The **`AUDIT_LOG`** table is created automatically on first server start.
- Every edit / add / remove records a row: who (name), where (IP), what changed
  (old → new), and when. Browse it in the UI under **View audit log**.

**Schema** (for reference / creating a fresh empty DB):
```sql
CREATE TABLE LIBRARY (
  ID            INTEGER PRIMARY KEY,
  OWNER         INTEGER NOT NULL,   -- stores the owner's name
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
```

**Importing books:** use the **Add book** dialog in the UI:
- *Single book* — type an ISBN/LCCN/OCLC and **Look up** to auto-fill fields
  (all still editable), or fill them by hand.
- *Bulk CSV* — paste or upload CSV with the columns
  `Owner, Borrower, Shelf, DD, Title, Creator, Publisher, Edition, Series, Notes, Subject, Creation Date, Identifier`.
  Each row needs a Title, an Owner, and an ISBN or LC identifier (a missing ISBN
  is looked up online when possible; otherwise the row is reported as skipped).

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
Concretely, requests to `https://your-host/api/...` must reach Sinatra, and
everything else must serve `frontend/dist/`. Every recipe below achieves that.

(You *can* split them across origins, but then you must proxy `/api` to the
backend yourself — the app has no configurable API base by design.)

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
        reverse_proxy localhost:4567
    }
    handle {
        root * /srv/WeinbergLedger/frontend/dist
        try_files {path} /index.html
        file_server
    }
}
```
Run Sinatra (`bundle exec ruby app.rb`) and Caddy (`caddy run`) side by side.

#### Option B — Let Sinatra serve the frontend (single process, no extra software)
Add these lines to `app.rb` (near the bottom, by `set :port`). Sinatra then
serves `frontend/dist/` for everything that isn't an `/api/*` route:

```ruby
set :public_folder, File.expand_path('frontend/dist', __dir__)

get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end
```
Then `bundle exec ruby app.rb` serves the whole app on `:4567`. Simplest for a
scrappy single-box deployment. (Put a reverse proxy in front only if you want
HTTPS/compression.)

> These two lines are **not** in the repo yet — add them if you choose Option B.

#### Option C — nginx
```nginx
server {
    listen 80;
    server_name your-host.example.com;
    root /srv/WeinbergLedger/frontend/dist;

    location /api/ { proxy_pass http://127.0.0.1:4567; }
    location /     { try_files $uri /index.html; }
}
```

---

### Deploy A: Local Mac mini (primary target)

Access over the LAN from any machine in the office.

1. Clone, `bundle install`, and `cd frontend && npm run build`.
2. Choose a serving option above. For LAN-only, **Option B** (Sinatra serves
   `dist/`) is simplest — the app is then at `http://<mac-mini-ip>:4567`.
3. Keep it running across logins/reboots with a **LaunchAgent**. Create
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
       <string>cd /Users/YOU/WeinbergLedger && exec bundle exec ruby app.rb</string>
     </array>
     <key>EnvironmentVariables</key>
     <dict><key>PORT</key><string>4567</string></dict>
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
4. Find the Mac mini's IP (`ipconfig getifaddr en0`) and share
   `http://<that-ip>:4567` with the group. macOS may prompt to allow incoming
   connections the first time — allow it.

> **Firewall:** this exposes the app to your local network only. For access from
> outside the office, use [Cloudflare Tunnel](#deploy-d-cloudflare-tunnel-remote-access)
> rather than opening router ports.

---

### Deploy B: Linux server (systemd + Caddy)

1. Clone to `/srv/WeinbergLedger`, `bundle install`, `npm run build` in `frontend/`.
2. Run the API under **systemd** — `/etc/systemd/system/weinberg-ledger.service`:

   ```ini
   [Unit]
   Description=Weinberg Ledger API
   After=network.target

   [Service]
   WorkingDirectory=/srv/WeinbergLedger
   Environment=PORT=4567
   ExecStart=/usr/bin/env bundle exec ruby app.rb
   Restart=always
   User=www-data

   [Install]
   WantedBy=multi-user.target
   ```
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now weinberg-ledger
   ```
   (If Ruby is installed via rbenv, use the full path to its `bundle` shim in
   `ExecStart`, e.g. `/home/USER/.rbenv/shims/bundle exec ruby app.rb`.)
3. Put **Caddy** in front (Option A) for static files + HTTPS.

---

### Deploy C: Windows

1. Install Ruby+Devkit and Node (see [Prerequisites](#prerequisites)).
2. On Ruby 3.4+/4.0, add the [bundled-gem lines](#ruby-version-compatibility) and
   `bundle install`.
3. `cd frontend && npm run build`.
4. Serve with **Caddy for Windows** (Option A) or use **Option B** and run
   `bundle exec ruby app.rb`. To keep it running as a service, use
   [NSSM](https://nssm.cc/) to wrap the `ruby app.rb` command.
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

1. Run the app locally so it's reachable at one origin, e.g. Caddy or Sinatra on
   `http://localhost:8080` (Option A/B).
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

All configuration is via environment variables (none are required — defaults
shown).

| Variable             | Default            | Purpose                                                                 |
|----------------------|--------------------|-------------------------------------------------------------------------|
| `PORT`               | `4567`             | Port the API server binds (on `0.0.0.0`).                               |
| `LIBRARY_DB`         | `./library.db`     | Path to the SQLite database file.                                       |
| `LIBRARY_IMG_DIR`    | `./img`            | Directory where fetched cover images are cached.                        |
| `DISABLE_OPENLIBRARY`| *(unset)*          | `1` = skip OpenLibrary (offline; lookups report "not found"). `error` = force the error path. Used by the test suite; handy for fully offline installs. |

Example (offline install on a box with no internet):
```bash
DISABLE_OPENLIBRARY=1 PORT=8080 bundle exec ruby app.rb
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

---

## Troubleshooting

**`Address already in use ... port 4567 (Errno::EADDRINUSE)`**
Another copy of the server is already running. Find and stop it:
```bash
lsof -ti tcp:4567 | xargs kill        # macOS/Linux
# Windows:  netstat -ano | findstr :4567    then    taskkill /PID <pid> /F
```

**`cannot load such file -- ostruct (LoadError)` (or `csv`, `logger`, `base64`)**
You're on Ruby 3.4+/4.0. Add the [bundled-gem lines](#ruby-version-compatibility)
to the `Gemfile` and `bundle install`.

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
