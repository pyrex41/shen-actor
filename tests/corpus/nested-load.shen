\\ load resolves against *home-directory*, not the loading file, and echoes
\\ each form's value.  Nested loads see each other's definitions.
(load "load/middle.shen")
(output "~A~%" (value loaded-inner))
(output "~A~%" (middle-f x))
(define outer-f X -> (middle-f X))
(output "~A~%" (outer-f y))
