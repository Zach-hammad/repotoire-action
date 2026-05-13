# Changelog

## [2.0.0](https://github.com/Zach-hammad/repotoire-action/compare/v1.1.1...v2.0.0) (2026-05-13)


### ⚠ BREAKING CHANGES

* the action now fails the build by default when a Blocking-tier finding lands in the change (previously it never failed unless `fail-on` was set). Set `fail-on-tier: ''` to restore the non-failing default, or `fail-on: high` for the legacy severity gate. The default gate requires `repotoire >= 0.9.0`.

### Features

* default to the 0.9.0 blocking-tier gate (--fail-on-tier blocking) ([#5](https://github.com/Zach-hammad/repotoire-action/issues/5)) ([2da5e9b](https://github.com/Zach-hammad/repotoire-action/commit/2da5e9b8a73ff50a01fa2be395b4f28f575514e5))

## [1.1.1](https://github.com/Zach-hammad/repotoire-action/compare/v1.1.0...v1.1.1) (2026-05-11)


### Bug Fixes

* **diff:** repotoire diff takes [PATH] positionally; handle diff-JSON shape ([#3](https://github.com/Zach-hammad/repotoire-action/issues/3)) ([d5eb1cf](https://github.com/Zach-hammad/repotoire-action/commit/d5eb1cffbe28f9b0cdaa20aacbede34d4ca62aa7))

## [1.1.0](https://github.com/Zach-hammad/repotoire-action/compare/v1.0.0...v1.1.0) (2026-03-19)


### Features

* add comment input and PR Comment composite step ([cec7b9c](https://github.com/Zach-hammad/repotoire-action/commit/cec7b9cc37fdea6adb75ba1ce864055d11b114b4))
* add PR comment script with top-5 findings and update-in-place ([351d06d](https://github.com/Zach-hammad/repotoire-action/commit/351d06d39890651798467ebab08b264b94bfdbc3))


### Bug Fixes

* curl auth header syntax (array), fail-on test uses step outcome ([fbf4353](https://github.com/Zach-hammad/repotoire-action/commit/fbf4353768fff88f4e92bb7f3f806b500b737efa))
* fail-on test — larger fixture, softer assertion, use --fail-on info ([d2b7552](https://github.com/Zach-hammad/repotoire-action/commit/d2b75526c4e7cbc0654c31cf6298a7104a95c246))
* graceful fallback for --json-sidecar, auth for API rate limits ([a8c8d4e](https://github.com/Zach-hammad/repotoire-action/commit/a8c8d4e93398c1769ee43b212382c24a11c1a062))
