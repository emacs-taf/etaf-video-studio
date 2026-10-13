;;; etaf-video-studio-gui-scenarios.el --- Real GUI acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Load ETAF's scripts/emacs-gui-verifier.el, then call
;; (etaf-video-studio-gui-run DIRECTORY).  The scenario builds a temporary
;; project library, generates a real clip with ffmpeg, drives the rendered
;; controls through native ETAF focus/RET and the documented keys, renders
;; a real preview and previews a publish without sending anything.  Windows
;; and displays are listed but no recording is started, so the user's
;; desktop and microphone stay untouched.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'etaf-video-studio)
(require 'emacs-gui-verifier)

(defvar etaf-video-studio-gui--root nil
  "Temporary project library of the running scenario.")

(defvar etaf-video-studio-gui--directory nil
  "Project directory of the running scenario.")

(defun etaf-video-studio-gui--state ()
  "Read the displayed studio's public state."
  (with-current-buffer "*Video Studio*" (etaf-video-studio-state)))

(defun etaf-video-studio-gui--key (key)
  "Send KEY to the displayed studio through the command loop."
  (with-current-buffer "*Video Studio*"
    (execute-kbd-macro (kbd key))))

(defun etaf-video-studio-gui--wait-idle ()
  "Wait until the studio has no in-flight CLI request.
A control disabled by the busy state must not be focused yet."
  (let ((end (+ (float-time) 10)))
    (while (and (< (float-time) end)
                (> (plist-get (etaf-video-studio-gui--state) :pending) 0))
      (sit-for 0.05)
      (redisplay t))))

(defun etaf-video-studio-gui--press (ref)
  "Activate displayed control REF through native focus and RET."
  (etaf-video-studio-gui--wait-idle)
  (let ((runtime (etaf-runtime-for-buffer "*Video Studio*")))
    (unless (etaf-focus runtime ref) (error "Cannot focus %s" ref))
    (execute-kbd-macro (kbd "RET"))))

(defun etaf-video-studio-gui--type (ref text)
  "Type TEXT into the mounted text input REF through the UI."
  (let ((runtime (etaf-runtime-for-buffer "*Video Studio*")))
    (unless (etaf-text-input-begin runtime ref) (error "Cannot edit %s" ref))
    (execute-kbd-macro (vconcat text))
    (etaf-text-input-end)))

(defun etaf-video-studio-gui--studio-frame ()
  "Return the frame showing the studio buffer."
  (window-frame (get-buffer-window "*Video Studio*" t)))

(defun etaf-video-studio-gui--resize (columns rows)
  "Make the studio frame COLUMNS by ROWS text cells, leaving maximization.
The frame resize is applied by the window system asynchronously, so this
waits for the application's refit to reach the new window before returning;
otherwise the verifier's pre-settle invariant checkpoint sees the old
layout in a smaller window."
  (let* ((frame (etaf-video-studio-gui--studio-frame))
         (buffer (get-buffer "*Video Studio*")))
    (set-frame-parameter frame 'fullscreen nil)
    (set-frame-size frame columns rows)
    (let ((end (+ (float-time) 5)))
      (while (and (< (float-time) end)
                  (let ((window (get-buffer-window buffer t)))
                    (or (not window)
                        (/= (cdr-safe (etaf-runtime-viewport
                                       (etaf-runtime-for-buffer buffer)))
                            (window-body-height window)))))
        (sit-for 0.05)
        (redisplay t)))))

(defun etaf-video-studio-gui--footer-visible-p ()
  "Whether the studio's last line is inside its window."
  (let ((buffer (get-buffer "*Video Studio*")))
    (when buffer
      (with-current-buffer buffer
        (pos-visible-in-window-p (1- (point-max)) (get-buffer-window buffer t))))))

(defun etaf-video-studio-gui--check (name predicate)
  "Return a named assertion for PREDICATE's current public observation."
  (list (etaf-gui-verifier-assert name (funcall predicate))))

(defun etaf-video-studio-gui--ffmpeg ()
  "Return the ffmpeg executable used for the generated clip."
  (or (and (file-executable-p "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg")
           "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg")
      (executable-find "ffmpeg")
      (error "GUI acceptance needs ffmpeg")))

(defun etaf-video-studio-gui--cli (&rest args)
  "Run one real CLI command with ARGS and return its parsed JSON."
  (let ((pi-skill (or (executable-find "pi-skill")
                      (error "GUI acceptance needs the pi-skill CLI")))
        (buffer (generate-new-buffer " *video-studio-gui-cli*")))
    (unwind-protect
        (progn
          (unless (zerop (apply #'call-process pi-skill nil buffer nil
                                (append args '("--json"))))
            (error "CLI failed: %s\n%s" args
                   (with-current-buffer buffer (buffer-string))))
          (with-current-buffer buffer
            (goto-char (point-min))
            (json-parse-buffer :object-type 'plist :array-type 'list)))
      (kill-buffer buffer))))

(defun etaf-video-studio-gui--prepare ()
  "Create and fill the temporary project library, returning its root."
  (let* ((root (make-temp-file "video-studio-gui-" t))
         (clip (expand-file-name "clip.mp4" root))
         (ffmpeg (etaf-video-studio-gui--ffmpeg))
         (log (expand-file-name "ffmpeg.log" root)))
    (with-temp-buffer
      (unless (zerop (call-process
                      ffmpeg nil t nil
                      "-hide_banner" "-loglevel" "error" "-y"
                      "-f" "lavfi" "-i" "testsrc=size=640x360:rate=30:duration=10"
                      "-f" "lavfi" "-i" "sine=frequency=440:duration=10"
                      "-c:v" "libx264" "-preset" "veryfast" "-pix_fmt" "yuv420p"
                      "-c:a" "aac" "-shortest" clip))
        (error "ffmpeg failed:\n%s" (buffer-string))))
    (ignore log)
    (let ((created (etaf-video-studio-gui--cli
                    "video-project" "create" "--title" "GUI 验收"
                    "--root" root "--yes")))
      (setq etaf-video-studio-gui--root root
            etaf-video-studio-gui--directory (plist-get created :directory)))
    (etaf-video-studio-gui--cli
     "video-project" "import" etaf-video-studio-gui--directory
     "--file" clip "--yes")
    (setq etaf-video-studio-gui--root root)))

(defun etaf-video-studio-gui-run (directory)
  "Verify the studio against a generated clip and save evidence to DIRECTORY."
  (let ((actions nil))
    (cl-labels
        ((step (name execute predicate &optional screenshot timeout)
           (push (etaf-gui-verifier-action-create
                  :id name :execute (lambda (_context) (funcall execute))
                  :settled-p (lambda (_context) (funcall predicate))
                  :settle-timeout (or timeout 5.0)
                  :assertions (lambda (_context)
                                (etaf-video-studio-gui--check name predicate))
                  :screenshot screenshot)
                 actions))
         (state (key) (plist-get (etaf-video-studio-gui--state) key))
         (task-done (kind profile)
           (cl-find-if (lambda (task)
                         (and (equal kind (plist-get task :kind))
                              (equal profile (plist-get task :profile))
                              (equal "completed" (plist-get task :status))))
                       (state :tasks))))
      (step "ready" #'ignore
            (lambda () (and (state :project) (= 1 (state :clips)))))
      (step "layout-wide"
            (lambda () (etaf-video-studio-gui--resize 170 55))
            (lambda () (and (>= (car-safe (etaf-runtime-viewport
                                           (etaf-runtime-for-buffer "*Video Studio*")))
                                1100)
                            (etaf-video-studio-gui--footer-visible-p)))
            t)
      (step "layout-medium"
            (lambda () (etaf-video-studio-gui--resize 110 40))
            (lambda () (let ((width (car-safe (etaf-runtime-viewport
                                               (etaf-runtime-for-buffer "*Video Studio*")))))
                         (and width (< width 1100) (>= width 700)
                              (etaf-video-studio-gui--footer-visible-p)))))
      (step "layout-narrow"
            (lambda () (etaf-video-studio-gui--resize 80 28))
            (lambda () (let ((width (car-safe (etaf-runtime-viewport
                                               (etaf-runtime-for-buffer "*Video Studio*")))))
                         (and width (< width 700)
                              (etaf-video-studio-gui--footer-visible-p))))
            t)
      (step "layout-restore"
            (lambda () (etaf-video-studio-gui--resize 170 55))
            (lambda () (and (>= (car-safe (etaf-runtime-viewport
                                           (etaf-runtime-for-buffer "*Video Studio*")))
                                1100)
                            (etaf-video-studio-gui--footer-visible-p))))
      (step "clip-select"
            (lambda () (etaf-video-studio-gui--press 'video-studio-clip-0))
            (lambda () (and (= 0 (state :clip-index)) (state :stage)))
            t)
      (step "properties-pane"
            (lambda () (etaf-video-studio-select-pane 'properties))
            (lambda () (eq 'properties (state :pane))))
      (step "clip-split"
            (lambda () (etaf-video-studio-gui--press 'video-studio-split-apply))
            (lambda () (= 2 (state :clips)))
            t)
      (step "undo"
            (lambda () (etaf-video-studio-gui--key "u"))
            (lambda () (= 1 (state :clips))))
      (step "preview-render"
            (lambda () (etaf-video-studio-gui--key "v"))
            (lambda () (and (state :preview) (state :stage-playing)))
            t 240)
      (step "screen-render"
            (lambda () (etaf-video-studio-gui--key "e"))
            (lambda () (task-done "render" "screen"))
            nil 300)
      (step "targets"
            (lambda ()
              (etaf-video-studio-select-pane 'record)
              (etaf-video-studio-refresh-targets))
            (lambda () (or (> (state :record-targets) 0) (state :message)))
            t)
      (step "publish-pane"
            (lambda () (etaf-video-studio-select-pane 'publish))
            (lambda () (eq 'publish (state :pane))))
      (step "publish-chat"
            (lambda () (etaf-video-studio-gui--type 'video-studio-publish-chat "12345"))
            (lambda () t))
      (step "publish-preview"
            (lambda () (etaf-video-studio-gui--press 'video-studio-publish-preview))
            (lambda () (state :publish-preview))
            t 60)
      (step "publish-reset"
            (lambda () (etaf-video-studio-gui--press 'video-studio-publish-reset))
            (lambda () (not (state :publish-preview))))
      (step "light-theme" (lambda () (etaf-video-studio-gui--key "T"))
            (lambda () (eq etaf-video-studio-theme-mode 'light)) t)
      (step "dark-theme" (lambda () (etaf-video-studio-gui--key "T"))
            (lambda () (eq etaf-video-studio-theme-mode 'dark)) t)
      (etaf-gui-verifier-run
       (etaf-gui-verifier-scenario-create
        :name "video-studio-workbench"
        :claim "Real clip, real CLI, native controls, responsive layouts and preview render"
        :initialize
        (lambda (context)
          (when (get-buffer "*Video Studio*")
            (with-current-buffer "*Video Studio*"
              (ignore-errors (etaf-video-studio-close))))
          (etaf-video-studio-gui--prepare)
          (set-frame-parameter (selected-frame) 'fullscreen nil)
          (set-frame-size (selected-frame) 170 55)
          (let* ((etaf-video-studio-root etaf-video-studio-gui--root)
                 (buffer (etaf-video-studio-open etaf-video-studio-gui--directory)))
            (when-let* ((window (get-buffer-window buffer t)))
              (with-selected-window window (delete-other-windows)))
            (setf (etaf-gui-verifier-context-target-buffer context) buffer)))
        :actions (nreverse actions)
        :invariants
        (lambda (_context)
          (let ((buffer (get-buffer "*Video Studio*")))
            (if (null buffer)
                (list (etaf-gui-verifier-assert "studio closed" t))
              (append
               (etaf-gui-verifier-line-height-assertions buffer)
               (list (etaf-gui-verifier-assert
                      "footer is visible"
                      (etaf-video-studio-gui--footer-visible-p)))))))
        ;; Closing removes the verifier's target buffer, so it runs as the
        ;; final completion step instead of an asserted action.
        :completion
        (lambda (_context)
          (etaf-video-studio-gui--key "q")
          (or (not (get-buffer "*Video Studio*"))
              (error "The studio did not close"))))
       directory))))

(provide 'etaf-video-studio-gui-scenarios)
;;; etaf-video-studio-gui-scenarios.el ends here
