;;; yon-chan.el --- A 4chan browser for Emacs

;; Copyright (C) 2013  David Thompson

;; Author: David Thompson <dthompson@member.fsf.org>
;; Keywords: hypermedia, games

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This mode uses the 4chan API to provide a board and thread browser
;; from within Emacs

;;; Code:

(require 'json)
(require 'cl)

;;; Yon-chan mode

(define-derived-mode yon-chan-mode
  special-mode "Yon-chan"
  "4chan browser.")

;; (defun yon-mode-keys ()
;;   "Set local key defs for yon-mode"
;;   (define-key yon-mode-map "q" 'quit-window)

;;; Faces

(defface yon-chan-greentext
  '((default)
    (((class color) (min-colors 16) (background light)) :foreground "ForestGreen")
    (((class color) (min-colors 88) (background dark))  :foreground "green3")
    (((class color) (min-colors 16) (background dark))  :foreground "green3")
    (((class color)) :foreground "green3"))
  "Basic greentext face for all the implications we can imply.")

(defface yon-face-post-author
  '((default :weight bold)
    (((class color) (min-colors 16) (background light)) :foreground "purple4")
    (((class color) (min-colors 16) (background dark))  :foreground "purple2")
    (((class color)) :foreground "purple"))
  "Basic face for the post author.")

(defface yon-face-post-subject
  '((default :weight bold)
    (((class color)) :foreground "brown"))
  "Basic face for the post subject.")

(defface yon-face-post-number
  '((default :weight bold)
    (((class color)) :foreground "red3"))
  "Basic face for the post number.")

(defface yon-face-post-number-link
  '((default :weight bold :underline t)
    (((class color)) :foreground "red3"))
  "Basic face for the post number.")

(defface yon-chan-deadlink
  '((default :strike-through t)
    (((class color)) :foreground "red2"))
  "Basic face for dead cross-links.")

;;; Comment sanitization and processing

(defun yon-clean-html-string (body)
  (let* ((replace-list (list '("&#039;" . "'")
                             '("&gt;" . ">")
                             '("&lt;" . "<")
                             '("&quot;" . "\"")
                             '("&amp;" . "&")
                             '("<br>" . "\n")
                             '("<wbr>" . "")))
         (replacer (lambda (x y)
                     (replace-regexp-in-string
                      (car y) (cdr y) x))))
    (reduce replacer (cons body replace-list))))


(defun yon-get-line-content ()
  (save-excursion
   (let ((pos-end (line-beginning-position 2)))
     (buffer-substring (line-beginning-position) pos-end))))

(defun yon-get-closing-point (bufstr close)
  (let ((match (string-match close bufstr)))
    (+ match (length close))))

(defun yon-get-section (start end)
  (save-excursion
    (buffer-substring start end)))


;; Interactive for now for testing
(defun yon-possibly-colorify-line-by-tags
  (opregex endregex colourface &optional newline)
  "Least elegant function that will replace quotes with greentext."
  (interactive)
  (let ((start (string-match opregex (yon-get-line-content)))
        (op opregex)
        (ed endregex))
    (when start
      (let* ((startn (+ start (line-beginning-position)))
             (end (+ (yon-get-closing-point
                      (yon-get-section startn (point-max)) ed)
                     startn)))
        (save-excursion
          (goto-char startn)
          (delete-char (length op))
          (goto-char (- end (length op)))
          (delete-backward-char (length ed))
          (goto-char startn)
          (let ((cont (yon-get-section startn (- end
                                                 (+ (length op)
                                                    (length ed))))))
            (progn
              (delete-char (length cont))
              (if newline
                  (insert (propertize (yon-strip-newlines cont)
                                      'face colourface))
                (insert (propertize cont
                                    'face colourface))))))))))


(defun yon-make-quote-buttons ()
  (let* ((start (string-match "<a href=\".*?\" class=\"quotelink\">" (yon-get-line-content)))
         (op "<a href\"")
         (ed  "</a>"))
    (when start
      (let* ((startn (+ start (line-beginning-position)))
             (end (+ (yon-get-closing-point
                      (yon-get-section startn (point-max)) ed)
                     startn)))
        (save-excursion
          (goto-char startn)
          (delete-char (+ 1 (length op)))
          (goto-char (- end (+ 1 (length op))))
          (delete-backward-char (length ed))
          (goto-char startn)
          (zap-to-char 1 (string-to-char "\""))
          (delete-char (length " class=\"quotelink\">"))
          (insert (current-kill 0))
          (delete-backward-char 1)
          (insert " ")
          (goto-char startn)
          (let* ((split-cont (split-string
                              (yon-get-section
                               startn
                               (- end (+ (length op)
                                         (length " class=\"quotelink\">")
                                         (length ed)
                                         1))) ;; space
                              " "))
                 (link (split-string (car split-cont) "#p"))
                 (res-start (string-match "/res/" (car link))))
            (progn
              (delete-char (+ (length (car split-cont))
                              (length (cadr split-cont))
                              1))
              (if res-start
                  (progn
                    (goto-char startn)
                    (lexical-let* ((board
                                    (with-temp-buffer
                                      (insert (car link))
                                      (goto-char (point-min))
                                      (zap-to-char 2 (string-to-char "/"))
                                      (erase-buffer)
                                      (insert (current-kill 0))
                                      (goto-char (point-min))
                                      (delete-char 1)
                                      (goto-char (point-max))
                                      (delete-backward-char 1)
                                      (buffer-string)))
                                   (thread
                                    (with-temp-buffer
                                      (insert (car link))
                                      (goto-char (point-min))
                                      (delete-char (+ 2
                                                      (length board)
                                                      (length "res/")))
                                      (buffer-string)))
                                   (post (cadr link)))
                      (let ((kmap (make-sparse-keymap)))
                        (define-key kmap (kbd "<return>")
                          (lambda ()
                            (interactive)
                            (yon-browse-thread
                             (switch-to-buffer-other-window
                              (generate-new-buffer
                               (concat "*yon-chan-/" board "/-" thread)))
                             board thread)))
                        (insert-text-button (yon-strip-newlines (cadr split-cont))
                                            'face 'yon-face-post-number-link
                                            'keymap kmap))))
                (lexical-let ((thread (car link))
                              (post (cadr link)) ;; for future use, post jumping
                              (kmap (make-sparse-keymap))
                              (board (with-current-buffer (buffer-name)
                                       yon-current-board)))
                  (define-key kmap (kbd "<return>")
                    (lambda ()
                      (interactive)
                      (yon-browse-thread
                       (switch-to-buffer-other-window
                        (generate-new-buffer
                         (concat "*yon-chan-/" board "/-" thread)))
                       board thread)))
                  (insert-text-button (yon-strip-newlines (cadr split-cont))
                                      'face 'yon-face-post-number-link
                                      'keymap kmap))))))))))

(defun yon-apply-deadlinks ()
  "Checks each line for deadlink replacement."
  (save-excursion
    (goto-char (point-min))
    (cl-loop until (eobp) do (yon-possibly-colorify-line-by-tags
                              "<span class=\"deadlink\">" "</span>"
                              'yon-chan-deadlink t)
             (forward-line 1))))

(defun yon-apply-greentext ()
  "Checks each line for greentext replacement."
  (save-excursion
    (goto-char (point-min))
    (cl-loop until (eobp) do (yon-possibly-colorify-line-by-tags
                              "<span class=\"quote\">" "</span>"
                              'yon-chan-greentext t)
             (forward-line 1))))

(defun yon-apply-quotelinks ()
  (goto-char (point-min))
  (cl-loop until (eobp) do (yon-make-quote-buttons) (forward-line 1)))



;; Interactive for now for testing
(defun yon-possibly-greenify-line ()
  "Least elegant function that will replace quotes with greentext."
  (interactive)
  (let ((op "<span class=\"quote\">")
        (ed "</span>"))))

(defun yon-strip-newlines (body)
  (replace-regexp-in-string "\n" "" body))

(defun yon-process-post (body)
  (let* ((cleaned (yon-clean-html-string body)))
    cleaned))

;;; 4chan JSON API

(defvar yon-api-url "http://api.4chan.org/")

(defun yon-elem (alst key &optional default)
  "Fetch value from alist with a default value if key is not present."
  (lexical-let ((elem (cdr (assoc key alst))))
    (if elem
        elem
      default)))

(defun yon-get-json-from-current-buffer ()
  (let ((json nil))
    (save-excursion
      (goto-char (point-min))
      (re-search-forward "^$" nil 'move)
      (setq json (buffer-substring-no-properties (point) (point-max)))
      (kill-buffer (current-buffer)))
    json))

(defun yon-parse-json (json)
  (json-read-from-string json))

(defun yon-get-and-parse-json ()
  (yon-parse-json (yon-get-json-from-current-buffer)))

;;; Posts

;; The atoms of 4chan.

(cl-defstruct yon-post
  subject author timestamp number comment
  filename replyto sticky closed time trip id capcode country
  country_name email ext fsize md5 image_w image_h thumbnail_w thumbnail_h
  filedeleted spoiler custom_spoiler omitted_posts omitted_images replies
  images bumplimit imagelimit new_filename)

(defun yon-build-post (response)
  "Builds a post object from deserialized JSON response."
  (make-yon-post :subject        (yon-elem response 'sub "No subject")
                 :author         (yon-elem response 'name "Anonymous")
                 :timestamp      (yon-elem response 'now)
                 :number         (yon-elem response 'no)
                 :comment        (yon-elem response 'com "")
                 :filename       (yon-elem response 'filename)
                 :replyto        (yon-elem response 'resto) ;; 0 is OP
                 :sticky         (yon-elem response 'sticky)
                 :closed         (yon-elem response 'closed)
                 :new_filename   (yon-elem response 'tim)
                 :time           (yon-elem response 'time)
                 :trip           (yon-elem response 'trip)
                 :id             (yon-elem response 'id)
                 :capcode        (yon-elem response 'capcode)
                 :country        (yon-elem response 'country)
                 :country_name   (yon-elem response 'country_name)
                 :email          (yon-elem response 'email)
                 :ext            (yon-elem response 'ext)
                 :fsize          (yon-elem response 'fsize)
                 :md5            (yon-elem response 'md5)
                 :image_w        (yon-elem response 'w)
                 :image_h        (yon-elem response 'h)
                 :thumbnail_w    (yon-elem response 'tn_w)
                 :thumbnail_h    (yon-elem response 'tn_h)
                 :filedeleted    (yon-elem response 'filedeleted)
                 :spoiler        (yon-elem response 'spoiler)
                 :custom_spoiler (yon-elem response 'custom_spoiler)
                 :omitted_posts  (yon-elem response 'omitted_posts)
                 :omitted_images (yon-elem response 'omitted_images)
                 :replies        (yon-elem response 'replies)
                 :images         (yon-elem response 'images)
                 :bumplimit      (yon-elem response 'bumplimit)
                 :imagelimit     (yon-elem response 'imagelimit)))

(defun yon-build-thread (response)
  (mapcar 'yon-build-post (yon-elem response 'posts)))

(defun yon-build-catalog (response)
  (mapcar 'yon-build-page response))

(defun yon-build-page (response)
  (mapcar 'yon-build-post (yon-elem response 'threads)))

;;; Rendering

(defun yon-apply-faces ()
  (yon-apply-greenstuff)
  (yon-apply-deadlinks)
  (yon-apply-quotelinks))

(defun yon-render (buffer proc obj)
  (with-current-buffer buffer
    (setq buffer-read-only nil)
    (insert (funcall proc obj))
    (yon-apply-faces)
    (setq buffer-read-only t)
    (goto-char (point-min))))

(defun yon-render-catalog (catalog)
  (mapconcat 'yon-render-catalog-page catalog "\n"))

(defun yon-render-catalog-page (page)
  (mapconcat 'yon-format-post page "\n"))

(defun yon-render-thread (posts)
  (let ((op (car posts))
        (replies (cdr posts)))
    (concat (yon-format-post op) "\n"
            (mapconcat (lambda (x) (replace-regexp-in-string ;; for now
                                    "^" "    "
                                    (yon-format-post x))) replies "\n"))))

;;; Formatting

(defun yon-format-post (post)
  "Returns a formatted string representation of a post"
  (format "%s\n%s"
          (yon-format-post-header post)
          (yon-format-post-comment post)))

(defun yon-format-post-header (post)
  "Returns a formatted string representation of a post header.
The header consists of the subject, author, timestamp, and post number."
  (format "%s - %s - %s - %s"
          (yon-format-post-subject post)
          (yon-format-post-author post)
          (yon-format-post-timestamp post)
          (yon-format-post-number post)))

(defun yon-format-post-comment (post)
  "Returns a processed comment string."
  (yon-process-post (yon-post-comment post)))

(defun yon-format-post-subject (post)
  "Returns a propertized, html-cleaned subject string."
  (propertize
    (yon-clean-html-string (yon-post-subject post))
    'face 'yon-face-post-subject))

(defun yon-format-post-author (post)
  "Returns a propertized, html-cleaned author string."
  (propertize
    (yon-clean-html-string (yon-post-author post))
    'face 'yon-face-post-author))

(defun yon-format-post-timestamp (post)
  "Returns an html-cleaned timestamp string."
  (yon-clean-html-string (yon-post-timestamp post)))

(defun yon-format-post-number (post)
  "Returns the post number. Clickable if it's a thread OP."
  (lexical-let ((op (equal 0 (yon-post-replyto post)))
                (kmap (make-sparse-keymap))
                (board (with-current-buffer (buffer-name)
                         (when (boundp 'yon-current-board)
                             yon-current-board)))
                (post-number (number-to-string (yon-post-number post))))
    (define-key kmap (kbd "<return>")
      (lambda ()
        (interactive)
        (yon-browse-thread
         (switch-to-buffer-other-window
          (generate-new-buffer
           (concat "*yon-chan-/" board "/-" post-number)))
         board post-number)))
    (if (and op board)
        (with-temp-buffer
          (insert-text-button post-number
                              'face 'yon-face-post-number-link
                              'keymap kmap)
          (buffer-string))
      (propertize post-number 'face 'yon-face-post-number))))

(defun yon-browse-board-catalog (buffer board)
  (url-retrieve (concat "http://api.4chan.org/" board "/catalog.json")
                (lexical-let ((yon-buffer buffer))
                  (with-current-buffer yon-buffer
                    (set (make-local-variable 'yon-current-board) board))
                  (lambda (status)
                    (yon-render yon-buffer
                                'yon-render-catalog
                                (yon-build-catalog (yon-get-and-parse-json)))))))

(defun yon-browse-thread (buffer board thread-number)
  (url-retrieve
   (concat "http://api.4chan.org/" board "/res/" thread-number ".json")
   (lexical-let ((yon-buffer buffer))
     (with-current-buffer buffer
       (set (make-local-variable 'yon-current-board) board))
     (lambda (status)
       (yon-render yon-buffer
                   'yon-render-thread
                   (yon-build-thread (yon-get-and-parse-json)))))))

;;;###autoload
(defun yon-chan ()
  "Fetch and display 4chan boards."
  (interactive)
  (with-current-buffer (switch-to-buffer-other-window
                        (generate-new-buffer "*yon-chan*"))
    (yon-chan-mode)
    (yon-browse-board-catalog (current-buffer) "g")))


(provide 'yon-chan)
;;; yon-chan.el ends here
