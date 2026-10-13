;;; etaf-video-studio-views.el --- Views of etaf-video-studio -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Views are pure projections of the model snapshot and the draft refs; no
;; storage, network, process or controller call belongs here, because ETAF
;; rejects a render with side effects.  The shell is a flow layout: a fixed
;; header, a resizable body (project/clip sidebar, centred preview, details
;; column on wide viewports, or tabbed panes on narrow ones) and a fixed
;; footer.  Every control a person can press carries a stable `:ref', so a
;; GUI pass can focus and activate it without synthesising clicks.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-video-studio-theme)
(require 'etaf-video-studio-model)

(declare-function etaf-video-studio-import-files "etaf-video-studio-app" (files))
(declare-function etaf-video-studio-create-project "etaf-video-studio-app" (title))
(declare-function etaf-video-studio-refresh "etaf-video-studio-app" ())
(declare-function etaf-video-studio-open-project "etaf-video-studio-app" (project))
(declare-function etaf-video-studio-select-pane "etaf-video-studio-app" (pane))
(declare-function etaf-video-studio-select-clip "etaf-video-studio-app" (index))
(declare-function etaf-video-studio-select-caption "etaf-video-studio-app" (index))
(declare-function etaf-video-studio-select-target "etaf-video-studio-app" (index))
(declare-function etaf-video-studio-select-task "etaf-video-studio-app" (index))
(declare-function etaf-video-studio-apply-trim "etaf-video-studio-app" ())
(declare-function etaf-video-studio-apply-split "etaf-video-studio-app" ())
(declare-function etaf-video-studio-apply-speed "etaf-video-studio-app" ())
(declare-function etaf-video-studio-apply-gain "etaf-video-studio-app" ())
(declare-function etaf-video-studio-move-clip-up "etaf-video-studio-app" ())
(declare-function etaf-video-studio-move-clip-down "etaf-video-studio-app" ())
(declare-function etaf-video-studio-remove-selected-clip "etaf-video-studio-app" ())
(declare-function etaf-video-studio-undo "etaf-video-studio-app" ())
(declare-function etaf-video-studio-redo "etaf-video-studio-app" ())
(declare-function etaf-video-studio-render-preview "etaf-video-studio-app" ())
(declare-function etaf-video-studio-render-screen "etaf-video-studio-app" ())
(declare-function etaf-video-studio-cancel-render "etaf-video-studio-app" ())
(declare-function etaf-video-studio-refresh-targets "etaf-video-studio-app" ())
(declare-function etaf-video-studio-show-captions "etaf-video-studio-app" ())
(declare-function etaf-video-studio-show-publish "etaf-video-studio-app" ())
(declare-function etaf-video-studio-show-record "etaf-video-studio-app" ())
(declare-function etaf-video-studio-show-tasks "etaf-video-studio-app" ())
(declare-function etaf-video-studio-seek-forward "etaf-video-studio-app" ())
(declare-function etaf-video-studio-seek-backward "etaf-video-studio-app" ())
(declare-function etaf-video-studio-toggle-record "etaf-video-studio-app" ())
(declare-function etaf-video-studio-publish-preview "etaf-video-studio-app" ())
(declare-function etaf-video-studio-publish-confirm "etaf-video-studio-app" ())
(declare-function etaf-video-studio-publish-reset "etaf-video-studio-app" ())
(declare-function etaf-video-studio-add-caption "etaf-video-studio-app" ())
(declare-function etaf-video-studio-delete-caption "etaf-video-studio-app" ())
(declare-function etaf-video-studio-clear-caption-form "etaf-video-studio-app" ())
(declare-function etaf-video-studio-stage-selected-clip "etaf-video-studio-app" ())
(declare-function etaf-video-studio-stage-preview-output "etaf-video-studio-app" ())
(declare-function etaf-video-studio-toggle-playback "etaf-video-studio-app" ())
(declare-function etaf-video-studio-toggle-stage-audio "etaf-video-studio-app" ())
(declare-function etaf-video-studio-mark-in "etaf-video-studio-app" ())
(declare-function etaf-video-studio-mark-out "etaf-video-studio-app" ())
(declare-function etaf-video-studio-split-at-stage "etaf-video-studio-app" ())
(declare-function etaf-video-studio-toggle-theme "etaf-video-studio-app" ())
(declare-function etaf-video-studio-close "etaf-video-studio-app" ())
(declare-function etaf-video-studio-task-retry "etaf-video-studio-app" ())

(defconst etaf-video-studio--sidebar-width '(ch 32)
  "Width of the project and clip sidebar.")

(defconst etaf-video-studio--aside-width '(ch 34)
  "Width of the wide-layout details column.")

(defconst etaf-video-studio--sidebar-min-pixels 700
  "Published viewport width from which the sidebar column is shown.")

(defconst etaf-video-studio--aside-min-pixels 1100
  "Published viewport width from which the details column is shown.")

(defconst etaf-video-studio--tab-keys
  '((projects . "项目")
    (clips . "片段")
    (preview . "预览")
    (properties . "属性")
    (captions . "字幕")
    (record . "录制")
    (publish . "发布")
    (tasks . "任务"))
  "Tab labels by pane key.")

(defun etaf-video-studio--view-value (value)
  "Read a display VALUE or a reactive value inside its consuming Host."
  (if (or (etaf-ref-p value) (etaf-computed-p value)) (etaf-value value) value))

(defun etaf-video-studio--border (color)
  "Return a one-pixel solid border in COLOR."
  (list '(px 1) 'solid color))

(defun etaf-video-studio--clock (seconds)
  "Format SECONDS as a playback clock."
  (let* ((seconds (max 0 (round (or seconds 0))))
         (hours (/ seconds 3600))
         (minutes (/ (% seconds 3600) 60))
         (rest (% seconds 60)))
    (if (> hours 0)
        (format "%d:%02d:%02d" hours minutes rest)
      (format "%02d:%02d" minutes rest))))

(defun etaf-video-studio--seconds (value)
  "Format a plan VALUE of seconds without trailing zeros."
  (if (numberp value)
      (let ((text (format "%.3f" (float value))))
        (replace-regexp-in-string "\\.?0+\\'" "" text))
    "—"))

(defun etaf-video-studio--basename (path)
  "Return PATH's file name, or an em dash for nil."
  (if (and (stringp path) (not (string-empty-p path)))
      (file-name-nondirectory path)
    "—"))

(defun etaf-video-studio--status-variant (status)
  "Return the badge variant for a task STATUS string."
  (pcase status
    ("completed" 'success)
    ((or "failed" "unknown") 'danger)
    ((or "running" "recording" "sending" "queued" "stopping") 'warning)
    ((or "interrupted" "lost") 'warning)
    (_ 'neutral)))

(defun etaf-video-studio--clip-duration (clip)
  "Return CLIP's contribution to the timeline, or nil when unknown."
  (let ((in (plist-get clip :in))
        (out (plist-get clip :out))
        (speed (or (plist-get clip :speed) 1)))
    (when (and (numberp in) (numberp out) (numberp speed) (> speed 0))
      (/ (- out in) (float speed)))))

(defun etaf-video-studio--stage-grid (aspect viewport-width viewport-rows sidebar aside)
  "Return the canvas (COLUMNS . ROWS) fitting the available centre space.
ASPECT is `(WIDTH . HEIGHT)' of the source; VIEWPORT-WIDTH and VIEWPORT-ROWS
are the published viewport; SIDEBAR and ASIDE say which columns exist."
  (let* ((cell-width (max 1 (frame-char-width)))
         (cell-height (max 1 (frame-char-height)))
         (reserved-ch (+ (if sidebar 32 0) (if aside 34 0) 6))
         (reserved-rows 8)
         (center-ch (max 16 (- (floor viewport-width cell-width) reserved-ch)))
         (available-rows (max 5 (- viewport-rows reserved-rows)))
         (aspect (if (and (consp aspect) (numberp (car aspect)) (numberp (cdr aspect))
                          (> (car aspect) 0) (> (cdr aspect) 0))
                     aspect (cons 16 9)))
         (by-width (max 12 (1- center-ch)))
         (rows-for-width (max 3 (round (/ (* by-width cell-width (cdr aspect))
                                          (* cell-height (car aspect))))))
         (columns (if (> rows-for-width available-rows)
                      (max 12 (round (/ (* available-rows cell-height (car aspect))
                                       (* cell-width (cdr aspect)))))
                    by-width))
         (rows (min available-rows
                    (max 3 (round (/ (* columns cell-width (cdr aspect))
                                     (* cell-height (car aspect))))))))
    (cons columns rows)))

(defun etaf-video-studio--pane-tabs (_state layout)
  "Return the tab items for STATE in LAYOUT.
The sidebar and the details column already show some panes, so the tab set
follows what the layout hides instead of repeating visible content."
  (let ((keys (cond
               ((eq layout 'wide) '(properties captions record publish tasks))
               ((eq layout 'narrow) '(projects clips preview properties captions record publish tasks))
               (t '(preview properties captions record publish tasks)))))
    (cl-loop for key in keys
             collect (list :key key
                           :label (alist-get key etaf-video-studio--tab-keys)))))

(defun etaf-video-studio--effective-pane (state layout)
  "Return the pane actually shown for STATE's selected pane in LAYOUT.
A pane that is visible in a column has no tab, so selecting it falls back to
the first tab of the layout instead of hiding every pane."
  (let* ((keys (mapcar (lambda (item) (plist-get item :key))
                       (etaf-video-studio--pane-tabs state layout)))
         (pane (plist-get state :pane)))
    (if (memq pane keys) pane (car keys))))

;;; Small shared components

(etaf-define-component etaf-video-studio--section-title
    (&key icon title action-label on-action disabled action-ref)
  "Render one section caption with an optional ghost action button."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1))
    (etaf-ui-icon :name (or icon 'list) :set 'svg :size 0.9 :min-width 2
                  :color (etaf-video-studio-color :muted))
    (box :height '(lh 1) :font-weight 'bold :color (etaf-video-studio-color :ink)
      (text (expr title)))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0))
    (etaf-button :if action-label :label action-label :variant 'ghost
                 :disabled disabled :ref action-ref :on-press on-action)))

(etaf-define-component etaf-video-studio--fact
    (&key label value value-color)
  "Render a label and a right-aligned value in one standard row."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1))
    (box :width '(ch 7) :height '(lh 1) :overflow 'hidden
         :color (etaf-video-studio-color :muted)
      (text (expr label)))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :text-align 'right
         :color (or value-color (etaf-video-studio-color :ink))
      (text (expr value)))))

(etaf-define-component etaf-video-studio--placeholder
    (&key title description action-label on-action)
  "Render an empty-state block inside a pane."
  :view
  (etaf-empty :title title :description description
              :action-label action-label :on-action on-action))

;;; Sidebar: projects and clips

(etaf-define-component etaf-video-studio--project-row
    (&key project selected on-press)
  "Render one project row with its revision badge."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0
        :ref (intern (format "video-studio-project-%s" (plist-get project :id)))
        :background-color (etaf-video-studio-color (if selected :accent-soft :panel))
        :hover-style (unless selected
                       (list :background-color (etaf-video-studio-color :hover)))
        :on-press on-press
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :font-weight (if selected 'bold 'normal)
         :color (etaf-video-studio-color (if selected :accent :ink))
      (text (expr (or (plist-get project :title) "未命名"))))
    (etaf-badge :text (format "r%s" (or (plist-get project :revision) 0))
                :variant 'neutral)))

(etaf-define-component etaf-video-studio--clip-row
    (&key clip index selected on-press)
  "Render one clip row: order, source name, trimmed length and rate."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0
        :ref (intern (format "video-studio-clip-%d" index))
        :background-color (etaf-video-studio-color (if selected :accent-soft :panel))
        :hover-style (unless selected
                       (list :background-color (etaf-video-studio-color :hover)))
        :on-press on-press
    (box :width '(ch 3) :height '(lh 1) :text-align 'right
         :color (etaf-video-studio-color (if selected :accent :dim))
      (text (expr (number-to-string (1+ index)))))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :font-weight (if selected 'bold 'normal)
         :color (etaf-video-studio-color (if selected :accent :ink))
      (text (expr (etaf-video-studio--basename (plist-get clip :file)))))
    (box :height '(lh 1) :color (etaf-video-studio-color :muted)
      (text (expr (etaf-video-studio--seconds
                   (etaf-video-studio--clip-duration clip)))))
    (etaf-badge :if (or (/= 1 (or (plist-get clip :speed) 1))
                        (/= 1 (or (plist-get clip :gain) 1)))
                :text (format "%sx%s" (etaf-video-studio--seconds (or (plist-get clip :speed) 1))
                              (let ((gain (or (plist-get clip :gain) 1)))
                                (if (= gain 1) "" (format " %s" (etaf-video-studio--seconds gain)))))
                :variant 'info)))

(etaf-define-component etaf-video-studio--projects
    (&key app state)
  "Render the project list, the create form and the open action."
  :render
  (let* ((projects (plist-get state :projects))
         (project (plist-get state :project))
         (current (plist-get project :id))
         (new-title (etaf-video-studio--app-new-title-ref app))
         (pending (> (or (plist-get state :pending) 0) 0)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 0)
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'list :title (format "项目 (%d)" (length projects))
        :action-label "刷新" :action-ref 'video-studio-refresh
        :on-action (lambda () (etaf-video-studio-refresh)))
       (etaf-video-studio--placeholder
        :if (null projects)
        :title "还没有视频项目" :description "在下面输入标题新建一个")
       (flex :for (entry projects) :key (plist-get entry :id)
             :flex-direction 'column :width 'stretch
         (etaf-video-studio--project-row
          :project entry :selected (equal current (plist-get entry :id))
          :on-press (lambda () (etaf-video-studio-open-project entry))))
       (box :height '(lh 1))
       (flex :flex-direction 'row :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1))
         (flex :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0)
           (etaf-text-input :bind new-title :hide-label t :placeholder "新项目标题"
                            :ref 'video-studio-new-title
                            :on-submit (lambda (text)
                                         (etaf-video-studio-create-project text))))
         (etaf-button :label "新建" :variant 'primary :disabled pending
                      :ref 'video-studio-create
                      :on-press (lambda ()
                                  (etaf-video-studio-create-project
                                   (etaf-value new-title)))))))))

(etaf-define-component etaf-video-studio--clips
    (&key app state)
  "Render the clip list with the import and selection actions."
  :render
  (let* ((clips (etaf-video-studio--app-clips app))
         (selected (plist-get state :clip-index))
         (project (plist-get state :project))
         (pending (> (or (plist-get state :pending) 0) 0)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'video :title (format "片段 (%d)" (length clips))
        :action-label "导入" :action-ref 'video-studio-import
        :on-action (lambda () (call-interactively #'etaf-video-studio-import-files)))
       (etaf-video-studio--placeholder
        :if (null project)
        :title "未打开项目" :description "从上面的项目列表选择一个")
       (etaf-video-studio--placeholder
        :if (and project (null clips))
        :title "还没有素材" :description "录制或导入一段视频"
        :action-label "导入素材"
        :on-action (lambda () (call-interactively #'etaf-video-studio-import-files)))
       (etaf-video-studio--clip-row
        :for (clip clips) :key (plist-get clip :id)
        :clip clip :index (cl-position clip clips :test #'equal)
        :selected (equal selected (cl-position clip clips :test #'equal))
        :on-press (lambda ()
                    (etaf-video-studio-select-clip
                     (% (cl-position clip clips :test #'equal) 1000))))
       (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
       (flex :flex-direction 'row :width 'stretch :justify-content 'end
             :gap '((lh 0) (ch 1))
         (etaf-button :label "撤销" :variant 'ghost :disabled (or pending (not (plist-get project :undo)))
                      :ref 'video-studio-undo
                      :on-press (lambda () (etaf-video-studio-undo)))
         (etaf-button :label "重做" :variant 'ghost :disabled (or pending (not (plist-get project :redo)))
                      :ref 'video-studio-redo
                      :on-press (lambda () (etaf-video-studio-redo))))))))

;;; Preview pane

(etaf-define-component etaf-video-studio--preview
    (&key app state layout aside stage-audio)
  "Render the native video stage and its controls."
  :render
  (let* ((stage (plist-get state :stage))
         (preview (plist-get state :preview))
         (project (plist-get state :project))
         (viewport (ignore-errors (etaf-runtime-viewport)))
         (viewport-width (or (car-safe viewport) 800))
         (viewport-rows (or (cdr-safe viewport) 30))
         (grid (etaf-video-studio--stage-grid
                (plist-get stage :aspect) viewport-width viewport-rows
                (not (eq layout 'narrow)) aside))
         (columns (car grid))
         (rows (cdr grid))
         (playing (plist-get state :stage-playing)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'video :title "预览"
        :action-label (if preview "成片预览" "选中片段")
        :action-ref 'video-studio-stage-source
        :on-action (lambda ()
                     (if (and preview (not (eq (plist-get stage :kind) 'preview)))
                         (etaf-video-studio-stage-preview-output)
                       (etaf-video-studio-stage-selected-clip))))
       (etaf-video-studio--placeholder
        :if (null stage)
        :title "暂无预览" :description "选择片段后生成低清预览，或直接播放素材")
       (box :if stage :width 'stretch :height (list 'lh (max 1 rows))
            :overflow 'hidden :background-color (etaf-video-studio-color :stage)
         (etaf-video :key (plist-get stage :key)
                     :src (plist-get stage :file)
                     :mode 'image :columns columns :rows rows
                     :autoplay t :audio stage-audio :volume 85
                     :position 'static :handle (plist-get stage :handle)
                     :on-press (lambda ()
                                 (etaf-video-studio-toggle-playback))))
       (flex :if stage :flex-direction 'row :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1))
         (etaf-button :label (if playing "暂停" "播放") :variant 'secondary
                      :ref 'video-studio-stage-play
                      :on-press (lambda () (etaf-video-studio-toggle-playback)))
         (etaf-ui-toggle-icon :value (etaf-value stage-audio)
                              :off 'volume-mute :on 'volume :set 'svg
                              :size 0.9 :min-width 3
                              :ref 'video-studio-stage-audio
                              :color (etaf-video-studio-color :muted)
                              :on-color (etaf-video-studio-color :accent)
                              :help-echo "预览声音 (m)"
                              :on-press (lambda () (etaf-video-studio-toggle-stage-audio)))
         (etaf-badge :text (if (eq (plist-get stage :kind) 'preview) "成片" "素材")
                     :variant 'info)
         (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0))
         (box :height '(lh 1) :color (etaf-video-studio-color :muted)
           (text :ref 'video-studio-position :id "video-studio-position"
                 (expr (or (plist-get state :stage-position) "—"))))
       (box :if stage :height '(lh 1) :overflow 'hidden
            :color (etaf-video-studio-color
                    (if (etaf-video-studio--stage-stale-p state) :warning :dim))
         (text (expr (etaf-video-studio--stage-caption state))))
       (flex :if (null stage) :flex-direction 'column :width 'stretch
         (etaf-video-studio--section-title
          :icon 'settings :title "快捷动作"
          :action-label "生成低清预览" :action-ref 'video-studio-render-preview
          :disabled (or (null project) (null (etaf-video-studio--app-clips app))
                        (> (or (plist-get state :pending) 0) 0))
          :on-action (lambda () (etaf-video-studio-render-preview)))
         (etaf-video-studio--fact :label "当前版本"
                                  :value (if project
                                             (format "r%s" (plist-get project :revision))
                                           "—"))
         (etaf-video-studio--fact :label "时间轴"
                                  :value (etaf-video-studio--clock
                                          (plist-get project :duration)))))))))

;;; Properties pane

(etaf-define-component etaf-video-studio--properties
    (&key app state)
  "Render the selected clip's facts and the explicit editing forms."
  :render
  (let* ((clip (plist-get state :clip))
         (index (plist-get state :clip-index))
         (pending (> (or (plist-get state :pending) 0) 0))
         (clips (etaf-video-studio--app-clips app))
         (count (length clips)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title :icon 'settings :title "片段属性")
       (etaf-video-studio--placeholder
        :if (null clip)
        :title "未选择片段" :description "在片段列表中选择一个")
       (flex :if clip :flex-direction 'column :width 'stretch :row-gap '(lh 0)
         (etaf-video-studio--fact :label "编号"
                                  :value (format "%d / %d" (1+ (or index 0)) count))
         (etaf-video-studio--fact :label "素材"
                                  :value (etaf-video-studio--basename (plist-get clip :file)))
         (etaf-video-studio--fact :label "源区间"
                                  :value (format "%s – %ss"
                                                 (etaf-video-studio--seconds (plist-get clip :in))
                                                 (etaf-video-studio--seconds (plist-get clip :out))))
         (etaf-video-studio--fact :label "成片"
                                  :value (concat (etaf-video-studio--seconds
                                                  (etaf-video-studio--clip-duration clip))
                                                 "s"))
         (etaf-video-studio--fact :label "速度"
                                  :value (format "%sx" (etaf-video-studio--seconds
                                                        (or (plist-get clip :speed) 1))))
         (etaf-video-studio--fact :label "增益"
                                  :value (etaf-video-studio--seconds
                                          (or (plist-get clip :gain) 1)))
         (box :height '(lh 1))
         (etaf-video-studio--section-title :icon 'settings :title "裁切（源时间）")
         (flex :flex-direction 'row :width 'stretch :align-items 'center
               :gap '((lh 0) (ch 1))
           (etaf-text-input :bind (etaf-video-studio--app-trim-in-ref app)
                            :width '(ch 6) :hide-label t :placeholder "入点"
                            :ref 'video-studio-trim-in)
           (etaf-text-input :bind (etaf-video-studio--app-trim-out-ref app)
                            :width '(ch 6) :hide-label t :placeholder "出点"
                            :ref 'video-studio-trim-out)
           (etaf-button :label "应用" :variant 'primary :disabled pending
                        :ref 'video-studio-trim-apply
                        :on-press (lambda () (etaf-video-studio-apply-trim))))
         (flex :flex-direction 'row :width 'stretch :align-items 'center
               :gap '((lh 0) (ch 1))
           (etaf-text-input :bind (etaf-video-studio--app-split-ref app)
                            :width '(ch 7) :hide-label t :placeholder "分割点"
                            :ref 'video-studio-split-at)
           (etaf-button :label "分割" :variant 'secondary :disabled pending
                        :ref 'video-studio-split-apply
                        :on-press (lambda () (etaf-video-studio-apply-split)))
           (etaf-button :label "设入点" :variant 'ghost :disabled pending
                        :ref 'video-studio-mark-in
                        :on-press (lambda () (etaf-video-studio-mark-in)))
           (etaf-button :label "设出点" :variant 'ghost :disabled pending
                        :ref 'video-studio-mark-out
                        :on-press (lambda () (etaf-video-studio-mark-out))))
         (flex :flex-direction 'row :width 'stretch :align-items 'center
               :gap '((lh 0) (ch 1))
           (etaf-select :bind (etaf-video-studio--app-speed-ref app)
                        :label "速度" :presentation 'dropdown
                        :options '((0.5 . "0.5x") (1 . "1x") (2 . "2x") (4 . "4x")))
           (etaf-button :label "应用速度" :variant 'ghost :disabled pending
                        :ref 'video-studio-speed-apply
                        :on-press (lambda () (etaf-video-studio-apply-speed))))
         (flex :flex-direction 'row :width 'stretch :align-items 'center
               :gap '((lh 0) (ch 1))
           (etaf-select :bind (etaf-video-studio--app-gain-ref app)
                        :label "增益" :presentation 'dropdown
                        :options '((0.5 . "0.5") (0.7 . "0.7") (1 . "1") (1.5 . "1.5")))
           (etaf-button :label "应用增益" :variant 'ghost :disabled pending
                        :ref 'video-studio-gain-apply
                        :on-press (lambda () (etaf-video-studio-apply-gain))))
         (flex :flex-direction 'row :width 'stretch :align-items 'center
               :justify-content 'end :gap '((lh 0) (ch 1))
           (etaf-button :label "上移" :variant 'ghost
                        :disabled (or pending (not index) (<= index 0))
                        :ref 'video-studio-move-up
                        :on-press (lambda () (etaf-video-studio-move-clip-up)))
           (etaf-button :label "下移" :variant 'ghost
                        :disabled (or pending (not index) (>= (1+ (or index 0)) count))
                        :ref 'video-studio-move-down
                        :on-press (lambda () (etaf-video-studio-move-clip-down)))
           (etaf-button :label "删除" :variant 'ghost
                        :disabled (or pending (not clip))
                        :ref 'video-studio-remove-clip
                        :on-press (lambda () (etaf-video-studio-remove-selected-clip)))))))))

;;; Captions pane

(etaf-define-component etaf-video-studio--caption-row
    (&key caption index selected on-press)
  "Render one caption row with its final-timeline window."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0
        :ref (intern (format "video-studio-caption-%d" index))
        :background-color (etaf-video-studio-color (if selected :accent-soft :panel))
        :hover-style (unless selected
                       (list :background-color (etaf-video-studio-color :hover)))
        :on-press on-press
    (box :height '(lh 1) :color (etaf-video-studio-color :muted)
      (text (expr (format "%s–%s"
                          (etaf-video-studio--clock (plist-get caption :start))
                          (etaf-video-studio--clock (plist-get caption :end))))))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :font-weight (if selected 'bold 'normal)
         :color (etaf-video-studio-color (if selected :accent :ink))
      (text (expr (or (plist-get caption :text) ""))))))

(etaf-define-component etaf-video-studio--captions
    (&key app state)
  "Render the caption list and the add/update/delete form."
  :render
  (let* ((captions (etaf-video-studio--app-captions app))
         (project (plist-get state :project))
         (selected (plist-get state :caption-index))
         (editing (plist-get state :caption-edit-id))
         (pending (> (or (plist-get state :pending) 0) 0)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'lyrics :title (format "字幕 (%d)" (length captions))
        :action-label (if editing "新建" "清空表单")
        :action-ref 'video-studio-caption-reset
        :on-action (lambda () (etaf-video-studio-clear-caption-form)))
       (etaf-video-studio--placeholder
        :if (and project (null captions))
        :title "还没有说明文字" :description "用下方表单在成片时间上添加")
       (etaf-video-studio--caption-row
        :for (caption captions) :key (plist-get caption :id)
        :caption caption
        :index (cl-position caption captions :test #'equal)
        :selected (equal selected (cl-position caption captions :test #'equal))
        :on-press (lambda ()
                    (etaf-video-studio-select-caption
                     (% (cl-position caption captions :test #'equal) 1000))))
       (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
       (etaf-video-studio--section-title
        :icon 'lyrics :title (if editing "编辑说明" "新建说明"))
       (flex :flex-direction 'row :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1))
         (etaf-text-input :bind (etaf-video-studio--app-caption-start-ref app)
                          :width '(ch 7) :hide-label t :placeholder "开始秒"
                          :ref 'video-studio-caption-start)
         (etaf-text-input :bind (etaf-video-studio--app-caption-end-ref app)
                          :width '(ch 7) :hide-label t :placeholder "结束秒"
                          :ref 'video-studio-caption-end))
       (etaf-text-input :bind (etaf-video-studio--app-caption-text-ref app)
                        :hide-label t :placeholder "说明文字" :ref 'video-studio-caption-text
                        :on-submit (lambda (_text) (etaf-video-studio-add-caption)))
       (flex :flex-direction 'row :width 'stretch :justify-content 'end
             :gap '((lh 0) (ch 1))
         (etaf-button :label "删除" :variant 'ghost :disabled (or pending (null selected))
                      :ref 'video-studio-caption-delete
                      :on-press (lambda () (etaf-video-studio-delete-caption)))
         (etaf-button :label (if editing "更新说明" "添加说明") :variant 'primary
                      :disabled (or pending (null project))
                      :ref 'video-studio-caption-add
                      :on-press (lambda () (etaf-video-studio-add-caption))))))))

;;; Record pane

(etaf-define-component etaf-video-studio--target-row
    (&key target index selected on-press)
  "Render one recording target row."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0
        :ref (intern (format "video-studio-target-%d" index))
        :background-color (etaf-video-studio-color (if selected :accent-soft :panel))
        :hover-style (unless selected
                       (list :background-color (etaf-video-studio-color :hover)))
        :on-press on-press
    (box :width '(ch 20) :height '(lh 1) :overflow 'hidden
         :font-weight (if selected 'bold 'normal)
         :color (etaf-video-studio-color (if selected :accent :ink))
      (text (expr (or (plist-get target :title) (plist-get target :name) "目标"))))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :color (etaf-video-studio-color :muted)
      (text (expr (format "%sx%s" (plist-get target :width) (plist-get target :height)))))))

(etaf-define-component etaf-video-studio--record
    (&key app state)
  "Render the target inventory, the recording settings and the toggle."
  :render
  (let* ((targets (plist-get state :record-targets))
         (selected (plist-get state :record-target-index))
         (task (plist-get state :record-task))
         (recording (and task t))
         (pending (> (or (plist-get state :pending) 0) 0))
         (project (plist-get state :project)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'video :title (format "录制目标 (%d)" (length targets))
        :action-label "刷新" :action-ref 'video-studio-targets-refresh
        :on-action (lambda () (etaf-video-studio-refresh-targets)))
       (etaf-video-studio--placeholder
        :if (null targets)
        :title "还没有目标" :description "刷新后选择窗口或屏幕")
       (etaf-video-studio--target-row
        :for (target targets) :key (or (plist-get target :id) (plist-get target :name))
        :target target :index (cl-position target targets :test #'equal)
        :selected (equal selected (cl-position target targets :test #'equal))
        :on-press (lambda ()
                    (etaf-video-studio-select-target
                     (% (cl-position target targets :test #'equal) 1000))))
       (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
       (flex :flex-direction 'row :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1))
         (etaf-select :bind (etaf-video-studio--app-record-audio-ref app)
                      :label "声音" :presentation 'dropdown
                      :options '(("none" . "不录") ("system" . "系统") ("microphone" . "麦克风")
                                 ("both" . "系统+麦克风")))
         (flex :width '(ch 10)
           (etaf-text-input :bind (etaf-video-studio--app-record-duration-ref app)
                            :hide-label t :placeholder "秒" :ref 'video-studio-record-duration)))
       (flex :flex-direction 'row :width 'stretch :align-items 'center
             :justify-content 'end :gap '((lh 0) (ch 2))
         (etaf-badge :if recording :text "录制中" :variant 'danger)
         (etaf-button :label (if recording "停止录制" "开始录制")
                      :variant (if recording 'primary 'secondary)
                      :disabled (or pending (null project)
                                    (and (null recording) (null selected)))
                      :ref 'video-studio-record-toggle
                      :on-press (lambda () (etaf-video-studio-toggle-record))))
       (box :height '(lh 1) :color (etaf-video-studio-color :dim)
         (text "录制默认不录声音；停止后自动导入为新片段。"))
       (etaf-video-studio--fact
        :if task
        :label "任务"
        :value (format "%s · %s" (plist-get task :status) (plist-get task :id)))))))

;;; Publish pane

(etaf-define-component etaf-video-studio--publish
    (&key app state)
  "Render export status, the publish form and the confirm step."
  :render
  (let* ((project (plist-get state :project))
         (preview (plist-get state :publish-preview))
         (export (etaf-video-studio--app-screen-export app))
         (pending (> (or (plist-get state :pending) 0) 0))
         (revision (plist-get project :revision))
         (confirmed (and preview (equal (plist-get preview :revision) revision))))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'send :title "发布"
        :action-label (if export "重新导出" "后台导出")
        :action-ref 'video-studio-render-screen
        :disabled (or pending (null project) (null (etaf-video-studio--app-clips app)))
        :on-action (lambda () (etaf-video-studio-render-screen)))
       (etaf-video-studio--fact
        :label "正式成片"
        :value (if export
                   (format "r%s 已完成" (plist-get export :revision))
                 "尚未导出")
        :value-color (if export (etaf-video-studio-color :ok)
                       (etaf-video-studio-color :muted)))
       (etaf-video-studio--fact
        :if export
        :label "成片文件"
        :value (etaf-video-studio--basename (plist-get export :output)))
       (box :height '(lh 1))
       (etaf-select :bind (etaf-video-studio--app-publish-target-ref app)
                    :label "目标"
                    :options '(("telegram" . "Telegram") ("share" . "公开链接")))
       (etaf-text-input :bind (etaf-video-studio--app-publish-chat-ref app)
                        :hide-label t :placeholder "Telegram chat（分享到链接可留空）"
                        :ref 'video-studio-publish-chat)
       (etaf-text-input :bind (etaf-video-studio--app-publish-text-ref app)
                        :hide-label t :placeholder "说明文字（默认项目标题）"
                        :ref 'video-studio-publish-text)
       (flex :flex-direction 'row :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1))
         (flex :width '(ch 14)
           (etaf-text-input :bind (etaf-video-studio--app-publish-topic-ref app)
                            :hide-label t :placeholder "话题 ID" :ref 'video-studio-publish-topic))
         (etaf-button :label "预览发布" :variant 'secondary
                      :disabled (or pending (null export))
                      :ref 'video-studio-publish-preview
                      :on-press (lambda () (etaf-video-studio-publish-preview))))
       (box :height '(lh 1))
       (flex :if preview :flex-direction 'column :width 'stretch :row-gap '(lh 0)
         (etaf-video-studio--fact :label "版本"
                                  :value (format "r%s" (plist-get preview :revision)))
         (etaf-video-studio--fact :label "可见"
                                  :value (or (plist-get preview :visibility) "—"))
         (etaf-video-studio--fact :label "文案"
                                  :value (or (plist-get preview :text) "—"))
         (flex :flex-direction 'row :width 'stretch :justify-content 'end
               :gap '((lh 0) (ch 1))
           (etaf-button :label "放弃预览" :variant 'ghost
                        :ref 'video-studio-publish-reset
                        :on-press (lambda () (etaf-video-studio-publish-reset)))
           (etaf-button :label "确认发布" :variant 'primary :disabled (or pending (not confirmed))
                        :ref 'video-studio-publish-confirm
                        :on-press (lambda () (etaf-video-studio-publish-confirm)))))
       (box :if (and preview (not confirmed)) :height '(lh 1)
            :color (etaf-video-studio-color :warning)
         (text "项目已变，请重新预览再确认"))
       (box :height '(lh 1) :color (etaf-video-studio-color :dim)
         (text "发布前先导出；结果不明的发布必须核对回执，不能自动重发。"))))))

;;; Tasks pane

(etaf-define-component etaf-video-studio--task-row
    (&key task index selected on-press)
  "Render one task row with status, profile and time."
  :view
  (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
        :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
        :role 'button :tab-index 0
        :ref (intern (format "video-studio-task-%d" index))
        :background-color (etaf-video-studio-color (if selected :accent-soft :panel))
        :hover-style (unless selected
                       (list :background-color (etaf-video-studio-color :hover)))
        :on-press on-press
    (etaf-badge :text (or (plist-get task :status) "?")
                :variant (etaf-video-studio--status-variant (plist-get task :status)))
    (box :height '(lh 1) :color (etaf-video-studio-color :muted)
      (text (expr (format "%s r%s" (or (plist-get task :kind) "?")
                          (plist-get task :revision)))))
    (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
         :overflow 'hidden :color (etaf-video-studio-color :ink)
      (text (expr (or (plist-get task :output) (plist-get task :message)
                      (plist-get task :id) ""))))))

(etaf-define-component etaf-video-studio--tasks
    (&key app state)
  "Render the task list with retry and cancel actions."
  :render
  (let* ((tasks (etaf-video-studio--app-tasks app))
         (selected (plist-get state :task-index))
         (pending (> (or (plist-get state :pending) 0) 0))
         (render (cl-find-if (lambda (task)
                               (and (equal (plist-get task :kind) "render")
                                    (member (plist-get task :status)
                                            etaf-video-studio--active-statuses)))
                             tasks)))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch :row-gap '(lh 1)
           :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :bg)
       (etaf-video-studio--section-title
        :icon 'clock :title (format "任务 (%d)" (length tasks))
        :action-label "刷新" :action-ref 'video-studio-tasks-refresh
        :on-action (lambda () (etaf-video-studio-refresh)))
       (etaf-video-studio--placeholder
        :if (null tasks)
        :title "还没有任务" :description "导出、录制或发布后在这里查看")
       (etaf-video-studio--task-row
        :for (task tasks) :key (plist-get task :id)
        :task task :index (cl-position task tasks :test #'equal)
        :selected (equal selected (cl-position task tasks :test #'equal))
        :on-press (lambda ()
                    (etaf-video-studio-select-task
                     (% (cl-position task tasks :test #'equal) 1000))))
       (box :flex-grow 1 :flex-basis '(lh 0) :min-height '(lh 0))
       (flex :flex-direction 'row :width 'stretch :justify-content 'end
             :gap '((lh 0) (ch 1))
         (etaf-button :label "续跑导出" :variant 'ghost
                      :disabled (or pending (null (plist-get state :project)))
                      :ref 'video-studio-render-resume
                      :on-press (lambda () (etaf-video-studio-task-retry)))
         (etaf-button :label "取消导出" :variant 'ghost :disabled (or pending (null render))
                      :ref 'video-studio-render-cancel
                      :on-press (lambda () (etaf-video-studio-cancel-render))))))))

;;; Header, footer and shell

(etaf-define-component etaf-video-studio--header
    (&key state)
  "Render the title row, the revision and the global actions."
  :render
  (let* ((project (plist-get state :project))
         (pending (plist-get state :pending)))
    (etaf-view
     (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
           :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
           :background-color (etaf-video-studio-color :panel2)
           :border-bottom (etaf-video-studio--border (etaf-video-studio-color :line))
       (etaf-ui-icon :name 'video :set 'svg :size 0.9 :min-width 2
                     :color (etaf-video-studio-color :accent))
       (box :height '(lh 1) :font-weight 'bold :color (etaf-video-studio-color :ink)
         (text "视频工作台"))
       (box :if project :height '(lh 1) :color (etaf-video-studio-color :dim)
         (text "·"))
       (box :if project :height '(lh 1) :overflow 'hidden
            :color (etaf-video-studio-color :muted)
         (text (expr (format "%s · r%s · %s"
                             (plist-get project :title)
                             (plist-get project :revision)
                             (etaf-video-studio--clock (plist-get project :duration))))))
       (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0))
       (etaf-badge :if (> (or pending 0) 0) :text (format "工作中 %s" pending)
                   :variant 'warning)
       (etaf-button :label "刷新" :variant 'ghost :ref 'video-studio-header-refresh
                    :on-press (lambda () (etaf-video-studio-refresh)))
       (etaf-button :label "主题" :variant 'ghost :ref 'video-studio-theme
                    :on-press (lambda () (etaf-video-studio-toggle-theme)))
       (etaf-button :label "帮助" :variant 'ghost :ref 'video-studio-help
                    :on-press (lambda () (call-interactively #'etaf-help)))))))

(etaf-define-component etaf-video-studio--footer
    (&key state)
  "Render the retained status line and the key hints."
  :render
  (let ((message (or (plist-get state :message) "就绪。")))
    (etaf-view
     (flex :flex-direction 'column :width 'stretch
           :background-color (etaf-video-studio-color :panel2)
           :border-top (etaf-video-studio--border (etaf-video-studio-color :line))
       (flex :flex-direction 'row :height '(lh 1) :width 'stretch :align-items 'center
             :gap '((lh 0) (ch 1)) :padding '((lh 0) (ch 1))
         (box :flex-grow 1 :flex-basis '(ch 0) :min-width '(ch 0) :height '(lh 1)
              :overflow 'hidden :color (etaf-video-studio-color :ink)
           (text :ref etaf-video-studio--status-ref :id "etaf-video-studio-status"
                 (expr message)))
         (box :height '(lh 1) :color (etaf-video-studio-color :dim)
           (text :ref 'video-studio-footer-position :id "video-studio-footer-position"
                 (expr (etaf-video-studio--footer-position-text state)))))
       (box :height '(lh 1) :padding '((lh 0) (ch 1)) :font-size 16
            :overflow 'hidden :color (etaf-video-studio-color :dim)
         (text "SPC 播放 · f/b 快退快进 · i/o 入出点 · s 分割 · x 删除 · v 预览 · e 导出 · r 录制 · p 发布 · t 任务 · T 主题 · ? 帮助 · q 关闭"))))))

(defun etaf-video-studio--stage-stale-p (state)
  "Whether STATE's rendered preview belongs to an older revision."
  (let ((stage (plist-get state :stage))
        (revision (plist-get (plist-get state :project) :revision)))
    (and stage (eq (plist-get stage :kind) 'preview)
         (not (equal (plist-get stage :revision) revision)))))

(defun etaf-video-studio--stage-caption (state)
  "Return the one-line caption under STATE's video stage."
  (let ((stage (plist-get state :stage)))
    (cond
     ((null stage) "")
     ((eq (plist-get stage :kind) 'preview)
      (if (etaf-video-studio--stage-stale-p state)
          (format "预览已过期：来自 r%s，按 v 重新生成 · %s"
                  (or (plist-get stage :revision) "?")
                  (etaf-video-studio--basename (plist-get stage :file)))
        (format "成片预览为当前版本 · %s"
                (etaf-video-studio--basename (plist-get stage :file)))))
     (t (format "素材预览 · %s"
                (etaf-video-studio--basename (plist-get stage :file)))))))

(defun etaf-video-studio--footer-position-text (state)
  "Return the footer's compact stage line for STATE."
  (or (plist-get state :stage-position) "无预览"))

(etaf-define-component etaf-video-studio--pane (&key app state pane)
  "Render PANE of APP from STATE; the other panes stay unmounted."
  :view
  (column :width 'stretch :height 'stretch
    (etaf-video-studio--projects :if (eq pane 'projects) :app app :state state)
    (etaf-video-studio--clips :if (eq pane 'clips) :app app :state state)
    (etaf-video-studio--preview :if (eq pane 'preview) :app app :state state
                                :layout 'narrow :aside nil
                                :stage-audio (etaf-video-studio--app-stage-audio-ref app))
    (etaf-video-studio--properties :if (eq pane 'properties) :app app :state state)
    (etaf-video-studio--captions :if (eq pane 'captions) :app app :state state)
    (etaf-video-studio--record :if (eq pane 'record) :app app :state state)
    (etaf-video-studio--publish :if (eq pane 'publish) :app app :state state)
    (etaf-video-studio--tasks :if (eq pane 'tasks) :app app :state state)))

(etaf-define-component etaf-video-studio--shell
    (&key app)
  "Render the application shell for APP with layout and theme bindings."
  :bindings ((theme (etaf-video-studio--app-theme-ref app))
             (data (etaf-video-studio--app-data-ref app))
             (stage-audio (etaf-video-studio--app-stage-audio-ref app)))
  :setup
  (etaf-theme-provide theme)
  :render
  (let* ((state (etaf-value data))
         (viewport (ignore-errors (etaf-runtime-viewport)))
         (viewport-width (or (car-safe viewport) 800))
         (viewport-rows (or (cdr-safe viewport) 30))
         (sidebar (>= viewport-width etaf-video-studio--sidebar-min-pixels))
         (aside (>= viewport-width etaf-video-studio--aside-min-pixels))
         (layout (cond (aside 'wide) (sidebar 'medium) (t 'narrow)))
         (body-rows (max 3 (- viewport-rows 3)))
         (lay  (let ((keys (mapcar (lambda (item) (plist-get item :key))
                                   (etaf-video-studio--pane-tabs state layout))))
                 (if (memq (plist-get state :pane) keys)
                     (plist-get state :pane)
                   (car keys))))
         (bg (etaf-video-studio-color :bg))
         (ink (etaf-video-studio-color :ink)))
    (etaf-view
     (box :position 'relative
          :width (list 'px viewport-width) :height (list 'lh viewport-rows)
          :background-color bg :color ink :overflow 'hidden
          :region (list :id 'video-studio-workspace :label "工作台" :key ?w
                        :neighbors (list :left 'video-studio-sidebar
                                         :right 'video-studio-details))
          :keys (list
                 (list "a" #'etaf-video-studio-import-files "导入素材")
                 (list "g" #'etaf-video-studio-refresh "刷新项目")
                 (list "u" #'etaf-video-studio-undo "撤销修改")
                 (list "U" #'etaf-video-studio-redo "重做修改")
                 (list "s" #'etaf-video-studio-split-at-stage "在当前位置分割")
                 (list "x" #'etaf-video-studio-remove-selected-clip "删除片段")
                 (list "i" #'etaf-video-studio-mark-in "设为入点")
                 (list "o" #'etaf-video-studio-mark-out "设为出点")
                 (list "," #'etaf-video-studio-move-clip-up "片段上移")
                 (list "." #'etaf-video-studio-move-clip-down "片段下移")
                 (list "v" #'etaf-video-studio-render-preview "生成低清预览")
                 (list "e" #'etaf-video-studio-render-screen "后台导出成片")
                 (list "C" #'etaf-video-studio-cancel-render "取消导出")
                 (list "c" #'etaf-video-studio-show-captions "字幕面板")
                 (list "r" #'etaf-video-studio-show-record "录制面板")
                 (list "R" #'etaf-video-studio-toggle-record "开始或停止录制")
                 (list "p" #'etaf-video-studio-show-publish "发布面板")
                 (list "t" #'etaf-video-studio-show-tasks "任务面板")
                 (list "T" #'etaf-video-studio-toggle-theme "切换主题"))
       (etaf-video-studio--header :state state)
       (flex :position 'absolute :left '(px 0) :top '(lh 1)
             :width (list 'px viewport-width) :height (list 'lh body-rows)
             :flex-direction 'row :overflow 'hidden
         (flex :if sidebar :flex-direction 'column
               :width etaf-video-studio--sidebar-width :flex-shrink 0
               :height (list 'lh body-rows) :overflow 'hidden
               :background-color (etaf-video-studio-color :panel)
               :border-right (etaf-video-studio--border (etaf-video-studio-color :line))
               :region (list :id 'video-studio-sidebar :label "项目与片段" :key ?f)
           (etaf-video-studio--projects :app app :state state)
           (box :height '(lh 1))
           (etaf-video-studio--clips :app app :state state))
         (flex :flex-direction 'column :flex-grow 1 :flex-basis '(ch 0)
               :min-width '(ch 0) :height (list 'lh body-rows) :overflow 'hidden
           (etaf-tabs :if (not aside)
                      :items (etaf-video-studio--pane-tabs state layout)
                      :active (etaf-video-studio--effective-pane state layout)
                      :on-change (lambda (key) (etaf-video-studio-select-pane key)))
           (flex :if aside :flex-direction 'row :width 'stretch :height 'stretch
                 :overflow 'hidden
             (flex :flex-direction 'column :flex-grow 1 :flex-basis '(ch 0)
                   :min-width '(ch 0) :height 'stretch :overflow 'hidden
                   :region (list :id 'video-studio-preview :label "预览" :key ?v)
               (etaf-video-studio--preview :app app :state state :layout layout
                                           :aside aside
                                           :stage-audio stage-audio))
             (flex :flex-direction 'column :width etaf-video-studio--aside-width
                   :flex-shrink 0 :height 'stretch :overflow 'hidden
                   :background-color (etaf-video-studio-color :panel)
                   :border-left (etaf-video-studio--border (etaf-video-studio-color :line))
                   :region (list :id 'video-studio-details :label "属性" :key ?d)
               (etaf-tabs :items (etaf-video-studio--pane-tabs state layout)
                          :active (etaf-video-studio--effective-pane state layout)
                          :on-change (lambda (key) (etaf-video-studio-select-pane key)))
               (etaf-video-studio--pane :app app :state state :pane lay)))
           (flex :if (not aside) :flex-direction 'column :flex-grow 1 :flex-basis '(lh 0)
                 :min-height '(lh 0) :overflow 'hidden
             (etaf-video-studio--pane :app app :state state :pane lay))))
       (box :position 'absolute :left '(px 0) :top (list 'lh (+ 1 body-rows))
            :width (list 'px viewport-width) :height '(lh 2) :overflow 'hidden
         (etaf-video-studio--footer :state state))))))

(provide 'etaf-video-studio-views)
;;; etaf-video-studio-views.el ends here
