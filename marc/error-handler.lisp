(in-package :marc)

(defun try-to-recover ()
  (invoke-restart 'try-to-recover))

(defun insert-token (symbol value)
  (invoke-restart 'insert-token symbol value))

(defvar *errors-count* 0)

(defun handle-lexer-error (c)
  (declare (type lexer-error c))
  (incf *errors-count*)
  (princ c)
  (invoke-restart 'continue))

(defun handle-parse-error (c)
  (declare (type yacc-parse-error c))
  (incf *errors-count*)
  (cond ((and (find (yacc-parse-error-terminal c) '(\; \{))
	      (find '\) (yacc-parse-error-expected-terminals c)))
	 (format t "Line ~A: Syntax error: expected )~%" (line (yacc-parse-error-value c)))
	 (insert-token '\) '\) ))
	(t ;(princ c)
	   (format t "Line ~A: Unexpected terminal ~A (value ~A) after terminal ~A ~
                      (value ~A).~%Expected one of: ~A~%"
		   (line (yacc-parse-error-value c))
		   (yacc-parse-error-terminal c)
		   (value (yacc-parse-error-value c))
		   (yacc-parse-error-preceding-terminal c)
		   (value (yacc-parse-error-preceding-value c))
		   (yacc-parse-error-expected-terminals c))
	   (try-to-recover))))

(defun handle-semantic-condition (c)
  (declare (type semantic-condition c))
  (incf *errors-count*)
  (princ c)
  (invoke-restart 'continue))

(defun handle-undeclared-identifier (c)
  (declare (type undeclared-identifier c))
  (incf *errors-count*)
  (princ c)
  (invoke-restart 'treat-as-int))

(defun handle-type-convert-condition (c)
  (declare (type type-convert-condition c))
  (incf *errors-count*)
  (princ c)
  (invoke-restart 'continue))

(defun handle-unsupported-construction (c)
  (declare (type unsupported-construction c))
  (incf *errors-count*)
  (princ c)
  (invoke-restart 'continue))
