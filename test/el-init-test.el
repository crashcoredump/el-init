;; -*- lexical-binding: t; -*-

(require 'undercover)

(when (string= (getenv "COVERALLS") "yes")
  (undercover "el-init.el"))

(require 'ert)
(require 'el-init)
(require 'el-init-test-helper)

;; not to unload `warnings' by `el-init-test-sandbox'
(require 'warnings)

;;;; Utilities

(ert-deftest el-init-test-provide ()
  (el-init-test-sandbox
   (require 'init-test-provide
            (el-init-test-get-path "test-inits/utilities/init-test-provide"))

   (should (featurep 'init-test-provide))))

;;;; Record

(ert-deftest el-init-test-record ()
  (el-init-test-sandbox
   (el-init-add-record 'el-init-test 'foo "foo")

   (should (equal (el-init-get-feature-record 'el-init-test)
                  '(foo "foo")))
   (should (string= (el-init-get-record 'el-init-test 'foo) "foo"))
   (should (eq (el-init-get-record 'el-init-test 'bar) nil))

   (setf (el-init-get-record 'el-init-test 'bar) "bar")

   (should (string= (el-init-get-record 'el-init-test 'bar) "bar"))))

;;;; Loader

(ert-deftest el-init-test-loader ()
  (let ((target-directory (el-init-test-get-path "test-inits/loader")))
    (el-init-test-sandbox
     (should-not (featurep 'init-test-a))
     (should-not (featurep 'init-test-b))
     (should-not (featurep 'init-test-c))

     (el-init-load target-directory
                   :subdirectories '(".")
                   :wrappers nil)

     (should     (featurep 'init-test-a))
     (should-not (featurep 'init-test-b))
     (should-not (featurep 'init-test-c)))

    ;; sub directory
    (el-init-test-sandbox
     (should-not (featurep 'init-test-a))
     (should-not (featurep 'init-test-b))
     (should-not (featurep 'init-test-c))

     (el-init-load target-directory
                   :subdirectories '("." "subdir1")
                   :wrappers nil)

     (should     (featurep 'init-test-a))
     (should     (featurep 'init-test-b))
     (should-not (featurep 'init-test-c)))

    ;; recursive
    (el-init-test-sandbox
     (should-not (featurep 'init-test-a))
     (should-not (featurep 'init-test-b))
     (should-not (featurep 'init-test-c))

     (el-init-load target-directory
                   :subdirectories '("." ("subdir1" t))
                   :wrappers nil)

     (should (featurep 'init-test-a))
     (should (featurep 'init-test-b))
     (should (featurep 'init-test-c)))

    ;; override
    (let* ((feature-list nil)
           (fn (lambda (only-init-files)
                 (add-to-list 'load-path target-directory)
                 (el-init-load target-directory
                               :subdirectories '("override")
                               :wrappers
                               (list
                                (lambda (feature &optional filename noerror)
                                  (push feature feature-list)
                                  (el-init-next feature filename noerror)))
                               :override t
                               :override-only-init-files only-init-files))))

      ;; override only for init files
      (el-init-test-sandbox
       (funcall fn t)
       (should-not (memq 'init-test-a        feature-list))
       (should     (memq 'init-test-override feature-list)))

      (setq feature-list nil)

      ;; override for all libraries
      (el-init-test-sandbox
       (funcall fn nil)
       (should (memq 'init-test-a        feature-list))
       (should (memq 'init-test-override feature-list))))

    ;; `el-init-override-only-init-files-p'
    (let ((overridden nil))
      (el-init-test-sandbox
        (el-init-load target-directory
                      :subdirectories '("in-overridden-require-p/a"
                                        "in-overridden-require-p/b")
                      :wrappers (list
                                 (lambda (feature &optional filename noerror)
                                   (when el-init-overridden-require-p
                                     (push feature overridden))
                                   (el-init-next feature filename noerror)))
                      :override t)
        (should (equal '(init-b) overridden))))))

;;;; Require Wrappers

(ert-deftest el-init-test-require/benchmark ()
  (el-init-test-sandbox
   (el-init-load (el-init-test-get-path "test-inits/wrappers/benchmark")
                 :subdirectories '(".")
                 :wrappers (list #'el-init-require/benchmark))

   (let ((record (el-init-get-record 'init-test-benchmark
                                     'el-init-require/benchmark)))
     (should (= (length record) 3))
     (should (cl-every #'numberp record)))))

(ert-deftest el-init-test-require/record-error ()
  (el-init-test-sandbox
    (el-init-test-dont-debug
      (el-init-load (el-init-test-get-path "test-inits/wrappers/error")
                    :subdirectories '(".")
                    :wrappers (list #'el-init-require/record-error)))

    (should (equal (el-init-get-record 'init-test-error
                                       'el-init-require/record-error)
                   '(error "Error")))))

(ert-deftest el-init-test-require/ignore-errors ()
  (el-init-test-sandbox
    (let ((caught nil))
      (condition-case e
          (el-init-test-dont-debug
            (el-init-load (el-init-test-get-path "test-inits/wrappers/error")
                          :subdirectories '(".")
                          :wrappers (list #'el-init-require/ignore-errors)))
        (error (setq caught e)))

      (should (null caught)))))

(ert-deftest el-init-test-require/record-eval-after-load-error ()
  (el-init-test-sandbox
    (el-init-test-dont-debug
      (el-init-load (el-init-test-get-path "test-inits/wrappers/eval-after-load")
                    :subdirectories '("error")
                    :wrappers (list #'el-init-require/record-eval-after-load-error))
      (add-to-list 'load-path
                   (el-init-test-get-path "test-inits/wrappers/eval-after-load"))
      (require 'init-test-library))

    (let ((record (el-init-get-record 'init-test-error
                                      'el-init-require/record-eval-after-load-error)))
      (should (= (length record) 1))
      (should (equal (plist-get (cl-first record) :error)
                     '(error "Error"))))))

(ert-deftest el-init-test-require/system-case ()
  (el-init-test-sandbox
   (el-init-load (el-init-test-get-path "test-inits/wrappers/system-case")
                 :subdirectories '(".")
                 :wrappers (list #'el-init-require/system-case))

   (should (= (length (cl-remove-if-not #'featurep
                                        '(init-mac-test
                                          init-windows-test
                                          init-linux-test
                                          init-freebsd-test)))
              1))))

(ert-deftest el-init-test-require/record-old-library ()
  (let* ((dir (el-init-test-get-path "test-inits/wrappers/old-library"))
         (el  (concat dir "/init-test.el"))
         (fn  (lambda ()
                (el-init-load
                 dir
                 :subdirectories '(".")
                 :wrappers (list #'el-init-require/record-old-library))))
         (rec (lambda ()
                (el-init-get-record 'init-test
                                    'el-init-require/record-old-library))))
    (byte-compile-file el)

    (el-init-test-sandbox
     (funcall fn)
     (should-not (funcall rec)))

    (sleep-for 1)                       ; certainly update timestamp
    (shell-command (format "touch %s" (shell-quote-argument el)))

    (el-init-test-sandbox
     (funcall fn)
     (should (funcall rec)))))

(ert-deftest el-init-test-require/compile-old-library ()
  (let* ((dir (el-init-test-get-path "test-inits/wrappers/old-library"))
         (el  (concat dir "/init-test.el"))
         (elc (concat el "c")))
    (byte-compile-file el)
    (sleep-for 1)
    (shell-command (format "touch %s" (shell-quote-argument el)))
    (sleep-for 1)

    (el-init-test-sandbox
     (el-init-load dir
                   :subdirectories '(".")
                   :wrappers (list #'el-init-require/compile-old-library))
     (should (el-init-get-record 'init-test
                                 'el-init-require/compile-old-library))
     (should (file-newer-than-file-p elc el)))))

(ert-deftest el-init-test-require/lazy ()
  (let ((dir (el-init-test-get-path "test-inits/wrappers/lazy")))
    (let* ((basic  (concat dir "/basic"))
           (libdir (concat basic "/lib"))
           (fn     (lambda ()
                     (el-init-test-sandbox
                       (add-to-list 'load-path libdir)
                       (el-init-load basic
                                     :subdirectories '(".")
                                     :wrappers (list #'el-init-require/lazy))

                       (should-not (featurep 'init-lazy-lib-dummy))

                       (require 'lib-dummy)

                       (should (featurep 'init-lazy-lib-dummy))))))

      (let ((el-init-lazy-feature-type 'string))
        (funcall fn))

      (let ((el-init-lazy-feature-type 'symbol))
        (funcall fn)))

    ;; recursive loading
    ;;
    ;; If `el-init-require/lazy' called `require' to load lib-foo.el
    ;; before loading init-lazy-lib-foo.el, init-lazy-lib-foo.el would
    ;; be loaded twice by the following steps.
    ;;
    ;; * `eval-after-load' registers init-lazy-lib-foo.el.
    ;; * `require' loads init-foo.el.
    ;;  * init-foo.el: `require' loads init-lazy-lib-foo.el.
    ;;   * init-lazy-lib-foo.el: `require' loads lib-foo.el.
    ;;    * `require' loads init-lazy-lib-foo.el by the form of `eval-after-load'.
    (let* ((rec    (concat dir "/recursive"))
           (libdir (concat rec "/lib")))
      (el-init-test-sandbox
        (add-to-list 'load-path libdir)
        (el-init-load rec
                      :subdirectories '("init-lazy" "init")
                      :wrappers (list #'el-init-require/lazy))

        (should (= el-init-test-init-lazy-recursive-count 1))))))

;;; el-init-test.el ends here
