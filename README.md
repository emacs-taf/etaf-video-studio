# etaf-video-studio

Record, edit and publish software tutorials from one ETAF workbench: a
project and clip sidebar, a native video preview, explicit edit forms for
clips and captions, background preview/export tasks, macOS screen recording
and a two-step publish flow. It is the text-application face of the
`video-project` skill and shares its projects with the CLI — no second
source of truth.

## Requirements

- Emacs 29.1 or newer.
- The `pi-skill` CLI with the `video-project` and `video-edit` skills, the
  `job-run` skill, and `ffmpeg` with libass for burned-in captions.
  `pi-skill video-project check` verifies the media side.
- macOS with the `macos-screencast` CLI for recording; other platforms can
  import, edit, export and publish.
- Provider checkouts: `etaf`, `etaf-ui`, `ebox` and `ecss`, either beside
  this repository (`../etaf` and so on) or two directories up (`../../etaf`)
  as in the workspace checkout.

## Install and run

Add this repository root and the four provider roots to `load-path`, then:

```elisp
(require 'etaf-video-studio)
M-x etaf-video-studio-open
```

The studio opens `~/Movies/Video Projects` (or
`PI_SKILL_VIDEO_PROJECT_DIRECTORY`); set `etaf-video-studio-root` to pin a
different library, or call
`(etaf-video-studio-open "project-id" "/path/to/library")`.

Keys: `SPC` play/pause, `v` preview, `e` export, `r` record pane, `R` start
or stop recording, `p` publish, `c` captions, `t` tasks, `i`/`o` mark in/out,
`s` split, `x` remove, `u`/`U` undo/redo, `T` theme, `g` refresh, `?` help,
`q` close. Closing the studio never stops a background task.

## Documentation

- [docs/manual.md](docs/manual.md) — workflows, keys, failure handling and a
  programmatic example.
- [docs/architecture.md](docs/architecture.md) — module responsibilities,
  data flow and invariants.
- The root entry's Commentary is the authoritative public interface list;
  `pi-skill video-project help` documents the shared CLI.

## Development

```sh
make check        # structure, byte compile, public acceptance, API boundary
make test         # only the public acceptance scenarios
make api-check    # root Commentary against the loaded definitions
make clean
```

Interface changes must keep the root Commentary, the manual and
`tests/acceptance.json` in step. GUI behavior changes need a real graphical
pass; `scripts/etaf-video-studio-gui-scenarios.el` drives the controls with
the shared window verifier against a generated clip and a temporary library.
