<?php

declare(strict_types=1);

namespace Drupal\pantheon_nextjs_demo\Form;

use Drupal\Component\Utility\Crypt;
use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\State\StateInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Installer step: configure the front end and show its environment variables.
 *
 * Collects the Next.js front end's base URL (used to configure the next_site)
 * and shows a ready-to-paste .env block with a copy button and a collapsible
 * view. This is where the operator is directed to create the front end site, so
 * the OAuth client secret — generated here and embedded in the block — is
 * available to set when creating the Next.js environment. The secret only
 * appears during installation (it is hashed once stored on the consumer).
 */
final class FrontendUrlForm extends FormBase {

  /**
   * Revalidate/preview secret shipped in the Site recipe's next_site config.
   */
  private const REVALIDATE_SECRET = 'nextjs-drupal';

  public function __construct(private readonly StateInterface $stateService) {}

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container): self {
    return new self($container->get('state'));
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId(): string {
    return 'pantheon_nextjs_demo_configure_front_end';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $form['#title'] = $this->t('Configure front end');
    $form['#attached']['library'][] = 'pantheon_nextjs_demo/env_copy';

    // Generate and persist the client secret once, so it is stable across form
    // rebuilds and available to the provisioning step. It is not editable — it is
    // shown only within the environment-variable block below.
    $secret = (string) $this->stateService->get('pantheon_nextjs_demo.client_secret', '');
    if ($secret === '') {
      $secret = substr(Crypt::randomBytesBase64(32), 0, 32);
      $this->stateService->set('pantheon_nextjs_demo.client_secret', $secret);
    }

    $request = $this->getRequest();
    $base_url = $request->getSchemeAndHttpHost();
    $host = $request->getHost();

    $form['intro'] = [
      '#markup' =>
        '<p>' . $this->t('Enter the base URL of your Next.js front end. This configures the site in Drupal (its base, preview and revalidate URLs). Leave it blank to set it later.') . '</p>' .
        '<p><strong>' . $this->t('Creating your front end site?') . '</strong> ' . $this->t('Create it in your Pantheon dashboard, pointing it at this Drupal site, and set the environment variables shown below (in the site\'s <code>.env.local</code> locally, or Pantheon Secrets on the platform). These values — including the OAuth client secret — are shown only during installation, so copy them now.') . '</p>',
    ];

    $dom_id = 'pntn-env';
    $form['front_end'] = [
      '#type' => 'fieldset',
      '#title' => $this->t('Next.js front end'),
    ];
    // 1. Copy button (always visible) + collapsible, formatted env block.
    $form['front_end']['env'] = [
      '#type' => 'inline_template',
      '#template' => <<<'TWIG'
        <div class="pntn-env">
          <div class="pntn-env__toolbar">
            <span class="pntn-env__label">{{ 'Environment variables'|t }}</span>
            <button type="button" class="button button--small pntn-env__copy" data-pntn-copy="{{ dom_id }}">{{ 'Copy'|t }}</button>
          </div>
          <details class="pntn-env__details">
            <summary>{{ 'Show variables'|t }}</summary>
            <pre id="{{ dom_id }}" class="pntn-env__pre">{{ env }}</pre>
          </details>
        </div>
        TWIG,
      '#context' => [
        'dom_id' => $dom_id,
        'env' => self::envBlock($secret, $base_url, $host),
      ],
    ];
    // 2. Field-level instructions describing the process.
    $form['front_end']['steps'] = [
      '#markup' => '<p class="pntn-env__steps description">' . $this->t('Copy these variables, then create the front end site in your Pantheon dashboard using them (as Pantheon Secrets, or a local <code>.env.local</code>). Once the site is running, paste its URL below so Drupal can send it preview and revalidation requests.') . '</p>',
    ];
    // 3. The resulting front end URL.
    $form['front_end']['url'] = [
      '#type' => 'url',
      '#title' => $this->t('Front end URL'),
      '#placeholder' => 'https://your-frontend.example.com',
      '#description' => $this->t('The base URL where the Next.js front end is served. Leave blank to set it later at Configuration → Web services → Next.js.'),
    ];

    $form['actions'] = ['#type' => 'actions'];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('Save and continue'),
      '#button_type' => 'primary',
    ];
    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state): void {
    $url = rtrim((string) $form_state->getValue('url'), '/');
    $this->stateService->set('pantheon_nextjs_demo.frontend_url', $url);
  }

  /**
   * Builds the .env block the front end needs to talk to this backend.
   */
  private static function envBlock(string $secret, string $base_url, string $host): string {
    return implode("\n", [
      'NEXT_PUBLIC_DRUPAL_BASE_URL=' . $base_url,
      'NEXT_IMAGE_DOMAIN=' . $host,
      'DRUPAL_CLIENT_ID=default_consumer',
      'DRUPAL_CLIENT_SECRET=' . $secret,
      'DRUPAL_REVALIDATE_SECRET=' . self::REVALIDATE_SECRET,
      'DRUPAL_PREVIEW_SECRET=' . self::REVALIDATE_SECRET,
    ]);
  }

}
