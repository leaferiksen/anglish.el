;;; anglish-filter.el --- Strip & filter the Anglish dictionary to in-use words.

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

;; Usage:
;;   `emacs --batch --script anglish-filter.el'

;; Fetches both source files from the web, writes anglish_filtered.json
;; to the current directory.

;; Requires Emacs 30+ for the native JSON parser and if-let*/when-let*.

;; Output schema: A JSON object whose keys are English words/phrases
;; and whose values are flat arrays of in-use Anglish alternatives,
;; deduplicated across all parts of speech:

;; { "remain": ["abide", "bide", "dwell", "linger"], ... }

;; Anglish words absent from the reference wordlist, or containing
;; whitespace, are dropped. English keys with no survivors are
;; omitted.

;;; Code:

;;; 0.  Constants

(defconst anglish-dict-url "https://raw.githubusercontent.com/pure-english/dictionary/refs/heads/main/english_to_anglish.json"
  "Source Anglish dictionary.")

(defconst anglish-words-url "https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-usa.txt"
  "Reference wordlist – one lowercase word per line.
Longer (>466k) alternate source: https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt")

(defconst anglish-output-file "anglish_filtered.json"
  "Output path (relative to the working directory).")

(defconst anglish--native-origins (regexp-opt '("Old English" "Anglo-Saxon" "Middle English" "Old Norse" "Norse" "North Germanic" "Scandinavian" "Proto-Germanic" "Germanic" "West Germanic" "Old High German" "Old Low German" "Old Saxon" "Old Frisian" "Old Dutch" "Dutch" "German" "New English") 'words)
  "Regexp matching etymology origins considered native to the Anglish tradition.
Built with `regexp-opt' for fast matching against the source dict's origin strings.")

(defconst anglish--inflection-suffixes '("ing" "ings" "ed" "s" "es" "er" "ers" "est" "ly" "ness" "nesses" "ment" "ments" "ful" "less" "ward" "wards" "wise" "some" "dom" "hood" "ship" "like" "ish" "en" "ened" "ening" "ens")
  "Common English inflectional and derivational suffixes.
Used by `anglish--key-already-native-p' to detect when an English key is merely
a morphological variant of one of its own Anglish alternatives.")

;;; 1.  Sanity-check

(unless (fboundp 'json-parse-buffer)
  (error "This script requires Emacs 30 with native JSON support"))

(require 'url)

;;; 2.  HTTP fetch helper

(defun anglish--fetch (url)
  "Fetch URL and return a buffer containing only the response body.
Uses `url-insert-file-contents', which strips HTTP headers automatically.
The caller is responsible for killing the returned buffer."
  (let ((out (generate-new-buffer " *anglish-fetch*"))
        (coding-system-for-read 'utf-8))
    (with-current-buffer out
      (url-insert-file-contents url))
    out))

;;; 3.  Load the reference wordlist

(defun anglish--load-wordlist (url)
  "Fetch URL and load its words into a hash-table for O(1) lookup."
  (message "[1/4] Fetching wordlist from %s …" url)
  (let ((ht (make-hash-table :test #'equal :size 400000))
        (buf (anglish--fetch url)))
    (with-current-buffer buf
      (dolist (word (split-string (buffer-string) "\n" t "[ \t\r]+"))
        (puthash word t ht)))
    (kill-buffer buf)
    (message "      Loaded %d words." (hash-table-count ht))
    ht))

;;; 4.  Parse the source dictionary

(defun anglish--parse-dict (url)
  "Fetch URL and parse the Anglish JSON dictionary using the native parser."
  (message "[2/4] Fetching dictionary from %s …" url)
  (let* ((buf (anglish--fetch url))
         (dict
          (with-current-buffer buf
            ;; json-parse-buffer – native C-level parser, fast in Emacs 30.
            ;;   :object-type 'hash-table – best for keyed lookup
            ;;   :array-type  'array      – returns Lisp vectors
            (json-parse-buffer :object-type 'hash-table :array-type 'array :null-object nil :false-object nil))))
    (kill-buffer buf)
    (message "      Parsed %d top-level entries." (hash-table-count dict))
    dict))

;;; 5.  Build the filtered output

(defun anglish--word-ok-p (word wordlist)
  "Return non-nil if WORD passes the basic lexical filter:
• non-empty string
• no whitespace (single token only)
• downcased form present in WORDLIST"
  (and (stringp word) (not (string-empty-p word)) (not (string-match-p "[ \t]" word)) (gethash (downcase word) wordlist)))

(defun anglish--origin-native-p (origin)
  "Return non-nil if ORIGIN is compatible with the Anglish tradition.
An absent or empty origin is treated as unknown and passed through —
only an explicitly non-native origin causes rejection."
  (or (not (stringp origin)) (string-empty-p origin) (string-match-p anglish--native-origins origin)))

(defun anglish--key-already-native-p (english-key anglish-words)
  "Return non-nil if ENGLISH-KEY is already a native word and needs no replacement.
Detects the common case where the key is a morphological inflection of one of
its own ANGLISH-WORDS alternatives — e.g. \"reading\" → \"read\" (read + -ing).
The key and each alternative are compared case-insensitively."
  (let ((key-lower (downcase english-key)))
    (cl-some
     (lambda (alt)
       (let ((alt-lower (downcase alt)))
         (or (string= key-lower alt-lower) (cl-some (lambda (sfx) (string= key-lower (concat alt-lower sfx))) anglish--inflection-suffixes))))
     anglish-words)))

(defun anglish--build-output (dict wordlist)
  "Return a hash-table: english-key → vector-of-strings.
All POS groups are collapsed into one flat deduplicated array.
Filtering applied:
1. Each Anglish alternative in DICT must be in WORDLIST.
2. Each Anglish alternative must carry a native Germanic/OE/Norse origin,
   or have no origin specified (treated as unknown, not rejected).
3. English keys that are themselves already native — detected when the
   key is a morphological inflection of one of its own alternatives —
   are dropped entirely."
  (message "[3/4] Filtering entries …")
  (let ((result (make-hash-table :test #'equal :size (hash-table-count dict)))
        (kept 0)
        (dropped-no-alts 0)
        (dropped-native-key 0))
    (maphash
     (lambda (english-key pos-table)
       (when (hash-table-p pos-table)
         (let (acc)
           ;; Collect alternatives that pass both the wordlist and origin checks.
           (maphash
            (lambda (_pos entries)
              (when (vectorp entries)
                (dotimes (i (length entries))
                  (when-let* ((entry (aref entries i))
                              ((hash-table-p entry))
                              (word (gethash "anglish_word" entry))
                              (origin (or (gethash "origin" entry) ""))
                              ((anglish--word-ok-p word wordlist))
                              ((anglish--origin-native-p origin))
                              ((not (member word acc))))
                    (push word acc)))))
            pos-table)
           (setq acc (nreverse acc))
           (cond
            ;; No alternatives survived the filters → drop the key entirely.
            ((null acc)
             (cl-incf dropped-no-alts))
            ;; The English key is already native (inflected form of its own alt).
            ((anglish--key-already-native-p english-key acc)
             (cl-incf dropped-native-key))
            ;; Good entry — keep it.
            (t
             (puthash english-key (vconcat acc) result)
             (cl-incf kept))))))
     dict)
    (message "      Kept %d entries; dropped %d (no valid alts), %d (key already native)." kept dropped-no-alts dropped-native-key)
    result))

;;; 6.  Serialise and write output

(defun anglish--write-output (result path)
  "Serialise RESULT to compact JSON and write it to PATH."
  (message "[4/4] Writing %s …" path)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-buffer
      ;; json-serialize – native C serialiser, fast in Emacs 30.
      (insert (json-serialize result))
      (write-region (point-min) (point-max) path nil 'silent)))
  (message "      Done."))

;;; 7.  Entry point

(defun anglish-filter-main ()
  "Build and write the filtered Anglish dictionary.
Fetches the source dictionary and reference wordlist from the web,
filters each entry to Anglish alternatives with native Germanic origins,
drops English keys that are already native words, and serialises the
result to `anglish-output-file' as compact JSON."
  (let* ((wordlist (anglish--load-wordlist anglish-words-url))
         (dict (anglish--parse-dict anglish-dict-url))
         (result (anglish--build-output dict wordlist)))
    (anglish--write-output result anglish-output-file))
  (message "anglish-filter.el finished → %s" anglish-output-file))

(anglish-filter-main)
;;; anglish-filter.el ends here

;; Local variables:
;; fill-column: 1000
;; end:
