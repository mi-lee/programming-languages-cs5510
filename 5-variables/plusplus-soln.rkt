#lang plai-typed
(require plai-typed/s-exp-match)

;; Start with "variable.rkt"

;; Add a `{++ <id>}` form (not as sugar) that increments a variable's
;; value (if it has a number value) and returns
;; the incremented value

(define-type-alias Location number)

(define-type Value
  [numV (n : number)]
  [closV (arg : symbol)
         (body : ExprC)
         (env : Env)])

(define-type ExprC
  [numC (n : number)]
  [idC (s : symbol)]
  [plusC (l : ExprC) 
         (r : ExprC)]
  [multC (l : ExprC)
         (r : ExprC)]
  [letC (n : symbol) 
        (rhs : ExprC)
        (body : ExprC)]
  [lamC (n : symbol)
        (body : ExprC)]
  [appC (fun : ExprC)
        (arg : ExprC)]
  [setC (var : symbol)
        (val : ExprC)]
  [beginC (l : ExprC)
          (r : ExprC)]
  [++C (id : symbol)])

(define-type Binding
  [bind (name : symbol)
        (location : Location)])

(define-type-alias Env (listof Binding))

(define mt-env empty)
(define extend-env cons)

(define-type Storage
  [cell (location : Location) 
        (val : Value)])

(define-type-alias Store (listof Storage))
(define mt-store empty)
(define override-store cons)

(define-type Result
  [v*s (v : Value) (s : Store)])

(module+ test
  (print-only-errors true))

;; parse ----------------------------------------
(define (parse [s : s-expression]) : ExprC
  (cond
    [(s-exp-match? `NUMBER s) (numC (s-exp->number s))]
    [(s-exp-match? `SYMBOL s) (idC (s-exp->symbol s))]
    [(s-exp-match? '{+ ANY ANY} s)
     (plusC (parse (second (s-exp->list s)))
            (parse (third (s-exp->list s))))]
    [(s-exp-match? '{* ANY ANY} s)
     (multC (parse (second (s-exp->list s)))
            (parse (third (s-exp->list s))))]
    [(s-exp-match? '{let {[SYMBOL ANY]} ANY} s)
     (let ([bs (s-exp->list (first
                             (s-exp->list (second
                                           (s-exp->list s)))))])
       (letC (s-exp->symbol (first bs))
             (parse (second bs))
             (parse (third (s-exp->list s)))))]
    [(s-exp-match? '{lambda {SYMBOL} ANY} s)
     (lamC (s-exp->symbol (first (s-exp->list 
                                  (second (s-exp->list s)))))
           (parse (third (s-exp->list s))))]
    [(s-exp-match? '{set! SYMBOL ANY} s)
     (setC (s-exp->symbol (second (s-exp->list s)))
           (parse (third (s-exp->list s))))]
    [(s-exp-match? '{begin ANY ANY} s)
     (beginC (parse (second (s-exp->list s)))
             (parse (third (s-exp->list s))))]
    [(s-exp-match? '{++ SYMBOL} s)
     (++C (s-exp->symbol (second (s-exp->list s))))]
    [(s-exp-match? '{ANY ANY} s)
     (appC (parse (first (s-exp->list s)))
           (parse (second (s-exp->list s))))]
    [else (error 'parse "invalid input")]))

(module+ test
  (test (parse '2)
        (numC 2))
  (test (parse `x) ; note: backquote instead of normal quote
        (idC 'x))
  (test (parse '{+ 2 1})
        (plusC (numC 2) (numC 1)))
  (test (parse '{* 3 4})
        (multC (numC 3) (numC 4)))
  (test (parse '{+ {* 3 4} 8})
        (plusC (multC (numC 3) (numC 4))
               (numC 8)))
  (test (parse '{let {[x {+ 1 2}]}
                  y})
        (letC 'x (plusC (numC 1) (numC 2))
              (idC 'y)))
  (test (parse '{lambda {x} 9})
        (lamC 'x (numC 9)))
  (test (parse '{double 9})
        (appC (idC 'double) (numC 9)))
  (test (parse '{set! b 0})
        (setC 'b (numC 0)))
  (test (parse '{begin 1 2})
        (beginC (numC 1) (numC 2)))
  (test/exn (parse '{{+ 1 2}})
            "invalid input"))

;; with form ----------------------------------------
(define-syntax-rule
  (with [(v-id sto-id) call]
    body)
  (type-case Result call
    [v*s (v-id sto-id) body]))
                                
;; interp ----------------------------------------
(define (interp [a : ExprC] [env : Env] [sto : Store]) : Result
  (type-case ExprC a
    [numC (n) (v*s (numV n) sto)]
    [idC (s) (v*s (fetch (lookup s env) sto)
                  sto)]
    [plusC (l r)
           (with [(v-l sto-l) (interp l env sto)]
             (with [(v-r sto-r) (interp r env sto-l)]
               (v*s (num+ v-l v-r) sto-r)))]
    [multC (l r)
           (with [(v-l sto-l) (interp l env sto)]
             (with [(v-r sto-r) (interp r env sto-l)]
               (v*s (num* v-l v-r) sto-r)))]
    [letC (n rhs body)
          (with [(v-rhs sto-rhs) (interp rhs env sto)]
            (let ([l (new-loc sto-rhs)])
              (interp body
                      (extend-env (bind n l)
                                  env)
                      (override-store (cell l v-rhs)
                                      sto-rhs))))]
    [lamC (n body)
          (v*s (closV n body env) sto)]
    [appC (fun arg)
          (with [(v-f sto-f) (interp fun env sto)]
            (with [(v-a sto-a) (interp arg env sto-f)]
              (type-case Value v-f
                [closV (n body c-env)
                       (let ([l (new-loc sto-a)])
                         (interp body
                                 (extend-env (bind n l)
                                             c-env)
                                 (override-store (cell l v-a)
                                                 sto-a)))]
                [else (error 'interp "not a function")])))]
    [setC (var val)
          (let ([l (lookup var env)])
            (with [(v-v sto-v) (interp val env sto)]
              (v*s v-v
                   (override-store (cell l v-v)
                                   sto-v))))]
    [beginC (l r)
            (with [(v-l sto-l) (interp l env sto)]
              (interp r env sto-l))]
    [++C (id)
         (let ([l (lookup id env)])
           (type-case Value (fetch l sto)
             [numV (n)
                   (let ([newVal (numV (+ n 1))])
                     (v*s newVal
                          (override-store (cell l newVal) sto)))]
             [else (error 'interp "not a number")]))]))

(module+ test
  (test (v*s-v (interp (parse '{let {[x 5]}
                                 {begin
                                   {++ x}
                                   x}})
                       mt-env
                       mt-store))
        (numV 6))
  
  (test (interp (parse '2) mt-env mt-store)
        (v*s (numV 2) 
             mt-store))
  (test/exn (interp (parse `x) mt-env mt-store)
            "free variable")
  (test (interp (parse `x) 
                (extend-env (bind 'x 1) mt-env)
                (override-store (cell 1 (numV 9))
                                mt-store))
        (v*s (numV 9)
             (override-store (cell 1 (numV 9))
                             mt-store)))
  (test (interp (parse '{+ 2 1}) mt-env mt-store)
        (v*s (numV 3)
             mt-store))
  (test (interp (parse '{* 2 1}) mt-env mt-store)
        (v*s (numV 2)
             mt-store))
  (test (interp (parse '{+ {* 2 3} {+ 5 8}})
                mt-env
                mt-store)
        (v*s (numV 19)
             mt-store))
  (test (interp (parse '{lambda {x} {+ x x}})
                mt-env
                mt-store)
        (v*s (closV 'x (plusC (idC 'x) (idC 'x)) mt-env)
             mt-store))
  (test (interp (parse '{let {[x 5]}
                          {+ x x}})
                mt-env
                mt-store)
        (v*s (numV 10)
             (override-store (cell 1 (numV 5))
                             mt-store)))
  (test (interp (parse '{let {[x 5]}
                          {let {[x {+ 1 x}]}
                            {+ x x}}})
                mt-env
                mt-store)
        (v*s (numV 12)
             (override-store (cell 2 (numV 6))
                             (override-store (cell 1 (numV 5))
                                             mt-store))))
  (test (interp (parse '{let {[x 5]}
                          {let {[y 6]}
                            x}})
                mt-env
                mt-store)
        (v*s (numV 5)
             (override-store (cell 2 (numV 6))
                             (override-store (cell 1 (numV 5))
                                             mt-store))))
  (test (interp (parse '{{lambda {x} {+ x x}} 8})
                mt-env
                mt-store)
        (v*s (numV 16)
             (override-store (cell 1 (numV 8))
                             mt-store)))
  (test (interp (parse '{begin 1 2})
                mt-env
                mt-store)
        (v*s (numV 2)
             mt-store))
  (test (interp (parse '{let {[x 5]}
                          {begin
                            {set! x 6}
                            x}})
                mt-env
                mt-store)
        (v*s (numV 6)
             (override-store (cell 1 (numV 6))
                             (override-store (cell 1 (numV 5))
                                             mt-store))))

  (test/exn (interp (parse '{1 2}) mt-env mt-store)
            "not a function")
  (test/exn (interp (parse '{+ 1 {lambda {x} x}}) mt-env mt-store)
            "not a number")
  (test/exn (interp (parse '{let {[bad {lambda {x} {+ x y}}]}
                              {let {[y 5]}
                                {bad 2}}})
                    mt-env
                    mt-store)
            "free variable"))

;; num+ and num* ----------------------------------------
(define (num-op [op : (number number -> number)] [l : Value] [r : Value]) : Value
  (cond
   [(and (numV? l) (numV? r))
    (numV (op (numV-n l) (numV-n r)))]
   [else
    (error 'interp "not a number")]))
(define (num+ [l : Value] [r : Value]) : Value
  (num-op + l r))
(define (num* [l : Value] [r : Value]) : Value
  (num-op * l r))

(module+ test
  (test (num+ (numV 1) (numV 2))
        (numV 3))
  (test (num* (numV 2) (numV 3))
        (numV 6)))

;; lookup ----------------------------------------
(define (lookup [n : symbol] [env : Env]) : Location
  (cond
   [(empty? env) (error 'lookup "free variable")]
   [else (cond
          [(symbol=? n (bind-name (first env)))
           (bind-location (first env))]
          [else (lookup n (rest env))])]))

(module+ test
  (test/exn (lookup 'x mt-env)
            "free variable")
  (test (lookup 'x (extend-env (bind 'x 8) mt-env))
        8)
  (test (lookup 'x (extend-env
                    (bind 'x 9)
                    (extend-env (bind 'x 8) mt-env)))
        9)
  (test (lookup 'y (extend-env
                    (bind 'x 9)
                    (extend-env (bind 'y 8) mt-env)))
        8))
  
;; store operations ----------------------------------------

(define (new-loc [sto : Store]) : Location
  (+ 1 (max-address sto)))

(define (max-address [sto : Store]) : Location
  (cond
   [(empty? sto) 0]
   [else (max (cell-location (first sto))
              (max-address (rest sto)))]))

(define (fetch [l : Location] [sto : Store]) : Value
  (cond
   [(empty? sto) (error 'interp "unallocated location")]
   [else (if (equal? l (cell-location (first sto)))
             (cell-val (first sto))
             (fetch l (rest sto)))]))

(module+ test
  (test (max-address mt-store)
        0)
  (test (max-address (override-store (cell 2 (numV 9))
                                     mt-store))
        2)
  
  (test (fetch 2 (override-store (cell 2 (numV 9))
                                 mt-store))
        (numV 9))
  (test (fetch 2 (override-store (cell 2 (numV 10))
                                 (override-store (cell 2 (numV 9))
                                                 mt-store)))
        (numV 10))
  (test (fetch 3 (override-store (cell 2 (numV 10))
                                 (override-store (cell 3 (numV 9))
                                                 mt-store)))
        (numV 9))
  (test/exn (fetch 2 mt-store)
            "unallocated location"))

