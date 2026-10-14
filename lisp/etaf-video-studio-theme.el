;;; etaf-video-studio-theme.el --- Semantic palette of etaf-video-studio -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Two full palettes (dark and light) behind one accessor, so a palette
;; change can never leak a half-updated set of colors, plus the projection
;; into the ETAF UI token names used by the standard catalog.  Every view
;; reads colors through `etaf-video-studio-color'; `etaf-theme-provide'
;; receives the token plist from `etaf-video-studio-theme-defaults'.  The
;; palette is four depth steps (page, card, bar, control) plus state
;; surfaces, so panes stay separated in both appearances.

;;; Code:

(require 'cl-lib)
(require 'etaf)

(defconst etaf-video-studio-palettes
  '((dark
     (:bg . "#0b0e14")
     (:panel . "#141922")
     (:panel2 . "#1a212d")
     (:panel3 . "#232c3a")
     (:hover . "#2a3446")
     (:stage . "#000000")
     (:ink . "#e8edf4")
     (:muted . "#9ba7b8")
     (:dim . "#6b7789")
     (:accent . "#4c9df3")
     (:accent-soft . "#16324f")
     (:accent-fg . "#ffffff")
     (:border . "#2c3644")
     (:frame . "#39455a")
     (:line . "#232c39")
     (:ok . "#4cc38a")
     (:ok-bg . "#123528")
     (:danger . "#f2777a")
     (:danger-bg . "#3a1d20")
     (:warning . "#e0af68")
     (:warning-bg . "#3a2f1a")
     (:info . "#7aa2f7")
     (:info-bg . "#1b2a46"))
    (light
     (:bg . "#eef2f7")
     (:panel . "#ffffff")
     (:panel2 . "#eaf0f7")
     (:panel3 . "#e2e8f0")
     (:hover . "#d7e1ec")
     (:stage . "#10141a")
     (:ink . "#263750")
     (:muted . "#5b6779")
     (:dim . "#8a95a6")
     (:accent . "#3b68b3")
     (:accent-soft . "#edf3fc")
     (:accent-fg . "#ffffff")
     (:border . "#ccd5e0")
     (:frame . "#c3cedd")
     (:line . "#dde4ec")
     (:ok . "#1f8a53")
     (:ok-bg . "#dcf3e6")
     (:danger . "#c04444")
     (:danger-bg . "#fbe3e3")
     (:warning . "#9a6b0f")
     (:warning-bg . "#faf0d7")
     (:info . "#2563eb")
     (:info-bg . "#e0ecff")))
  "Dark and light semantic palettes of the application.")

(defvar etaf-video-studio-theme-mode 'dark
  "Appearance of the application: `dark' (default) or `light'.")

(defun etaf-video-studio-color (key &optional mode)
  "Return KEY's raw color for explicit MODE, or a deferred Theme token.
Views keep the deferred value so retained Hosts follow palette changes
without relying on an unrelated snapshot projection being invalidated."
  (let* ((palette (or (alist-get (or mode etaf-video-studio-theme-mode)
                                etaf-video-studio-palettes)
                      (alist-get 'dark etaf-video-studio-palettes)))
         (color (or (alist-get key palette) (alist-get :ink palette))))
    (if mode color
      (etaf-theme-token (intern (concat ":video-studio-" (substring (symbol-name key) 1)))
                        color))))

(defun etaf-video-studio-theme-defaults (&optional mode)
  "Return the ETAF UI token plist for MODE (default the current mode).
The application passes the result to `etaf-theme-provide' before mounting,
otherwise etaf-ui Components (buttons, badges, inputs, ranges) keep their
own light defaults and the app looks half-themed.  Sources, fields and
selects are exercised by this app, so every relevant catalog token is set."
  (let* ((mode (or mode etaf-video-studio-theme-mode))
         (c (lambda (key) (etaf-video-studio-color key mode)))
         (bg (funcall c :bg))
         (panel (funcall c :panel))
         (panel2 (funcall c :panel2))
         (panel3 (funcall c :panel3))
         (hover (funcall c :hover))
         (ink (funcall c :ink))
         (muted (funcall c :muted))
         (dim (funcall c :dim))
         (accent (funcall c :accent))
         (accent-soft (funcall c :accent-soft))
         (border (funcall c :border))
         (line (funcall c :line)))
    (append
     (cl-loop for (key . color) in (alist-get mode etaf-video-studio-palettes)
              append (list (intern (concat ":video-studio-" (substring (symbol-name key) 1)))
                           color))
     (list
     ;; Page, text and structure.
     :ui-fg ink
     :ui-bg bg
     :ui-border border
     :ui-muted-fg muted
     :ui-divider-bg line
     :ui-panel-fg ink
     :ui-panel-bg panel
     :ui-panel-border (funcall c :frame)
     ;; Buttons and selection controls.
     :ui-accent accent
     :ui-accent-fg (funcall c :accent-fg)
     :ui-accent-soft-bg accent-soft
     :ui-button-primary-fg (funcall c :accent-fg)
     :ui-button-primary-bg accent
     :ui-button-primary-hover-bg (etaf-video-studio--mix accent (funcall c :accent-fg) 0.12)
     :ui-button-secondary-fg accent
     :ui-button-secondary-bg accent-soft
     :ui-button-secondary-hover-bg (etaf-video-studio--mix accent-soft hover 0.35)
     :ui-button-ghost-fg muted
     :ui-button-ghost-hover-bg panel3
     :ui-checkbox-enabled-fg ink
     :ui-checkbox-disabled-fg dim
     ;; Fields, pickers and search.  Outlined fields are flat filled
     ;; surfaces: no outline, no radius, one standard row.
     :ui-input-padding '((lh 0) (ch 2))
     :ui-input-radius '(px 0)
     :ui-input-bg panel2
     :ui-input-border panel2
     :ui-search-bg panel3
     :ui-search-fg ink
     :ui-picker-item-bg panel2
     :ui-picker-item-fg ink
     :ui-picker-item-muted-fg muted
     ;; Status surfaces.
     :ui-success-fg (funcall c :ok)
     :ui-success-bg (funcall c :ok-bg)
     :ui-success-border (funcall c :ok)
     :ui-danger-fg (funcall c :danger)
     :ui-danger-bg (funcall c :danger-bg)
     :ui-danger-border (funcall c :danger)
     :ui-warning-fg (funcall c :warning)
     :ui-warning-bg (funcall c :warning-bg)
     :ui-warning-border (funcall c :warning)
     :ui-info-fg (funcall c :info)
     :ui-info-bg (funcall c :info-bg)
     :ui-info-border (funcall c :info)
     :ui-disabled-fg dim
     :ui-disabled-bg panel2
     :ui-disabled-border border
     ;; Data surfaces.
     :ui-table-border line
     :ui-table-selected-fg ink
     :ui-table-selected-bg accent-soft
     :ui-data-grid-error-fg (funcall c :danger)
     :ui-pagination-muted-fg muted
     ;; Progress and ranges.
     :ui-progress-track panel3
     :ui-range-track panel3
     :ui-range-fill accent
     ;; Desktop surface tokens, unused by this app but part of the contract
     ;; a full catalog theme provides.
     :ui-shell-bg bg
     :ui-shell-fg ink
     :ui-shell-muted-fg muted
     :ui-shell-item-fg ink
     :ui-shell-item-minimized-fg dim
     :ui-window-bg panel
     :ui-window-fg ink
     :ui-window-border border
     :ui-window-title-bg panel2
     :ui-window-title-fg muted
     :ui-window-title-active-fg ink
     ;; Playing-card tokens carry over so a nested catalog component is themed.
     :ui-playing-card-bg panel
     :ui-playing-card-black ink
     :ui-playing-card-red (funcall c :danger)
     :ui-playing-card-back-bg accent-soft
     :ui-playing-card-back-fg accent
     :ui-playing-card-empty-bg panel3
     :ui-playing-card-empty-fg dim
     :ui-playing-card-selected-bg accent-soft
     :ui-playing-card-hover-bg hover))))

(defun etaf-video-studio--mix (from to amount)
  "Return FROM mixed AMOUNT of the way toward TO.
Both colors must be `#RRGGBB' strings; any other spelling returns FROM so a
named color keeps working."
  (let ((a (etaf-video-studio--channels from))
        (b (etaf-video-studio--channels to)))
    (if (and a b)
        (apply #'format "#%02X%02X%02X"
               (cl-mapcar (lambda (x y)
                            (max 0 (min 255 (round (+ x (* (- y x) amount))))))
                          a b))
      from)))

(defun etaf-video-studio--channels (color)
  "Return COLOR's (RED GREEN BLUE) channels, or nil when it is not hex."
  (when (and (stringp color)
             (string-match "\\`#\\([0-9A-Fa-f]\\{2\\}\\)\\([0-9A-Fa-f]\\{2\\}\\)\\([0-9A-Fa-f]\\{2\\}\\)\\'" color))
    (mapcar (lambda (index) (string-to-number (match-string index color) 16))
            '(1 2 3))))

(provide 'etaf-video-studio-theme)
;;; etaf-video-studio-theme.el ends here
