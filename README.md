# Decoupled Drupal backend — Pantheon Next.js custom upstream

A Drupal 11 site that serves content to a single Next.js front end over JSON:API. Content
flows from Drupal to the front end; preview and on-demand revalidation are handled by the
Next.js for Drupal (`next`) module. This repo is a **Pantheon custom upstream** — sites
created from it get the decoupled content model, the Next.js wiring, and (optionally) the
demo content out of the box. The matching front end is a separate repository,
[`willjackson/d11-nextjs-starter-fe`](https://github.com/willjackson/d11-nextjs-starter-fe).

**Full setup, usage, and deploy:** see **[GUIDEBOOK.md](GUIDEBOOK.md)** (ships identically in
the backend and front-end repos).

## Stack

- Drupal 11 on PHP 8.3, docroot `web/`, hosted on Pantheon (Integrated Composer).
- DDEV project `d11-nextjs-be`, served at `https://d11-nextjs-be.ddev.site`.
- Front end: a separate Next.js repo (`d11-nextjs-starter-fe`, DDEV project `d11-nextjs-fe`).

## Requirements

- [DDEV](https://ddev.com/) (local development) and Composer.
- Contrib modules, installed via Composer through the upstream (see
  [`upstream-configuration/composer.json`](upstream-configuration/composer.json)):
  `drupal/next`, `drupal/decoupled_router`, `drupal/consumers`, `drupal/simple_oauth`,
  `drupal/pathauto`.

## Quick start (local, DDEV)

```bash
ddev init          # start, Composer install, install Drupal, apply recipes, configure preview
ddev show-links    # admin login link + the registered front end URL
```

`ddev init` runs `ddev init-site` (Composer install + `drush site:install standard`) followed
by `ddev apply-recipes`. Then start the front end from its own repo (`ddev init` there).

## Recipes

The Next.js configuration and demo content ship as two Composer packages under the
`pantheon-systems-ps` org (published on Packagist), installed into `recipes/` and applied by
`ddev apply-recipes`:

| Recipe | Type | Purpose |
| --- | --- | --- |
| [`pantheon_nextjs_demo`](https://github.com/pantheon-systems-ps/pantheon_nextjs_demo) | Site | Content model (Page, Article, Event), JSON:API, OAuth, the `next`/`next_jsonapi`/`decoupled_router`/`consumers`/`pathauto` modules, the `nextjs` menu, and the `next_site` connection. Takes a `base_url` input (the front end URL). |
| [`pantheon_nextjs_demo_content`](https://github.com/pantheon-systems-ps/pantheon_nextjs_demo_content) | Content | Demo content — 7 Articles, 5 Events, 3 Pages, 6 Tags, images, and menu links. Depends on and auto-applies the Site recipe. |

```bash
ddev apply-recipes                          # Site recipe + demo content (default), then configure preview
ddev apply-recipes pantheon_nextjs_demo     # just the Site recipe (no demo content)
```

`apply-recipes` passes the front end's URL into the Site recipe's `base_url` input, so the
`next_site` base/preview/revalidate URLs are configured automatically.

## Custom upstream

This repo follows Pantheon's `drupal-composer-managed` pattern:

- **`pantheon.upstream.yml`** — the upstream platform defaults (PHP 8.3, MariaDB 10.6, drush
  10, `build_step`, protected paths). Sites may add their own `pantheon.yml` to override.
- **`upstream-configuration/`** — the shared dependencies (`pantheon-upstreams/upstream-configuration`,
  wired into the root `composer.json` as a `path` repository). Add upstream-level packages here
  (`composer upstream:require <package>`), not to the root `composer.json`, which stays thin
  per site.
- **`web/profiles/custom/pantheon_nextjs_demo`** — a recipe-driven install profile for the
  **Pantheon browser install**: it brands the installer, collects the front end URL (showing a
  copy-paste `.env` block with a one-time OAuth secret), applies the recipes, and provisions
  draft preview. Local DDEV installs the `standard` profile + `ddev apply-recipes` instead
  (form-based install tasks don't run cleanly under `drush site:install`).

To use it as an upstream: push this repo, then in the Pantheon dashboard add it as a Custom
Upstream and create sites from it. Integrated Composer builds the site (installing the modules
and recipes), and the install profile walks the operator through connecting the front end.

## How the front end connects

- The front end is registered as a Drupal `next_site` entity (`nextjs`) whose `base_url`,
  `preview_url`, and `revalidate_url` point at the Next.js site.
- Content is read over **JSON:API** (e.g. `/jsonapi/node/article`); navigation is served via the
  **linkset endpoint** (`/system/menu/nextjs/linkset`), enabled by the Site recipe.
- Authenticated calls (draft preview) use **Simple OAuth** client credentials. `ddev
  apply-recipes` runs `configure-preview` to generate the signing keys and configure
  `default_consumer` (confidential, secret `nextjs-drupal`).
- The front end's environment variables (base URL, image domain, client id/secret, revalidate
  and preview secrets) are documented in the front-end repo's `.env.example` and in
  [GUIDEBOOK.md](GUIDEBOOK.md).

## Common commands

```bash
ddev drush cache:rebuild        # clear caches (first thing to try on stale config or 404s)
ddev drush config:export        # export configuration
ddev apply-recipes              # re-apply the recipes
ddev configure-preview          # (re)provision the OAuth pieces for draft preview
ddev show-links                 # admin login link + registered front end
```

Remote (Pantheon) drush via Terminus: `terminus drush <site>.<env> -- cache:rebuild`.

## Conventions

- Docroot is `web/` (`web_docroot: true` on Pantheon).
- `recipes/` is Composer-populated and gitignored — recipes are packages, not committed here.
- OAuth keys and secrets are never committed (`keys/` is gitignored; on Pantheon the profile
  writes them to the private filesystem). Use Pantheon Secrets for the front end's client
  secret in production (see [GUIDEBOOK.md](GUIDEBOOK.md) for the Terminus commands).
