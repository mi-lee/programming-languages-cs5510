#lang plai-typed
(require plai-typed/s-exp-match)

(define-type ExprC
  [numC (n : number)]
  [idC (s : symbol)]
  [plusC (l : ExprC) 
         (r : ExprC)]
  [multC (l : ExprC)
         (r : ExprC)]
  [appC (s : symbol)
        (arg : ExprC)]
  [letC (n : symbol) 
        (rhs : ExprC)
        (body : ExprC)])

(define-type FunDefC
  [fdC (name : symbol) 
       (arg : symbol) 
       (body : ExprC)])

(define-type Binding
  [bind (name : symbol)
        (val : number)])

(define-type-alias Env (listof Binding))

(define mt-env empty)
(define extend-env cons)

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
    [(s-exp-match? '{SYMBOL ANY} s)
     (appC (s-exp->symbol (first (s-exp->list s)))
           (parse (second (s-exp->list s))))]
    [(s-exp-match? '{let {[SYMBOL ANY]} ANY} s)
     (let ([bs (s-exp->list (first
                             (s-exp->list (second
                                           (s-exp->list s)))))])
       (letC (s-exp->symbol (first bs))
             (parse (second bs))
             (parse (third (s-exp->list s)))))]
    [else (error 'parse "invalid input")]))

(define (parse-fundef [s : s-expression]) : FunDefC
  (cond
    [(s-exp-match? '{define {SYMBOL SYMBOL} ANY} s)
     (fdC (s-exp->symbol (first (s-exp->list (second (s-exp->list s)))))
          (s-exp->symbol (second (s-exp->list (second (s-exp->list s)))))
          (parse (third (s-exp->list s))))]
    [else (error 'parse-fundef "invalid input")]))

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
  (test (parse '{double 9})
        (appC 'double (numC 9)))
  (test (parse '{let {[x {+ 1 2}]}
                  y})
        (letC 'x (plusC (numC 1) (numC 2))
              (idC 'y)))
  (test/exn (parse '{{+ 1 2}})
            "invalid input")

  (test (parse-fundef '{define {double x} {+ x x}})
        (fdC 'double 'x (plusC (idC 'x) (idC 'x))))
  (test/exn (parse-fundef '{def {f x} x})
            "invalid input")

  (define double-def
    (parse-fundef '{define {double x} {+ x x}}))
  (define quadruple-def
    (parse-fundef '{define {quadruple x} {double {double x}}})))

;; interp ----------------------------------------
(define (interp [a : ExprC] [env : Env] [fds : (listof FunDefC)]) : number
  (type-case ExprC a
    [numC (n) n]
    [idC (s) (lookup s env)]
    [plusC (l r) (+ (interp l env fds) (interp r env fds))]
    [multC (l r) (* (interp l env fds) (interp r env fds))]
    [appC (s arg) (local [(define fd (get-fundef s fds))]
                    (interp (fdC-body fd)
                            (extend-env
                             (bind (fdC-arg fd)
                                   (interp arg env fds))
                             mt-env)
                            fds))]
    [letC (n rhs body)
          (interp body
                  (extend-env 
                   (bind n (interp rhs env fds))
                   env)
                  fds)]))

(module+ test
  (test (interp (parse '2) mt-env empty)
        2)
  (test/exn (interp (parse `x) mt-env empty)
            "free variable")
  (test (interp (parse `x) 
                (extend-env (bind 'x 9) mt-env)
                empty)
        9)
  (test (interp (parse '{+ 2 1}) mt-env empty)
        3)
  (test (interp (parse '{* 2 1}) mt-env empty)
        2)
  (test (interp (parse '{+ {* 2 3} {+ 5 8}})
                mt-env
                empty)
        19)
  (test (interp (parse '{double 8})
                mt-env
                (list double-def))
        16)
  (test (interp (parse '{quadruple 8})
                mt-env
                (list double-def quadruple-def))
        32)
  (test (interp (parse '{let {[x 5]}
                          {+ x x}})
                mt-env
                empty)
        10)
  (test (interp (parse '{let {[x 5]}
                          {let {[x {+ 1 x}]}
                            {+ x x}}})
                mt-env
                empty)
        12)
  (test (interp (parse '{let {[x 5]}
                          {let {[y 6]}
                            x}})
                mt-env
                empty)
        5)
  (test/exn (interp (parse '{let {[y 5]}
                              {bad 2}})
                    mt-env
                    (list (parse-fundef '{define {bad x} {+ x y}})))
            "free variable"))

;; get-fundef ----------------------------------------
(define (get-fundef [s : symbol] [fds : (listof FunDefC)]) : FunDefC
  (cond
    [(empty? fds) (error 'get-fundef "undefined function")]
    [(cons? fds) (if (eq? s (fdC-name (first fds)))
                     (first fds)
                     (get-fundef s (rest fds)))]))

(module+ test
  (test (get-fundef 'double (list double-def))
        double-def)
  (test (get-fundef 'double (list double-def quadruple-def))
        double-def)
  (test (get-fundef 'double (list quadruple-def double-def))
        double-def)
  (test (get-fundef 'quadruple (list quadruple-def double-def))
        quadruple-def)
  (test/exn (get-fundef 'double empty)
            "undefined function"))

;; lookup ----------------------------------------
(define (lookup [n : symbol] [env : Env]) : number
  (cond
   [(empty? env) (error 'lookup "free variable")]
   [else (cond
          [(symbol=? n (bind-name (first env)))
           (bind-val (first env))]
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
  
