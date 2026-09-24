# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.4] - 2026-09-24

## [0.3.3] - 2026-08-11

## [0.3.2] - 2026-08-11

## [0.3.1] - 2026-08-11

## [0.3.0] - 2026-08-11

## [0.2.2] - 2026-08-10

## [0.2.1] - 2026-08-10

## [0.2.0] - 2026-08-10

### Added

- `SMTP_TLS` (`always` (default) / `if_available` / `never`) selects the TLS
  mode of the mailer, so a relay without STARTTLS can be used.

### Changed

- `SMTP_USERNAME`/`SMTP_PASSWORD` are optional: set both for an authenticated
  relay, leave both unset for an internal relay without AUTH (the mailer then
  uses `auth: :never` and sends no credentials). Setting only one of the two
  aborts the boot instead of silently sending unauthenticated. Empty values
  count as unset.

## [0.1.9] - 2026-07-11

### Added

- Production password-reset emails are now sent over authenticated SMTP
  (Swoosh + `gen_smtp`). Relay, credentials, sender, and port are configured at
  runtime via `SMTP_RELAY`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAIL_FROM`, and
  optional `MAIL_FROM_NAME`/`SMTP_PORT`; the release aborts at boot when
  required values are missing. STARTTLS is enforced and the relay certificate
  is verified.

### Security

- Password-reset delivery results are now handled: a successful delivery keeps
  exactly one active reset token per user, while a failed delivery or adapter
  exception removes the newly created token so a previously delivered one stays
  valid. The public response stays generic. (ORB-SEC-004/005)
- Hardened the public redirect hot path against anonymous resource exhaustion:
  the click buffer caps admission and truncates oversized IP/user-agent/referrer
  values, the rate limiter serializes decisions (no more racing past the limit)
  and sweeps entries by their actual window expiry, and the redirect cache
  enforces a hard entry bound with active TTL sweeping. (ORB-SEC-001/002/003)
- Removed Perl from the production runtime image.

## [0.1.8] - 2026-07-10

## [0.1.7] - 2026-07-10

## [0.1.6] - 2026-07-09

## [0.1.5] - 2026-07-09

## [0.1.4] - 2026-07-09

## [0.1.3] - 2026-07-09

## [0.1.2] - 2026-07-09

### Changed

- Release image publishing now builds the multi-arch Docker image once, pushes all configured tags from that build, and uses the GitHub Actions BuildKit cache to speed up subsequent release builds.

## [0.1.1] - 2026-07-09

### Added

- Added release version tracking through `VERSION`, `CHANGELOG.md`, and `release.sh`, and show the current app version in the navigation bar.
