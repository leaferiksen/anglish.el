;;; anglish.el --- Anglish Flymake backend -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Leaf Eriksen

;; Author: Leaf Eriksen <leaferiksen@gmail.com>
;; Keywords: text, wp
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/leaferiksen/anglish.el

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `anglish-mode' is a buffer-local minor mode. It registers a Flymake
;; backend to offer Anglish-Friendly alternatives to Latin, Greek, and
;; French loanwords. The dictionary is loaded once on first use and
;; cached globally. Call `anglish-reload-dict' to force a reload after
;; regenerating the JSON.

;; I find this to be a fun way to deepen my understanding of the roots
;; of the words I use, but I have no interest in linguistic purism. As
;; the lovely linguists in the anglish community have made clear,
;; conlangs are fun, but white nationalism is not to be tolerated. Or,
;; as Cheap Perfume put it, "Yes, it's okay to punch Nazis!"

;;; Code:

;;; Dependencies

(require 'flymake)

;;; Customisation

(defgroup anglish nil
  "Flymake backend for Anglish word alternatives."
  :group 'tools
  :prefix "anglish-")

(defconst anglish-json-file (expand-file-name "anglish_filtered.json" (file-name-directory (or load-file-name buffer-file-name)))
  "Path to anglish_filtered.json, expected alongside anglish.el.")

(defcustom anglish-diagnostic-type :note
  "Flymake diagnostic severity used for Anglish suggestions.
Use `:note' for a subtle hint, `:warning' to make them more prominent."
  :type '(choice (const :tag "Note" :note) (const :tag "Warning" :warning))
  :group 'anglish)

;;; Dictionary

(defvar anglish--dict nil
  "Hash-table mapping lowercase single-token English words to alternative vectors.
Nil until first use; populated by `anglish--load-dict'.")

(defun anglish--load-dict ()
  "Parse `anglish-json-file' and populate variable `anglish--dict'.
Only single-word keys are kept – multi-word phrases are not matchable
token-by-token and are discarded.  Returns the new hash-table."
  (message "anglish: loading dictionary from %s …" anglish-json-file)
  (with-temp-buffer
    (insert-file-contents anglish-json-file)
    (let ((raw (json-parse-buffer :object-type 'hash-table :array-type 'array :null-object nil :false-object nil))
          (ht (make-hash-table :test #'equal :size 10000)))
      (maphash
       (lambda (key alts)
         (unless (string-match-p "[ \t]" key)
           (puthash (downcase key) alts ht)))
       raw)
      (message "anglish: loaded %d entries." (hash-table-count ht))
      (setq anglish--dict ht))))

(defun anglish-reload-dict ()
  "Flush the cached dictionary and reload it from `anglish-json-file'.
Useful after regenerating the JSON with anglish-filter.el."
  (interactive)
  (setq anglish--dict nil)
  (anglish--load-dict))

(defsubst anglish--dict ()
  "Return the dictionary, loading it on first call."
  (or anglish--dict (anglish--load-dict)))

;;; Flymake backend

(defun anglish--check-buffer (report-fn &rest _)
  "Flymake backend: scan the current buffer and report Anglish suggestions.
REPORT-FN is the callback supplied by Flymake.  Each word present in the
dictionary produces a diagnostic whose message lists the alternatives."
  (let ((dict (anglish--dict))
        diags)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\\<\\([a-zA-Z]+\\)\\>" nil t)
        (when-let* ((alts (gethash (downcase (match-string-no-properties 0)) dict)))
          (push (flymake-make-diagnostic (current-buffer) (match-beginning 0) (match-end 0) anglish-diagnostic-type (concat "Anglish: " (mapconcat #'identity alts ", "))) diags))))
    (funcall report-fn (nreverse diags))))

;;; Minor mode

;;;###autoload
(define-minor-mode anglish-mode
  "Minor mode that underlines words with Anglish alternatives via Flymake.
Enables Flymake automatically when turned on, and removes only the Anglish
backend when turned off (leaving any other Flymake backends intact)."
  :lighter " Angl"
  :group
  'anglish
  (if anglish-mode
      (progn
        (flymake-mode 1)
        (add-hook 'flymake-diagnostic-functions #'anglish--check-buffer nil t)
        (flymake-start))
    (remove-hook 'flymake-diagnostic-functions #'anglish--check-buffer t)
    (when (null flymake-diagnostic-functions)
      (flymake-mode -1))))

(provide 'anglish)

;;; anglish.el ends here

;; Local variables:
;; fill-column: 1000
;; end:
