# Guidebook: Decoupled Drupal 11 + Next.js 16 on Pantheon

Follow this start to finish to stand up a decoupled ("headless") CMS locally and deploy it
to Pantheon: **Drupal 11** as the content backend, **Next.js 16** as the frontend. Content
flows Drupal → Next.js over **JSON:API**; navigation over the **Decoupled Menus linkset**
endpoint; draft preview and on-demand revalidation via the **Next.js for Drupal** module.

**Time:** about 15 minutes for a local stack the first time (DDEV image pulls, Composer, and
npm install dominate).

**End state:** a Drupal backend and a Next.js frontend running as two local DDEV projects,
the frontend rendering live Drupal content — and a clear path to deploy each to Pantheon
(the backend as a **Custom Upstream**, the frontend as a **Front-End Site**).

> This guidebook ships **identically in both repositories** (backend and frontend), so it
> reads the same whichever you cloned. Commands are shown **relative to a repository's
> root** — each repo is a standalone app; there is no shared parent folder when cloned.

New to Next.js on Pantheon? The [Next.js Overview](https://docs.pantheon.io/nextjs) covers the
platform (and [Migrating from Front-End Sites](https://docs.pantheon.io/nextjs/migrating-from-front-end-sites)
if you're on the legacy offering); this guidebook covers standing up *this* Drupal-backed starter.

---

## 1. Prerequisites

### Access

| You need | Notes |
|---|---|
| Pantheon Dashboard access | The workspace/organization your sites and custom upstream belong to |
| GitHub account or organization | Both repos live on GitHub; the frontend (a Front-End Site) deploys **from** GitHub, and the backend is registered as a Custom Upstream from its GitHub repo |

### Tools

```bash
brew install ddev/ddev/ddev terminus   # or your preferred install route
# Docker (Docker Desktop, OrbStack, or Colima) must be installed and running.
```

- **[DDEV](https://ddev.com/) + Docker** — the recommended way to run **both** apps locally.
- **[Terminus](https://docs.pantheon.io/terminus)** — Pantheon's CLI, for deploys and site ops.
- **Node 22+ / npm** — only if you intend to run the frontend **without** DDEV (§4, Option B).
- Composer and Drush are **not** needed on your host — DDEV provides them inside the backend
  container.

### One-time setup

```bash
terminus auth:login --machine-token=<token>   # https://docs.pantheon.io/terminus/install
mkcert -install                                # only if you'll run the frontend on the host over HTTPS
```

### Prerequisite check

```bash
ddev --version && docker info >/dev/null && echo "docker ok"
terminus auth:whoami
```

Resolve anything that errors before continuing.

---

## 2. The repositories & architecture

The backend and frontend are **separate, standalone git repositories** — each independently
versioned and deployable, each with its own DDEV project. Clone whichever you need; git
creates a directory named after the repo:

```bash
git clone git@github.com:willjackson/d11-nextjs-starter-be.git   # → d11-nextjs-starter-be/  (Drupal backend)
git clone git@github.com:willjackson/d11-nextjs-starter-fe.git   # → d11-nextjs-starter-fe/  (Next.js frontend)
```

| Part | Repository | DDEV project | Local URL |
| --- | --- | --- | --- |
| Drupal 11 backend | [`willjackson/d11-nextjs-starter-be`](https://github.com/willjackson/d11-nextjs-starter-be) | `d11-nextjs-be` | https://d11-nextjs-be.ddev.site |
| Next.js 16 frontend | [`willjackson/d11-nextjs-starter-fe`](https://github.com/willjackson/d11-nextjs-starter-fe) | `d11-nextjs-fe` | https://d11-nextjs-fe.ddev.site |

Clone each repository wherever you like — they do **not** need to be in sibling folders.
When both DDEV projects are running, the frontend reaches the backend over the shared,
machine-wide DDEV router **by hostname**, so their locations on disk are irrelevant.

> **Docroot note:** in the backend repo the Drupal docroot is `web/` (standard for the
> `drupal-composer-managed` pattern), so docroot paths below — e.g. `profiles/custom/…` —
> live under `web/`.

The frontend reads content from Drupal over **JSON:API** (`/jsonapi/node/*`) and builds
navigation from the **linkset** endpoint (`/system/menu/nextjs/linkset`), authenticating
with **OAuth** for draft preview; when content changes, Drupal calls the frontend's
**`/api/revalidate`**. Next.js renders the pages visitors see.

- Drupal exposes **Page, Article, Event** content types (+ a **Tags** vocabulary) over
  JSON:API and registers the frontend as a **`next_site`** entity (base/preview/revalidate URLs).
- Next.js maps content to routes: Pages → `/[...slug]` (by path alias), Articles →
  `/posts/[slug]`, Events → `/events/[slug]`, Tags → `/tags`. Navigation comes from the
  Drupal `nextjs` menu via the linkset endpoint (surfaced at `/api/menu`).

### Related projects

The **WordPress-backed** counterpart uses the same Next.js patterns with WordPress + the WP
REST API instead of Drupal + JSON:API:

- [`willjackson/wp-nextjs-starter-be`](https://github.com/willjackson/wp-nextjs-starter-be) — WordPress on Pantheon.
- [`willjackson/wp-nextjs-starter-fe`](https://github.com/willjackson/wp-nextjs-starter-fe) — headless WordPress + Next.js 16.

---

## 3. Run the backend (Drupal) locally

A Drupal 11 site served at its own primary URL (`https://d11-nextjs-be.ddev.site`). From the
**backend** repository root:

```bash
ddev init            # = ddev start + ddev init-site + ddev apply-recipes + ddev show-links
```

- **`ddev init-site`** — Composer install, links local dev settings, `drush site:install`.
- **`ddev apply-recipes`** — installs (from Packagist) and applies the two recipe packages,
  passes the frontend URL into the Site recipe, then provisions OAuth draft preview.
- **`ddev show-links`** — backend URL, an admin login link, and the registered `next_site`.

### Recipes

The content model and demo content ship as two Composer packages under the
`pantheon-systems-ps` org, installed into `recipes/` (gitignored, Composer-populated):

| Recipe | Type | Provides |
| --- | --- | --- |
| `pantheon-systems-ps/pantheon_nextjs_demo` | Site | JSON:API, OAuth, `next`/`decoupled_router`/`consumers`/`simple_oauth`/`pathauto`, the Page/Article/Event content types, the `nextjs` menu, and the `next_site` connection (takes a `base_url` input). |
| `pantheon-systems-ps/pantheon_nextjs_demo_content` | Content | Demo content — Articles, Events, Pages, Tags, images, menu links. Depends on and auto-applies the Site recipe. |

```bash
ddev apply-recipes                              # both recipes (default) + configure preview
ddev apply-recipes pantheon_nextjs_demo         # just the Site recipe (no demo content)
```

`ddev apply-recipes` is a thin wrapper around the standard `drush recipe` workflow that adds
the two things a local environment needs on top of applying the recipes:

1. **Injects the local front-end URL.** It passes the DDEV front end's host
   (`https://d11-nextjs-fe.ddev.site`) into the Site recipe's `base_url` input, so the `nextjs`
   `next_site`'s `base_url` / `preview_url` / `revalidate_url` are wired to your local front end
   without prompting.
2. **Provisions OAuth draft preview** (by calling `ddev configure-preview`) — the pieces that
   carry secrets and so can't ship as recipe config: it generates the Simple OAuth RSA key pair,
   points `simple_oauth.settings` at them, and configures `default_consumer` as confidential
   with a known secret (`nextjs-drupal`) and the `client_credentials` grant.

#### Applying the recipes manually

These are ordinary Drupal recipes — you can skip the wrapper and apply them the standard way
with `drush recipe`, using the **relative path from the project (Composer) root** exactly as
each recipe's own README shows. (The `ddev apply-recipes` wrapper uses the absolute container
path `/var/www/html/recipes/<name>` instead, because `ddev drush` runs from the docroot
(`web/`) — from there, `cd /var/www/html` first, or use the absolute path.) Two things the
wrapper does for you then become manual:

**1. Pass the front-end URL.** `base_url` is an input of the **Site recipe
(`pantheon_nextjs_demo`) only** — the demo-content recipe defines no input of its own. It
prompts (default `http://localhost:3000`) when not provided, so pass it non-interactively,
namespaced to the recipe that defines it. Because the content recipe depends on and re-applies
the Site recipe, pass the same namespaced input there too, or `base_url` resets to its default:

```bash
# Site recipe — defines the base_url input:
drush recipe recipes/pantheon_nextjs_demo \
  --input=pantheon_nextjs_demo.base_url=https://your-frontend.example

# Demo content — no input of its own; the namespaced input flows to the Site recipe it re-applies:
drush recipe recipes/pantheon_nextjs_demo_content \
  --input=pantheon_nextjs_demo.base_url=https://your-frontend.example

drush cache:rebuild
```

The value is written to the `nextjs` `next_site`'s `base_url` / `preview_url` / `revalidate_url`.

**2. Set up the OAuth keys and consumer.** Draft preview and authenticated JSON:API reads use
Simple OAuth (`client_credentials`). Generate the signing keys, point Simple OAuth at them, and
make the consumer confidential with a known secret:

```bash
drush simple-oauth:generate-keys /var/www/html/keys
drush config:set simple_oauth.settings public_key  /var/www/html/keys/public.key
drush config:set simple_oauth.settings private_key /var/www/html/keys/private.key
# then make default_consumer confidential with a known client secret + the client_credentials
# grant (and attach the nextjs_preview role/scope if the recipe defined it). The front end
# authenticates with client_id=default_consumer / client_secret=<that secret>.
```

Keep the client secret and the `keys/` directory out of version control (both are gitignored);
use Pantheon Secrets for the secret in production (see §6).

### Install profile

The backend also ships a recipe-driven install profile in the Drupal docroot at
`profiles/custom/pantheon_nextjs_demo`. It powers the **Pantheon browser install** of a site
created from the custom upstream — it brands the installer, collects the front-end URL,
applies the recipes, and provisions draft preview, on a full standard Drupal baseline (Views,
Field UI, dblog, …). Local DDEV uses the `standard` profile + `ddev apply-recipes` instead
(browser-form install tasks don't run under `drush`).

---

## 4. Run the frontend (Next.js) locally

A standalone Next.js 16 app (App Router, React 19, Tailwind CSS 4) that renders the Drupal
content. There are **two ways to run it** — from the **frontend** repository root.

### Option A — DDEV (recommended)

```bash
ddev init            # start container, seed .env.local, npm install, start the dev server
# day to day:
ddev develop            # start/restart the dev server; attaches to the tmux session (live logs — Ctrl-b d to detach)
ddev develop --background # run it detached, returning to your shell
ddev develop-stop     # stop it
ddev npm <cmd>        # run npm in the project
```

Served at `https://d11-nextjs-fe.ddev.site`. **DDEV is recommended** because it wires up the
whole decoupled setup for you:

- A reverse proxy from the primary HTTPS URL to the Next.js dev server on port 3000
  (`.ddev/nginx-proxy.conf`).
- A route to the Drupal backend over the shared DDEV router
  (`.ddev/docker-compose.backend.yaml` maps `d11-nextjs-be.ddev.site` to the host gateway),
  with **trusted HTTPS**, so server-side fetches "just work."
- A container matched to Pantheon's Node runtime (Node 22).

### Option B — run directly with Node

The frontend is a plain Next.js app, so you can run it without DDEV, from the repo root:

```bash
cp .env.example .env.local          # then edit: point the URLs at a reachable Drupal backend
npm install
npm run dev                          # http://localhost:3000
```

Fine for frontend-only work, but **you own the wiring** DDEV otherwise handles:

- Point `NEXT_PUBLIC_DRUPAL_BASE_URL` / `NEXT_IMAGE_DOMAIN` at a backend your machine can
  reach (a running DDEV backend, or a Pantheon environment URL) — a bare `next dev` will
  **not** discover the DDEV backend on its own.
- To use the DDEV backend over HTTPS, your host must trust DDEV's CA (`mkcert -install`).
- Standalone + cache-handler parity only exercises under `npm run build` / `npm run start`.

**Use DDEV unless you specifically need a bare Node process.**

### Environment variables

Copy `.env.example` → `.env.local` (`ddev init` does this). Both live at the frontend repo
root. On Pantheon, set these as **Pantheon Secrets** — see
[environment variables for Next.js](https://docs.pantheon.io/nextjs/environment-variables)
and [Manage Settings](https://docs.pantheon.io/guides/decoupled/overview/manage-settings).

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_DRUPAL_BASE_URL` | Drupal backend URL (browser + server-side fetches). |
| `NEXT_IMAGE_DOMAIN` | Drupal host allowed for `next/image` (host only). |
| `DRUPAL_CLIENT_ID` / `DRUPAL_CLIENT_SECRET` | Simple OAuth consumer (defaults `default_consumer` / `nextjs-drupal`). |
| `DRUPAL_REVALIDATE_SECRET` | On-demand revalidation secret; matches the Drupal `next_site`. |
| `DRUPAL_PREVIEW_SECRET` | Draft-mode secret; matches the `next_site` preview secret. |

**Setting them on Pantheon (Secrets Manager via Terminus).** Front-End Site env vars are
stored as Pantheon Secrets of `--type=env` (Secrets Manager is built into Terminus 4.2+).
Target `<fe-site>` for **all environments**, or `<fe-site>.<env>` to override one; `--rebuild`
triggers a redeploy so the Node app picks up the change. Use the exact values shown by the
Drupal installer's **Configure front end** step (§6):

```bash
# Set for ALL environments (add --rebuild on the last one → a single redeploy)
terminus secret:site:set <fe-site> NEXT_PUBLIC_DRUPAL_BASE_URL "https://<backend>.pantheonsite.io" --type=env
terminus secret:site:set <fe-site> NEXT_IMAGE_DOMAIN           "<backend>.pantheonsite.io"          --type=env
terminus secret:site:set <fe-site> DRUPAL_CLIENT_ID            "default_consumer"                   --type=env
terminus secret:site:set <fe-site> DRUPAL_CLIENT_SECRET        "<one-time-secret>"                  --type=env
terminus secret:site:set <fe-site> DRUPAL_REVALIDATE_SECRET    "nextjs-drupal"                      --type=env
terminus secret:site:set <fe-site> DRUPAL_PREVIEW_SECRET       "nextjs-drupal"                      --type=env --rebuild

# Override a single environment (e.g. a Multidev branch env)
terminus secret:site:set <fe-site>.<env> NEXT_PUBLIC_DRUPAL_BASE_URL "https://<env>-<backend>.pantheonsite.io" --type=env --rebuild

# Inspect / remove
terminus secret:site:list   <fe-site>
terminus secret:site:delete <fe-site> DRUPAL_PREVIEW_SECRET
```

> `--scope` (`ic`, `user`, `web`) can further restrict a secret; the default is fine for
> Next.js env vars. Full reference: [Managing env vars with Secrets Manager](https://docs.pantheon.io/guides/secrets).

---

## 5. Use the site

1. Log into Drupal (`ddev show-links` → login link, or `ddev drush uli` in the backend repo).
2. Create/edit **Pages, Articles, Events**; assign **Tags**; add items to the `nextjs` menu.
   Path aliases determine the frontend URL for a node.
3. The Next.js frontend renders it: home page, `/posts`, `/events`, `/tags`, and Pages at
   their aliases (e.g. `/about`). Navigation comes from the `nextjs` menu.
4. **Draft preview** and **on-demand revalidation** flow through the `next` module using the
   OAuth consumer and the revalidate/preview secrets — see
   [Configure Content Preview](https://docs.pantheon.io/guides/decoupled/drupal-nextjs-frontend-starters/content-preview).

---

## 6. Deploy to Pantheon

The two apps use **different** Pantheon deployment models — don't mix them up.

### Backend — Custom Upstream (Integrated Composer)

The backend repo is a Pantheon **Custom Upstream** using the `drupal-composer-managed`
pattern: `pantheon.upstream.yml` + `upstream-configuration/` hold the shared platform config
and dependencies; each site's root `composer.json` stays thin. See
[Integrated Composer](https://docs.pantheon.io/guides/integrated-composer) and
[Custom Upstream Usage](https://docs.pantheon.io/guides/integrated-composer/ic-upstreams).

- **New site:** create it from the custom upstream in the dashboard
  ([Create a Composer-managed CMS site](https://docs.pantheon.io/guides/integrated-composer/create));
  Integrated Composer builds it (core, modules, recipe packages) and the install profile
  walks you through connecting the front end.
- **Existing site — pull upstream changes:**
  ```bash
  terminus upstream:updates:status <backend-site>.dev
  terminus upstream:updates:apply  <backend-site>.dev --updatedb
  ```
  > Pantheon caches custom upstreams and syncs the source repo periodically (~hourly), so
  > freshly pushed upstream commits may take a while to appear as available updates.
- Promote through the pipeline: `terminus env:deploy <backend-site>.test`, then `.live`
  ([Pantheon WebOps Workflow](https://docs.pantheon.io/pantheon-workflow)).

### The installer's "Configure front end" step

When you install the backend **from the Pantheon Dashboard/UI** (a site created from the
custom upstream installs with the `pantheon_nextjs_demo` profile), the installer includes a
**Configure front end** step. This is the hand-off between backend and frontend, and it sets
the recommended order of operations: **stand up the backend first**, then use this step to
wire up the front end.

It shows a **copy-paste `.env` block** (with a Copy button) containing exactly the variables
the Next.js front end needs to talk to this backend:

```env
NEXT_PUBLIC_DRUPAL_BASE_URL=<this Drupal site's URL>
NEXT_IMAGE_DOMAIN=<this Drupal host>
DRUPAL_CLIENT_ID=default_consumer
DRUPAL_CLIENT_SECRET=<generated here — shown only once>
DRUPAL_REVALIDATE_SECRET=nextjs-drupal
DRUPAL_PREVIEW_SECRET=nextjs-drupal
```

plus a **Front end URL** field (optional — you can set it later).

> The `DRUPAL_CLIENT_SECRET` is generated during install and **displayed only on this
> screen** — it's hashed once stored on the OAuth consumer, so copy the block now.

Which path you take depends on whether the Front-End Site already exists:

- **Front-End Site already created (you know its URL):** enter that URL in the *Front end
  URL* field and set the copied variables as the site's **Pantheon Secrets**. The frontend is
  fully wired from its first build.
- **Front-End Site not created yet:** copy the `.env` block now (the secret won't be shown
  again) and finish the install; then create the Front-End Site and add these values as its
  **Pantheon Secrets**. Point Drupal at the frontend afterward under **Configuration → Web
  services → Next.js** (the `next_site` base / preview / revalidate URLs) — the installer
  links you there when you leave the URL blank.

If the secret is lost, regenerate it: locally with `ddev configure-preview` (which sets the
dev value `nextjs-drupal`), or on the platform by resetting the `default_consumer` secret and
updating the matching Pantheon Secret.

> **Local DDEV skips this interactive step** — it installs the `standard` profile and runs
> the same OAuth provisioning non-interactively via `ddev configure-preview` (client secret
> `nextjs-drupal`, matching `.env.example`). The `.env` step above is specific to the
> Dashboard/UI install.

### Frontend — Front-End Site (Git deploy)

The frontend deploys as a Pantheon **Front-End Site** — **Git-based, not** `upstream:updates`.
Pantheon builds automatically when you push to the connected repository
([Migrating from Front-End Sites](https://docs.pantheon.io/nextjs/migrating-from-front-end-sites),
[Build details](https://docs.pantheon.io/guides/decoupled/no-starter-kit/build-details)):

```bash
# From the frontend repo root:
git push origin main                                   # → Dev build
git checkout -b my-change && git push origin my-change # → open a PR → Multidev preview
```

- Push `main` → builds & deploys to **Dev**; a feature branch / PR → a **Multidev** preview
  environment ([FES Multidev](https://docs.pantheon.io/guides/decoupled/overview/fes-multidev)).
- Watch the build (Site Dashboard → Overview → **Live Build**), then promote **Dev → Test →
  Live** ([Test and Live for Next.js](https://docs.pantheon.io/nextjs/test-and-live-env)).
- Production runs the **standalone** build with the persistent
  [cache handler](https://docs.pantheon.io/nextjs/architecture)
  (`@pantheon-systems/nextjs-cache-handler`); Node version is pinned via `engines` in
  `package.json`.

---

## Two DDEV projects, one per app

Local dev mirrors production — separate DDEV projects, started independently, coexisting on
the shared `ddev-router`. Each repo carries its own `.ddev/` config at its root.

| | Backend (`d11-nextjs-starter-be`) | Frontend (`d11-nextjs-starter-fe`) |
| --- | --- | --- |
| DDEV `type` | `drupal11` | `generic` (Node 22) |
| Serves | Drupal via PHP-FPM/nginx | Next.js dev server on `:3000`, reverse-proxied |
| Reaches the other | — | host-gateway → backend router (`.ddev/docker-compose.backend.yaml`) |
| Key commands | `init`, `init-site`, `apply-recipes`, `configure-preview`, `show-links` | `init`, `develop`, `develop-stop`, `npm` |

## Command reference

**Backend** (run in the `d11-nextjs-starter-be` repo)

| Task | Command |
| --- | --- |
| Full init (start + install + recipes) | `ddev init` |
| Re-apply recipes (+ demo content) | `ddev apply-recipes` |
| (Re)provision OAuth draft preview | `ddev configure-preview` |
| URLs + admin login + front ends | `ddev show-links` |
| Drush / Composer | `ddev drush <cmd>` / `ddev composer <cmd>` |

**Frontend** (run in the `d11-nextjs-starter-fe` repo)

| Task | Command |
| --- | --- |
| Full init (start + env + deps + dev server) | `ddev init` |
| Start / restart dev server | `ddev develop` (attaches; `--background` to detach) |
| Stop dev server | `ddev develop-stop` |
| npm | `ddev npm <cmd>` |
| Run without DDEV | `npm install && npm run dev` (see §4, Option B) |

## Troubleshooting

- **Frontend shows "Drupal Connection Issue" / empty content:** the backend isn't running or
  `NEXT_PUBLIC_DRUPAL_BASE_URL` doesn't point at a reachable Drupal. Start the backend and
  confirm the frontend's `.env.local`.
- **404s / stale content on the backend:** `ddev drush cache:rebuild`.
- **Frontend can't reach the backend under bare Node:** you're missing the DDEV host-gateway
  route — run the frontend under DDEV (§4, Option A) or point env vars at a public URL.
- **`ddev` project name conflict:** DDEV names are unique per machine; if `d11-nextjs-be` /
  `d11-nextjs-fe` collide, rename in that repo's `.ddev/config.yaml`.
- **Pantheon frontend build didn't pick up my change:** Front-End Sites deploy on **git
  push** — confirm you pushed the branch mapped to the target environment (not
  `terminus upstream:updates`, which is backend-only).
- **`curl` of a dev site returns a "sandbox" page:** dev environments show an interstitial;
  bypass it for automated testing with the documented HTTP header
  ([site plans](https://docs.pantheon.io/guides/account-mgmt/plans/site-plans#bypassing-the-interstitial-page-with-an-http-header-during-automated-testing)).

## Going further

**Backend / Custom Upstream**
- [Integrated Composer](https://docs.pantheon.io/guides/integrated-composer) · [Custom Upstream Usage](https://docs.pantheon.io/guides/integrated-composer/ic-upstreams) · [Create a Composer-managed CMS site](https://docs.pantheon.io/guides/integrated-composer/create)
- [Drupal Composer Managed](https://docs.pantheon.io/drupal-composer-managed) · [Terminus](https://docs.pantheon.io/terminus)

**Frontend / Next.js on Pantheon**
- [Next.js Overview](https://docs.pantheon.io/nextjs) · [Build & Runtime Architecture](https://docs.pantheon.io/nextjs/architecture) · [Migrating from Front-End Sites](https://docs.pantheon.io/nextjs/migrating-from-front-end-sites)
- [Environment variables](https://docs.pantheon.io/nextjs/environment-variables) · [Manage Settings](https://docs.pantheon.io/guides/decoupled/overview/manage-settings) · [Multidev](https://docs.pantheon.io/guides/decoupled/overview/fes-multidev) · [Test & Live](https://docs.pantheon.io/nextjs/test-and-live-env)
- [Configure Content Preview (Drupal + Next.js)](https://docs.pantheon.io/guides/decoupled/drupal-nextjs-frontend-starters/content-preview) · [Troubleshooting](https://docs.pantheon.io/guides/decoupled/overview/troubleshooting)

**Platform**
- [WebOps Workflow](https://docs.pantheon.io/pantheon-workflow) · [Git on Pantheon](https://docs.pantheon.io/guides/git) · [DDEV](https://ddev.com/)
