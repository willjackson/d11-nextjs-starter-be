# CLAUDE.md — Drupal 11 backend

Headless Drupal 11 content backend for the Next.js frontend in `../web`. See the
[root CLAUDE.md](../CLAUDE.md) for the cross-project picture and Pantheon/Terminus ops.

## Stack

- **Drupal 11** (`drupal/core-recommended ^11`), PHP **8.3** local / **8.4** on Pantheon.
- **Drush 13** local (`drush_version: 10` declared in `pantheon.yml`).
- **Docroot**: `web/` (`web_docroot: true`). Composer root is this directory.
- **Hosting**: Pantheon (`pantheon-systems/drupal-integrations`), MariaDB 10.6/10.11.
- Git origin: `git@github.com:willjackson/pantheon-nextjs-demo-drupal.git`.

## Layout

```
drupal/
├── composer.json             # per-site root (thin) — requires the upstream-configuration package
├── upstream-configuration/   # custom-upstream shared deps (modules + recipe packages) + scripts
├── pantheon.upstream.yml     # upstream platform defaults (php 8.3, mariadb 10.6, build_step)
├── pantheon.yml              # per-site platform override (php 8.4, protected paths)
├── config/sync/              # exported site configuration
├── recipes/                  # Composer-installed recipe packages (gitignored; see below)
├── .ddev/                    # backend DDEV project (d11-nextjs-be) — config + init/recipe commands
├── drush/drush.yml           # pins drush --uri to the backend hostname (d11-nextjs-be.ddev.site)
├── private/                  # private files (gitignored on Pantheon)
└── web/                      # Drupal docroot
    ├── modules/contrib/      # Composer-managed contrib modules
    └── ...
```

## Custom upstream (Pantheon `drupal-composer-managed`)

This backend is a **Pantheon custom upstream**. Shared dependencies live in
`upstream-configuration/composer.json` (the `pantheon-upstreams/upstream-configuration`
package, wired into the root `composer.json` as a `path` repository); the root
`composer.json` is the per-site file that stays thin. Add upstream-level dependencies to
`upstream-configuration/composer.json` (e.g. `composer upstream:require <package>`), not to
the root.

- `pantheon.upstream.yml` — upstream platform defaults (PHP 8.3, MariaDB 10.6, drush 10,
  `build_step`, protected paths). `pantheon.yml` is the per-site override (PHP 8.4 here).
- `upstream-configuration/` — `composer.json` (the shared deps: the contrib modules
  `next`/`decoupled_router`/`consumers`/`simple_oauth`/`pathauto` + the two recipe
  packages), `scripts/ComposerScripts.php` (pre/post-update hooks), `README.md`, `.gitignore`.

## Recipes

The Next.js configuration and demo content ship as two recipe packages under the
**`pantheon-systems-ps`** org, required by the upstream:

| Recipe | Type | Role |
| --- | --- | --- |
| `pantheon-systems-ps/pantheon_nextjs_demo` | Site | Decoupled config: `next`, `next_jsonapi`, `decoupled_router`, `consumers`, `simple_oauth`, `pathauto`, the `nextjs` menu, content types (Page/Article/Event). |
| `pantheon-systems-ps/pantheon_nextjs_demo_content` | Content | Demo content: Articles, Events, Pages, Tags taxonomy. Depends on and auto-applies the Site recipe. |

`pantheon_nextjs_demo` takes a `base_url` input (the Next.js base URL) and writes it into
`next.next_site.nextjs` (`base_url`, `preview_url`, `revalidate_url`). It also enables the
`linkset_endpoint` feature flag and attaches the `nextjs` menu to the Page type.

> **`recipes/` is gitignored.** Recipes are Composer packages (`type: drupal-recipe`)
> installed into `recipes/{name}` — not committed to this repo. Each recipe's canonical home
> is its own package/repo under `pantheon-systems-ps`; what lives in `recipes/` locally is the
> working/installed copy.

Apply them with `ddev apply-recipes` (see `.ddev/commands/web/apply-recipes`), which applies
`pantheon_nextjs_demo` (passing `base_url` for the front end) and `pantheon_nextjs_demo_content`,
then runs `configure-preview` for the OAuth pieces. Local testing without publishing (this
`drupal/` dir is the DDEV mount, so recipes resolve under `/var/www/html/recipes`):

```bash
ddev drush recipe /var/www/html/recipes/pantheon_nextjs_demo
ddev drush recipe /var/www/html/recipes/pantheon_nextjs_demo_content
ddev drush cache:rebuild
```

> The recipe packages are published on Packagist (`pantheon-systems-ps/pantheon_nextjs_demo`
> and `…_content`, tagged `1.0.0`), so the root `composer.json` needs no `vcs` repositories —
> they resolve from Packagist like any other dependency.

## Install profile (`web/profiles/custom/pantheon_nextjs_demo`)

A Drupal-CMS-style, recipe-driven install profile for the **Pantheon custom-upstream install
experience**: a site created from this upstream installs directly with it (no profile
picker). Its install tasks (`pantheon_nextjs_demo.profile`):

1. **Configure front end** — a branded installer step (`src/Form/FrontendUrlForm.php`,
   `themes/pantheon_nextjs_installer`) that collects the Next.js base URL and shows a
   copy-paste `.env` block including the one-time OAuth client secret.
2. **Install the base site** — applies curated core recipes (admin/front theme, text
   formats + CKEditor, `tags_taxonomy`) instead of `standard`, avoiding
   navigation/layout_builder/big_pipe that a JSON:API backend doesn't need.
3. **Install content model and front end** — applies `pantheon_nextjs_demo` (seeding the
   collected URL as `base_url`) and `pantheon_nextjs_demo_content`.
4. **Configure draft preview** — provisions OAuth (keys in `private://keys`, the default
   consumer) — the install-time, Pantheon-persistent equivalent of `ddev configure-preview`.

> **Local DDEV still installs the `standard` profile** + `ddev apply-recipes` (form-based
> install tasks don't run cleanly under `drush site:install`). The profile is the path for
> installing a **site from the Pantheon custom upstream** in the browser.

## Common commands

Run via DDEV from this `drupal/` dir (`ddev drush …`), or directly here once shelled in.

```bash
drush cache:rebuild           # cr — first thing to try on 404s / stale config
drush config:export           # cex — write config to config/sync
drush config:import           # cim
drush recipe ../recipes/<name>
drush user:login              # uli — one-time admin login link
drush updatedb                # updb
```

Remote (Pantheon) drush via Terminus: `terminus drush <site>.<env> -- cr`.

## Headless / API conventions

- **JSON:API** is the contract with Next.js. Anonymous read access is granted for the
  decoupled content types; don't tighten permissions without checking the frontend.
- **Simple OAuth** (client credentials) authenticates privileged calls (draft preview).
  The default consumer is `default_consumer`; the frontend's `DRUPAL_CLIENT_ID` /
  `DRUPAL_CLIENT_SECRET` must match a Drupal consumer.
- **Path aliases** (`pathauto`) determine Next.js routes — design aliases with the
  frontend URL structure in mind.
- The **`nextjs` menu** drives frontend navigation (`/api/menu` on the Next.js side).
- Preview/revalidation URLs on the `nextjs` next_site must point at the live frontend
  (`/api/draft`, `/api/revalidate`).

## Gotchas

- This backend is its **own DDEV project** (`d11-nextjs-be`, served at
  `https://d11-nextjs-be.ddev.site`); the Next.js frontend is a separate project (`d11-nextjs-fe`)
  in `../web`. `drush/drush.yml` pins `--uri` to the backend's primary URL so drush emits
  correct absolute URLs (login links, etc.).
- A core patch is applied via `cweagans/composer-patches` (see `composer.json` →
  `extra.patches`); keep it when running `composer update`.
- `pantheon.yml` protects `/private/`, file private dir, and `files/config/`.
- There's a committed DB dump (`d11-headless-nextjs-demo.sql.gz`) used for local seeding.
