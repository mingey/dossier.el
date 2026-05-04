;;; dossier.el --- Document Review Environment -*- lexical-binding: t -*-

;; Copyright (C) 2026 Brian Robertson

;; Version: 0.1
;; Package-requires: ((emacs "30.1"))
;; Keywords: convenience, files, tools

;;; Commentary:
;;
;; `dossier' provides a unified, three-pane workspace for reviewing,
;; navigating, and annotating large sets of PDF documents
;;
;; It coordinates three buffers simultaneously:
;; 1. A Dired buffer (acting as the file index)
;; 2. A PDF-View buffer (acting as the document viewer)
;; 3. An Org-mode buffer (acting as the control center and notebook)
;;
;; The minor mode `dossier-mode' is designed to be activated inside the
;; Org-mode buffer. It intercepts navigation keys to silently control the
;; Dired and PDF buffers, automatically syncing the Org file with the
;; currently viewed document.

;;; Code:

(require 'dired)
(require 'org)
(require 'pdf-tools)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                CUSTOMIZATION                               ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; We use a defgroup to organize our custom variables. This allows us to
;; tweak the behavior of the mode later using `M-x customize-group'.

(defgroup dossier nil
  "Settings for the document review environment."
  :group 'applications)

;; (We will add defcustom variables here later, such as the preferred width
;; of the Dired window, or the specific Org-mode TOREAD keyword to use.)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;              PHASE 1: WORKSPACE ARCHITECT (Window Management)              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Functions to set up the strict 3-column layout (Dired | PDF | Org)
;; and safely tear it down when finished.

;; TODO: How about a fancier starting buffer than *scratch*? Recent file list? Funny image?
;; TODO: Write `dossier-teardown-workspace'

(defun dossier-setup-workspace (dossier-dir)
  "Set up the 3-column workspace for document review.
Prompts for DOSSIER-DIR containing the PDF files.
Layout: Dired (10%) | PDF-Viewer (45%) | Org-mode (45%)."
  (interactive "DDirectory containing PDFs: ")

  ;; 1. Save our current buffer (the Org notes) to restore it later
  (let ((org-buf (current-buffer)))

	;; 2. Clear the frame to start with a blank slate
	(delete-other-windows)

	;; 3. Calculate dynamic window widths based on the current frame size
	(let* ((frame-w (frame-width))
		   (dired-w (truncate (* frame-w 0.10))) ;; 10% for the index
		   (pdf-w (truncate (* (- frame-w dired-w) 0.50)))) ;; 50% of the remaining space for the PDF

	  ;; 4. Split the windows from left to right
	  (let* ((dired-win (selected-window))
			 (pdf-win (split-window-right dired-w))
			 (org-win (with-selected-window pdf-win
						(split-window-right pdf-w))))

		;; Tag each window with an invisible ID badge (this makes certain our functions
		;; are working on the right buffers)
		(set-window-parameter dired-win 'dossier-role 'index)
		(set-window-parameter pdf-win 'dossier-role 'viewer)
		(set-window-parameter org-win 'dossier-role 'control)
		
		;; 5. Populate the Left Window (Dired)
		(with-selected-window dired-win
		  (dired dossier-dir)
		  (setq-local truncate-lines t) ;; Keep filenames on a single line...
		  (setq-local fringe-indicator-alist
					  (cons '(truncation . nil) fringe-indicator-alist))) ;; ...and hide the arrows

		;; 6. Populate the Middle Window (PDF Viewer)
		(with-selected-window pdf-win
		  (switch-to-buffer "*scratch*"))

		;; 7. Populate the Right Window (Org Notes)
		(with-selected-window org-win
		  (switch-to-buffer org-buf))

		;; 8. Snap the user's cursor back to the Org buffer
		(select-window org-win)

		;; 9. Turn on the minor mode
		(dossier-mode 1)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;           PHASE 2: THE REMOTE CONTROL (Dired + PDF Coordination)           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Functions that execute silently in the background, telling Dired to move
;; to the next file and telling the PDF viewer to open it, without moving
;; the user's cursor out of the Org buffer

;; TODO: Could the random function not simply rerun itself until it finds a file?

;; Highlight open file in Dired buffer
(defvar-local dossier--active-file-overlay nil
  "Overlay marking the currently viewed file in the Dossier index.")

(defun dossier--set-fringe-indicator ()
  "Mark the current Dired line with a fringe arrow and optional highlight."
  ;; 1. Clean up the old overlay if it exists
  (when (overlayp dossier--active-file-overlay)
	(delete-overlay dossier--active-file-overlay))

  ;; 2. Create a new overlay wrapping the current line
  (let ((ov (make-overlay (line-beginning-position) (line-end-position))))

	;; 3, Inject a built-in right-triangle bitmap into the left fringe
	(overlay-put ov 'before-string
				 (propertize " " 'display '(left-fringe right-triangle)))
	;; Optional: Uncomment this next line if you ALSO want the hl-line
	;; background color applied securely to the active file
	(overlay-put ov 'face 'hl-line)

	;; 4. Save the overlay to our local variable
	(setq dossier--active-file-overlay ov)))

(defvar dossier--dark-mode-p nil
  "Internal state tracking whether pdfs should open in midnight mode.")

(defun dossier-toggle-dark-mode ()
  "Toggle persistent dark mode for the Dossier workspace."
  (interactive)
  ;; 1. Flip the internal switch
  (setq dossier--dark-mode-p (not dossier--dark-mode-p))

  ;; 2. Immediately apply it to the currently open PDF
  (let ((pdf-win (dossier--get-window-by-role 'viewer)))
	(when pdf-win
	  (with-selected-window pdf-win
		(when (derived-mode-p 'pdf-view-mode)
		  (if dossier--dark-mode-p
			  (pdf-view-midnight-minor-mode 1)
			(pdf-view-midnight-minor-mode -1))))))

  (message "Dossier midnight mode %s" (if dossier--dark-mode-p "enabled" "disabled")))

;; Helper function to safely locate our workspace windows
(defun dossier--get-window-by-role (role)
  "Return the first window in the current frame assigned to ROLE."
  (get-window-with-predicate
   (lambda (w)
	 (eq (window-parameter w 'dossier-role) role))
   nil t))

(defun dossier--open-and-sync (filepath)
  "The Master Manager: Opens the PDF at FILEPATH, sizes it, applies theme, and triggers the Org sync."
  (let ((pdf-win (dossier--get-window-by-role 'viewer)))
	;; 1. Handle the PDF window
	(with-selected-window pdf-win
	  (let ((old-buf (current-buffer)))
		(find-file filepath)
		(when (derived-mode-p 'pdf-view-mode)
		  (pdf-view-fit-width-to-window)
		  (when dossier--dark-mode-p
			(pdf-view-midnight-minor-mode 1))
		  (kill-buffer old-buf))))

	;; 2. Handle the Org sync
	(dossier-sync-org-headline filepath)))

(defun dossier-open-next-document ()
  "Tell Dired to move to the next file, open it in the PDF window, and sync notes."
  (interactive)
  (let ((dired-win (dossier--get-window-by-role 'index)))
	(unless dired-win (user-error "Dossier workspace is not fully active."))

	(let ((filepath nil))
	  ;; 1. Send the drone to Dired to move down and grab the filename
	  (with-selected-window dired-win
		(dired-next-line 1)
		;; 'nil t' means don't throw a fatal error if there is not file here
		(setq filepath (dired-get-filename nil t))
		(when filepath (dossier--set-fringe-indicator)))

	  ;; Send the drone to the PDF viewer to swap the files
	  (if filepath
		  (dossier--open-and-sync filepath)
		(message "No more files in this directory.")))))

(defun dossier-open-previous-document ()
  "Tell Dired to move to the previous file, open it in the PDF window, and sync notes."
  (interactive)
  (let ((dired-win (dossier--get-window-by-role 'index)))
	(unless dired-win (user-error "Dossier workspace is not fully active."))

	(let ((filepath nil))
	  (with-selected-window dired-win
		(dired-previous-line 1)
		(setq filepath (dired-get-filename nil t))
		(when filepath (dossier--set-fringe-indicator)))

	  (if filepath
		  (dossier--open-and-sync filepath)
		(message "Already at the first file.")))))

(defun dossier-open-random-document ()
  "Tell Dired to jump to a random file, open it in the PDF window, and sync notes."
  (interactive)
  (let ((dired-win (dossier--get-window-by-role 'index)))

	(unless dired-win (user-error "Dossier workspace is not fully active."))

	(let ((filepath nil))
	  (with-selected-window dired-win
		;; Jump to a completely random line in the buffer
		(goto-char (point-min))
		(forward-line (random (count-lines (point-min) (point-max))))

		;; Dired has header/footer lines. If we landed on one,
		;; scroll down until we hit an actual file.
		(while (and (not (eobp)) (not (dired-get-filename nil t)))
		  (forward-line 1))

		;; If we hit the absolute bottom of the buffer, step backward to the last file
		(unless (dired-get-filename nil t)
		  (dired-previous-line 1))

		(setq filepath (dired-get-filename nil t))
		(when filepath (dossier--set-fringe-indicator)))

	  (if filepath
		  (dossier--open-and-sync filepath)
		(message "Could not find a valid file.")))))

(defun dossier-open-document-from-headline ()
  "Read the filename from the current Org headline and open it in the PDF viewer.
Also updates the Dired index cursor and fringe indicator."
  (interactive)
  ;; 1. Make sure we're actually in the Org buffer
  (unless (derived-mode-p 'org-mode)
	(user-error "Must be called from within the Org buffer."))

  ;; 2. Use the Org API to parse the current headline
  (let* ((components (org-heading-components))
		 (headline-text (nth 4 components)))

	(unless headline-text
	  (user-error "Cursor is not on a valid Org headline."))

	;; 3. Defensively extract the filename
	;; We split the text by spaces and take the first item
	;; This means if your headline is "* TOREAD 104-10067 - CIA Memo",
	;; it cleanly extracts just "104-10067".
	(let* ((extracted-name (car (split-string headline-text)))
		   ;; Strip extension just in case you typed it, then forcefully add .pdf
		   (basename (file-name-sans-extension extracted-name))
		   (filename (concat basename ".pdf"))
		   (dired-win (dossier--get-window-by-role 'index))
		   (pdf-win (dossier--get-window-by-role 'viewer)))

	  (unless (and dired-win pdf-win)
		(user-error "Dossier workspace is not fully active."))

	  (let ((filepath nil))
		;; 4. Send the drone to Dired to find the file
		(with-selected-window dired-win
		  (let* ((dired-dir (dired-current-directory))
				 (target-path (expand-file-name filename dired-dir)))

			;; `dired-go-to-file' is a native function that searches the
			;; buffer for the absolute path and moves the cursor there.
			(if (dired-goto-file target-path)
				(progn
				  (setq filepath target-path)
				  (dossier--set-fringe-indicator))
			  (message "File %s is not found in the Dired index." filename))))

		;; 5. If found, send the drone to the PDF viewer to open it
		(when filepath
		  (with-selected-window pdf-win
			(let ((old-buf (current-buffer)))
			  (find-file filepath)
			  (when (derived-mode-p 'pdf-view-mode)
				(pdf-view-fit-width-to-window)
				(when dossier--dark-mode-p
				  (pdf-view-midnight-minor-mode 1))
				(kill-buffer old-buf))))
		  (message "Loaded dossier: %s" basename))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;               PHASE 3: THE ORG-SYNC ENGINE (NOTE MANAGEMENT)               ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Functions that parse the active Org buffer for the current filename. If
;; found, move point to that headline. If not, append a new TOREAD headline.

;; TODO: Insert newline before new headline

(defun dossier-sync-org-headline (filepath)
  "Sync the Org buffer to the headline for the file at FILEPATH.
If it doesn't exist, append a new '* TOREAD [filename]' headline."
  (let* ((org-win (dossier--get-window-by-role 'control))
		 ;; extract just the file base name from the filepath
		 (filename (file-name-nondirectory filepath))
		 (basename (file-name-sans-extension filename)))

	(unless org-win
	  (user-error "Dossier Org window not found."))

	(with-selected-window org-win
	  (goto-char (point-min))

	  ;; 1. Build a safe regular expression to search for the filename
	  ;; `regexp-quote` ensures the "." in ".pdf" is treated as a literal dot
	  (let ((search-rgx (format "^\\*+ .*\\b%s\\b" (regexp-quote basename))))

		;; 2. Search the buffer silently
		(if (re-search-forward search-rgx nil t)
			(progn
			  (beginning-of-line)
			  (org-show-context)) ;; Unfold the Org tree if it was hidden

		  ;; 3. If not found, go to the end of the file and append it
		  (goto-char (point-max))
		  (unless (bolp) (insert "\n")) ;; Ensure we start on a fresh line
		  (insert (format "* TOREAD %s\n" basename))
		  (forward-line -1)
		  (org-show-context))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                      PHASE 4: THE MINOR MODE & KEYMAP                      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The actual minor mode definition that glues all the above functions
;; together and binds them to our custom keys.

(defun dossier-scroll-forward ()
  "Scroll the Dossier PDF window. Advance to the next document at the end."
  (interactive)
  (let ((pdf-win (dossier--get-window-by-role 'viewer)))
	(unless pdf-win (user-error "Dossier PDF window not found."))
	(with-selected-window pdf-win
	  (condition-case err
		  (pdf-view-scroll-up-or-next-page)
		(error
		 (if (string-match-p "No such page" (error-message-string err))
			 (dossier-open-next-document)
		   (signal (car err) (cdr err))))))))

(defun dossier-scroll-backward ()
  "Scroll the Dossier PDF window backward. Go to the previous document at the beginning."
  (interactive)
  (let ((pdf-win (dossier--get-window-by-role 'viewer)))
	(unless pdf-win (user-error "Dossier PDF window not found."))
	(with-selected-window pdf-win
	  (condition-case err
		  (pdf-view-scroll-down-or-previous-page)
		(error
		 (if (string-match-p "No such page" (error-message-string err))
			 (dossier-open-previous-document)
		   (signal (car err) (cdr err))))))))

(defvar dossier-mode-map
  (let ((map (make-sparse-keymap)))
	;; Bind our remote-control functions to your preferred keys
	(define-key map (kbd "s-n") #'dossier-open-next-document)
	(define-key map (kbd "s-p") #'dossier-open-previous-document)
	(define-key map (kbd "s-r") #'dossier-open-random-document)
	(define-key map (kbd "s-.") #'dossier-open-document-from-headline)
	(define-key map (kbd "s-m") #'dossier-toggle-dark-mode)
	(define-key map (kbd "<f8>") #'dossier-scroll-forward)
	(define-key map (kbd "<f7>") #'dossier-scroll-backward)
	map)
  "Keymap for `dossier-mode'.")

;;;###autoload
(define-minor-mode dossier-mode
  "Toggle dossier mode for document review.

When active, this mode intercepts navigation keys to coordinate a Dired
index and a PDF viewer from within an Org-mode buffer."
  :init-value nil
  :lighter " Dossier"
  :keymap dossier-mode-map

  (if dossier-mode
	  (message "Dossier mode enabled. Ready to review.")
	(message "Dossier mode disabled.")))

(provide 'dossier)

;; Local variables:
;; eval: (add-hook 'after-save-hook #'emacs-lisp-byte-compile nil t)
;; End:
;;; dossier.el ends here
