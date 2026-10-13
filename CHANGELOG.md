# Changelog

All notable changes to this project are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The video studio application: a project/library sidebar, a native
  `etaf-video` preview stage for a clip or the rendered cut, details and
  captions panes, a recording pane, a publish pane and a task pane, with
  wide, medium and narrow layouts over one ETAF Runtime.
- Non-destructive editing through the `video-project` CLI: import, trim,
  split, remove, reorder, speed, gain, caption add/update/delete, undo and
  redo, each carrying the revision the form was loaded with.
- Background preview (960 pixel) and screen (1920 pixel, CRF 18) renders
  with a status poll that adopts completed results, resumes interrupted
  exports and cancels only the open project's export; the jobs survive
  closing the application.
- macOS window/display recording with explicit target, audio mode and
  duration; the worker imports the saved file as a new clip.
- A two-step publish flow: silent preview of revision, target, visibility
  and text, then confirmation with the previewed revision; identical
  artifacts are never sent twice and unknown results are never retried.
- Public API: `etaf-video-studio-open`, `/close`, `/state`, `/refresh`, the
  project/import/edit/render/record/publish/selection/stage commands, plus
  `etaf-video-studio-root`, `etaf-video-studio-executable`,
  `etaf-video-studio-theme-mode`, `etaf-video-studio-poll-seconds` and
  `etaf-video-studio-request-timeout`.
