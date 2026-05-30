(define-library (test strings)
  (export string-join string-repeat)
  (import (scheme base))
  (begin
    (define (string-join strs sep)
      (if (null? strs)
          ""
          (let loop ((rest (cdr strs)) (acc (car strs)))
            (if (null? rest)
                acc
                (loop (cdr rest) (string-append acc sep (car rest)))))))
    (define (string-repeat s n)
      (let loop ((i 0) (acc ""))
        (if (= i n)
            acc
            (loop (+ i 1) (string-append acc s)))))))
