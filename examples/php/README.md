# PHP Usage Examples

## Prerequisites

Install the PHP package from the monorepo:
```bash
cd packages/php && composer install
```

## Running the example

```bash
SCRYWATCH_API_KEY=your_key_here php examples/php/basic.php
```

## Files

- `basic.php` — demonstrates all client methods: `info`, `warn`, `error`, `log` (with custom type), and `send` (batch)

## Notes

- The example uses a relative autoload path (`../../packages/php/vendor/autoload.php`) for monorepo development.
- In a real project, use `composer require scrywatch/php` and the standard `vendor/autoload.php`.
