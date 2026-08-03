<?php

declare(strict_types=1);

namespace Drupal\pantheon_nextjs_demo\Recipe;

use Drupal\Core\Recipe\InputCollectorInterface;
use Drupal\Core\TypedData\DataDefinitionInterface;

/**
 * Supplies recipe input values collected during installation.
 *
 * Values are keyed by the input's fully-qualified name, "<recipe-dir>.<input>"
 * (e.g. "pantheon_nextjs_demo.base_url"). An empty/missing value falls back to
 * the recipe's declared default, so a front end URL left blank keeps its default.
 */
final class PredefinedInputCollector implements InputCollectorInterface {

  /**
   * @param array<string, mixed> $values
   *   Predefined input values, keyed by fully-qualified input name.
   */
  public function __construct(private readonly array $values) {}

  /**
   * {@inheritdoc}
   */
  public function collectValue(string $name, DataDefinitionInterface $definition, mixed $default_value): mixed {
    $value = $this->values[$name] ?? NULL;
    return ($value === NULL || $value === '') ? $default_value : $value;
  }

}
