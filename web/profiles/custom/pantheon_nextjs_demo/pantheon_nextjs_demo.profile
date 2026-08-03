<?php

/**
 * @file
 * Install-time behavior for the Pantheon Next.js Demo profile.
 *
 * Adds an installer step that collects the Next.js front end URL, then applies
 * the demo recipes — passing the collected URL as the Site recipe's `base_url`
 * input so the next_site's base/preview/revalidate URLs are configured without
 * hardcoding. Modeled on Drupal CMS's recipe-driven installer.
 */

declare(strict_types=1);

use Drupal\Component\Utility\Crypt;
use Drupal\Core\File\FileSystemInterface;
use Drupal\Core\Recipe\Recipe;
use Drupal\Core\Recipe\RecipeRunner;
use Drupal\pantheon_nextjs_demo\Recipe\PredefinedInputCollector;
use Drupal\user\Entity\User;

/**
 * Implements hook_install_tasks().
 */
function pantheon_nextjs_demo_install_tasks(array &$install_state): array {
  return [
    // Collect the front end URL before any recipe is applied.
    'pantheon_nextjs_demo_frontend_url' => [
      'display_name' => t('Configure front end'),
      'type' => 'form',
      'function' => 'Drupal\pantheon_nextjs_demo\Form\FrontendUrlForm',
      'run' => INSTALL_TASK_RUN_IF_NOT_COMPLETED,
    ],
    // Apply core's base recipes FIRST and let them finish, so node, taxonomy,
    // text formats, etc. exist before the demo recipes are built and validated
    // (recipe validation checks that config-action targets like node.type.page
    // belong to an installed extension).
    'pantheon_nextjs_demo_apply_base' => [
      'display_name' => t('Install the base site'),
      'type' => 'batch',
      'function' => 'pantheon_nextjs_demo_apply_base',
    ],
    // Apply the Site + Content recipes, seeding the front end URL.
    'pantheon_nextjs_demo_apply_recipes' => [
      'display_name' => t('Install content model and front end'),
      'type' => 'batch',
      'function' => 'pantheon_nextjs_demo_apply_recipes',
    ],
    // Provision the OAuth pieces for draft preview (keys, consumer).
    'pantheon_nextjs_demo_configure_preview' => [
      'display_name' => t('Configure draft preview'),
      'function' => 'pantheon_nextjs_demo_configure_preview',
    ],
  ];
}

/**
 * Install task: apply core's base recipes for a headless site.
 *
 * Assembles the pieces of "standard" that a JSON:API backend actually needs —
 * admin/front themes, text formats + CKEditor, and the taxonomy "tags"
 * vocabulary (field_tags references taxonomy_term) — while deliberately avoiding
 * navigation/layout_builder/big_pipe.
 */
function pantheon_nextjs_demo_apply_base(array &$install_state): array {
  $web_root = \Drupal::root();
  $base_recipes = [
    'core_recommended_admin_theme',
    'core_recommended_front_end_theme',
    'basic_html_format_editor',
    'full_html_format_editor',
    'restricted_html_format',
    'tags_taxonomy',
  ];
  $operations = [];
  foreach ($base_recipes as $name) {
    $recipe = Recipe::createFromDirectory($web_root . '/core/recipes/' . $name);
    $operations = array_merge($operations, RecipeRunner::toBatchOperations($recipe));
  }
  return [
    'operations' => $operations,
    'title' => t('Installing the base site'),
  ];
}

/**
 * Install task: apply the Site and Content recipes with the collected URL.
 *
 * Runs after the base recipes, so node/taxonomy/etc. are already installed.
 */
function pantheon_nextjs_demo_apply_recipes(array &$install_state): array {
  $base_url = \Drupal::state()->get('pantheon_nextjs_demo.frontend_url', '');

  // Seed the recipe input. The key is "<recipe-dir-name>.<input-name>"; an empty
  // value falls back to the recipe's declared default.
  $collector = new PredefinedInputCollector([
    'pantheon_nextjs_demo.base_url' => $base_url !== '' ? $base_url : NULL,
  ]);

  $code_root = dirname(\Drupal::root());
  $recipe_paths = [
    $code_root . '/recipes/pantheon_nextjs_demo',
    $code_root . '/recipes/pantheon_nextjs_demo_content',
  ];

  $operations = [];
  foreach ($recipe_paths as $path) {
    if (!is_dir($path)) {
      continue;
    }
    $recipe = Recipe::createFromDirectory($path);
    // Resolve inputs (uses defaults for anything not seeded above).
    $recipe->input->collectAll($collector);
    $operations = array_merge($operations, RecipeRunner::toBatchOperations($recipe));
  }

  return [
    'operations' => $operations,
    'title' => t('Setting up your front end'),
  ];
}

/**
 * Install task: provision the OAuth pieces required for draft preview.
 *
 * The equivalent of `ddev configure-preview`, adapted for Pantheon: keys are
 * written to the private file system, which is writable and persists across
 * deploys (the code directory is read-only). Written defensively — the
 * nextjs_preview role/scope are wired up only if the recipe ships them.
 */
function pantheon_nextjs_demo_configure_preview(): void {
  // The client secret was generated (and shown) on the "Configure front end"
  // step and stored in state; fall back to generating one if it is missing.
  $secret = (string) \Drupal::state()->get('pantheon_nextjs_demo.client_secret', '');
  if ($secret === '') {
    $secret = substr(Crypt::randomBytesBase64(32), 0, 32);
  }

  // 1. Signing keys in the private file system (writable, persistent, not served).
  $file_system = \Drupal::service('file_system');
  $key_dir = 'private://keys';
  if ($file_system->prepareDirectory($key_dir, FileSystemInterface::CREATE_DIRECTORY)) {
    $dir = $file_system->realpath($key_dir);
    $private_path = "$dir/private.key";
    $public_path = "$dir/public.key";
    if (!file_exists($private_path)) {
      $resource = openssl_pkey_new([
        'private_key_bits' => 2048,
        'private_key_type' => OPENSSL_KEYTYPE_RSA,
      ]);
      openssl_pkey_export($resource, $private_key);
      $public_key = openssl_pkey_get_details($resource)['key'];
      file_put_contents($private_path, $private_key);
      file_put_contents($public_path, $public_key);
      @chmod($private_path, 0600);
      @chmod($public_path, 0640);
    }
    \Drupal::configFactory()->getEditable('simple_oauth.settings')
      ->set('public_key', $public_path)
      ->set('private_key', $private_path)
      ->save();
  }
  else {
    \Drupal::messenger()->addWarning(t('Could not prepare the private key directory; set the Simple OAuth keys manually.'));
  }

  // 2. Optional service user holding the nextjs_preview role, if the recipe
  // created that role.
  $entity_type_manager = \Drupal::entityTypeManager();
  $user = NULL;
  if ($entity_type_manager->getStorage('user_role')->load('nextjs_preview')) {
    $user_storage = $entity_type_manager->getStorage('user');
    $existing = $user_storage->loadByProperties(['name' => 'nextjs_preview']);
    $user = $existing ? reset($existing) : User::create(['name' => 'nextjs_preview', 'status' => 1]);
    if (!$user->hasRole('nextjs_preview')) {
      $user->addRole('nextjs_preview');
    }
    $user->save();
  }

  // 3. Default consumer: confidential + secret + client_credentials + a non-zero
  // token lifetime (the default 0 makes tokens expire instantly). The service
  // user and nextjs_preview scope are set only when available.
  $consumer_storage = $entity_type_manager->getStorage('consumer');
  $consumer = $consumer_storage->load(1);
  if (!$consumer) {
    $consumers = $consumer_storage->loadByProperties(['client_id' => 'default_consumer']);
    $consumer = $consumers ? reset($consumers) : NULL;
  }
  if ($consumer) {
    $consumer->set('confidential', TRUE);
    $consumer->set('secret', $secret);
    $consumer->set('grant_types', ['client_credentials', 'refresh_token', 'authorization_code']);
    if ($consumer->hasField('access_token_expiration')) {
      $consumer->set('access_token_expiration', 3600);
    }
    if ($consumer->hasField('refresh_token_expiration')) {
      $consumer->set('refresh_token_expiration', 1209600);
    }
    if ($user) {
      $consumer->set('user_id', $user->id());
    }
    if ($entity_type_manager->hasDefinition('oauth2_scope') && $entity_type_manager->getStorage('oauth2_scope')->load('nextjs_preview')) {
      $consumer->set('scopes', [['scope_id' => 'nextjs_preview']]);
    }
    $consumer->save();
  }

  // The secret was displayed on the "Configure front end" step; remove it from
  // state now that it has been applied to the consumer.
  \Drupal::state()->delete('pantheon_nextjs_demo.client_secret');
  \Drupal::messenger()->addStatus(t('Draft preview configured.'));
}
