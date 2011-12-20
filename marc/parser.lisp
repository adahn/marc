;;;; Lexer and parser definitions.

(in-package :marc)

(eval-when (:compile-toplevel :load-toplevel :execute)
 (defun quote-nonalpha (token)
   (coerce (loop for c across token
	      appending (if (alphanumericp c)
			    `(,c)
			    `(#\\ ,c))) 'string))

 ;;; Tokens split into 3 categories.
 (define-constant +tokens+ '((char double do else float for if int long return 
			  short sizeof void while)
			 (<= >= == != \; { } \, = \( \) [ ] ! ~ -- ++ - + * /
			  % < > ^ \|\| \&\& \| \&)
			 (identifier constant string)) :test #'equal))

(defclass token-info ()
  ((value :type symbol
	  :accessor value
	  :initarg :value)
   (line :type integer
	 :accessor line
	 :initarg :line))
  (:documentation "It holds token value and some additional info (line number for now)."))

(defgeneric change-token-value (token value))

(defmethod change-token-value ((token token-info) value)
  (make-instance 'token-info :value value :line (line token)))

(defmethod value ((n symbol))
  n)

(defmethod value ((n (eql nil)))
  0)

(defmethod value (n)
  nil)

(defmethod print-object ((object token-info) stream)
  (print-unreadable-object (object stream)
    (format stream "~s" (value object))))

(define-condition lexer-error (error)
  ((sign :initarg :sign :reader sign)
   (line :initarg :line :reader line))
  (:report (lambda (c stream)
	     (format stream "Line ~D: Forbiden character ~C" (line c) (sign c)))))

(defmacro create-c-lexer (name)
  `(let ((line-number 1))
     (define-string-lexer ,name
	 ;; comments
	 ("/\\*(\\*[^/]|[^\\*])*\\*/")
       ;; keywords and operators
       ,@(loop for op in (append (first +tokens+)
				 (second +tokens+))
	    collecting `(,(quote-nonalpha 
			   (string-downcase (string op))) 
			  (return (values ',op
					  (make-instance 'token-info 
							 :value ',op :line line-number)))))
       ("[A-Za-z_]\\w*" (return
			  (values
			   'identifier 
			   (make-instance 'token-info
					  :value
					  (intern 
					   (regex-replace-all "_" $@ "-"))
					  :line line-number))))
       ;; literals (integers, floats and characters)
       ;; TODO: implement numeric escape sequences
       ,@(loop for pattern in '("\\d*\\.\\d+([eE][+-]?\\d+)?[fF]" ; float
				"\\d+\\.\\d*([eE][+-]?\\d+)?[fF]"
				"\\d+([eE][+-]?\\d+)?[fF]"
				"\\d*\\.\\d+([eE][+-]?\\d+)?" ; double
				"\\d+\\.\\d*([eE][+-]?\\d+)?"
				"\\d+[eE][+-]?\\d+"
				"\\d*\\.\\d+([eE][+-]?\\d+)?[lL]" ; long double
				"\\d+\\.\\d*([eE][+-]?\\d+)?[lL]"
				"\\d+([eE][+-]?\\d+)?[lL]"
				"'(\\.|[^\\'])'" ; char
				"L'(\\.|[^\\']){1,2}'" ; unsigned short (wchar_t)
				"\\d+" "0[0-7]+" "0x|X[0-9A-Fa-f]+" ; integer
				"'(\\.|[^\\']){2,4}'"
				"\\d+[uU]" "0[0-7]+[uU]" "0x|X[0-9A-Fa-f]+[uU]" ; unsigned
				"\\d+[lL]" "0[0-7]+[lL]" "0x|X[0-9A-Fa-f]+[lL]" ; long
				"\\d+[uU][lL]" "0[0-7]+[uU][lL]" ; unsigned long
				"0x|X[0-9A-Fa-f]+[uU][lL]" 
				"\"(\\.|[^\\\"])*\"" ; char*
				"L\"(\\.|[^\\\"])*\"") ; unsigned short* (wchar_t*)
	      for type in '(float-literal float-literal float-literal
			    double-literal double-literal double-literal
			    long-double-literal long-double-literal long-double-literal
			    char-literal
			    unsigned-short-literal
			    int-literal int-literal int-literal
			    int-literal
			    unsigned-literal unsigned-literal unsigned-literal
			    long-literal long-literal long-literal
			    unsigned-long-literal unsigned-long-literal 
			    unsigned-long-literal
			    char*-literal
			    unsigned-short*-literal)
	    collecting `(,pattern 
			 (return (values 
				  ',type
				  (make-instance 'token-info
						 :value (intern $@)
						 :line line-number)))))

       #|,@(loop for pattern in '("\\d*\\.\\d+([eE][+-]?\\d+)?[fFlL]?" 
				"\\d+\\.\\d*([eE][+-]?\\d+)?[fFlL]?"
				"\\d+([eE][+-]?\\d+)?[fFlL]?"
				"\\d+[uUlL]?" "0[0-7]+[uUlL]?" "0x|X[0-9A-Fa-f]+[uUlL]?"
				"L?'(\\.|[^\\'])+'")
	    collecting `(,pattern 
			 (return (values 
				  'constant
				  (make-instance 'token-info
						 :value (read-from-string $@)
						 :line line-number)))))
       ;; string literals
       ("L?\"(\\.|[^\\\"])*\"" (return 
				 (values 'string (make-instance 'token-info
								:value (intern $@)
								:line line-number))))|#
       ;; end of line
       ("\\n" (incf line-number))
       ;;other characters
       ("\\S" (with-simple-restart (continue "Continue reading input.")
		(error 'lexer-error :sign (character $@) :line line-number))))))

(defun c-stream-lexer (stream lexer-fun)
  (labels ((reload-closure (stream) 
	     (let ((line (read-line stream nil)))
	       (if (null line)
		   nil
		   (funcall lexer-fun line)))))
    (let ((lexer-closure (reload-closure stream)))
      (labels ((get-nonempty-token ()
		 (multiple-value-bind (token value) (funcall lexer-closure)
		   (if (null token)
		       (progn
			 (setf lexer-closure (reload-closure stream))
			 (if (null lexer-closure)
			     (values nil nil)
			     (get-nonempty-token)))
		       (values token value)))))
	(lambda ()
	  (if lexer-closure
	      (get-nonempty-token)
	      nil))))))


;;; cl-yacc parser
(define-parser *c-parser*
  (:muffle-conflicts t)
  (:start-symbol source)
  (:terminals (char double do else float for if int long return 
	      short sizeof void while identifier float-literal double-literal
	      long-double-literal char-literal unisgned-short-literal int-literal
	      unsigned-literal long-literal unsigned-long-literal char*-literal
	      unsigned-short*-literal << >> ++ -- \&\& \|\| <= >= == != \; { }
	      \, = \( \) [ ] ! ~ - + * / % < > ^ \|))
  (:precedence ((:left * / %) (:left + -) (:left << >>)
               (:left < > <= >=) (:left == !=) (:left &)
               (:left ^) (:left \|) (:left \&\&) (:left \|\|)
               (:right =) (:left \,) (:nonassoc if else)))

  (source
    (file #'nreverse))

  (file 
    (declaration-line)
    (file declaration-line #'rcons)
    (function)
    (file function #'rcons))
  
  (declaration-line
    (declaration \; (lambda (a b) (declare (ignore b)) a)))

  (declaration
    (type var-init-list (lambda (a b) 
			  (list 'declaration-line a (nreverse b)))))
  
  (var-init-list
    (var-init-list \, var-init #'skip-and-rcons)
    (var-init))
  
  (var-init
    (pointer-declarator = initializer (lambda (a b c) 
					(declare (ignore b)) 
					(list a c)))
    (pointer-declarator))

  (pointer-declarator
    declarator
    (* pointer-declarator))
  
  (declarator
    identifier 
    (\( declarator \) (lambda (a b c)
			(declare (ignore a c)) b))
    (declarator [ expression ] (lambda (a b c d)
				 (declare (ignore b d))
				 (list '|[]| a c)))
    (declarator [ ] (lambda (a b c)
		      (declare (ignore b c))
		      (list '|[]| a)))
    (declarator \( param-list \) (lambda (a b c d)
				   (declare (ignore b d))
				   (list '|()| a (nreverse c))))
    (declarator \( \) (lambda (a b c)
			(declare (ignore b c))
			(list '|()| a))))
    
  (initializer
    ({ initializer-list } (lambda (a b c)
			    (declare (ignore a c))
			    (cons '{} (nreverse b))))
    expression)
  
  (initializer-list
    (initializer)
    (initializer-list \, initializer #'skip-and-rcons))
  
  (function
    (type pointer-declarator block (lambda (a b c)
				     (list 'fun-definition a b c))))
  
  (type 
    char
    double
    float
    int
    long
    short
    void)
  
  (param-list
    (param-list \, parameter #'skip-and-rcons)
    (parameter))

  (parameter
    (type var-init))
  
  (block
    ({ } (lambda (a b) (declare (ignore a b)) '(new-block)))
    ({ instruction-list } (lambda (a b c)
			    (declare (ignore a c)) (list 'new-block '() (nreverse b))))
    ({ declaration-list } (lambda (a b c)
			    (declare (ignore a c)) (list 'new-block (nreverse b) '())))
    ({ declaration-list instruction-list } 
       (lambda (a b c d) (declare (ignore a d)) (list 'new-block
						      (nreverse b) (nreverse c)))))
  
  (declaration-list
    (declaration-line)
    (declaration-list declaration-line #'rcons))
  
  (instruction-list
    (instruction-list instruction #'rcons)
    (instruction))
  
  (instruction
    block 
    expression-instr
    conditional
    loop
    (return expression \; (lambda (a b c)
			    (declare (ignore c))
			    (list a b)))
    (return \; (lambda (a b)
		 (declare (ignore b))
		 (list a))))
  
  (expression-instr
    (\; (lambda (a)
	  (declare (ignore a))
	  nil))
    (expression \; (lambda (a b) 
		     (declare (ignore b))
		     a)))
  

  (expression
    cast-expression
    (expression * expression #'to-pn)
    (expression / expression #'to-pn)
    (expression % expression #'to-pn)
    (expression + expression #'to-pn)
    (expression - expression #'to-pn)
    (expression << expression  #'to-pn)
    (expression >> expression #'to-pn)
    (expression > expression #'to-pn)
    (expression < expression #'to-pn)
    (expression >= expression #'to-pn)
    (expression <= expression #'to-pn)
    (expression == expression #'to-pn)
    (expression != expression #'to-pn)
    (expression & expression  #'to-pn)
    (expression ^ expression  #'to-pn)
    (expression \| expression  #'to-pn)
    (expression \&\& expression  #'to-pn)
    (expression \|\| expression  #'to-pn)
    (unary-expression = expression #'to-pn)
    (expression \, expression #'to-pn))
  
  (cast-expression
    unary-expression
    (\( type \) cast-expression (lambda (a b c d)
				  (declare (ignore c))
				  (list (change-token-value a 'type-cast) d b))))
  
  (unary-expression
    postfix-expression
    (++ unary-expression)
    (-- unary-expression)
    (+ cast-expression (lambda (a b) 
			 (declare (ignore a))
			 b))
    (- cast-expression (lambda (a b)
			 (list (change-token-value a 'unary-) b)))
    (* cast-expression (lambda (a b)
			 (list (change-token-value a 'unary*) b)))
    (& cast-expression (lambda (a b)
			 (list (change-token-value a 'unary&) b)))
    (! cast-expression)
    (~ cast-expression)
    (sizeof unary-expression)
    (sizeof \( type \) (lambda (a b c d)
			   (declare (ignore b d)) (list a c))))

  (postfix-expression
    (postfix-expression \( expression \) 
			(lambda (a b c d) 
			  (declare (ignore b d))			    
			  (list '|()| a c)))
    (postfix-expression \( \) (lambda (a b c)
				(declare (ignore b c))
 				(list '|()| a)))
    (postfix-expression [ expression ] (lambda (a b c d)
					 (declare (ignore b d))
					 (list '|[]| a c)))
    (postfix-expression ++ (lambda (a b)
			     (list (change-token-value b 'post++) a)))
    (postfix-expression -- (lambda (a b)
			     (list (change-token-value b 'post--) a)))
    highest-expression)
    
  (highest-expression
    (identifier (lambda (a) (list 'var-name a)))
    (float-literal (lambda (a) (list 'float-literal a)))
    (double-literal (lambda (a) (list 'double-literal a)))
    (long-double-literal (lambda (a) (list 'long-double-literal a)))
    (char-literal (lambda (a) (list 'char-literal a)))
    (unsigned-short-literal (lambda (a) (list 'unsigned-short-literal a)))
    (int-literal (lambda (a) (list 'int-literal a)))
    (unsigned-literal (lambda (a) (list 'unsigned-literal a)))
    (long-literal (lambda (a) (list 'long-literal a)))
    (unsigned-long-literal (lambda (a) (list 'unsigned-long-literal a)))
    (char*-literal (lambda (a) (list 'char*-literal a)))
    (unsigned-short*-literal (lambda (a) (list 'unsigned-short*-literal a)))
    (\( expression \) (lambda (a b c)
			(declare (ignore a c))
			b)))
    
  (conditional
    (if \( expression \) instruction else instruction
	(lambda (a b expression c instr-if d instr-else)
	  (declare (ignore a b c d))
	  (list 'if-else expression instr-if instr-else)))
    (if \( expression \) instruction
	(lambda (a b expression c instr-if)
	  (declare (ignore a b c))
 	  (list 'if-else expression instr-if))))
    
  (repeat
    (for \( expression-instr expression-instr expression \) instruction
	 (lambda (a b expr1 expr2 expr3 c instruction)
	   (declare (ignore a b c))
	   (list 'for-loop expr1 expr2 expr3 instruction)))
    (for \( expression-instr expression-instr \) instruction
	 (lambda (a b expr1 expr2 c instruction)
	   (declare (ignore a b c))
	   (list 'for-loop expr1 expr2 instruction)))
    (while \( expression \) instruction (lambda (a b expression c instruction)
					  (declare (ignore a b c))
					  (list 'while-loop expression instruction)))
    (do instruction while \( expression \) \;
      (lambda (a instruction b c expression d e)
	(declare (ignore a b c d e))
	(list 'do-loop expression instruction)))))


(defun build-syntax-tree (source)
  (declare (type string source))
  (create-c-lexer c-lexer)
  (parse-with-lexer (c-lexer source) *c-parser*))
