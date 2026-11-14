;; CAD_POINTS_TO_PROKON.lsp
;; Command: CAD2PROKON
;; Select AutoCAD POINT/CIRCLE entities, choose a rebar diameter and export
;; origin, then copy PROKON General Column point rows to the Windows clipboard.

(vl-load-com)

(defun cp2p:fmt (v / s)
  (if (< (abs v) 0.0000001)
    "0"
    (progn
      (setq s (rtos v 2 4))
      ;; Only trim zeroes from a decimal fraction.  Trimming an integer
      ;; directly would corrupt values such as 400, 690 and 1540.
      (if (vl-string-search "." s)
        (setq s (vl-string-right-trim "." (vl-string-right-trim "0" s))))
      s)))

(defun cp2p:get-point (e / d typ)
  (setq d (entget e) typ (cdr (assoc 0 d)))
  (cond
    ((= typ "POINT") (cdr (assoc 10 d)))
    ((= typ "CIRCLE") (trans (cdr (assoc 10 d)) e 0))
    (T nil)))

(defun cp2p:copy-file (fn / sh cmd result)
  (setq sh (vlax-create-object "WScript.Shell"))
  (setq cmd (strcat "cmd.exe /c type \"" fn "\" | clip.exe"))
  (setq result (vlax-invoke-method sh 'Run cmd 0 :vlax-true))
  (vlax-release-object sh)
  (= result 0))

(defun c:CAD2PROKON (/ *error* olderr dia ss i p pts origin fn f tab count)
  (setq olderr *error*)
  (defun *error* (msg)
    (if f (close f))
    (if (and fn (findfile fn)) (vl-file-delete fn))
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg)))
    (princ))

  (initget 6)
  (setq dia (getreal "\nRebar diameter in mm <32>: "))
  (if (null dia) (setq dia 32.0))
  (prompt "\nSelect reinforcement POINT or CIRCLE entities: ")
  (setq ss (ssget '((0 . "POINT,CIRCLE"))))
  (if ss
    (progn
      (setq pts '() i 0)
      (repeat (sslength ss)
        (setq p (cp2p:get-point (ssname ss i)))
        (if p (setq pts (cons p pts)))
        (setq i (+ i 1)))
      (setq origin (getpoint "\nPick the point to use as PROKON 0,0 <Keep CAD WCS 0,0>: ")
            origin (if origin (trans origin 1 0) '(0.0 0.0 0.0)))
      (setq pts (reverse pts)
            tab (chr 9)
            fn (strcat (getvar "TEMPPREFIX") "CAD2PROKON_points.txt")
            f (open fn "w")
            count 0)
      (if f
        (progn
          (foreach p pts
            (write-line (strcat "+" tab (cp2p:fmt (- (car p) (car origin)))
                               tab (cp2p:fmt (- (cadr p) (cadr origin)))) f)
            (write-line (strcat "b" tab (cp2p:fmt dia) tab "") f)
            (setq count (+ count 1)))
          (close f)
          (setq f nil)
          (if (cp2p:copy-file fn)
            (prompt (strcat "\nCopied " (itoa count) " reinforcement points to clipboard. In PROKON, click the first Code cell and press Ctrl+V."))
            (prompt "\nCould not copy data to the Windows clipboard."))
          (if (findfile fn) (vl-file-delete fn)))
        (prompt "\nCould not create the temporary transfer file.")))
    (prompt "\nNo POINT or CIRCLE entities selected."))
  (setq *error* olderr)
  (princ))

(princ "\nCAD_POINTS_TO_PROKON loaded. Type CAD2PROKON.")
(princ)
