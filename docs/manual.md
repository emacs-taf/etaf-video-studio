# ETAF Video Studio manual

`etaf-video-studio` is the text-application face of the `video-project`
skill. It begins with the skill's help: `pi-skill video-project help`.
Prerequisites are the `pi-skill` CLI with the `video-project` and
`video-edit` skills, `ffmpeg` with libass for burned-in captions, and the
`job-run` skill for background work. Recording additionally needs the
macOS `macos-screencast` CLI. Start the studio with `M-x
etaf-video-studio-open`, or
`(etaf-video-studio-open "video-1" "~/Movies/Video Projects")` to open one
project in a specific library. Every project change goes through the skill,
so the quality bar of `pi-skill video-project` applies unchanged:
non-destructive edits, background jobs that survive Emacs, and an explicit
confirmation before anything leaves the machine.

## Projects

The sidebar lists the projects of the session's library (default
`~/Movies/Video Projects`, or `PI_SKILL_VIDEO_PROJECT_DIRECTORY`). Click a
row to open it. Type a title into the field under the list and press the
新建 button (or RET) to create and open a new project. 刷新 ( `g` )
reloads both the list and the open project. A project shows its revision
and total duration in the header, and the status menu reports the
revision through the CLI parser, so the window and the skill always agree.

The application never reads or writes `project.json`; closing the studio
neither stops a running export/recording/publish nor removes a project.
Reopening re-reads the library.

## Recording

Open the recording pane (`r`) and press 刷新目标 to list the current macOS
windows and displays. Targets come from the CLI's inventory at that
moment; a stale ID is rejected by the skill. Select a row, choose the audio
mode (`none` by default; `system`, `microphone` or both) and the maximum
duration (1–7200 seconds), then 开始录制 (`R`). 停止录制 sends the stop
request; the worker saves the file and imports it as a new clip at the end
of the timeline. Recording failures leave the partial source file alone.

## Importing

`a` (or the 导入 button) asks for one video file and imports it as a new
clip. Repeat the command to add more. The CLI probes each file's duration;
an unreadable file is rejected before the project changes.

## Editing

The clip list is the timeline. Selecting a row (click, RET, or
`etaf-video-studio-select-clip`) shows its facts and the edit form in the
details column, and loads the source into the preview stage so `i`, `o` and
`s` can mark positions while watching.

| Action | Form | Key |
| --- | --- | --- |
| Trim to source in/out | 入点 出点 应用 | `i` / `o` mark from the stage |
| Split | 分割点 分割 | `s` at the stage position |
| Move | 上移 / 下移 | `,` / `.` |
| Remove | 删除 | `x` (undo restores it) |
| Speed | 速度选择 + 应用速度 | — |
| Gain | 增益选择 + 应用增益 | — |
| Undo / redo | 撤销 / 重做 | `u` / `U` |

Source times are seconds in the *material*; captions are positioned on the
*finished* timeline. The CLI remaps captions when clips are trimmed, split,
reordered, sped up or removed, and the skill's history (100 snapshots)
covers every edit. An operation reports `conflict` when another entry
changed the project since the form was loaded; 刷新 (`g`) re-reads it
before retrying. Nothing is written until the operation is applied.

Captions live in the 字幕 pane: select a row to load it into the form, edit
the start/end seconds and text, then 更新说明. RET in the text field
submits the same update. `删除` removes the selected caption and 新建
clears the form for a new one.

## Preview and playback

`v` starts a low-resolution (960 pixel) preview render of the current
revision in the background. While it runs, the task pane shows its status;
when it completes, the stage switches to the rendered cut and 成片预览 /
选中片段 switches between the cut and the selected clip's material. The
preview is always the same edit decision list as the export, so a cut that
plays here is the cut that renders.

The stage plays silently by default; `m` toggles sound. `SPC` play/pause,
`f`/`b` seek five seconds, and the footer clock follows the native video
session. Editing the project makes the rendered preview stale: it is
replaced by the next completed preview of the new revision instead of
pretending to be the new cut. The stage falls back to a density-ramp canvas
on terminal frames.

## Exporting

`e` starts a background screen-profile export (1920 pixel, CRF 18) of the
current revision. The task pane (`t`) lists tasks with status and output;
续跑导出 resumes an interrupted export and reuses validated segments, and
取消导出 stops only this project's export. Closing the studio does not
stop these jobs — they belong to `job-run`. A failed export keeps its task
and message, and 续跑导出 retries from the finished segments.

## Publishing

The 发布 pane previews before it sends. Choose the target (`Telegram` or
公开链接), fill the chat ID for Telegram, and optionally the text and
topic; 预览发布 asks the CLI for a preview object naming the revision,
target, visibility and text. Nothing is sent. Review it, then 确认发布
sends the same request with the previewed revision and `--yes`; a project
that changed in between requires a new preview, and an identical artifact
and text is never sent again. A publish whose result is unknown is reported
as such and must be checked against the target — the application never
retries it automatically.

## Layout and keys

Wide windows show the project/clip sidebar, the preview stage and the
details column; ordinary windows show the sidebar and tabbed panes; narrow
windows show only the panes, with 项目 as a tab, so no feature disappears.
The minimum usable viewport is 80 columns by 24 rows; below that the layout
keeps its structure and the window clips deliberately. The footer always
carries the key hints; `?` opens ETAF's full help, `M-g` jumps between
regions and TAB moves focus.

## State and programmatic use

`etaf-video-studio-state` returns a detached plist of the open buffer;
`etaf-video-studio-open`, `etaf-video-studio-open-project`,
`etaf-video-studio-create-project`, `etaf-video-studio-import-files` and
the command functions cover the documented workflows, and
`etaf-video-studio-close` releases timers and in-flight queries. The root
entry Commentary is the authoritative interface list.

```elisp
(let* ((root (make-temp-file "library-" t))
       (etaf-video-studio-root root)
       (buffer (etaf-video-studio-open)))
  (etaf-video-studio-create-project "第一个教程")
  ;; Wait for the CLI round trips, then inspect the public state.
  (plist-get (etaf-video-studio-state) :project))
```
