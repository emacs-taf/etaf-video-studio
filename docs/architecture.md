# ETAF Video Studio architecture

## Responsibilities

`etaf-video-studio` is an application. It owns the buffer, the layout, the
selection, the edit forms and the status timers. The `video-project` skill
owns the project store, the edit history, the render/record/publish tasks
and every background process, and ETAF's native `etaf-video` Component owns
decoding and playback. No framework mechanism and no project rule is
re-implemented here.

| Module | Owns |
| --- | --- |
| `etaf-video-studio-app` | the buffer, keys, timers, public commands and the CLI request lifecycle |
| `etaf-video-studio-views` | the shell, panes and rows as pure projections of the snapshot and the draft refs |
| `etaf-video-studio-model` | the application record, the snapshot ref, selection and stage reconciliation, request/pending bookkeeping |
| `etaf-video-studio-backend` | one bounded asynchronous `pi-skill` invocation per request, JSON parsing and the CLI error contract |
| `etaf-video-studio-theme` | the dark/light palettes and their ETAF UI token projection |

The root entry re-exports the supported subset; everything unlisted is
internal.

## Data flow

1. `etaf-video-studio-open` creates the record, displays the buffer, mounts
   the shell and starts a 0.5 s stage clock plus a 2 s status poll. The
   first refresh lists the library; opening a project fetches its public
   `status` object.
2. Every command builds one CLI argument list and passes it to
   `etaf-video-studio--app-request`, which counts the in-flight query,
   publishes a busy snapshot and calls the backend. The backend spawns
   `pi-skill … --json`, accumulates stdout/stderr, and delivers a parsed
   plist to the application buffer when the process exits. A missing
   executable is an immediate `deps` result; a request past
   `etaf-video-studio-request-timeout` is killed and reported. The command
   loop is never blocked.
3. A successful project answer is adopted through
   `etaf-video-studio--app-adopt-project`: the public project replaces the
   record's copy, selections are clamped into the refreshed lists, a
   publish confirmation for another revision is dropped, and the stage
   follows the current revision's completed preview unless the user is
   watching a clip. A changed stage file is probed once for its size with
   `video-edit probe`; the result only sizes the canvas.
4. The shell binds the snapshot ref, the theme ref and the form refs.
   Commands mutate the record and set the snapshot ref, so one publication
   paints the affected panes. The status poll compares a signature of the
   project (revision, updated time, task statuses and receipts) and only
   then republishes; the footer clock and play state reach their Hosts
   through retained content updates instead. Form drafts live in their own
   refs, so a poll never overwrites what a person typed.
5. Background work leaves the application: `render`, `record start` and
   `publish` return a task immediately, and the worker runs in a `job-run`
   process group. A completed preview render becomes `:preview`; a
   completed recording is imported by the worker as a new clip at the end
   of the timeline.
6. `etaf-video-studio-close` cancels the timers, kills the in-flight CLI
   queries and unmounts the Runtime. It never stops a task.

## Invariants

- The CLI is the only writer. The application never reads or writes a
  project file, never rescales a timeline itself and never guesses a
  revision.
- Every mutation carries the revision the form was loaded with. A
  `conflict` answer is reported and the project is re-read; no write is
  retried blindly.
- Publish has two distinct steps: a preview object names revision, target,
  visibility and text, and the confirmation sends the *previewed* revision
  plus `--yes`. A changed revision invalidates the confirmation, and an
  `unknown` result is reported as needing human verification.
- The stage never mounts a missing file, so a stale preview cannot start a
  decoder. A rendered preview is tied to its revision: editing the project
  clears or replaces it instead of presenting an old cut as the new one.
- Views are side-effect free; requests come from commands and callbacks,
  never from a render.
- Hidden panes do not exist in the layout: narrow windows mount only the
  selected pane, wide windows mount the preview and the selected details
  pane. The layout switches with the published viewport and loses no
  feature.

## Failure semantics

| Answer | Application behavior |
| --- | --- |
| `usage` | the offending form stays loaded and the CLI message is shown |
| `deps` | the status line names the missing executable; no retry loop |
| `conflict` | the message asks for a refresh; `g` re-reads the project |
| `blocked` | the skill's reason and hint are shown; `unknown` publishes are never resent automatically |
| `timeout` | the query ends; the background task keeps running and the poll still adopts its result |
| `interrupted` | the task row stays; 续跑导出 resumes the export |

## Layout and sizing

The shell is a fixed plane: a one-row header, a body sized from the
published viewport (`etaf-runtime-viewport`, reactive on refit) and a
two-row footer. The body hosts the sidebar, the preview and the details
column according to two width thresholds (700 and 1100 logical pixels, the
same order as the sibling player). The preview canvas is derived from the
stage's probed aspect, the available centre cells and the frame's cell
metrics, so a resize reflows instead of stretching the picture. Panes that
overflow the body are clipped deliberately; 80×24 is the documented
minimum usable viewport.

## Testing

Public behavior is covered by `tests/etaf-video-studio-tests.el` with a
fixture CLI that records its arguments and answers canned JSON, so the
whole command surface — open/create/import/edit/history/render/record/
publish/state — runs offline. GUI acceptance mounts the real skill against
a real generated clip; see the repository README for the commands.
