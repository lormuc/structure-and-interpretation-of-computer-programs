(load "prelude.scm")

(test-begin)

(define (type exp)
  (if (pair? exp)
      (car exp)
      (error "unknown expression type" exp)))

(define (contents exp)
  (if (pair? exp)
      (cdr exp)
      (error "unknown expression contents" exp)))

(test 'and (type '(and (a (? x)) (b (? x)))))
(test '((a (? x)) (b (? x)))
      (contents '(and (a (? x)) (b (? x)))))

(define (rule? statement)
  (tagged-list? statement 'rule))
(test #f (rule? '(x y z)))
(test #t (rule? '(rule (a (? x)) (b (? x)))))

(define (rule-body rule)
  (if (null? (cddr rule))
      '(always-true)
      (caddr rule)))

(define (conclusion rule)
  (cadr rule))
(test '(abc (? a) (? b) (? c))
      (conclusion '(rule (abc (? a) (? b) (? c)))))

(define (var? exp)
  (tagged-list? exp '?))

(define (constant-symbol? exp)
  (symbol? exp))

(test #f (constant-symbol? '(? x)))
(test #t (constant-symbol? 'a))

(define (contract-question-mark var)
  (string->symbol
   (string-append
    "?"
    (if (number? (cadr var))
        (string-append (symbol->string (caddr var))
                       "-"
                       (number->string (cadr var)))
        (symbol->string (cadr var))))))

(test '?var (contract-question-mark '(? var)))
(test '?x-0 (contract-question-mark '(? 0 x)))

(define (make-binding variable value)
  (cons variable value))

(define (binding-variable binding)
  (car binding))

(define (binding-value binding)
  (cdr binding))

(test
 '(x . 0)
 (let ((binding (make-binding 'x 0)))
   (cons (binding-variable binding)
         (binding-value binding))))

(define (binding-in-frame variable frame)
  (assoc variable frame))

(test
 #f
 (binding-in-frame '(? x) '()))
(test
 '((? y) . 3)
 (binding-in-frame
  '(? y)
  '(((? x) . 0) ((? y) . 3) ((? z) . 5))))

(define (extend variable value frame)
  (cons (make-binding variable value) frame))

(test '(((? x) . 0)) (extend '(? x) 0 '()))
(test '(((? y) . 1) ((? x) . 0))
      (extend '(? y) 1 '(((? x) . 0))))

(define (use-index? exp)
  (constant-symbol? (car exp)))
(test #t (use-index? '(x y)))
(test #f (use-index? '((? x) (? y) z)))

(define (index-key-of pat)
  (if (constant-symbol? (car pat))
      (car pat)
      '?))
(test '? (index-key-of '((? x) (? y))))
(test 'x (index-key-of '(x (? y) z)))

(define (indexable? pat)
  (let ((head (car pat)))
    (or (var? head) (constant-symbol? head))))
(test #t (indexable? '((? x) y z)))
(test #t (indexable? '(a b c)))
(test #f (indexable? '((u v) w)))

(define (get-stream table key-1 key-2)
  (or (table-get table key-1 key-2) the-empty-stream))

(define (store-assertion-in-index assertion table)
  (if (indexable? assertion)
      (let ((index (index-key-of assertion)))
        (let ((prev (get-stream table index 'assertion-stream)))
          (table-put table index 'assertion-stream
                     (cons-stream assertion prev))))))

(test
 '(((a b c) (a d e)) ((b b c)))
 (let ((table (make-table)))
   (store-assertion-in-index '(a d e) table)
   (store-assertion-in-index '(a b c) table)
   (store-assertion-in-index '(b b c) table)
   (store-assertion-in-index '((? x) b c) table)
   (list
    (stream->list
     ((table 'lookup-proc) 'a 'assertion-stream))
    (stream->list
     ((table
       'lookup-proc) 'b 'assertion-stream)))))

(define (store-rule-in-index rule table)
  (if (indexable? (conclusion rule))
      (let ((key (index-key-of (conclusion rule))))
        (let ((old (get-stream table key 'rule-stream)))
          (table-put table key 'rule-stream
                     (cons-stream rule old))))))

(test
 '((rule (f (? a)) ((? a) b c d))
   (rule (f (? a)))
   (rule (f (? x) (? y)) (x y z)))
 (let ((table (make-table)))
   (store-rule-in-index '(rule (f (? x) (? y)) (x y z)) table)
   (store-rule-in-index '(rule (f (? a))) table)
   (store-rule-in-index '(rule (f (? a)) ((? a) b c d)) table)
   (store-rule-in-index '(rule (i (? a)) (x b c d)) table)
   (stream->list (table-get table 'f 'rule-stream))))
(test
 '((rule ((? a)) (b c)))
 (let ((table (make-table)))
   (store-rule-in-index '(rule ((? a)) (b c)) table)
   (stream->list (table-get table '? 'rule-stream))))

(define (make-rule-counter)
  (let ((counter -1))
    (lambda (request)
      (cond ((eq? request 'new-rule-application-id)
             (set! counter (+ counter 1))
             counter)
            (else (error "unknown request -- rule-counter" request))))))

(test-error ((make-rule-counter) 'unknown-request))
(test
 '(0 1)
 (let ((rc (make-rule-counter)))
   (let ((x (rc 'new-rule-application-id)))
     (let ((y (rc 'new-rule-application-id)))
       (list x y)))))

(define (make-database)
  (let ((the-assertions the-empty-stream)
        (the-rules the-empty-stream)
        (index (make-table))
        (rule-counter (make-rule-counter)))
    (define (dispatch request)
      (cond ((eq? request 'add-assertion!)
             (lambda (assertion)
               (store-assertion-in-index assertion index)
               (let ((old the-assertions))
                 (set! the-assertions
                       (cons-stream assertion old))
                 'ok)))
            ((eq? request 'get-all-assertions)
             the-assertions)
            ((eq? request 'add-rule!)
             (lambda (rule)
               (store-rule-in-index rule index)
               (let ((old the-rules))
                 (set! the-rules (cons-stream rule old))
                 'ok)))
            ((eq? request 'get-all-rules)
             the-rules)
            ((eq? request 'get-index) index)
            ((eq? request 'add-rule-or-assertion!)
             (lambda (x)
               (if (rule? x)
                   ((dispatch 'add-rule!) x)
                   ((dispatch 'add-assertion!) x))))
            ((eq? request 'new-rule-application-id)
             (rule-counter 'new-rule-application-id))
            (else (error "unknown request -- database"
                         request))))
    dispatch))

(test
 '(#t ((d e f g) (a b c)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(a b c))
   ((db 'add-assertion!) '(d e f g))
   (let ((a (db 'get-all-assertions)))
     (list (promise? (cdr a)) (stream->list a)))))
(test
 '(#t ((d e f g) (a b c)) ((a b c)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(a b c))
   ((db 'add-assertion!) '(d e f g))
   (let ((a (db 'get-all-assertions)))
     (list (promise? (cdr a)) (stream->list a)
           (stream->list
            (table-get (db 'get-index) 'a 'assertion-stream))))))
(test
 '(#t ((rule (r (? x) (? y))) (rule (s) (t u v)))
      ((rule (r (? x) (? y)))))
 (let ((db (make-database)))
   ((db 'add-rule!) '(rule (s) (t u v)))
   ((db 'add-rule!) '(rule (r (? x) (? y))))
   (let ((a (db 'get-all-rules)))
     (list (promise? (cdr a)) (stream->list a)
           (stream->list
            (table-get (db 'get-index) 'r 'rule-stream))))))
(let ((rule-0 '(rule (s (? x) (? y)) (t u)))
      (rule-1 '(rule (a (? z)) (b)))
      (assert-0 '(a b c))
      (assert-1 '(d e f)))
  (test
   (list assert-1 assert-0 rule-1 rule-0)
   (let ((db (make-database)))
     ((db 'add-rule-or-assertion!) rule-0)
     ((db 'add-rule-or-assertion!) assert-0)
     ((db 'add-rule-or-assertion!) rule-1)
     ((db 'add-rule-or-assertion!) assert-1)
     (append (stream->list (db 'get-all-assertions))
             (stream->list (db 'get-all-rules))))))
(test
 '(0 1)
 (let ((db (make-database)))
   (let* ((id-0 (db 'new-rule-application-id))
          (id-1 (db 'new-rule-application-id)))
     (list id-0 id-1))))

(define (get-indexed-rules pattern database)
  (stream-append
   (get-stream (database 'get-index)
               (index-key-of pattern)
               'rule-stream)
   (get-stream (database 'get-index)
               '?
               'rule-stream)))

(define (fetch-rules pattern database)
  (if (use-index? pattern)
      (get-indexed-rules pattern database)
      (database 'get-all-rules)))

(test
 '((rule (h) i)
   (rule ((? a) f (? b)) c) (rule ((? x) g (? y)) z))
 (let ((db (make-database)))
   ((db 'add-rule!) '(rule ((? x) g (? y)) z))
   ((db 'add-rule!) '(rule (((a b)) c) d))
   ((db 'add-rule!) '(rule ((? a) f (? b)) c))
   ((db 'add-rule!) '(rule (h) i))
   (stream->list (fetch-rules '(h) db))))

(define (fetch-assertions pattern database)
  (if (use-index? pattern)
      (get-stream (database 'get-index)
                  (index-key-of pattern)
                  'assertion-stream)
      (database 'get-all-assertions)))

(test
 '(((a d e f) (a b c))
   ((w x y z) ((d e) f) (a d e f) (a b c)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(a b c))
   ((db 'add-assertion!) '(a d e f))
   ((db 'add-assertion!) '((d e) f))
   ((db 'add-assertion!) '(w x y z))
   (list (stream->list (fetch-assertions '(a) db))
         (stream->list
          (fetch-assertions '((? x) y) db)))))

(define (depends-on? exp-arg var frame)
  (define (tree-walk exp)
    (cond ((var? exp)
           (or (equal? exp var)
               (let ((binding (binding-in-frame exp frame)))
                 (and binding
                      (tree-walk (binding-value binding))))))
          ((pair? exp)
           (or (tree-walk (car exp)) (tree-walk (cdr exp))))
          (else false)))
  (tree-walk exp-arg))

(test true (depends-on? '((? x)) '(? x) '()))
(test false (depends-on? '(? y) '(? x) '()))
(test false (depends-on? '((? y) ((? z))) '(? x) '()))
(test true
      (depends-on? '(? y) '(? x) '(((? y) . (? x)))))
(test true
      (depends-on? '(a b c (? y)) '(? x)
                   '(((? y) . (f g (h (? x)))))))

(define (extend-if-possible var val frame)
  (let ((binding (binding-in-frame var frame)))
    (cond (binding
           (unify-match
            (binding-value binding) val frame))
          ((var? val)
           (let ((binding (binding-in-frame val frame)))
             (if binding
                 (unify-match
                  var (binding-value binding) frame)
                 (extend var val frame))))
          ((depends-on? val var frame)
           'failed)
          (else (extend var val frame)))))

(define (unify-match p1 p2 frame)
  (cond ((eq? frame 'failed) 'failed)
        ((equal? p1 p2) frame)
        ((var? p1)
         (extend-if-possible p1 p2 frame))
        ((var? p2)
         (extend-if-possible p2 p1 frame))
        ((and (pair? p1) (pair? p2))
         (unify-match (cdr p1)
                      (cdr p2)
                      (unify-match (car p1)
                                   (car p2)
                                   frame)))
        (else 'failed)))

(test
 '(((? x) . 0))
 (extend-if-possible '(? x) 0 '()))
(test
 'failed
 (extend-if-possible '(? y) 1 '(((? y) . 0))))
(test
 '(((? y) . b) ((? x) . (f (? y))))
 (extend-if-possible '(? x) '(f b)
                     '(((? x) . (f (? y))))))
(test
 'failed
 (extend-if-possible '(? x) '(? y)
                     '(((? y) . (z (? x))))))
(test
 '(((? x) . (? x)))
 (extend-if-possible '(? x) '(? x) '()))
(test
 '(((? y) . (? x)))
 (extend-if-possible '(? x) '(? y) '(((? y) . (? x)))))
(test
 'failed
 (extend-if-possible '(? x) '(? y)
                     '(((? y) . (a (? x))))))

(test
 '(((? x) . a))
 (unify-match '((? x)) '(a) '()))
(test
 'failed
 (unify-match '(? x) 0 'failed))
(test
 '(((? x) . (? y)))
 (unify-match '(? x) '(? y) '()))
(test
 '(((? x) . a))
 (unify-match '((? x) a) '(a (? x)) '()))
(test
 '(((? y) . a) ((? x) . a))
 (unify-match '((? x) (? y)) '(a (? x)) '()))
(test
 '(((? x) . a))
 (unify-match '(? x) 'a '(((? x) . a))))
(test
 '(((? y) . a) ((? x) . a))
 (unify-match '(? x) '(? y) '(((? x) . a))))
(test
 'failed
 (unify-match 'b '(? x) '(((? x) . a))))
(test
 'failed
 (unify-match '((? x) (? x)) '((? y) (a (? y))) '()))
(test
 '(((? x) . (? y)))
 (unify-match '((? x) (? x)) '((? y) (? y)) '()))
(test
 '(((? y) . a) ((? z) . a) ((? x) . (? y)))
 (unify-match '((? x) a (? y)) '((? y) (? z) a) '()))
(test
 'failed
 (unify-match '((? x) (? y) a) '((? x) b (? y)) '()))
(test
 '(((? z) . c) ((? y) . b) ((? x) a (? y) c))
 (unify-match '((? x) (? x))
              '((a (? y) c) (a b (? z)))
              '()))

(define (make-new-variable var id)
  (cons '? (cons id (cdr var))))
(test '(? 0 xyz) (make-new-variable '(? xyz) 0))

(define (rename-variables exp id)
  (cond ((var? exp)
         (make-new-variable exp id))
        ((pair? exp)
         (cons (rename-variables (car exp) id)
               (rename-variables (cdr exp) id)))
        (else exp)))
(test
 '(rule (a (? 0 x) (? 0 y)) ((? 0 x) b (? 0 y)))
 (rename-variables
  '(rule (a (? x) (? y)) ((? x) b (? y)))
  0))

(define (instantiate exp frame unbound-var-handler)
  (define (copy exp)
    (cond ((var? exp)
           (let ((binding (binding-in-frame exp frame)))
             (if binding
                 (copy (binding-value binding))
                 (unbound-var-handler exp frame))))
          ((pair? exp)
           (cons (copy (car exp))
                 (copy (cdr exp))))
          (else exp)))
  (copy exp))

(test
 '()
 (instantiate '() '() '()))
(test
 '0
 (instantiate '(? x) '(((? x) . 0)) '()))
(test
 '((3 a) (3 b) 3)
 (instantiate
  '(((? x) a) ((? y) b) (? x))
  '(((? x) . (? y)) ((? y) . 3)) '()))
(let ((frame (extend '(? y) 3 '())))
  (test
   (list '(? x) frame)
   (instantiate '(? x) frame
                (lambda (var frame)
                  (list var frame)))))

(define (extend-if-consistent var dat frame)
  (let ((binding (binding-in-frame var frame)))
    (if binding
        (pattern-match (binding-value binding) dat frame)
        (extend var dat frame))))

(define (pattern-match pattern data frame)
  (cond ((eq? frame 'failed) 'failed)
        ((equal? pattern data) frame)
        ((var? pattern)
         (extend-if-consistent pattern data frame))
        ((and (pair? pattern) (pair? data))
         (pattern-match (cdr pattern)
                        (cdr data)
                        (pattern-match (car pattern)
                                       (car data)
                                       frame)))
        (else 'failed)))

(test
 '(((? x) . 0))
 (extend-if-consistent '(? x) 0 '()))
(test
 'failed
 (extend-if-consistent '(? y) 1 '(((? y) . 0))))
(test
 '(((? y) . b) ((? x) . (f (? y))))
 (extend-if-consistent '(? x) '(f b)
                       '(((? x) . (f (? y))))))

(test
 '(((? x) . a))
 (pattern-match '((? x)) '(a) '()))
(test
 'failed
 (pattern-match '(?x) 0 'failed))

(define (check-an-assertion assertion query-pat query-frame)
  (let ((match-result
         (pattern-match query-pat assertion query-frame)))
    (if (eq? match-result 'failed)
        the-empty-stream
        (singleton-stream match-result))))

(define (find-assertions pattern frame database)
  (stream-flatmap
   (lambda (datum)
     (check-an-assertion datum pattern frame))
   (fetch-assertions pattern database)))

(test
 '((((? y) . 2) ((? x) . 0)) (((? y) . 4) ((? x) . 2)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(+ 0 1 1))
   ((db 'add-assertion!) '(+ 2 2 4))
   ((db 'add-assertion!) '(+ 2 0 2))
   (stream->list
    (find-assertions '(+ 2 (? x) (? y)) '() db))))

(define (simple-query query-pattern frame-stream database)
  (stream-flatmap
   (lambda (frame)
     (stream-append-delayed
      (find-assertions query-pattern frame database)
      (delay (apply-rules query-pattern frame database))))
   frame-stream))

(define (qeval query frame-stream database)
  (let ((qproc (get (type query) 'qeval)))
    (if qproc
        (qproc (contents query) frame-stream database)
        (simple-query query frame-stream database))))

(define (apply-rules pattern frame database)
  (stream-flatmap
   (lambda (rule)
     (apply-a-rule rule pattern frame database))
   (fetch-rules pattern database)))

(define (apply-a-rule rule query-pattern query-frame db)
  (let ((clean-rule (rename-variables
                     rule (db 'new-rule-application-id))))
    (let ((unify-result
           (unify-match query-pattern
                        (conclusion clean-rule)
                        query-frame)))
      (if (eq? unify-result 'failed)
          the-empty-stream
          (qeval (rule-body clean-rule)
                 (singleton-stream unify-result)
                 db)))))

(test
 '()
 (stream->list
  (simple-query '(a b c) '(()) (make-database))))
(test
 '((((? x) . 2)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(inc 0 1))
   ((db 'add-assertion!) '(inc 1 2))
   ((db 'add-assertion!) '(inc 2 3))
   (stream->list
    (simple-query '(inc 1 (? x)) '(()) db))))
(test
 '(((((? 0 z) . p) ((? 0 y) . q))) ())
 (let ((db (make-database)))
   ((db 'add-assertion!) '(inc 0 1))
   ((db 'add-rule!) '(rule (r (? y) (? z)) (a (? y))))
   ((db 'add-assertion!) '(a q))
   (list (stream->list
          (simple-query '(r q p) '(()) db))
         (stream->list
          (simple-query '(r s s) '(()) db)))))

(define (map-over-symbols proc exp)
  (cond ((symbol? exp) (proc exp))
        ((pair? exp) (cons (map-over-symbols proc (car exp))
                           (map-over-symbols proc (cdr exp))))
        (else exp)))

(define (expand-question-mark symbol)
  (let ((chars (symbol->string symbol)))
    (if (string=? (substring chars 0 1) "?")
        (list '? (string->symbol
                  (substring chars 1 (string-length chars))))
        symbol)))

(define (query-syntax-process exp)
  (map-over-symbols expand-question-mark exp))

(test
 '((? x) (((? w)) (? y)) z)
 (query-syntax-process '(?x ((?w) ?y) z)))

(define (database-query query db)
  (let ((query (query-syntax-process query)))
    (stream-map
     (lambda (frame)
       (instantiate query frame
                    (lambda (var frame)
                      (contract-question-mark var))))
     (qeval query (singleton-stream '()) db))))

(define (conjoin exps frame-stream database)
  (if (null? exps)
      frame-stream
      (conjoin (cdr exps)
               (qeval (car exps) frame-stream database)
               database)))

(put 'and 'qeval conjoin)

(test
 '((and (even 2) (prime 2)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(prime 2))
   ((db 'add-assertion!) '(prime 3))
   ((db 'add-assertion!) '(prime 5))
   ((db 'add-assertion!) '(even 2))
   (stream->list
    (database-query '(and (even ?x) (prime ?x)) db))))
(test
 '((/6 6) (/6 0))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(/3 0))
   ((db 'add-assertion!) '(/3 3))
   ((db 'add-assertion!) '(/3 6))
   ((db 'add-assertion!) '(/2 0))
   ((db 'add-assertion!) '(/2 2))
   ((db 'add-assertion!) '(/2 4))
   ((db 'add-assertion!) '(/2 6))
   ((db 'add-rule!)
    '(rule (/6 (? x))
           (and (/3 (? x))
                (and (/2 (? x)) (/2 (? x)))
                (/3 0))))
   (stream->list (database-query '(/6 ?x) db))))
(test
 '((/6 6) (/6 0))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(/3 0))
   ((db 'add-assertion!) '(/3 3))
   ((db 'add-assertion!) '(/3 6))
   ((db 'add-assertion!) '(/2 0))
   ((db 'add-assertion!) '(/2 2))
   ((db 'add-assertion!) '(/2 4))
   ((db 'add-assertion!) '(/2 6))
   ((db 'add-rule!)
    '(rule (/6 (? x))
           (and (/3 (? x))
                (and (/2 (? x)) (/2 (? x)))
                (/3 0))))
   (stream->list (database-query '(/6 ?x) db))))

(define (disjoin disjuncts frame-stream database)
  (if (null? disjuncts)
      the-empty-stream
      (interleave-delayed
       (qeval (car disjuncts)
              frame-stream
              database)
       (delay (disjoin (cdr disjuncts)
                       frame-stream
                       database)))))

(put 'or 'qeval disjoin)

(put 'always-true 'qeval
     (lambda (exps frame-stream database)
       frame-stream))

(test
 '((always-true))
 (stream->list
  (database-query '(always-true) (make-database))))

(test
 '(())
 (let ((db (make-database)))
   ((db 'add-assertion!) '(even 0))
   (stream->list (disjoin '((even 0)) '(()) db))))
(test
 '()
 (let ((db (make-database)))
   ((db 'add-assertion!) '(even 0))
   (stream->list (disjoin '((even 1)) '(()) db))))
(test
 '((((? x) . 2)) (((? y) . 3))
   (((? x) . 0)) (((? y) . 1)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(even 0))
   ((db 'add-assertion!) '(odd 1))
   ((db 'add-assertion!) '(even 2))
   ((db 'add-assertion!) '(odd 3))
   (stream->list
    (disjoin '((even (? x)) (odd (? y)))
             '(()) db))))

(test
 '((same a a))
 (let ((db (make-database)))
   ((db 'add-rule!) '(rule (same (? x) (? x))))
   (stream->list (database-query '(same a a) db))))

(test
 '((plus 2 2 4))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(inc 0 1))
   ((db 'add-assertion!) '(inc 1 2))
   ((db 'add-assertion!) '(inc 2 3))
   ((db 'add-assertion!) '(inc 3 4))
   ((db 'add-assertion!) '(inc 4 5))
   ((db 'add-rule!) '(rule (same (? x) (? x))))
   ((db 'add-rule!)
    '(rule (plus (? a) (? b) (? c))
           (or (and (same (? a) 0)
                    (same (? b) (? c)))
               (and (inc (? d) (? a))
                    (inc (? e) (? c))
                    (plus (? d) (? b) (? e))))))
   (stream->list (database-query '(plus 2 2 ?x) db))))

(define (execute call)
  (apply (eval (car call) (scheme-report-environment 5))
         (cdr call)))

(define (lisp-value call frame-stream database)
  (stream-flatmap
   (lambda (frame)
     (if (execute
          (instantiate
           call frame
           (lambda (v f)
             (error "unbound variable -- lisp-value" v))))
         (singleton-stream frame)
         the-empty-stream))
   frame-stream))

(put 'lisp-value 'qeval lisp-value)

(test
 '(())
 (stream->list
  (lisp-value '(< 3 4) '(()) (make-database))))
(test
 '()
 (lisp-value '(symbol? 0) '(()) (make-database)))
(test
 '((((? x) . 0) ((? y) . 1)))
 (stream->list
  (lisp-value '(> (? y) (? x)) '((((? x) . 0) ((? y) . 1)))
              (make-database))))

(define (negate exps frame-stream database)
  (stream-flatmap
   (lambda (frame)
     (if (stream-null? (qeval (car exps)
                              (singleton-stream frame)
                              database))
         (singleton-stream frame)
         the-empty-stream))
   frame-stream))

(put 'not 'qeval negate)

(test
 '((and (a 0) (not (b ?y))))
 (let ((db (make-database)))
   ((db 'add-assertion!)
    '(a 0))
   (stream->list
    (database-query
     '(and (a ?x)
           (not (b ?y)))
     db))))

(test
 '((((? x) . 1)))
 (let ((db (make-database)))
   ((db 'add-assertion!) '(even 0))
   ((db 'add-assertion!) '(even 2))
   ((db 'add-assertion!) '(even 4))
   (stream->list
    (negate
     '((even (? x)))
     '((((? x) . 0)) (((? x) . 1)) (((? x) . 2)))
     db))))

(define (database-add database statements)
  (for-each (lambda (statement)
              ((database 'add-rule-or-assertion!)
               (query-syntax-process statement)))
            statements))

(test
 '((inc-inc 0 2))
 (let ((db (make-database)))
   (database-add db '((inc 0 1)
                      (inc 1 2)
                      (rule (inc-inc ?a ?b)
                            (and (inc ?a ?c)
                                 (inc ?c ?b)))))
   (stream->list (database-query '(inc-inc ?x ?y) db))))

(define microshaft-data-base
  '((address (bitdiddle ben) (slumerville (ridge road) 10))
    (job (bitdiddle ben) (computer wizard))
    (salary (bitdiddle ben) 60000)

    (address (hacker alyssa p) (cambridge (mass ave) 78))
    (job (hacker alyssa p) (computer programmer))
    (salary (hacker alyssa p) 40000)
    (supervisor (hacker alyssa p) (bitdiddle ben))

    (address (fect cy d) (cambridge (ames street) 3))
    (job (fect cy d) (computer programmer))
    (salary (fect cy d) 35000)
    (supervisor (fect cy d) (bitdiddle ben))

    (address (tweakit lem e) (boston (bay state road) 22))
    (job (tweakit lem e) (computer technician))
    (salary (tweakit lem e) 25000)
    (supervisor (tweakit lem e) (bitdiddle ben))

    (address (reasoner louis) (slumerville (pine tree road) 80))
    (job (reasoner louis) (computer programmer trainee))
    (salary (reasoner louis) 30000)
    (supervisor (reasoner louis) (hacker alyssa p))

    (supervisor (bitdiddle ben) (warbucks oliver))

    (address (warbucks oliver) (swellesley (top heap road)))
    (job (warbucks oliver) (administration big wheel))
    (salary (warbucks oliver) 150000)

    (address (scrooge eben) (weston (shady lane) 10))
    (job (scrooge eben) (accounting chief accountant))
    (salary (scrooge eben) 75000)
    (supervisor (scrooge eben) (warbucks oliver))

    (address (cratchet robert) (allston (n harvard street) 16))
    (job (cratchet robert) (accounting scrivener))
    (salary (cratchet robert) 18000)
    (supervisor (cratchet robert) (scrooge eben))

    (address (aull dewitt) (slumerville (onion square) 5))
    (job (aull dewitt) (administration secretary))
    (salary (aull dewitt) 25000)
    (supervisor (aull dewitt) (warbucks oliver))

    (can-do-job (computer wizard) (computer programmer))
    (can-do-job (computer wizard) (computer technician))

    (can-do-job (computer programmer)
                (computer programmer trainee))

    (can-do-job (administration secretary)
                (administration big wheel))

    (rule (lives-near ?person-1 ?person-2)
          (and (address ?person-1 (?town . ?rest-1))
               (address ?person-2 (?town . ?rest-2))
               (not (same ?person-1 ?person-2))))

    (rule (same ?x ?x))

    (rule (wheel ?person)
          (and (supervisor ?middle-manager ?person)
               (supervisor ?x ?middle-manager)))

    (rule (outranked-by ?staff-person ?boss)
          (or (supervisor ?staff-person ?boss)
              (and (supervisor ?staff-person ?middle-manager)
                   (outranked-by ?middle-manager ?boss))))))

(define (do-queries statements queries)
  (let ((db (make-database)))
    (database-add db statements)
    (for-each
     (lambda (query)
       (newline)
       (display ";;; query input:")
       (newline)
       (display query)
       (newline)
       (newline)
       (display ";;; query results:")
       (newline)
       (let ((answer
              (stream->list (database-query query db))))
         (if (pair? answer)
             (for-each (lambda (query-result)
                         (display query-result)
                         (newline))
                       answer)
             (begin (display answer)
                    (newline)))))
     queries)))

(test-end)

(set! log? #t)

(let ((db (make-database)))
  (database-add
   db
   '((a () ())
     (rule (a (?x) ?y) (a ?x ?y))
     (rule (a () (?y)) (a () ?y))))
  ;; in this example, if stream-flatmap appended streams, the returned
  ;; stream would not iterate through all possible answers, but only
  ;; those in which ?x is ().  interleaving ensures that any answer
  ;; can be eventually obtained.
  (display-list
   (stream-get-items 10 (database-query '(a ?x ?y) db))))
