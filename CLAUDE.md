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
├── composer.json        # dependencies (incl. the recipes below)
├── pantheon.yml         # Pantheon platform config (php 8.4, build_step, protected paths)
├── config/sync/         # exported site configuration
├── recipes/             # applied Drupal recipes (see below)
├── drush/drush.yml      # pins drush --uri to the drupal. hostname
├── private/             # private files (gitignored on Pantheon)
└── web/                 # Drupal docroot
    ├── modules/contrib/ # Composer-managed contrib modules
    └── ...
```

## Recipes

The site is built from recipes rather than a hand-installed profile. Applied with:

```bash
drush recipe ../recipes/<name>
drush cache:rebuild
```

> **`recipes/` is gitignored** (see `.gitignore`). Recipes are distributed as Composer
> packages (`"type": "drupal-recipe"`) and installed into `recipes/{name}` by
> `composer/installers` — they are **not** committed to this repo. So the canonical home
> for each recipe is its own package/repo; what lives in `recipes/` locally is the
> installed copy. New recipes must be published as packages and added via
> `composer require`, not committed here.

| Recipe | Type | Role |
| --- | --- | --- |
| `willjackson/saplings_nextjs` | Site | Decoupled config: `next`, `next_jsonapi`, `decoupled_router`, `consumers`, `simple_oauth`, `pathauto`, the `nextjs` menu, content types (Page/Article/Event). |
| `willjackson/dns_default_content` | Content | Demo content: Articles, Events, Pages, Tags taxonomy. |

`saplings_nextjs` takes a `site_url` input (the Next.js base URL) and writes it into
`next.next_site.nextjs` (`base_url`, `preview_url`, `revalidate_url`). It also enables
the `linkset_endpoint` feature flag and attaches the `nextjs` menu to the Page type.

### Planned recipe replacement (documented, not yet built)

Two recipes will be **replaced** — content to be provided later:

- `saplings_nextjs` → **`pantheon_nextjs_demo`** (Site config recipe)
- `dns_default_content` → **`pantheon_nextjs_demo_content`** (Content recipe)

The replacements are developed at the **project root** — `../pantheon_nextjs_demo` and
`../pantheon_nextjs_demo_content` (relative to this `drupal/` dir) — each as its own
package/repo bound for GitHub. They are intentionally outside `recipes/` (which is
gitignored and Composer-populated). At build time Composer installs them into
`recipes/` like any other recipe package.

Local testing without publishing (from the repo root, the DDEV mount):
```bash
ddev drush recipe /var/www/html/pantheon_nextjs_demo
ddev drush recipe /var/www/html/pantheon_nextjs_demo_content
ddev drush cache:rebuild
```

When the replacements are ready to ship:
1. Publish each recipe package, then update the `require` block in `composer.json`
   (swap the two `willjackson/*` packages).
2. Update install/apply steps that reference the old recipe names/paths — primarily
   `.ddev/commands/web/init-drupal-nextjs` and `.ddev/commands/web/generate-content`.
3. `composer update`, re-run `drush recipe ../recipes/pantheon_nextjs_demo`, then the
   content recipe, then `drush cache:rebuild`.
4. Keep the old recipes in place until the new ones are verified — do not delete
   `recipes/saplings_nextjs` or `recipes/dns_default_content` preemptively.

## Common commands

Run via DDEV from the repo root (`ddev drush …`), or directly here once shelled in.

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

- `drush/drush.yml` pins `--uri` to `http://drupal.d11-nextjs-starter.ddev.site`
  because the primary DDEV URL serves Next.js, not Drupal.
- A core patch is applied via `cweagans/composer-patches` (see `composer.json` →
  `extra.patches`); keep it when running `composer update`.
- `pantheon.yml` protects `/private/`, file private dir, and `files/config/`.
- There's a committed DB dump (`d11-headless-nextjs-demo.sql.gz`) used for local seeding.
