;;; elpaso.el --- Emacs lisp package archive self officiator  -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2021 The Authors of elpaso.el

;; Authors: dickmao <github id: dickmao>
;; Version: 0.1.0
;; Keywords: maint tools
;; URL: https://github.com/dickmao/elpaso
;; Package-Requires: ((emacs "26.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with elpaso.el.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Self-officiating package manager for the emacs text editor.  Like quelpa_.
;;
;; Elpaso abjures the middle-man role played by package archive operators like
;; ELPA and MELPA, building packages directly from upstream sources.
;;
;; ``M-x elpaso``
;;   Specifying owner/package, e.g., ``magnars/dash.el`` yields the desired github **or
;;   gitlab** repo.  More conveniently, enter free-form keywords to conduct
;;   a github search.  As of this writing, gitlab's nascent search
;;   functionality is unviable.  *First-time users will need to authenticate with
;;   both github and gitlab's GraphQL API.*
;;
;;   If the target has not registered a recipe, elpaso will forge ahead
;;   by running ``package-buffer-info`` on the ``<name>.el``.  If you are an author,
;;   you can help elpaso's cause by opening your ``<name>.el``, and running
;;   ``M-: (package-buffer-info)`` to ensure it produces a proper package descriptor.
;;
;;   To leave less to chance, a package author may ``git add .recipe`` to his
;;   toplevel directory a suitable recipe in the MELPA or ELPA format.  Such
;;   a ``.recipe`` file overrides all other recipes.
;;
;; ``M-x elpaso-refresh``
;;   Refresh recipes from all sources in ``elpaso-admin-cookbooks`` (defaults to
;;   melpa, elpa, and nongnu).
;;
;; ``M-x elpaso-install``
;;   Enter the package name to install or reinstall.
;;
;; ``M-x elpaso-delete``
;;   Enter the package name, then ``TAB``, to delete.
;;
;; ``M-x elpaso-purge``
;;   Deletes residual files in ``elpaso-defs-toplevel-dir`` (defaults to ``~/.emacs.d/elpaso``).
;;

;;; Code:

(require 'package)
(require 'elpaso-admin)
(require 'elpaso-defs)

(defvar ert--running-tests)

;;;###autoload
(defun elpaso-delete (package &optional force nosave)
  "Merely calls `package-delete' but spares guff about dependencies."
  (interactive
   (let* ((package-table
           (mapcar
            (lambda (p) (cons (package-desc-full-name p) p))
            (delq nil
                  (mapcar (lambda (p) (unless (package-built-in-p p) p))
                          (apply #'append (mapcar #'cdr package-alist))))))
          (package-name (completing-read "Delete package: "
                                         (mapcar #'car package-table)
                                         nil t)))
     (list (assoc-default package-name package-table)
           current-prefix-arg nil)))
  (let ((cease-and-desist
	 (lambda (args)
	   (setf (nthcdr 1 args) (cons t (nthcdr 2 args)))
	   args)))
    (unwind-protect
	(progn
	  (add-function :filter-args (symbol-function 'package-delete) cease-and-desist)
	  (package-delete package force nosave))
      (remove-function (symbol-function 'package-delete) cease-and-desist))))

;;;###autoload
(defun elpaso-install (package)
  "Fetch and install PACKAGE directly from git forges."
  (interactive (list (completing-read
                      "Package: "
                      (mapcar #'car (let ((inhibit-message t))
				      (elpaso-admin--get-specs)))
                      nil t nil)))
  (when (symbolp package) (setq package (symbol-name package)))
  (if (equal package "elpaso")
      ;; elpaso must be bootstrapped from source
      (message "elpaso-install: nice try")
    (elpaso-admin-for-pkg package (elpaso-admin-batch-install))
    (unless (bound-and-true-p ert--running-tests)
      (package-menu--post-refresh))))

;;;###autoload
(defun elpaso-refresh (&optional cookbook)
  "Refresh COOKBOOK, generally one of user, melpa, elpa, nongnu."
  (interactive (when current-prefix-arg
		 (list (completing-read
			"Archive: "
			(mapcar #'symbol-name elpaso-admin-cookbooks)
			nil t nil))))
  (dolist (c (if cookbook (list cookbook) elpaso-admin-cookbooks))
    (elpaso-admin-for-pkg c (elpaso-admin-batch-refresh)))
  (message nil))

;;;###autoload
(defun elpaso-purge ()
  "Purge residual git worktrees and references, and still-born packages.
Will not delete the backups subdirectory."
  (interactive)
  (elpaso-admin-purge))

(declare-function use-package-as-symbol "use-package-core")

;;;###autoload
(defvar elpaso--use-package-ensure-refreshed-p nil)

;;;###autoload
(defalias 'elpaso-use-package-ensure-function
  (lambda (name args _state)
    "Hook into the use-package ensure subsystem."
    (dolist (ensure args)
      (when-let ((package
		  (or (and (eq ensure t) (use-package-as-symbol name))
		      ensure)))
	(when (consp package)
          (setq package (car package)))
        (unless (package-installed-p package)
	  (unless elpaso--use-package-ensure-refreshed-p
	    (elpaso-refresh)
	    (setq elpaso--use-package-ensure-refreshed-p t))
          (elpaso-install package))))))

(defalias 'elapso-install #'elpaso-install)
(defalias 'elapso-delete #'elpaso-delete)
(defalias 'elapso-refresh #'elpaso-refresh)
(defalias 'elapso-purge #'elpaso-purge)

(when (equal elpaso-defs-toplevel-dir elpaso-defs-install-dir)
  (let ((default-directory elpaso-defs-toplevel-dir))
    (if (not (executable-find "git"))
        (display-warning 'elpaso "git program not found" :error)
      (unless (zerop (elpaso-admin--call nil "git" "rev-parse" "--show-toplevel"))
        (with-temp-buffer
          (unless (zerop (elpaso-admin--call t "git" "init" "--bare"))
            (error "elpaso abort: %s" (buffer-string))))))))

(provide 'elpaso)
;;; elpaso.el ends here
