
;; title: hello-stacks
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;
(define-data-var col uint u123)
;; data maps
;;

;; public functions
;;
(define-public (write-message (message (string-utf8 500)))
    (begin
        (print {message:message ,col:(var-get col)})
        (ok "Message printed")
    )
)
;; read only functions
;;

;; private functions
;;

