(import trace)
(load "prelude.scm")

;;;from section 4.1.4 -- must precede def of metacircular apply
(define apply-in-underlying-scheme apply)

;;;section 4.1.1

(define (eval exp env)
  (log-line "eval" exp)
  (cond ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        (else
         (let ((proc (get 'eval (car exp))))
           (if proc
               (proc exp env)
               (if (application? exp)
                   (apply (eval (operator exp) env)
                          (list-of-values (operands exp) env))
                   (error "unknown expression type -- eval" exp)))))))

(define (apply procedure arguments)
  (cond ((primitive-procedure? procedure)
         (apply-primitive-procedure procedure arguments))
        ((compound-procedure? procedure)
         (eval-sequence
          (procedure-body procedure)
          (extend-environment
           (procedure-parameters procedure)
           arguments
           (procedure-environment procedure))))
        (else
         (error
          "unknown procedure type -- apply" procedure))))


(define (list-of-values exps env)
  (if (no-operands? exps)
      '()
      (cons (eval (first-operand exps) env)
            (list-of-values (rest-operands exps) env))))

(define (eval-if exp env)
  (if (true? (eval (if-predicate exp) env))
      (eval (if-consequent exp) env)
      (eval (if-alternative exp) env)))

(define (eval-sequence exps env)
  (cond ((last-exp? exps) (eval (first-exp exps) env))
        (else (eval (first-exp exps) env)
              (eval-sequence (rest-exps exps) env))))

(define (eval-assignment exp env)
  (set-variable-value! (assignment-variable exp)
                       (eval (assignment-value exp) env)
                       env)
  'ok)

(define (eval-definition exp env)
  (define-variable! (definition-variable exp)
    (eval (definition-value exp) env)
    env)
  'ok)

(put 'eval 'quote
     (lambda (exp env) (text-of-quotation exp)))
(put 'eval 'set! eval-assignment)
(put 'eval 'define eval-definition)
(put 'eval 'if eval-if)
(put 'eval 'lambda
     (lambda (exp env)
       (make-procedure (lambda-parameters exp)
                       (lambda-body exp)
                       env)))
(put 'eval 'begin
     (lambda (exp env)
       (eval-sequence (begin-actions exp) env)))

(define (eval-and exp env)
  (define (loop args)
    (if (null? args)
        #t
        (let ((value (eval (car args) env)))
          (if (true? value)
              (if (null? (cdr args))
                  value
                  (loop (cdr args)))
              #f))))
  (loop (cdr exp)))

(put 'eval 'and eval-and)

(define (expand-and exp)
  (define (loop args)
    (if (null? args)
        #t
        (if (null? (cdr args))
            (car args)
            (list 'if (car args)
                  (loop (cdr args))
                  #f))))
  (loop (cdr exp)))

(put 'eval 'and
     (lambda (exp env)
       (eval (expand-and exp) env)))

(define (eval-or exp env)
  (define (loop args)
    (if (null? args)
        #f
        (let ((value (eval (car args) env)))
          (if (true? value)
              value
              (loop (cdr args))))))
  (loop (cdr exp)))
(put 'eval 'or eval-or)

;;;section 4.1.2

(define (self-evaluating? exp)
  (cond ((number? exp) true)
        ((string? exp) true)
        ((boolean? exp) true)
        (else false)))

(define (quoted? exp)
  (tagged-list? exp 'quote))

(define (text-of-quotation exp) (cadr exp))

(define (tagged-list? exp tag)
  (if (pair? exp)
      (eq? (car exp) tag)
      false))

(define (variable? exp) (symbol? exp))

(define (assignment? exp)
  (tagged-list? exp 'set!))

(define (assignment-variable exp) (cadr exp))

(define (assignment-value exp) (caddr exp))


(define (definition? exp)
  (tagged-list? exp 'define))

(define (definition-variable exp)
  (if (symbol? (cadr exp))
      (cadr exp)
      (caadr exp)))

(define (definition-value exp)
  (if (symbol? (cadr exp))
      (caddr exp)
      (make-lambda (cdadr exp)
                   (cddr exp))))

(define (lambda? exp) (tagged-list? exp 'lambda))

(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))

(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)))


(define (if? exp) (tagged-list? exp 'if))

(define (if-predicate exp) (cadr exp))

(define (if-consequent exp) (caddr exp))

(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
      (cadddr exp)
      'false))

(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))


(define (begin? exp) (tagged-list? exp 'begin))

(define (begin-actions exp) (cdr exp))

(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))

(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq))))

(define (make-begin seq) (cons 'begin seq))


(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))

(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))


(define (cond? exp) (tagged-list? exp 'cond))

(define (cond-clauses exp) (cdr exp))

(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else))

(define (cond-predicate clause) (car clause))

(define (cond-actions clause) (cdr clause))

(define (cond->if exp)
  (expand-clauses (cond-clauses exp)))

(define (expand-clauses clauses)
  (if (null? clauses)
      'false                          ; no else clause
      (let ((first (car clauses))
            (rest (cdr clauses)))
        (if (cond-else-clause? first)
            (if (null? rest)
                (sequence->exp (cond-actions first))
                (error "else clause isn't last -- cond->if"
                       clauses))
            (make-if (cond-predicate first)
                     (sequence->exp (cond-actions first))
                     (expand-clauses rest))))))

(define (eval-cond exp env)
  (define (arrow-clause? clause)
    (eq? (cadr clause) '=>))
  (define (arrow-clause-recipient clause)
    (caddr clause))
  (define (loop clauses)
    (if (null? clauses)
        (eval 'false env)
        (let ((first (car clauses))
              (rest (cdr clauses)))
          (let ((predicate-value
                 (eval (if (cond-else-clause? first)
                           'true
                           (cond-predicate first))
                       env)))
            (if (true? predicate-value)
                (if (arrow-clause? first)
                    (let ((recipient
                           (eval (arrow-clause-recipient first) env)))
                      (apply recipient (list predicate-value)))
                    (eval (sequence->exp (cond-actions first)) env))
                (loop rest))))))
  (loop (cond-clauses exp)))

(put 'eval 'cond eval-cond)

(define (let-named? exp)
  (symbol? (cadr exp)))

(define (let-body exp)
  (if (let-named? exp)
      (cdddr exp)
      (cddr exp)))

(define (let-bindings exp)
  (if (let-named? exp)
      (caddr exp)
      (cadr exp)))

(define (let-name exp)
  (cadr exp))

(define (make-application proc args)
  (cons proc args))

(define (make-define name value)
  (list 'define name value))

(define (let->combination exp)
  (let ((bindings (let-bindings exp))
        (body (let-body exp)))
    (let ((vars (map car bindings))
          (exps (map cadr bindings)))
      (if (let-named? exp)
          (let ((name (let-name exp)))
            `((lambda ()
                (define ,name (lambda ,vars ,@body))
                (,name ,@exps))))
          `((lambda ,vars ,@body) ,@exps)))))

(put 'eval 'let
     (lambda (exp env)
       (eval (let->combination exp) env)))

(define (make-let* bindings body)
  (cons 'let* (cons bindings body)))

(define (make-let bindings body)
  (cons 'let (cons bindings body)))

(define (let*->nested-lets exp)
  (let ((bindings (cadr exp))
        (body (cddr exp)))
    (if (null? (cdr bindings))
        (make-let bindings body)
        (make-let (list (car bindings))
                  (list (let*->nested-lets
                         (make-let* (cdr bindings)
                                    body)))))))

(put 'eval 'let*
     (lambda (exp env) (eval (let*->nested-lets exp) env)))

(define (expand-for exp)
  (assert (eq? 'do (cadddr exp)))
  (let ((var (cadr exp))
        (limit (caddr exp))
        (body (cddddr exp)))
    `(let ((body (lambda (,var) ,@body)))
       (define (loop i)
         (if (= i ,limit)
             #f
             (begin (body i)
                    (loop (+ i 1)))))
       (loop 0))))

(put 'eval 'for
     (lambda (exp env) (eval (expand-for exp) env)))

(define (expand-while exp)
  (assert (eq? 'do (caddr exp)))
  (let ((condition (cadr exp))
        (body (cdddr exp)))
    `(let ((body (lambda () ,@body))
           (condition (lambda () ,condition)))
       (define (loop)
         (if (condition)
             (begin (body)
                    (loop))))
       (loop))))

(put 'eval 'while
     (lambda (exp env) (eval (expand-while exp) env)))

(put 'eval 'make-unbound!
     (lambda (exp env)
       (frame-delete-binding! (first-frame env)
                              (cadr exp))))

(define (expand-letrec exp)
  (let ((bindings (cadr exp))
        (body (cddr exp)))
    (make-let
     (map (lambda (binding)
            (list (car binding) ''*unassigned*))
          bindings)
     (append
      (map (lambda (binding)
             (list 'set! (car binding) (cadr binding)))
           bindings)
      body))))

(put 'eval 'letrec
     (lambda (exp env) (eval (expand-letrec exp) env)))

;;;section 4.1.3

(define (true? x)
  (not (eq? x false)))

(define (false? x)
  (eq? x false))


(define (make-procedure parameters body env)
  (list 'procedure parameters body env))

(define (compound-procedure? p)
  (tagged-list? p 'procedure))


(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))


(define (enclosing-environment env) (cdr env))

(define (first-frame env) (car env))

(define the-empty-environment '())

(define (make-frame variables values)
  (cons variables values))

(define (frame-variables frame) (car frame))
(define (frame-values frame) (cdr frame))

(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))))

(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
      (cons (make-frame vars vals) base-env)
      (if (< (length vars) (length vals))
          (error "too many arguments supplied" vars vals)
          (error "too few arguments supplied" vars vals))))

(define (scan-frame frame var)
  (define (scan vars vals)
    (cond ((null? vars) '())
          ((eq? (car vars) var) vals)
          (else (scan (cdr vars) (cdr vals)))))
  (scan (frame-variables frame) (frame-values frame)))

(define (scan-env env var)
  (define (loop env)
    (if (eq? env the-empty-environment)
        '()
        (let ((vals (scan-frame (first-frame env) var)))
          (if (null? vals)
              (loop (enclosing-environment env))
              vals))))
  (loop env))

(define (lookup-variable-value var env)
  (let ((vals (scan-env env var)))
    (if (null? vals)
        (error "unbound variable" var)
        (car vals))))

(define (set-variable-value! var val env)
  (let ((vals (scan-env env var)))
    (if (null? vals)
        (error "unbound variable -- set!" var)
        (set-car! vals val))))

(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (let ((vals (scan-frame frame var)))
      (if (null? vals)
          (add-binding-to-frame! var val frame)
          (set-car! vals val)))))

(define (frame-delete-binding! frame var)
  (define (loop vars vals)
    (cond ((null? (cdr vars)) #f)
          ((eq? (cadr vars) var)
           (set-cdr! vars (cddr vars))
           (set-cdr! vals (cddr vals))
           #t)
          (else (loop (cdr vars) (cdr vals)))))
  (let ((vars (car frame))
        (vals (cdr frame)))
    (cond ((null? vars) #f)
          ((eq? (car vars) var)
           (set-car! frame (cdr vars))
           (set-cdr! frame (cdr vals))
           #t)
          (else (loop vars vals)))))

;;;section 4.1.4

(define (setup-environment)
  (let ((initial-env
         (extend-environment (primitive-procedure-names)
                             (primitive-procedure-objects)
                             the-empty-environment)))
    (define-variable! 'true true initial-env)
    (define-variable! 'false false initial-env)
    initial-env))

(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive))

(define (primitive-implementation proc) (cadr proc))

(define primitive-procedures
  (list (list 'car car)
        (list 'cdr cdr)
        (list 'cons cons)
        (list 'null? null?)
        (list '+ +)
        (list '* *)
        (list '= =)
        (list '- -)
        (list '< <)
        (list '> >)
        (list 'list list)))

(define (primitive-procedure-names)
  (map car
       primitive-procedures))

(define (primitive-procedure-objects)
  (map (lambda (proc) (list 'primitive (cadr proc)))
       primitive-procedures))

(define (apply-primitive-procedure proc args)
  (apply-in-underlying-scheme
   (primitive-implementation proc) args))

(define the-global-environment (setup-environment))

(define (application? exp) (tagged-list? exp 'call))
(define (operator exp) (cadr exp))
(define (operands exp) (cddr exp))

(test-group
 "procedure-call-begins-with-call"
 (test-error (eval '(+ 1 2) (setup-environment)))
 (test 3 (eval '(call + 1 2) (setup-environment)))
 (test 'a (eval '(call car (call cons 'a 'b)) (setup-environment))))

(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))

(test-group
 "eval"
 (test 29 (eval '(+ (* 1 2) (* 3 (+ 4 5)))
                (setup-environment)))
 (test 2 (eval '(if (null? 0) 1 2) (setup-environment)))
 (test 3 (eval '(begin 0 1 2 3) (setup-environment))))

(test-group
 "and"
 (test #t (eval '(and) (setup-environment)))
 (test #f (eval '(and #f) (setup-environment)))
 (test 1 (eval '(and 1) (setup-environment)))
 (test 3 (eval '(and #t 3) (setup-environment)))
 (test 0 (eval '(begin (define x 0)
                       (and #f (set! x 1))
                       x) (setup-environment))))

(test-group
 "or"
 (test #f (eval '(or) (setup-environment)))
 (test #f (eval '(or #f) (setup-environment)))
 (test 1 (eval '(or 1) (setup-environment)))
 (test #t (eval '(or #t 3) (setup-environment)))
 (test 0 (eval '(begin (define x 0)
                       (or #t (set! x 1))
                       x) (setup-environment))))

(test-group
 "expand-and"
 (test #t (expand-and '(and)))
 (test
  '(if 0 1 #f)
  (expand-and '(and 0 1)))
 (test
  '(if 0 (if 1 2 #f) #f)
  (expand-and '(and 0 1 2))))

(test-group
 "cond"
 (test
  3
  (eval '(cond (#f 1)
               (#f 2)
               (0 3))
        (setup-environment)))
 (test
  2
  (eval '(cond (#f x)
               (#f y)
               (else 2))
        (setup-environment)))
 (test
  0
  (eval '(cond ((+ 2 3) 0)
               (else 1))
        (setup-environment))))

(test-group
 "cond =>"
 (test
  0
  (eval '(cond ((cons 0 1) => car))
        (setup-environment)))
 (test
  3
  (eval '(cond (#f 0)
               (#f => 1)
               ((cons 2 3) => cdr)
               (else 2))
        (setup-environment))))

(test-group
 "let->combination"
 (test
  '((lambda ()))
  (let->combination '(let ())))
 (test
  '((lambda (a) c d) b)
  (let->combination '(let ((a b)) c d)))
 (test
  '((lambda (a) c d) b)
  (let->combination '(let ((a b)) c d)))
 (test
  '((lambda (a c) e f) b d)
  (let->combination '(let ((a b) (c d)) e f))))

(test-group
 "let"
 (test
  0
  (eval '(let ((x 0)) x)
        (setup-environment)))
 (test
  4
  (eval '(let ((x 0) (y (+ 1 3))) (+ x y))
        (setup-environment)))
 (test
  0
  (eval '(begin (define x 0)
                (let () (define x 1))
                x)
        (setup-environment))))

(test-group
 "let*->nested-lets"
 (test
  '(let ((x 3))
     (let ((y (+ x 2)))
       (let ((z (+ x y 5)))
         (* x z))))
  (let*->nested-lets
   '(let* ((x 3)
           (y (+ x 2))
           (z (+ x y 5)))
      (* x z)))))

(test-group
 "let*"
 (test
  39
  (eval '(let* ((x 3)
                (y (+ x 2))
                (z (+ x y 5)))
           (* x z))
        (setup-environment))))

(test-group
 "let->combination named"
 (test
  '((lambda ()
      (define f (lambda (v0 v1) body))
      (f e0 e1)))
  (let->combination '(let f ((v0 e0) (v1 e1)) body))))

(test-group
 "let named"
 (test
  3
  (eval
   '(let g ((n 2))
      (if (= n 0)
          3
          (g (- n 1))))
   (setup-environment)))
 (test
  8
  (eval
   '(let fib-iter ((a 1) (b 0) (count 6))
      (if (= count 0)
          b
          (fib-iter (+ a b)
                    a
                    (- count 1))))
   (setup-environment)))
 (test
  0
  (eval
   '(let ((x 0))
      (let x ((y 0)) 0)
      (+ x 0))
   (setup-environment))))

(test-group
 "expand-for"
 (test
  '(let ((body (lambda (i) x y)))
     (define (loop i)
       (if (= i 10)
           #f
           (begin (body i)
                  (loop (+ i 1)))))
     (loop 0))
  (expand-for '(for i 10 do
                    x y)))
 (test
  '(let ((body (lambda (x) #f)))
     (define (loop i)
       (if (= i y)
           #f
           (begin (body i)
                  (loop (+ i 1)))))
     (loop 0))
  (expand-for '(for x y do #f))))

(test-group
 "for"
 (test
  0
  (eval
   '(begin (define x 0)
           (for x 10 do #f)
           x)
   (setup-environment)))
 (test
  45
  (eval
   '(let ((s 0))
      (for i 10 do (set! s (+ s i)))
      s)
   (setup-environment))))

(test-group
 "expand-while"
 (test
  '(let ((body (lambda () b c))
         (condition (lambda () a)))
     (define (loop)
       (if (condition)
           (begin (body)
                  (loop))))
     (loop))
  (expand-while '(while a do b c))))

(test-group
 "while"
 (test
  45
  (eval
   '(begin (define i 0)
           (define s 0)
           (while (< i 10) do
                  (set! s (+ s i))
                  (set! i (+ i 1)))
           s)
   (setup-environment))))

(test-group
 "frame-delete-binding"
 (test
  #f
  (let ((frame (make-frame '() '())))
    (frame-delete-binding! frame 'a)))
 (test
  '(() ())
  (let ((frame (make-frame '(x) '(0))))
    (frame-delete-binding! frame 'x)
    (list (frame-variables frame) (frame-values frame))))
 (test
  '((y z) (4 5))
  (let ((frame (make-frame '(x y z) '(3 4 5))))
    (frame-delete-binding! frame 'x)
    (list (frame-variables frame) (frame-values frame))))
 (test
  '((x z) (3 5))
  (let ((frame (make-frame '(x y z) '(3 4 5))))
    (frame-delete-binding! frame 'y)
    (list (frame-variables frame) (frame-values frame))))
 (test
  '((x y) (3 4))
  (let ((frame (make-frame '(x y z) '(3 4 5))))
    (frame-delete-binding! frame 'z)
    (list (frame-variables frame) (frame-values frame)))))

(test-group
 "make-unbound!"
 (test
  0
  (eval
   '(let ((x 0))
      (let ((x 1))
        (make-unbound! x)
        x))
   (setup-environment)))
 (test-error
  (eval
   '(let ((a 3))
      (make-unbound! a)
      a)
   (setup-environment))))

(test-group
 "expand-letrec"
 (test
  '(let () x)
  (expand-letrec
   '(letrec () x)))
 (test
  '(let ((v '*unassigned*))
     (set! v e)
     b)
  (expand-letrec
   '(letrec ((v e)) b)))
 (test
  '(let ((v '*unassigned*)
         (v1 '*unassigned*))
     (set! v e)
     (set! v1 e1)
     x y)
  (expand-letrec
   '(letrec ((v e) (v1 e1)) x y))))

(test-group
 "letrec"
 (test
  120
  (eval
   '(letrec
        ((fact
          (lambda (n)
            (if (= n 1)
                1
                (* n (fact (- n 1)))))))
      (fact 5))
   (setup-environment)))
 (test
  '(#t #f #t)
  (eval
   '(letrec
        ((even?
          (lambda (n)
            (if (= n 0)
                true
                (odd? (- n 1)))))
         (odd?
          (lambda (n)
            (if (= n 0)
                false
                (even? (- n 1))))))
      (list (even? 0) (even? 1) (even? 2)))
   (setup-environment))))

(define debug #t)
