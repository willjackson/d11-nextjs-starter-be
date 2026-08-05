# CLAUDE.md — Drupal 11 backend

Headless **Drupal 11** content backend for a decoupled **Next.js 16** frontend. Content is
served over JSON:API; navigation over the Decoupled Menus linkset endpoint; draft preview
and revalidation via the Next.js for Drupal (`next`) module.

This repository is a **Pantheon Custom Upstream** (the `drupal-composer-managed` pattern).
Its counterpart frontend repo is
[`willjackson/d11-nextjs-starter-fe`](https://github.com/willjackson/d11-nextjs-starter-fe).
For end-to-end install/use/deploy instructions, see **[GUIDEBOOK.md](GUIDEBOOK.md)**.

## Stack

- **Drupal 11** (`drupal/core-recommended ^11`), **PHP 8.3** (set in `pantheon.upstream.yml`).
- **Drush 13** locally (`drush_version: 10` declared for Pantheon in `pantheon.upstream.yml`).
- **Docroot**: `web/` (`web_docroot: true`); the repo root is the Composer root.
- **Hosting**: Pantheon Custom Upstream + Integrated Composer, MariaDB 10.6.
- Git origin: `git@github.com:willjackson/d11-nextjs-starter-be.git`.

## Layout

The repository root **is** the Drupal Composer project:

```
├── composer.json             # per-site root (thin) — requires the upstream-configuration package
├── upstream-configuration/   # custom-upstream shared deps (modules + recipe packages) + scripts
├── pantheon.upstream.yml      # platform config (php 8.3, mariadb 10.6, drush 10, build_step, protected paths)
├── config/sync/              # exported site configuration
├── recipes/                  # Composer-installed recipe packages (gitignored; see below)
├── .ddev/                    # DDEV project (d11-nextjs-be) — config + init/recipe commands
├── drush/drush.yml           # pins drush --uri to the backend hostname (d11-nextjs-be.ddev.site)
├── private/                  # private files (gitignored)
└── web/                      # Drupal docroot
    └── modules/contrib/, profiles/custom/, …
```

## Custom upstream (Pantheon `drupal-composer-managed`)

Shared dependencies live in `upstream-configuration/composer.json` (the
`pantheon-upstreams/upstream-configuration` package, wired into the root `composer.json` as a
`path` repository); the root `composer.json` is the per-site file that stays thin. Add
upstream-level dependencies to `upstream-configuration/composer.json`
(`composer upstream:require <package>`), not to the root.

- `pantheon.upstream.yml` — platform config: PHP 8.3, MariaDB 10.6, drush 10, `build_step`,
  protected web paths (`/private/`, the files private dir, `files/config/`).
- `upstream-configuration/` — `composer.json` (shared deps: contrib modules
  `next`/`decoupled_router`/`consumers`/`simple_oauth`/`pathauto` + the two recipe packages),
  `scripts/ComposerScripts.php` (pre/post-update hooks), `README.md`, `.gitignore`.

## Recipes

The Next.js configuration and demo content ship as two recipe packages under the
**`pantheon-systems-ps`** org (published on Packagist, tagged `1.0.0`), required by the
upstream:

| Recipe | Type | Role |
| --- | --- | --- |
| `pantheon-systems-ps/pantheon_nextjs_demo` | Site | Decoupled config: `next`, `next_jsonapi`, `decoupled_router`, `consumers`, `simple_oauth`, `pathauto`, the `nextjs` menu, content types (Page/Article/Event). Takes a `base_url` input. |
| `pantheon-systems-ps/pantheon_nextjs_demo_content` | Content | Demo content: Articles, Events, Pages, Tags taxonomy. Depends on and auto-applies the Site recipe. |

`pantheon_nextjs_demo` writes its `base_url` input into `next.next_site.nextjs` (`base_url`,
`preview_url`, `revalidate_url`), enables the `linkset_endpoint` feature flag, and attaches
the `nextjs` menu to the Page type.

> **`recipes/` is gitignored.** Recipes are Composer packages (`type: drupal-recipe`)
> installed into `recipes/{name}` — not committed here. Each recipe's canonical home is its
> own package/repo under `pantheon-systems-ps`; what's in `recipes/` locally is the installed
> copy.

Apply them with `ddev apply-recipes` (see `.ddev/commands/web/apply-recipes`), which applies
`pantheon_nextjs_demo` (passing `base_url` for the front end) and
`pantheon_nextjs_demo_content`, then runs `configure-preview` for the OAuth pieces. The repo
root is the DDEV mount, so recipes resolve under `/var/www/html/recipes`:

```bash
ddev drush recipe /var/www/html/recipes/pantheon_nextjs_demo
ddev drush cache:rebuild
```

## Install profile (`web/profiles/custom/pantheon_nextjs_demo`)

A Drupal-CMS-style, recipe-driven install profile for the **Pantheon browser install** of a
site created from the custom upstream (installs directly with it, no profile picker). Its
install tasks (`pantheon_nextjs_demo.profile`):

1. **Configure front end** — a branded installer step (`src/Form/FrontendUrlForm.php`,
   `themes/pantheon_nextjs_installer`) collecting the Next.js base URL and showing a
   copy-paste `.env` block including the one-time OAuth client secret.
2. **Install the base site** — installs the full standard Drupal baseline (Views, Field UI,
   dblog, block, contextual, page cache + BigPipe, navigation, CKEditor 5, …) minus
   `layout_builder`, plus core recipes for themes, text formats, and the `tags` vocabulary.
3. **Install content model and front end** — applies `pantheon_nextjs_demo` (seeding the
   collected URL) and `pantheon_nextjs_demo_content`.
4. **Configure draft preview** — provisions OAuth (keys in `private://keys`, the default
   consumer).

> **Local DDEV installs the `standard` profile** + `ddev apply-recipes` instead — browser-form
> install tasks don't run cleanly under `drush site:install`. The profile is the path for
> installing a site from the custom upstream in the browser.

## Common commands

Run via DDEV from the repo root (`ddev drush …`), or directly once shelled in.

```bash
drush cache:rebuild                          # cr — first thing to try on 404s / stale config
drush config:export                          # cex — write config to config/sync
drush config:import                          # cim
drush recipe /var/www/html/recipes/<name>    # apply a recipe (absolute path in the container)
drush user:login                             # uli — one-time admin login link
drush updatedb                               # updb
```

Remote (Pantheon) drush via Terminus: `terminus drush <site>.<env> -- cr`.

## Headless / API conventions

- **JSON:API** is the contract with the frontend. Anonymous read access is granted for the
  decoupled content types; don't tighten permissions without checking the frontend.
- **Simple OAuth** (client credentials) authenticates privileged calls (draft preview). The
  default consumer is `default_consumer`; the frontend's `DRUPAL_CLIENT_ID` /
  `DRUPAL_CLIENT_SECRET` must match it.
- **Path aliases** (`pathauto`) determine Next.js routes — design aliases with the frontend
  URL structure in mind.
- The **`nextjs` menu** drives frontend navigation (served via the linkset endpoint).
- Preview/revalidation URLs on the `nextjs` next_site must point at the live frontend
  (`/api/draft`, `/api/revalidate`).

## Gotchas

- This backend is served as its own site/URL; the Next.js frontend is a **separate
  repository** ([`d11-nextjs-starter-fe`](https://github.com/willjackson/d11-nextjs-starter-fe)),
  not part of this repo. Local dev runs each as its own DDEV project.
- `drush/drush.yml` pins `--uri` to the backend's primary URL so drush emits correct absolute
  URLs (login links, etc.); on Pantheon the platform sets the URI.
- A core patch and a `subrequests` PHP-8.4 compatibility patch are applied via
  `cweagans/composer-patches` (see `composer.json` → `extra.patches`); keep them when running
  `composer update`.
