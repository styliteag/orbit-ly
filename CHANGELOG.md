# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-07-09

## [0.1.3] - 2026-07-09

## [0.1.2] - 2026-07-09

### Changed

- Release image publishing now builds the multi-arch Docker image once, pushes all configured tags from that build, and uses the GitHub Actions BuildKit cache to speed up subsequent release builds.

## [0.1.1] - 2026-07-09

### Added

- Added release version tracking through `VERSION`, `CHANGELOG.md`, and `release.sh`, and show the current app version in the navigation bar.
