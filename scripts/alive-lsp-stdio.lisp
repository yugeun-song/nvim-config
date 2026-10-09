(require :asdf)
(require :sb-posix)

(defpackage #:alive-lsp-stdio
  (:use #:cl))

(in-package #:alive-lsp-stdio)

(defvar *root* (uiop:ensure-directory-pathname (second sb-ext:*posix-argv*)))

;; Keep the protocol on private fds so stray writes to fd 1 or reads from fd 0 cannot corrupt it.
(defvar *lsp-in* (sb-posix:dup 0))
(defvar *lsp-out* (sb-posix:dup 1))

(sb-posix:dup2 2 1)
(let ((null-fd (sb-posix:open "/dev/null" sb-posix:o-rdonly)))
  (sb-posix:dup2 null-fd 0)
  (sb-posix:close null-fd))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,(merge-pathnames "ocicl/" *root*)) :ignore-inherited-configuration))

(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (asdf:load-system "alive-lsp"))
  (error (e)
    (format *error-output* "alive-lsp failed to load: ~A~%" e)
    (sb-ext:exit :code 1 :abort t)))

;; alive-lsp passes buffer text to READ (#+ features, in-package names); #. must not evaluate.
(setf (sb-ext:symbol-global-value '*read-eval*) nil
      *read-eval* nil
      sb-ext:*exit-timeout* 2)

(defun table (&rest pairs)
  (let ((h (make-hash-table :test #'equalp)))
    (loop :for (k v) :on pairs :by #'cddr
          :do (setf (gethash k h) v))
    h))

(defun respond (id result)
  (let ((resp (alive/lsp/message/abstract:create-response id)))
    (setf (gethash "result" resp) result)
    resp))

(defun conform (method resp)
  (let ((result (and (hash-table-p resp) (gethash "result" resp))))
    (when (hash-table-p result)
      (cond ((string= method "initialize")
             (setf (gethash "hoverProvider" (gethash "capabilities" result)) t
                   (gethash "documentFormattingProvider" (gethash "capabilities" result)) t))
            ((string= method "textDocument/hover")
             (let ((text (gethash "value" result)))
               (setf (gethash "result" resp)
                     (when (and (stringp text) (string/= text ""))
                       (table "contents" (table "kind" "plaintext" "value" text))))))
            ((string= method "textDocument/definition")
             (unless (gethash "uri" result)
               (setf (gethash "result" resp) nil)))))
    resp))

(let* ((in (flexi-streams:make-flexi-stream
            (make-two-way-stream
             (sb-sys:make-fd-stream *lsp-in* :input t :element-type '(unsigned-byte 8) :buffering :full)
             (make-broadcast-stream))))
       (out (sb-sys:make-fd-stream *lsp-out* :output t :element-type '(unsigned-byte 8) :buffering :full))
       (state (alive/session/state:create :log (alive/logger:create *error-output* alive/logger:*error*)))
       (deps (alive/server::create-deps :input-stream in :output-stream out :state state))
       (handle (alive/deps:msg-handler deps)))
  (setf (alive/deps::dependencies-msg-handler deps)
        (lambda (d msg)
          (let ((method (or (cdr (assoc :method msg)) "")))
            (cond ((string= method "textDocument/formatting")
                   (funcall handle d (list* (cons :method "textDocument/rangeFormatting")
                                            (cons :params (acons :range `((:start (:line . 0) (:character . 0))
                                                                          (:end (:line . ,most-positive-fixnum)
                                                                                (:character . 0)))
                                                                 (cdr (assoc :params msg))))
                                            msg)))
                  ((string= method "shutdown") (respond (cdr (assoc :id msg)) nil))
                  ((string= method "exit") (sb-ext:exit :code 0 :abort t))
                  ((string= method "workspace/didChangeConfiguration") nil)
                  (t (conform method (funcall handle d msg)))))))
  (alive/session:start deps state)
  (loop :while (alive/session/state:running state)
        :do (sleep 0.2))
  (sb-ext:exit :code 0 :abort t))
