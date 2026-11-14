;; WALL_TO_PROKON.lsp
;; Commands:
;;   WALLBARPOINTS       Divide selected bar-centre curves into editable POINTs.
;;   WALLBARPOINTS2P     Legacy two-point straight-run divider.
;;   COVER2BARPOINTS     Offset covering curves and create points in one command.
;;   WALLSHAPE2PROKON    Copy straight closed-polyline shape increments to PROKON.

(vl-load-com)

(defun w2p:fmt (v / s)
  (if (< (abs v) 0.0000001)
    "0"
    (progn
      (setq s (rtos v 2 4))
      (if (vl-string-search "." s)
        (setq s (vl-string-right-trim "." (vl-string-right-trim "0" s))))
      s)))

(defun w2p:bar-offset (dia)
  (cond
    ((equal dia 10.0 0.0001) 5.0)
    ((equal dia 13.0 0.0001) 7.5)
    ((equal dia 16.0 0.0001) 8.0)
    ((equal dia 20.0 0.0001) 10.0)
    ((equal dia 25.0 0.0001) 12.5)
    ((equal dia 32.0 0.0001) 16.0)
    ((equal dia 40.0 0.0001) 20.0)
    (T (/ dia 2.0))))

(defun w2p:create-sided-offset (ent amount side / before after)
  ;; Use AutoCAD's native OFFSET command so its normal corner/arc handling
  ;; and the user's OFFSETGAPTYPE setting are respected in AutoCAD 2021.
  (setq before (entlast))
  (vl-cmdf "_.OFFSET" amount ent side "")
  (setq after (entlast))
  (if (and after (not (eq after before))) after nil))

(defun w2p:copy-lines (lines / fn f sh cmd result)
  (setq fn (strcat (getvar "TEMPPREFIX") "WALL2PROKON_clipboard.txt")
        f (open fn "w"))
  (if f
    (progn
      (foreach line lines (write-line line f))
      (close f)
      (setq sh (vlax-create-object "WScript.Shell")
            cmd (strcat "cmd.exe /c type \"" fn "\" | clip.exe")
            result (vlax-invoke-method sh 'Run cmd 0 :vlax-true))
      (vlax-release-object sh)
      (if (findfile fn) (vl-file-delete fn))
      (= result 0))
    nil))

(defun w2p:unique-add (p points tol / found)
  (setq found nil)
  (foreach old points
    (if (< (distance p old) tol) (setq found T)))
  (if found points (append points (list p))))

(defun w2p:space-count (len target / count)
  ;; Follow the drawing's floor rule. If a short run exceeds the target but
  ;; floor would leave no middle point, split it once at the middle.
  ;; Examples: 305/@200 -> 2 spaces; 305/@150 -> 2 spaces.
  (setq count (max 1 (fix (/ len target))))
  (if (and (> len (+ target 0.0000001)) (< count 2))
    (setq count 2))
  count)

(defun w2p:run-points (p1 p2 side offset target / dx dy len nx ny mid sign count actual i result)
  (setq dx (- (car p2) (car p1))
        dy (- (cadr p2) (cadr p1))
        len (sqrt (+ (* dx dx) (* dy dy))))
  (if (> len 0.0000001)
    (progn
      (setq nx (/ (- dy) len)
            ny (/ dx len)
            mid (list (/ (+ (car p1) (car p2)) 2.0)
                      (/ (+ (cadr p1) (cadr p2)) 2.0)
                      0.0)
            sign (if (>= (+ (* (- (car side) (car mid)) nx)
                             (* (- (cadr side) (cadr mid)) ny)) 0.0) 1.0 -1.0)
            count (w2p:space-count len target))
      (setq actual (/ len count)
            i 0
            result '())
      (repeat (1+ count)
        (setq result
          (append result
            (list
              (list (+ (car p1) (* (/ dx len) actual i) (* nx offset sign))
                    (+ (cadr p1) (* (/ dy len) actual i) (* ny offset sign))
                    0.0))))
        (setq i (1+ i)))
      (list result count actual))
    nil))

(defun c:WALLBARPOINTS2P (/ *error* olderr target p1 p2 run allpts p)
  (setq olderr *error*)
  (defun *error* (msg)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg)))
    (princ))

  (initget 6)
  (setq target (getdist "\nTarget spacing in mm <200>: "))
  (if (null target) (setq target 200.0))

  (setq allpts '())
  (while (setq p1 (getpoint "\nPick START point on the prepared bar-centre line <finish>: "))
    (setq p2 (getpoint p1 "\nPick END point on the prepared bar-centre line: "))
    (if p2
      (progn
        ;; The user prepares the final bar-centre line with OFFSET/TRIM/EXTEND.
        ;; Keep both picked endpoints exact and only divide the run.
        (setq run (w2p:run-points p1 p2 p1 0.0 target))
        (if run
          (progn
            (foreach p (car run)
              (setq allpts (w2p:unique-add p allpts 0.001))
              (entmakex (list '(0 . "POINT") (cons 10 (trans p 1 0)))))
            (prompt
              (strcat "\nCreated " (itoa (1+ (cadr run)))
                      " points; " (itoa (cadr run))
                      " spaces @ " (w2p:fmt (caddr run))
                      " mm; endpoints kept exactly where picked.")))
          (prompt "\nStart and end points must be different.")))))

  (if allpts
    (prompt
      (strcat "\nCreated " (itoa (length allpts))
              " unique POINT entities. Review them, then use CAD2PROKON to export."))
    (prompt "\nNo wall reinforcement points were created."))
  (setq *error* olderr)
  (princ))

(defun w2p:curve-run-points (ent d1 d2 target / len count actual i d p result)
  (setq len (- d2 d1))
  (if (> len 0.0000001)
    (progn
      (setq count (w2p:space-count len target))
      (setq actual (/ len count) i 0 result '())
      (repeat (1+ count)
        (setq d (if (= i count) d2 (+ d1 (* actual i)))
              p (vlax-curve-getPointAtDist ent d))
        (if p (setq result (append result (list p))))
        (setq i (1+ i)))
      (list result count actual))
    nil))

(defun w2p:curve-points (ent target / typ startParam endParam seg nextParam d1 d2 run result totalSpaces)
  (setq typ (cdr (assoc 0 (entget ent)))
        startParam (vlax-curve-getStartParam ent)
        endParam (vlax-curve-getEndParam ent)
        result '()
        totalSpaces 0)
  (if (or (= typ "LWPOLYLINE") (= typ "POLYLINE"))
    (progn
      (setq seg (fix startParam))
      (while (< seg (- endParam 0.0000001))
        (setq nextParam (min (1+ seg) endParam)
              d1 (vlax-curve-getDistAtParam ent seg)
              d2 (vlax-curve-getDistAtParam ent nextParam)
              run (w2p:curve-run-points ent d1 d2 target))
        (if run
          (progn
            (foreach p (car run) (setq result (w2p:unique-add p result 0.001)))
            (setq totalSpaces (+ totalSpaces (cadr run)))))
        (setq seg (1+ seg))))
    (progn
      (setq d1 (vlax-curve-getDistAtParam ent startParam)
            d2 (vlax-curve-getDistAtParam ent endParam)
            run (w2p:curve-run-points ent d1 d2 target))
      (if run
        (setq result (car run) totalSpaces (cadr run)))))
  (list result totalSpaces))

(defun w2p:orthogonal-segments (ent / verts closed i p1 p2 dx dy segments valid)
  (setq verts (w2p:poly-vertices-wcs ent)
        closed (append verts (list (car verts)))
        i 0 segments '() valid T)
  (while (and valid (< i (1- (length closed))))
    (setq p1 (nth i closed) p2 (nth (1+ i) closed)
          dx (- (car p2) (car p1)) dy (- (cadr p2) (cadr p1)))
    (cond
      ((< (abs dx) 0.001)
       (setq segments
         (append segments
           (list (list (cons 0 i) (cons 1 'V) (cons 2 (/ (+ (car p1) (car p2)) 2.0))
                       (cons 3 (min (cadr p1) (cadr p2))) (cons 4 (max (cadr p1) (cadr p2)))
                       (cons 10 p1) (cons 11 p2))))))
      ((< (abs dy) 0.001)
       (setq segments
         (append segments
           (list (list (cons 0 i) (cons 1 'H) (cons 2 (/ (+ (cadr p1) (cadr p2)) 2.0))
                       (cons 3 (min (car p1) (car p2))) (cons 4 (max (car p1) (car p2)))
                       (cons 10 p1) (cons 11 p2))))))
      (T (setq valid nil)))
    (setq i (1+ i)))
  (if valid segments nil))

(defun w2p:paired-span (s1 s2 target / axis separation lo hi len count actual i station points)
  (setq axis (cdr (assoc 1 s1))
        separation (abs (- (cdr (assoc 2 s1)) (cdr (assoc 2 s2))))
        lo (max (cdr (assoc 3 s1)) (cdr (assoc 3 s2)))
        hi (min (cdr (assoc 4 s1)) (cdr (assoc 4 s2)))
        len (- hi lo))
  ;; 1000 mm limits accidental pairing with a remote wall face.
  (if (and (= axis (cdr (assoc 1 s2))) (> separation 0.001)
           (<= separation 1000.0) (> len 0.001))
    (progn
      (setq count (w2p:space-count len target))
      (setq actual (/ len count) i 0 points '())
      (repeat (1+ count)
        (setq station (+ lo (* actual i)))
        (if (= axis 'V)
          (setq points
            (append points
              (list (list (cdr (assoc 2 s1)) station 0.0)
                    (list (cdr (assoc 2 s2)) station 0.0))))
          (setq points
            (append points
              (list (list station (cdr (assoc 2 s1)) 0.0)
                    (list station (cdr (assoc 2 s2)) 0.0)))))
        (setq i (1+ i)))
      (list points count))
    nil))

(defun w2p:paired-orthogonal-points (ent target / segments verts result paired total s1 s2 span run)
  (setq segments (w2p:orthogonal-segments ent))
  (if segments
    (progn
      (setq verts (w2p:poly-vertices-wcs ent)
            result '() paired '() total 0)
      (foreach p verts (setq result (w2p:unique-add p result 0.001)))
      (foreach s1 segments
        (foreach s2 segments
          (if (> (cdr (assoc 0 s2)) (cdr (assoc 0 s1)))
            (progn
              (setq span (w2p:paired-span s1 s2 target))
              (if span
                (progn
                  (foreach p (car span) (setq result (w2p:unique-add p result 0.001)))
                  (setq paired (cons (cdr (assoc 0 s1)) (cons (cdr (assoc 0 s2)) paired))
                        total (+ total (* 2 (cadr span))))))))))
      ;; A cap or isolated segment with no opposite face is divided normally.
      (foreach s1 segments
        (if (not (member (cdr (assoc 0 s1)) paired))
          (progn
            (setq run (w2p:run-points (cdr (assoc 10 s1)) (cdr (assoc 11 s1))
                                      (cdr (assoc 10 s1)) 0.0 target))
            (if run
              (progn
                (foreach p (car run) (setq result (w2p:unique-add p result 0.001)))
                (setq total (+ total (cadr run))))))))
      (list result total))
    nil))

(defun w2p:smart-curve-points (ent target / data typ paired)
  (setq data (entget ent) typ (cdr (assoc 0 data)))
  (if (and (= typ "LWPOLYLINE")
           (/= 0 (logand 1 (cdr (assoc 70 data))))
           (not (w2p:has-arcs ent)))
    (setq paired (w2p:paired-orthogonal-points ent target)))
  (if paired paired (w2p:curve-points ent target)))

(defun w2p:cw-close-p (a b)
  (equal a b 0.000001))

(defun w2p:cw-edges (ent / data verts prev p edges valid d)
  ;; Corewall uses closed, orthogonal outlines in the WCS XY plane.
  (setq data (entget ent))
  (if (and (= (cdr (assoc 0 data)) "LWPOLYLINE")
           (= 1 (logand 1 (cdr (assoc 70 data))))
           (not (w2p:has-arcs ent))
           (w2p:cw-close-p (cdr (assoc 210 data)) '(0.0 0.0 1.0))
           (w2p:cw-close-p (cdr (assoc 38 data)) 0.0)
           (not (vl-some '(lambda (item)
                           (and (member (car item) '(39 40 41 43))
                                (not (w2p:cw-close-p (cdr item) 0.0)))) data)))
    (progn
      (setq verts (w2p:poly-vertices-wcs ent) prev (last verts) valid T)
      (foreach p verts
        (cond
          ((w2p:cw-close-p prev p))
          ((w2p:cw-close-p (car prev) (car p))
           (setq edges (cons (list 'V (car p) (min (cadr prev) (cadr p))
                                  (max (cadr prev) (cadr p))) edges)))
          ((w2p:cw-close-p (cadr prev) (cadr p))
           (setq edges (cons (list 'H (cadr p) (min (car prev) (car p))
                                  (max (car prev) (car p))) edges)))
          (T (setq valid nil)))
        (setq prev p))
      (if (and valid (>= (length edges) 4)) (reverse edges)))))

(defun w2p:cw-inside (point edges / count e)
  (setq count 0)
  (foreach e edges
    (if (and (eq (car e) 'V) (> (cadr e) (car point))
             (<= (caddr e) (cadr point)) (< (cadr point) (cadddr e)))
      (setq count (1+ count))))
  (= 1 (rem count 2)))

(defun w2p:cw-between (v lo hi)
  (<= (- lo 0.000001) v (+ hi 0.000001)))

(defun w2p:cw-touch (a b / h v)
  (if (eq (car a) (car b))
    (and (w2p:cw-close-p (cadr a) (cadr b))
         (<= (max (caddr a) (caddr b)) (+ (min (cadddr a) (cadddr b)) 0.000001)))
    (progn
      (if (eq (car a) 'H) (setq h a v b) (setq h b v a))
      (and (w2p:cw-between (cadr v) (caddr h) (cadddr h))
           (w2p:cw-between (cadr h) (caddr v) (cadddr v))))))

(defun w2p:cw-simple (edges / left right index valid a)
  ;; Adjacent segments share a vertex by construction.
  (setq left edges index 0 valid T)
  (while (and valid left)
    (setq a (car left) right (cddr left))
    (if (= index 0) (setq right (reverse (cdr (reverse right)))))
    (if (vl-some '(lambda (b) (w2p:cw-touch a b)) right) (setq valid nil))
    (setq left (cdr left) index (1+ index)))
  valid)

(defun w2p:cw-first-point (group)
  (if (eq (caar group) 'H) (list (caddar group) (cadar group))
                          (list (cadar group) (caddar group))))

(defun w2p:cw-depth (group groups / point depth other)
  (setq point (w2p:cw-first-point group) depth 0)
  (foreach other groups
    (if (and (not (eq group other)) (w2p:cw-inside point other))
      (setq depth (1+ depth))))
  depth)

(defun w2p:cw-topology (groups / valid outer group other depth)
  (setq valid T outer 0)
  (foreach group groups
    (if (not (w2p:cw-simple group)) (setq valid nil))
    (setq depth (w2p:cw-depth group groups))
    (foreach other groups
      (if (not (eq group other))
        (if (vl-some '(lambda (a) (vl-some '(lambda (b) (w2p:cw-touch a b)) other)) group)
          (setq valid nil))))
    (cond ((= depth 0) (setq outer (1+ outer)))
          ((/= depth 1) (setq valid nil))))
  (and valid (= outer 1)))

(defun w2p:cw-offsets-toward-concrete (covers paths / cover path valid)
  (setq valid T)
  (foreach cover covers
    (setq path (car paths) paths (cdr paths))
    (if (= 0 (w2p:cw-depth cover covers))
      (if (not (w2p:cw-inside (w2p:cw-first-point path) cover)) (setq valid nil))
      (if (not (w2p:cw-inside (w2p:cw-first-point cover) path)) (setq valid nil))))
  valid)

(defun w2p:cw-add-span (key lo hi spans / old intervals latest)
  ;; Slab splits on unrelated faces must not restart the spacing.
  (setq old (assoc key spans) intervals (cdr old) latest (car intervals))
  (setq intervals
    (if (and latest (w2p:cw-close-p (cdr latest) lo))
      (cons (cons (car latest) hi) (cdr intervals))
      (cons (cons lo hi) intervals)))
  (if old (subst (cons key intervals) old spans)
          (cons (cons key intervals) spans)))

(defun w2p:cw-point (axis fixed station)
  (if (eq axis 'H) (list station fixed 0.0) (list fixed station 0.0)))

(defun w2p:cw-anchors (axis fixed lo hi anchors / point station result)
  (setq result (list lo hi))
  (foreach point anchors
    (if (eq axis 'H) (setq station (car point)) (setq station (cadr point)))
    (if (and (> station (+ lo 0.000001)) (< station (- hi 0.000001))
             (w2p:cw-close-p fixed (if (eq axis 'H) (cadr point) (car point))))
      (setq result (cons station result))))
  result)

(defun w2p:cw-points (groups target /
                       all axis edges cuts left lo hi mid active e a b spans
                       anchors entry key span face stations count j station points)
  (setq all (apply 'append groups))
  (foreach axis '(H V)
    (setq edges (vl-remove-if-not '(lambda (edge) (eq (car edge) axis)) all)
          cuts (vl-sort (append (mapcar 'caddr edges) (mapcar 'cadddr edges)) '<)
          left cuts)
    (while (cdr left)
      (setq lo (car left) hi (cadr left) mid (* 0.5 (+ lo hi))
            left (cdr left) active nil)
      (if (> (- hi lo) 0.000001)
        (progn
          (foreach e edges
            (if (< (caddr e) mid (cadddr e)) (setq active (cons (cadr e) active))))
          (setq active (vl-sort active '<))
          (while (cdr active)
            (setq a (car active) b (cadr active) active (cddr active))
            (if (<= (- b a) 1000.0)
              (setq spans (w2p:cw-add-span (list axis a b) lo hi spans))
              (progn
                (setq spans (w2p:cw-add-span (list axis a) lo hi spans))
                (setq spans (w2p:cw-add-span (list axis b) lo hi spans)))))))))
  ;; All corner and junction limits are established before any run is divided.
  (foreach entry spans
    (setq key (car entry))
    (foreach span (cdr entry)
      (foreach face (cdr key)
        (setq anchors (cons (w2p:cw-point (car key) face (car span))
                       (cons (w2p:cw-point (car key) face (cdr span)) anchors))))))
  (foreach entry spans
    (setq key (car entry))
    (foreach span (cdr entry)
      (setq stations nil)
      (foreach face (cdr key)
        (setq stations (append (w2p:cw-anchors (car key) face (car span) (cdr span) anchors)
                               stations)))
      (setq stations (vl-sort stations '<))
      (while (cdr stations)
        (setq lo (car stations) hi (cadr stations) stations (cdr stations))
        (if (> (- hi lo) 0.000001)
          (progn
            (setq count (w2p:space-count (- hi lo) target) j 0)
            (repeat (1+ count)
              (setq station (if (= j count) hi (+ lo (* j (/ (- hi lo) count)))))
              (foreach face (cdr key)
                (setq points (w2p:unique-add (w2p:cw-point (car key) face station) points 0.001)))
              (setq j (1+ j))))))))
  points)

(defun w2p:cw-offset (ent amount side / before after)
  (setq before (entlast))
  (vl-cmdf "_.OFFSET" "_Erase" "_No" amount ent side "")
  (setq after (entlast))
  (if (and after (not (eq after before))) after))

(defun w2p:cw-offset-side (edges interior / edge longest station fixed probe)
  ;; Test just off the middle of a long edge, away from its corners.
  (setq longest (car edges))
  (foreach edge (cdr edges)
    (if (> (- (cadddr edge) (caddr edge)) (- (cadddr longest) (caddr longest)))
      (setq longest edge)))
  (setq station (* 0.5 (+ (caddr longest) (cadddr longest)))
        fixed (cadr longest)
        probe 0.01)
  ;; Stay nearer to the chosen edge than any other parallel edge across the probe.
  (foreach edge edges
    (if (and (eq (car edge) (car longest)) (< (caddr edge) station (cadddr edge))
             (not (w2p:cw-close-p (cadr edge) fixed)))
      (setq probe (min probe (* 0.25 (abs (- (cadr edge) fixed)))))))
  (if (not (eq (w2p:cw-inside (w2p:cw-point (car longest) (+ fixed probe) station)
                            edges) interior))
    (setq probe (- probe)))
  (trans (w2p:cw-point (car longest) (+ fixed probe) station) 0 1))

(defun w2p:cw-corners (ent / verts prev next p result)
  (setq verts (w2p:poly-vertices-wcs ent) prev (last verts)
        next (append (cdr verts) (list (car verts))))
  (foreach p verts
    (if (not (or (and (w2p:cw-close-p (car prev) (car p))
                      (w2p:cw-close-p (car p) (caar next)))
                 (and (w2p:cw-close-p (cadr prev) (cadr p))
                      (w2p:cw-close-p (cadr p) (cadar next)))))
      (setq result (cons p result)))
    (setq prev p next (cdr next)))
  (reverse result))

(defun w2p:cw-cover-pair (outer inner cover / a b p candidate valid)
  ;; For a mitered uniform offset, each turn has a matching turn one cover
  ;; distance away on both axes. Require a one-to-one match.
  (setq a (w2p:cw-corners outer) b (w2p:cw-corners inner)
        valid (and (>= (length a) 4) (= (length a) (length b))))
  (foreach p a
    (if valid
      (progn
        (setq candidate (vl-remove-if-not
          '(lambda (q)
             (and (equal (abs (- (car p) (car q))) cover 0.01)
                  (equal (abs (- (cadr p) (cadr q))) cover 0.01))) b))
        (if (= 1 (length candidate))
          (setq b (vl-remove (car candidate) b))
          (setq valid nil)))))
  valid)

(defun w2p:cw-find-covers (seed cover / outer candidates nearby i ent edges entries inside a b mates covers selected valid)
  (setq outer (w2p:cw-edges seed)
        candidates (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 410 (getvar "CTAB"))))
        i 0 valid T)
  (repeat (sslength candidates)
    (setq ent (ssname candidates i) i (1+ i))
    (if (and (not (eq ent seed)) (setq edges (w2p:cw-edges ent)))
      (cond
        ((and (w2p:cw-inside (w2p:cw-first-point outer) edges)
              (w2p:cw-cover-pair ent seed cover))
         (setq nearby (cons ent nearby)))
        ((and (w2p:cw-inside (w2p:cw-first-point edges) outer)
              (not (vl-some '(lambda (edge) (vl-some '(lambda (e) (w2p:cw-touch edge e)) outer)) edges)))
         (setq entries (cons (cons ent edges) entries))))))
  (if (= 1 (length nearby))
    (progn
      (setq selected (ssadd seed))
      (foreach a entries
        (setq mates nil)
        (foreach b entries
          (if (and (not (eq a b))
                   (w2p:cw-inside (w2p:cw-first-point (cdr b)) (cdr a))
                   (w2p:cw-cover-pair (car a) (car b) cover))
            (setq mates (cons b mates))))
        (cond
          ((= 1 (length mates))
           (setq covers (cons (cdr a) covers))
           (ssadd (car a) selected))
          ((> (length mates) 1) (setq valid nil))))
      (cond
        ((not valid) (prompt "\nAmbiguous opening cover pairs. Select the covering loops manually.") nil)
        ((not covers) (prompt "\nNo matching opening cover pairs found at this cover distance.") nil)
        ((not (w2p:cw-topology (cons outer covers)))
         (prompt "\nDetected opening loops overlap or are nested. Select the covering loops manually.") nil)
        (T selected)))
    (progn
      (prompt "\nCould not identify one outer concrete outline. Select its inner covering line and check the cover distance.")
      nil)))

(defun w2p:cw-expand-selection (ss / seed cover expanded answer)
  (setq seed (ssname ss 0))
  (if (not (w2p:cw-edges seed))
    (prompt "\nSelect a closed, orthogonal outer covering polyline at WCS Z=0.")
    (progn
      (initget 6)
      (setq cover (getreal "\nOne loop selected. Enter concrete cover in mm to find openings <40>: "))
      (if (setq expanded (w2p:cw-find-covers seed (if cover cover 40.0)))
        (progn
          (sssetfirst nil expanded)
          (initget "Yes No")
          (setq answer (getkword
            (strcat "\nFound " (itoa (1- (sslength expanded)))
                    " opening covering loop(s). Generate from highlighted loops? [Yes/No] <No>: ")))
          (sssetfirst nil nil)
          (if (= answer "Yes") expanded))))))

(defun w2p:corewall (amount target / *error* ss i ent side barEnt edges inputs covers groups paths made p failed gap snap item)
  (defun *error* (msg)
    (foreach ent (append made paths) (if (entget ent) (entdel ent)))
    (if gap (setvar "OFFSETGAPTYPE" gap))
    (if snap (setvar "OSMODE" snap))
    (sssetfirst nil nil)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nError: " msg)))
    (princ))
  (setq ss (ssget "_I" '((0 . "LWPOLYLINE"))))
  (if (not ss)
    (progn
      (prompt "\nSelect all covering loops, or select the outer covering loop only to find openings, then press Enter: ")
      (setq ss (ssget '((0 . "LWPOLYLINE"))))))
  (if (and ss (= (sslength ss) 1)) (setq ss (w2p:cw-expand-selection ss)))
  (cond
    ((not ss) (prompt "\nNo corewall points created."))
    (T
     (setq i 0)
     (while (and (not failed) (< i (sslength ss)))
       (setq ent (ssname ss i) i (1+ i) edges (w2p:cw-edges ent))
       (if edges
         (setq inputs (cons (cons ent edges) inputs) covers (cons edges covers))
         (setq failed "\nSelect only closed, orthogonal, zero-width covering polylines at WCS Z=0.")))
     (if (and (not failed) (not (w2p:cw-topology covers)))
       (setq failed "\nSelect one outer covering loop and its separate openings. Remove concrete outlines or duplicate loops from the selection."))
     (if (not failed)
       (progn
         (setq gap (getvar "OFFSETGAPTYPE") snap (getvar "OSMODE"))
         (setvar "OFFSETGAPTYPE" 0)
         (setvar "OSMODE" 0)
         (foreach item inputs
           (if (not failed)
             (progn
               (setq edges (cdr item)
                     side (w2p:cw-offset-side edges (= 0 (w2p:cw-depth edges covers)))
                     barEnt (w2p:cw-offset (car item) amount side))
               (if barEnt (setq paths (cons barEnt paths)))
               (if (and barEnt (setq edges (w2p:cw-edges barEnt)))
                 (setq groups (cons edges groups))
                 (setq failed "\nCould not offset a loop. Check the section and bar diameter.")))))
         (setq groups (reverse groups))
         (if (and (not failed)
                  (not (and (w2p:cw-topology groups)
                            (w2p:cw-offsets-toward-concrete covers groups))))
           (setq failed "\nThe bar-centre outlines overlap or do not fit inside the covering section."))))
     (if (not failed)
       (foreach p (w2p:cw-points groups target)
         (if (and (not failed) (setq ent (entmakex (list '(0 . "POINT") (cons 10 p)))))
           (setq made (cons ent made))
           (setq failed "\nCorewall points could not be created."))))
     (if failed
       (progn (*error* nil) (prompt failed))
       (progn
         (setvar "OFFSETGAPTYPE" gap)
         (setvar "OSMODE" snap)
         (prompt (strcat "\nCreated " (itoa (length made)) " corewall POINTs from "
                         (itoa (length groups)) " covering loops. Review before CAD2PROKON."))))))
  (princ))

(defun c:COVER2BARPOINTS (/ *error* olderr dia amount target mode sel ent typ side barEnt result allpts before p pathCount)
  (setq olderr *error*)
  (defun *error* (msg)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg)))
    (princ))

  (initget 6)
  (setq dia (getreal "\nRebar diameter in mm <25>: "))
  (if (null dia) (setq dia 25.0))
  (setq amount (w2p:bar-offset dia))
  (initget 6)
  (setq target (getdist "\nTarget spacing in mm <200>: "))
  (if (null target) (setq target 200.0))
  (prompt (strcat "\nCover-to-bar-centre offset = " (w2p:fmt amount) " mm."))

  (initget "Single Corewall")
  (setq mode (getkword "\nLayout [Single/Corewall] <Single>: "))
  (if (= mode "Corewall")
    (w2p:corewall amount target)
    (progn
  (setq allpts '() pathCount 0)
  (while (setq sel (entsel "\nSelect covering LINE/POLYLINE/ARC <finish>: "))
    (setq ent (car sel) typ (cdr (assoc 0 (entget ent))))
    (if (member typ '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
      (progn
        (setq side (getpoint "\nPick the side where bar centres are required: "))
        (if side
          (progn
            (setq barEnt (w2p:create-sided-offset ent amount side))
            (if barEnt
              (progn
                (setq result (w2p:smart-curve-points barEnt target))
                (foreach p (car result)
                  (setq before (length allpts)
                        allpts (w2p:unique-add p allpts 0.001))
                  (if (> (length allpts) before)
                    (entmakex (list '(0 . "POINT") (cons 10 p)))))
                (setq pathCount (1+ pathCount))
                (prompt
                  (strcat "\nCreated offset path and " (itoa (length (car result)))
                          " points in " (itoa (cadr result)) " spaces.")))
              (prompt "\nAutoCAD could not offset this covering curve.")))))
      (prompt "\nUnsupported object. Select LINE, ARC, LWPOLYLINE or POLYLINE.")))

  (if allpts
    (prompt
      (strcat "\nCreated " (itoa (length allpts)) " unique POINT entities on "
              (itoa pathCount) " offset path(s). Use CAD2PROKON after checking."))
    (prompt "\nNo bar-centre paths or points were created."))))
  (setq *error* olderr)
  (princ))

(defun c:WALLBARPOINTS (/ *error* olderr target sel ent typ result allpts before p curveCount)
  (setq olderr *error*)
  (defun *error* (msg)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled"))
      (prompt (strcat "\nError: " msg)))
    (princ))

  (initget 6)
  (setq target (getdist "\nTarget spacing in mm <200>: "))
  (if (null target) (setq target 200.0))
  (setq allpts '() curveCount 0)
  (while (setq sel (entsel "\nSelect prepared bar-centre LINE/POLYLINE/ARC <finish>: "))
    (setq ent (car sel) typ (cdr (assoc 0 (entget ent))))
    (if (member typ '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
      (progn
        (setq result (w2p:curve-points ent target))
        (foreach p (car result)
          (setq before (length allpts)
                allpts (w2p:unique-add p allpts 0.001))
          (if (> (length allpts) before)
            (entmakex (list '(0 . "POINT") (cons 10 p)))))
        (setq curveCount (1+ curveCount))
        (prompt
          (strcat "\nCurve divided into " (itoa (cadr result))
                  " spaces and " (itoa (length (car result))) " points.")))
      (prompt "\nUnsupported object. Select LINE, ARC, LWPOLYLINE or POLYLINE.")))

  (if allpts
    (prompt
      (strcat "\nCreated " (itoa (length allpts)) " unique POINT entities from "
              (itoa curveCount) " curve(s). Use CAD2PROKON after checking."))
    (prompt "\nNo reinforcement points were created."))
  (setq *error* olderr)
  (princ))

(defun w2p:poly-vertices-wcs (ent / data elev result pair)
  (setq data (entget ent)
        elev (cond ((cdr (assoc 38 data))) (0.0))
        result '())
  (foreach pair data
    (if (= (car pair) 10)
      (setq result
        (append result
          (list (trans (list (car (cdr pair)) (cadr (cdr pair)) elev) ent 0))))))
  result)

(defun w2p:has-arcs (ent / found pair)
  (setq found nil)
  (foreach pair (entget ent)
    (if (and (= (car pair) 42) (not (equal (cdr pair) 0.0 0.0000001)))
      (setq found T)))
  found)

(defun w2p:nearest-index (pick points / i best bestdist d)
  (setq i 0 best 0 bestdist nil)
  (foreach p points
    (setq d (distance pick p))
    (if (or (null bestdist) (< d bestdist))
      (setq best i bestdist d))
    (setq i (1+ i)))
  best)

(defun w2p:rotate-list (items index / first)
  (repeat index
    (setq first (car items)
          items (append (cdr items) (list first))))
  items)

(defun c:WALLSHAPE2PROKON (/ sel ent data verts startPick startWcs index answer ordered closed prev curr dx dy tab lines)
  (setq sel (entsel "\nSelect a straight closed wall polyline: "))
  (if sel
    (progn
      (setq ent (car sel) data (entget ent))
      (cond
        ((/= (cdr (assoc 0 data)) "LWPOLYLINE")
         (prompt "\nPlease select an LWPOLYLINE."))
        ((= 0 (logand 1 (cdr (assoc 70 data))))
         (prompt "\nThe wall polyline must be closed."))
        ((w2p:has-arcs ent)
         (prompt "\nArc wall segments are not supported in this version."))
        (T
         (setq startPick (getpoint "\nPick PROKON start vertex <WCS 0,0>: "))
         (if startPick
           (setq startWcs (trans startPick 1 0))
           (setq startWcs '(0.0 0.0 0.0)))
         (setq verts (w2p:poly-vertices-wcs ent)
               index (w2p:nearest-index startWcs verts)
               ordered (w2p:rotate-list verts index))
         (initget "Current Reverse")
         (setq answer (getkword "\nPolyline direction [Current/Reverse] <Current>: "))
         (if (= answer "Reverse")
           (setq ordered (cons (car ordered) (reverse (cdr ordered)))))
         (setq closed (append ordered (list (car ordered)))
               tab (chr 9)
               lines (list (strcat "+" tab tab))
               prev (car closed))
         (foreach curr (cdr closed)
           (setq dx (- (car curr) (car prev))
                 dy (- (cadr curr) (cadr prev))
                 lines (append lines (list (strcat tab (w2p:fmt dx) tab (w2p:fmt dy))))
                 prev curr))
         (if (w2p:copy-lines lines)
           (prompt (strcat "\nCopied wall shape with " (itoa (1- (length closed))) " segments to the clipboard."))
           (prompt "\nCould not copy the wall shape to the clipboard."))))))
  (princ))

(princ "\nWALL_TO_PROKON loaded. Commands: COVER2BARPOINTS, WALLBARPOINTS, WALLBARPOINTS2P, WALLSHAPE2PROKON.")
(princ)
