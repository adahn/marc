(in-package :asdf)

(defsystem "marc"
  :description "marc: Micro ARm Compiler"
  :version "0.01"
  :author "Adam Rzepka <adrzepka@gmail.com>"
  :license "GNU GPL"
  :depends-on (cl-ppcre cl-lex yacc alexandria)
  :components ((:module "marc"
			:serial t
			:components
			((:file "init")
			 (:file "utils")
			 (:file "translator")
			 (:file "parser")
			 (:file "error-handler")
			 (:file "marc")))))