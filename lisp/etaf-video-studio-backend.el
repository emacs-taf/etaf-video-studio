;;; etaf-video-studio-backend.el --- CLI boundary of etaf-video-studio -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The application never reads or writes a project file itself: the
;; `video-project' skill owns the store and runs every backend job in a
;; `job-run' process group that survives this Emacs.  This module only turns
;; one CLI invocation into one parsed JSON result and hands it to a callback
;; with the application buffer current, so the command loop is never blocked
;; while a probe or a lock waits.  Requests are bounded: a request that
;; exceeds `etaf-video-studio-request-timeout' is killed and reported, and
;; closing the application cancels its in-flight requests without touching
;; the background jobs.

;;; Code:

(require 'cl-lib)
(require 'json)

(defcustom etaf-video-studio-executable "pi-skill"
  "Program that provides the `video-project' and `video-edit' commands.
Set this to a fake program in tests; the application only passes it a
command name, its arguments and `--json'."
  :type 'string
  :group 'etaf-video-studio)

(defcustom etaf-video-studio-request-timeout 300
  "Seconds after which a single CLI request is killed and reported.
Background jobs started by the CLI are not affected; their own timeout
lives in the project task."
  :type 'integer
  :group 'etaf-video-studio)

(defvar etaf-video-studio-backend--live nil
  "Alist of application buffer to its in-flight CLI processes.")

(defun etaf-video-studio-backend-cancel (buffer)
  "Kill every in-flight CLI request of BUFFER without running its callback."
  (let ((entry (assq buffer etaf-video-studio-backend--live)))
    (dolist (process (cdr entry))
      (when (process-live-p process)
        (process-put process 'etaf-video-studio-cancelled t)
        (delete-process process)))
    (setq etaf-video-studio-backend--live
          (delq entry etaf-video-studio-backend--live))
    nil))

(defun etaf-video-studio-backend--register (buffer process)
  "Record PROCESS as an in-flight request of BUFFER."
  (let ((entry (assq buffer etaf-video-studio-backend--live)))
    (if entry
        (setcdr entry (cons process (cdr entry)))
      (push (list buffer process) etaf-video-studio-backend--live))))

(defun etaf-video-studio-backend--unregister (buffer process)
  "Forget PROCESS among BUFFER's in-flight requests."
  (let ((entry (assq buffer etaf-video-studio-backend--live)))
    (when entry
      (setcdr entry (delq process (cdr entry)))
      (unless (cdr entry)
        (setq etaf-video-studio-backend--live
              (delq entry etaf-video-studio-backend--live))))))

(defun etaf-video-studio-backend--parse (text)
  "Parse TEXT as one JSON value with keyword plists, or return nil.
JSON false and null both become nil, which suits the CLI's boolean
fields (`undo', `redo', `reused') and absent optional fields."
  (when (and (stringp text)
             (not (string-empty-p (string-trim text))))
    (condition-case nil
        (json-parse-string (string-trim text)
                           :object-type 'plist
                           :array-type 'list
                           :null-object nil
                           :false-object nil)
      (error nil))))

(defun etaf-video-studio-backend--result (exit-code stdout stderr)
  "Build the callback result for a finished request.
EXIT-CODE is the process exit status; STDOUT and STDERR are its captured
streams.  A zero exit parses STDOUT; a nonzero exit prefers the CLI's JSON
error object on STDOUT and falls back to its stderr."
  (let ((parsed (etaf-video-studio-backend--parse stdout)))
    (cond
     ((and (zerop exit-code) (not (null parsed)))
      (list :ok t :data parsed))
     ((and parsed (eq (plist-get parsed :ok) nil)
           (or (plist-get parsed :error) (plist-get parsed :message)))
      (list :ok nil
            :code (or (plist-get parsed :error) "internal")
            :message (or (plist-get parsed :message) "video-project 请求失败")
            :hint (or (plist-get parsed :hint) "")
            :need (plist-get parsed :need)))
     ((zerop exit-code)
      (list :ok nil :code "internal" :message "video-project 输出不是有效 JSON"
            :hint (string-trim (or stdout ""))))
     (t
      (list :ok nil :code "external"
            :message (or (and (stringp stderr) (not (string-empty-p (string-trim stderr)))
                              (string-trim stderr))
                         (format "video-project 退出状态 %s" exit-code)))))))

(defun etaf-video-studio-backend--deliver (buffer process result)
  "Deliver RESULT to PROCESS's callback in BUFFER exactly once.
A cancelled or timed-out request may have delivered already; the flag keeps
the callback single-shot.  A dead application buffer discards the result."
  (unless (process-get process 'etaf-video-studio-delivered)
    (process-put process 'etaf-video-studio-delivered t)
    (let ((callback (process-get process 'etaf-video-studio-callback)))
      (when (and callback (buffer-live-p buffer))
        (with-current-buffer buffer
          (funcall callback result))))))

(defun etaf-video-studio-backend--finish (buffer process)
  "Clean PROCESS up and deliver its parsed result for BUFFER.
The streams are collected before the work buffers are killed, so the
callback can still read the CLI's message."
  (let* ((out-buffer (process-get process 'etaf-video-studio-out))
         (err-buffer (process-get process 'etaf-video-studio-err))
         (timeout (process-get process 'etaf-video-studio-timeout))
         (cancelled (process-get process 'etaf-video-studio-cancelled))
         (exit-code (process-exit-status process))
         (stdout (and (buffer-live-p out-buffer)
                      (with-current-buffer out-buffer
                        (buffer-substring-no-properties (point-min) (point-max)))))
         (stderr (and (buffer-live-p err-buffer)
                      (with-current-buffer err-buffer
                        (buffer-substring-no-properties (point-min) (point-max))))))
    (when (timerp timeout) (cancel-timer timeout))
    (etaf-video-studio-backend--unregister buffer process)
    (ignore-errors (kill-buffer out-buffer))
    (ignore-errors (kill-buffer err-buffer))
    (unless cancelled
      (etaf-video-studio-backend--deliver
       buffer process (etaf-video-studio-backend--result exit-code stdout stderr)))))

(defun etaf-video-studio-backend--sentinel (buffer process _event)
  "Deliver PROCESS's finished result to BUFFER."
  (when (memq (process-status process) '(exit signal))
    (etaf-video-studio-backend--finish buffer process)))

(defun etaf-video-studio-backend--timeout (buffer process)
  "Report PROCESS as timed out for BUFFER and kill it.
The background job the CLI started keeps running; only this query ends."
  (when (process-live-p process)
    (etaf-video-studio-backend--deliver
     buffer process
     (list :ok nil :code "timeout"
           :message (format "请求超过 %s 秒未完成" etaf-video-studio-request-timeout)
           :hint "可重试；后台任务仍在运行"))
    (delete-process process)))

(defun etaf-video-studio-backend-call (buffer args callback)
  "Run the video CLI with ARGS for BUFFER and call CALLBACK with the result.
ARGS is a list of strings after the executable, for example
(\"video-project\" \"status\" DIRECTORY); `--json' is appended here.  The
CALLBACK runs with BUFFER current and receives `(:ok t :data JSON)' or
`(:ok nil :code CODE :message MESSAGE :hint HINT)'.  A missing executable
reports `deps' immediately; the request itself never signals."
  (let* ((value etaf-video-studio-executable)
         (executable (if (file-name-directory value)
                         (let ((path (expand-file-name value)))
                           (and (file-executable-p path) path))
                       (executable-find value))))
    (if (null executable)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (funcall callback
                     (list :ok nil :code "deps"
                           :message (format "找不到 %s；请先安装或设置 `etaf-video-studio-executable'"
                                            etaf-video-studio-executable)
                           :hint "pi-skill video-project check"))))
      (let* ((out-buffer (generate-new-buffer " *etaf-video-studio-out*"))
             (err-buffer (generate-new-buffer " *etaf-video-studio-err*"))
             (process (make-process
                       :name "etaf-video-studio"
                       :buffer out-buffer
                       :stderr err-buffer
                       :command (cons executable (append args (list "--json")))
                       :noquery t
                       :coding 'utf-8-unix
                       :sentinel (lambda (process event)
                                   (etaf-video-studio-backend--sentinel
                                    buffer process event)))))
        (process-put process 'etaf-video-studio-out out-buffer)
        (process-put process 'etaf-video-studio-err err-buffer)
        (process-put process 'etaf-video-studio-callback callback)
        (etaf-video-studio-backend--register buffer process)
        (process-put process 'etaf-video-studio-timeout
                     (run-at-time etaf-video-studio-request-timeout nil
                                  #'etaf-video-studio-backend--timeout buffer process))
        process))))

(provide 'etaf-video-studio-backend)
;;; etaf-video-studio-backend.el ends here
