;;;=============================================================================
;;; Well Name Header (WNH) - 2026-11-25
;;;
;;; Writes the well name lines at the top of wellsite page 1, one per well:
;;;
;;;     Operator  UWI  HZ/DD  Strike Area  LS-SEC-TWP-RGE      (max 36 chars)
;;;     e.g.  CVE 100 HZ BERLRW 5-18-59-24
;;;
;;; Where the pieces come from:
;;;   Operator, HZ or DD, Strike Area  -> drawing properties (DWGPROPS)
;;;   Wells                            -> "Drill Path" polylines: the end at
;;;                                       the pad is the well centre, the other
;;;                                       end is the bottom hole
;;;   LS, Sec, Twp, Rge, Mer           -> worked out from the "10-Section Labels"
;;;                                       (section number over 59-24-5 at each
;;;                                       section centre), LSD by 4 x 4 split
;;;   UWI                              -> nearby "Bottom Hole 100/5-18" label,
;;;                                       else UWI drawing property, else 100
;;;   Line order                       -> order of the wells in the page 1
;;;                                       ELEVATIONS note, else north to south
;;; Fallbacks: no drill paths -> "Bottom Hole" labels (Twp/Rge from ATS
;;; quarter labels or BH props); nothing at all -> one line from BH props.
;;;
;;; Warnings in the list: point within 25 m of an LSD line, drawing label
;;; disagrees, AER bottom hole already in the LSD (UWI may need 102), well
;;; centres in more than one LS.
;;;
;;; Usage: type WNH (from any tab), check the names it lists, answer Yes.
;;; It finds page 1 by itself: the "PLAN SHOWING ..." title that sits on the
;;; sheet of a layout, and the big name lines straight under it. Those are
;;; replaced in the same style/spot, the lines underneath (WELL(S) ...
;;; DRILLED, LS ... line, county) are moved to suit, WELL/WELLS is corrected,
;;; and the Sur / BH drawing properties are filled in (replaces UDP) so the
;;; LS line fields update. Only if the header can't be found does it ask you
;;; to select the old name lines. One U undoes everything.
;;;=============================================================================

(vl-catch-all-apply 'vl-load-com nil)

;;; ---- Settings ---------------------------------------------------------------
(setq WNH_MAX_LENGTH 36)
(setq WNH_DEFAULT_SPACING 7.919)		; gap between name lines on Wellsite.dwt
(setq WNH_BH_LAYER "Drill Path Text")
(setq WNH_ATS_LAYER "ATS Labels Quarter")
(setq WNH_PATH_LAYER "Drill Path")		; well centre -> bottom hole polylines
(setq WNH_SECTION_LAYER "10-Section Labels")	; "18" over "59-24-5" at section centres
(setq WNH_EDGE_WARN 25.0)			; warn if a point is this close (m) to an LSD line

;;; Operators that always show the UWI, even 100 on the first well.
;;; Everyone else leaves 100 out (TOURMALINE HZ ...) and shows 102, 103 ...
(setq WNH_ALWAYS_SHOW_UWI '("CVE"))

;;; AER abbreviations, only used when a name is over the limit.
;;; Operator is shortened first, then strike area. ("FULL NAME" . "ABBR")
(setq WNH_OPERATOR_ABBR '())
(setq WNH_STRIKE_ABBR '())


;;;=============================================================================
;;; Main command
(defun c:WNH (/ *error* wells names ss)
  (defun *error* (msg)
    (if	(not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nWNH error: " msg))
    ) ;_ end of if
    (command-s "_.UNDO" "_END")
    (princ)
  ) ;_ end of defun

  (setvar "CMDECHO" 0)
  (wnh-ensure-props)

  (setq wells (wnh-get-wells)
	names (mapcar 'car wells)
  ) ;_ end of setq
  (wnh-report wells)

  (initget "Yes No")
  (if (= (getkword "\nWrite these names onto page 1? [Yes/No] <Yes>: ") "No")
    (exit)
  ) ;_ end of if

  ;; Find the name lines under the page 1 title; ask only if they can't be found
  (if (setq ss (wnh-find-name-lines))
    (progn
      (if (/= (getvar "CTAB") (car ss)) (setvar "CTAB" (car ss)))
      (setq ss (cdr ss))
      (princ (strcat "\nFound " (itoa (length ss)) " well name line(s) on layout " (getvar "CTAB") "."))
    ) ;_ end of progn
    (progn
      (if (= (getvar "TILEMODE") 1)
	(progn (alert "Couldn't find the page 1 header.\nGo to the page 1 layout and run WNH again.") (exit))
      ) ;_ end of if
      (prompt "\nCouldn't find the page 1 header - select the existing well name lines: ")
      (setq ss (wnh-ss->list (ssget '((0 . "TEXT")))))
    ) ;_ end of progn
  ) ;_ end of if

  (if ss
    (progn
      (command "_.UNDO" "_BEGIN")
      (wnh-write names ss)
      (if (wnh-update-props wells)
	(princ "\nWNH: Sur / BH drawing properties updated from the drill paths.")
      ) ;_ end of if
      (command "_.UNDO" "_END")
      (princ (strcat "\nWNH: wrote " (itoa (length names)) " well name line(s)."))
    ) ;_ end of progn
    (princ "\nNothing selected - page 1 not changed.")
  ) ;_ end of if
  (princ)
) ;_ end of defun


;;;=============================================================================
;;; Build the list of wells, in page order.
;;; Each well: (name twpRgeFromProps warnings surfaceLegal bhLegal)
;;;   legal = (ls sec twp rge mer), nil when not worked out from the drawing
;;;
;;; Sources, best first:
;;;   1. Drill Path polylines + section labels (fully automatic)
;;;   2. "Bottom Hole 100/5-18" labels
;;;   3. BH drawing properties (one well)
(defun wnh-get-wells (/ op typ strike paths secs bhs ats out tr fromProps)
  (setq	op     (wnh-prop "Operator")
	typ    (wnh-prop "HZ or DD")
	strike (wnh-prop "Strike Area")
	paths  (wnh-drill-paths)
	secs   (wnh-section-labels)
  ) ;_ end of setq

  (cond
    ((and paths secs)
     (setq bhs (wnh-order-wells (wnh-wells-from-paths paths secs))))
    ((setq bhs (wnh-get-bottom-holes))
     (setq bhs (wnh-order-wells bhs)))
    (T
     (setq bhs (list (list "" (wnh-prop "UWI") (wnh-prop "BH LS") (wnh-prop "BH Sec")
			   (wnh-prop "BH Twp") (wnh-prop "BH Rge") '(0.0 0.0 0.0)))))
  ) ;_ end of cond

  (setq ats (if (not (and paths secs)) (wnh-get-ats-labels)))
  (foreach bh bhs	; bh = (key uwi ls sec twp rge point [warnings sur bhLegal])
    (setq fromProps nil)
    (cond ((and (nth 4 bh) (nth 5 bh)) (setq tr (list (nth 4 bh) (nth 5 bh))))
	  ((and ats (setq tr (wnh-twp-rge-at (nth 6 bh) ats))))
	  (T (setq tr (list (wnh-prop "BH Twp") (wnh-prop "BH Rge")) fromProps T))
    ) ;_ end of cond
    (setq out (cons (list (wnh-build-name op (nth 1 bh) typ strike
					  (strcat (nth 2 bh) "-" (nth 3 bh) "-" (car tr) "-" (cadr tr)))
			  fromProps
			  (nth 7 bh)
			  (nth 8 bh)
			  (nth 9 bh))
		    out))
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun


;;;=============================================================================
;;; Drill paths: returns list of (surfacePoint bottomHolePoint)
;;; The surface end is the one nearest another path (pad wells share a
;;; surface); with a single path the first vertex is taken as the surface.
(defun wnh-drill-paths (/ ss i e v ends lst)
  (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,LINE") (cons 8 WNH_PATH_LAYER) '(410 . "Model"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e (entget (ssname ss i)) i (1+ i) v nil)
	(if (= (wnh-dxf 0 e) "LINE")
	  (setq v (list (wnh-dxf 11 e) (wnh-dxf 10 e)))
	  (foreach p e (if (= (car p) 10) (setq v (cons (cdr p) v))))
	) ;_ end of if
	(if (> (length v) 1)
	  (setq ends (cons (list (wnh-2d (last v)) (wnh-2d (car v))) ends))	; (first last)
	) ;_ end of if
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  (foreach pe ends
    (if	(and (> (length ends) 1)
	     (> (wnh-nearest-other-end (car pe) pe ends)
		(wnh-nearest-other-end (cadr pe) pe ends)))
      (setq lst (cons (list (cadr pe) (car pe)) lst))
      (setq lst (cons pe lst))
    ) ;_ end of if
  ) ;_ end of foreach
  lst
) ;_ end of defun

(defun wnh-nearest-other-end (pt me ends / bd)
  (setq bd 1e99)
  (foreach pe ends
    (if	(not (equal pe me))
      (setq bd (min bd (distance pt (car pe)) (distance pt (cadr pe))))
    ) ;_ end of if
  ) ;_ end of foreach
  bd
) ;_ end of defun


;;;=============================================================================
;;; Section labels: MTEXT "18" over "59-24-5" at each section centre.
;;; Returns list of (sec twp rge mer x y)
(defun wnh-section-labels (/ ss i e parts trm lst)
  (if (setq ss (ssget "_X" (list '(0 . "MTEXT") (cons 8 WNH_SECTION_LAYER) '(410 . "Model"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e	    (entget (ssname ss i))
	      i	    (1+ i)
	      parts (mapcar 'wnh-strip-codes
			    (wnh-split (wnh-replace-all (wnh-replace-all (wnh-text e) "\r\n" "\\P") "\n" "\\P") "\\P"))
	      parts (vl-remove "" parts)
	) ;_ end of setq
	(if (and (= (length parts) 2)
		 (wcmatch (car parts) "#,##")
		 (wcmatch (cadr parts) "*#-*#-*#"))
	  (setq	trm (wnh-split (cadr parts) "-")
		lst (cons (list (car parts) (nth 0 trm) (nth 1 trm) (nth 2 trm)
				(car (wnh-dxf 10 e)) (cadr (wnh-dxf 10 e)))
			  lst)
	  ) ;_ end of setq
	) ;_ end of if
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  lst
) ;_ end of defun

;;; "\pxsm0.75,qc;18" -> "18",  "{\Farial|c0;\H0.5x;59-24-5}" -> "59-24-5"
(defun wnh-strip-codes (s / pos)
  (setq s (vl-string-trim " {}" (wnh-replace-all (wnh-replace-all s "{" "") "}" "")))
  (if (setq pos (vl-string-position 59 s nil T))		; 59 = semicolon
    (setq s (substr s (+ pos 2)))
  ) ;_ end of if
  (vl-string-trim " " s)
) ;_ end of defun


;;;=============================================================================
;;; Legal location of a point from the section labels.
;;; Takes the nearest section centre, gets the section's east/north axes from
;;; the neighbouring section centres, splits it 4 x 4 and numbers the LSD.
;;; Returns (ls sec twp rge mer metresToNearestLsdLine)
(defun wnh-legal-at (pt secs / best bd d c ev nv dx dy w h u v col row ls)
  (setq pt (wnh-2d pt) bd 1e99)
  (foreach s secs
    (setq d (distance pt (list (nth 4 s) (nth 5 s))))
    (if (< d bd) (setq bd d best s))
  ) ;_ end of foreach
  (if best
    (progn
      (setq c (list (nth 4 best) (nth 5 best)))
      (foreach s secs
	(setq d (distance c (list (nth 4 s) (nth 5 s))))
	(if (and (> d 1200.0) (< d 2100.0))
	  (progn
	    (setq dx (- (nth 4 s) (car c)) dy (- (nth 5 s) (cadr c)))
	    (cond ((and (> (abs dx) (abs dy)) (null ev))
		   (setq ev (if (> dx 0) (list dx dy) (list (- dx) (- dy)))))
		  ((and (> (abs dy) (abs dx)) (null nv))
		   (setq nv (if (> dy 0) (list dx dy) (list (- dx) (- dy)))))
	    ) ;_ end of cond
	  ) ;_ end of progn
	) ;_ end of if
      ) ;_ end of foreach
      (if (null ev) (setq ev '(1609.3 0.0)))
      (if (null nv) (setq nv '(0.0 1609.3)))
      (setq dx	(- (car pt) (car c))
	    dy	(- (cadr pt) (cadr c))
	    w	(distance '(0.0 0.0) ev)
	    h	(distance '(0.0 0.0) nv)
	    u	(/ (+ (* dx (car ev)) (* dy (cadr ev))) (* w w))	; -0.5 west .. 0.5 east
	    v	(/ (+ (* dx (car nv)) (* dy (cadr nv))) (* h h))	; -0.5 south .. 0.5 north
	    col	(min 3 (max 0 (fix (* (+ u 0.5) 4))))
	    row	(min 3 (max 0 (fix (* (+ v 0.5) 4))))
	    ls	(nth col (nth row '((4 3 2 1) (5 6 7 8) (12 11 10 9) (13 14 15 16))))
      ) ;_ end of setq
      (list (itoa ls) (nth 0 best) (nth 1 best) (nth 2 best) (nth 3 best)
	    (min (wnh-edge u w) (wnh-edge v h)))
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;; Metres from fraction f (-0.5..0.5) of a section to the nearest LSD line
(defun wnh-edge (f size / q)
  (setq q (* (+ f 0.5) 4.0))
  (* (abs (- q (fix (+ q 0.5)))) (/ size 4.0))
) ;_ end of defun


;;;=============================================================================
;;; Turn drill paths into well records:
;;; (key uwi ls sec twp rge bhPoint warnings surLegal bhLegal)
(defun wnh-wells-from-paths (paths secs / labels aer out bh sur lab uwi warn key)
  (setq	labels (wnh-get-bottom-holes)
	aer    (wnh-aer-bottom-holes)
  ) ;_ end of setq
  (foreach p paths
    (setq sur  (wnh-legal-at (car p) secs)
	  bh   (wnh-legal-at (cadr p) secs)
	  warn nil
	  lab  (wnh-nearest-label (cadr p) labels 600.0)
	  uwi  (cond ((cadr lab)) ((/= (wnh-prop "UWI") "") (wnh-prop "UWI")) ("100"))
	  key  (strcat uwi "/" (car bh) "-" (cadr bh))
    ) ;_ end of setq
    (if	(< (nth 5 bh) WNH_EDGE_WARN)
      (setq warn (cons (strcat "bottom hole is only " (rtos (nth 5 bh) 2 0)
			       " m from an LSD line - check the LS (or road allowance)")
		       warn))
    ) ;_ end of if
    (if	(and lab (not (and (= (nth 2 lab) (car bh)) (= (nth 3 lab) (cadr bh)))))
      (setq warn (cons (strcat "label on the drawing says " (car lab)) warn))
    ) ;_ end of if
    (if	(and (= uwi "100") (wnh-aer-well-in-lsd bh aer secs))
      (setq warn (cons "an AER bottom hole is already in this LSD - UWI may need to be 102" warn))
    ) ;_ end of if
    (setq out (cons (list key uwi (car bh) (cadr bh) (caddr bh) (cadddr bh) (cadr p)
			  (reverse warn) sur bh)
		    out))
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

(defun wnh-nearest-label (pt labels maxd / best bd d)
  (setq bd maxd)
  (foreach l labels
    (setq d (distance (wnh-2d pt) (wnh-2d (nth 6 l))))
    (if (< d bd) (setq bd d best l))
  ) ;_ end of foreach
  best
) ;_ end of defun

;;; AER bottom hole points already in the drawing (layer bottom_hole)
(defun wnh-aer-bottom-holes (/ ss i lst)
  (if (setq ss (ssget "_X" '((0 . "POINT") (8 . "bottom_hole") (410 . "Model"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq lst (cons (wnh-2d (wnh-dxf 10 (entget (ssname ss i)))) lst) i (1+ i))
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  lst
) ;_ end of defun

(defun wnh-aer-well-in-lsd (bh aer secs / found l)
  (foreach p aer
    (if	(and (not found) (setq l (wnh-legal-at p secs)))
      (setq found (and (= (car l) (car bh)) (= (cadr l) (cadr bh))
		       (= (caddr l) (caddr bh)) (= (cadddr l) (cadddr bh))))
    ) ;_ end of if
  ) ;_ end of foreach
  found
) ;_ end of defun


;;;=============================================================================
;;; Fill the Sur / BH drawing properties (what UDP used to do) so the LS line
;;; and other fields on the plan match. BH = first well on page 1.
(defun wnh-update-props (wells / sur bh)
  (setq	sur (nth 3 (car wells))
	bh  (nth 4 (car wells))
  ) ;_ end of setq
  (if (and sur bh (not WNH_TEST_PROPS))
    (progn
      (wnh-set-prop "Sur LS" (nth 0 sur))
      (wnh-set-prop "Sur Sec" (nth 1 sur))
      (wnh-set-prop "Sur Twp" (nth 2 sur))
      (wnh-set-prop "Sur Rge" (nth 3 sur))
      (wnh-set-prop "Mer" (nth 4 sur))
      (wnh-set-prop "BH LS" (nth 0 bh))
      (wnh-set-prop "BH Sec" (nth 1 bh))
      (wnh-set-prop "BH Twp" (nth 2 bh))
      (wnh-set-prop "BH Rge" (nth 3 bh))
      (command "_.UPDATEFIELD" (ssget "_X") "")
      T
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;; A fresh Well Site.dwt has Operator = OPERATOR and Strike Area = STRIKE.
;;; Ask for anything still on a placeholder and save it to the drawing
;;; properties, so every page's name fields pick it up.
(defun wnh-ensure-props (/ v typ chk)
  (wnh-load-strike-areas)
  (if (wnh-placeholder-p "Operator" '("" "OPERATOR" "COP"))
    (if (/= "" (setq v (strcase (getstring T "\nOperator abbreviation (e.g. CVE, TOURMALINE): "))))
      (wnh-set-prop "Operator" v)
    ) ;_ end of if
  ) ;_ end of if
  (if (wnh-placeholder-p "Strike Area" '("" "STRIKE" "CARROT"))
    (progn
      (wnh-strike-hints)
      (if (/= "" (setq v (strcase (getstring T "\nField / Strike Area name or abbreviation (see Job Info\\Strike Area.pdf): "))))
	(progn
	  (setq chk (wnh-check-strike v))
	  (if (cadr chk) (princ (strcat "\n  " (cadr chk))))
	  (wnh-set-prop "Strike Area" (car chk))
	) ;_ end of progn
      ) ;_ end of if
    ) ;_ end of progn
    ;; Already filled in: swap a full name for its AER abbreviation
    (if (and (not WNH_TEST_PROPS)
	     (setq chk (wnh-check-strike (wnh-prop "Strike Area")))
	     (/= (car chk) (strcase (wnh-prop "Strike Area")))
	     (wnh-strike-known-p (car chk)))
      (progn
	(wnh-set-prop "Strike Area" (car chk))
	(princ (strcat "\n  " (cadr chk)))
      ) ;_ end of progn
    ) ;_ end of if
  ) ;_ end of if
  (if (and (not WNH_TEST_PROPS) (= (wnh-prop "Sur LS") "X"))	; fresh drawing - confirm well type once
    (progn
      (initget "HZ DD Vertical")
      (setq typ (getkword "\nWell type [HZ/DD/Vertical] <HZ>: "))
      (wnh-set-prop "HZ or DD" (cond ((= typ "DD") " DD ") ((= typ "Vertical") " ") (" HZ ")))
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;;=============================================================================
;;; AER field / strike area list (AER Strike Areas.lsp, from AER Map-94).
;;; OGCR 13.020(2)(c): use the designated field name, or the strike area name
;;; if not in/next to a field - or the AER-approved abbreviation.
(defun wnh-load-strike-areas ()
  (if (not WNH_STRIKE_AREAS)
    (if	(not (load "O:/IGI/Cad Support/Visual LISP Development/AER Strike Areas.lsp" nil))
      (load "AER Strike Areas.lsp" nil)	; anywhere on the support path
    ) ;_ end of if
  ) ;_ end of if
  WNH_STRIKE_AREAS
) ;_ end of defun

(defun wnh-strike-known-p (abbr)
  (vl-some (function (lambda (e) (= (car e) abbr))) WNH_STRIKE_AREAS)
) ;_ end of defun

;;; Returns (value message). value is the AER abbreviation when found.
(defun wnh-check-strike (v / e)
  (setq v (strcase (vl-string-trim " " v)))
  (cond	((null WNH_STRIKE_AREAS) (list v nil))			; list not loaded - can't check
	((= v "") (list v nil))
	((wnh-strike-known-p v) (list v nil))
	((setq e (vl-some (function (lambda (e) (if (= (cadr e) v) e))) WNH_STRIKE_AREAS))
	 (list (car e) (strcat "Strike Area \"" v "\" changed to its AER abbreviation " (car e) ".")))
	(T (list v (strcat "Strike Area \"" v "\" is not in the AER field / strike area list - check it.")))
  ) ;_ end of cond
) ;_ end of defun

;;; Print the fields whose AER reference township is closest to the pad, as a
;;; hint only - the real boundary is on the strike area map (Strike Area.pdf).
(defun wnh-strike-hints (/ paths secs sur twp rge mer scored n)
  (if (and WNH_STRIKE_AREAS
	   (setq paths (wnh-drill-paths))
	   (setq secs (wnh-section-labels))
	   (setq sur (wnh-legal-at (car (car paths)) secs)))
    (progn
      (setq twp (atoi (nth 2 sur)) rge (atoi (nth 3 sur)) mer (atoi (nth 4 sur)))
      (foreach e WNH_STRIKE_AREAS
	(if (= (nth 4 e) mer)
	  (setq scored (cons (cons (+ (abs (- (nth 2 e) twp)) (abs (- (nth 3 e) rge))) e) scored))
	) ;_ end of if
      ) ;_ end of foreach
      (setq scored (vl-sort scored (function (lambda (a b) (< (car a) (car b))))) n 0)
      (princ (strcat "\nAER fields/strike areas referenced near Twp " (nth 2 sur) " Rge " (nth 3 sur) " W" (nth 4 sur) "M (hint only):"))
      (foreach s scored
	(if (< n 6)
	  (princ (strcat "\n   " (cadr s) "  " (caddr s) "  (Twp " (itoa (nth 3 s)) " Rge " (itoa (nth 4 s)) ")"))
	) ;_ end of if
	(setq n (1+ n))
      ) ;_ end of foreach
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

(defun wnh-placeholder-p (key placeholders)
  (and (not WNH_TEST_PROPS)
       (member (strcase (wnh-prop key)) placeholders))
) ;_ end of defun

(defun wnh-set-prop (key val)
  (vl-catch-all-apply
    'vla-SetCustomByKey
    (list (vla-get-SummaryInfo (vla-get-ActiveDocument (vlax-get-acad-object))) key val)
  ) ;_ end of vl-catch-all-apply
) ;_ end of defun

(defun wnh-2d (p) (list (car p) (cadr p)))


;;;=============================================================================
;;; Operator UWI HZ Strike LS-SEC-TWP-RGE, abbreviating if over the limit
(defun wnh-build-name (op uwi typ strike loc / abbr name)
  (if (not (or (member (strcase op) (mapcar 'strcase WNH_ALWAYS_SHOW_UWI))
	       (/= uwi "100")))
    (setq uwi "")
  ) ;_ end of if
  (setq name (wnh-join (list op uwi typ strike loc)))
  (if (and (> (strlen name) WNH_MAX_LENGTH)
	   (setq abbr (cdr (assoc (strcase op) WNH_OPERATOR_ABBR))))
    (setq op abbr name (wnh-join (list op uwi typ strike loc)))
  ) ;_ end of if
  (if (and (> (strlen name) WNH_MAX_LENGTH)
	   (setq abbr (cdr (assoc (strcase strike) WNH_STRIKE_ABBR))))
    (setq strike abbr name (wnh-join (list op uwi typ strike loc)))
  ) ;_ end of if
  name
) ;_ end of defun


;;;=============================================================================
;;; Find "Bottom Hole 100/5-18" labels in model space.
;;; Returns list of (key uwi ls sec twp rge point), twp/rge nil unless the
;;; label has them (100/5-18-59-24).
(defun wnh-get-bottom-holes (/ ss i e s pos uwi parts key seen lst)
  (if (setq ss (ssget "_X" (list '(0 . "MTEXT,TEXT") (cons 8 WNH_BH_LAYER) '(410 . "Model"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e	(entget (ssname ss i))
	      i	(1+ i)
	      s	(strcase (wnh-plain (wnh-text e)))
	) ;_ end of setq
	(if (and (wcmatch s "BOTTOM HOLE*/*-*") (setq pos (vl-string-search "/" s)))
	  (progn
	    (setq uwi	(last (wnh-split (substr s 1 pos) " "))
		  parts	(wnh-split (car (wnh-split (substr s (+ pos 2)) " ")) "-")
	    ) ;_ end of setq
	    (if	(>= (length parts) 2)
	      (progn
		(setq key (strcat uwi "/" (nth 0 parts) "-" (nth 1 parts)))
		(if (not (member key seen))
		  (setq	seen (cons key seen)
			lst  (cons (list key uwi (nth 0 parts) (nth 1 parts)
					 (nth 2 parts) (nth 3 parts) (wnh-dxf 10 e))
				   lst)
		  ) ;_ end of setq
		) ;_ end of if
	      ) ;_ end of progn
	    ) ;_ end of if
	  ) ;_ end of progn
	) ;_ end of if
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  (reverse lst)
) ;_ end of defun


;;;=============================================================================
;;; Same quarter labels UDP uses. Returns list of (text x y z)
(defun wnh-get-ats-labels (/ ss i e lst)
  (if (setq ss (ssget "_X" (list '(0 . "MTEXT") (cons 8 WNH_ATS_LAYER))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e	  (entget (ssname ss i))
	      i	  (1+ i)
	      lst (cons (cons (wnh-plain (wnh-text e)) (wnh-dxf 10 e)) lst)
	) ;_ end of setq
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  lst
) ;_ end of defun

;;; Twp & Rge of the closest quarter label, read the same way UDP does.
(defun wnh-twp-rge-at (pt labels / best bd d tok)
  (setq bd 1e99)
  (foreach l labels
    (setq d (distance (list (car pt) (cadr pt)) (list (cadr l) (caddr l))))
    (if (< d bd) (setq bd d best (car l)))
  ) ;_ end of foreach
  (if best
    (progn
      (setq tok (wnh-split (wnh-replace-all best "-" " ") " "))
      (if (and (nth 4 tok) (nth 5 tok)) (list (nth 4 tok) (nth 5 tok)))
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun


;;;=============================================================================
;;; Order wells as they appear in the page 1 ELEVATIONS note, else north first.
(defun wnh-order-wells (wells / ss i s e)
  (setq s "")
  (if (setq ss (ssget "_X" '((0 . "MTEXT") (-4 . "<NOT") (410 . "Model") (-4 . "NOT>"))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e (strcase (wnh-text (entget (ssname ss i))))
	      i (1+ i)
	) ;_ end of setq
	(if (wcmatch e "*ELEVATIONS*") (setq s (strcat s " " e " ")))
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  (vl-sort wells
	   (function
	     (lambda (a b / ia ib)
	       (setq ia	(wnh-find-key s (car a))
		     ib	(wnh-find-key s (car b))
	       ) ;_ end of setq
	       (cond ((and ia ib) (< ia ib))
		     (ia T)
		     (ib nil)
		     (T (> (cadr (nth 6 a)) (cadr (nth 6 b))))
	       ) ;_ end of cond
	     ) ;_ end of lambda
	   ) ;_ end of function
  ) ;_ end of vl-sort
) ;_ end of defun

;;; Position of key in s where it isn't followed by another digit (so 100/5-1
;;; doesn't match 100/5-18). Returns nil if not found.
(defun wnh-find-key (s key / pos nxt found)
  (setq pos 0)
  (while (and (not found) (setq pos (vl-string-search key s pos)))
    (setq nxt (substr s (+ pos (strlen key) 1) 1))
    (if	(wcmatch nxt "#")
      (setq pos (1+ pos))
      (setq found pos)
    ) ;_ end of if
  ) ;_ end of while
  found
) ;_ end of defun


;;;=============================================================================
;;; Show the names on the command line and in an alert
(defun wnh-report (wells / msg anyProps w n surs s)
  (setq msg "")
  (foreach w wells
    (setq n (car w))
    (setq msg (strcat msg "\n" n "   (" (itoa (strlen n)) ")"
		      (if (> (strlen n) WNH_MAX_LENGTH) "  <-- OVER 36!" "")
		      (if (cadr w) "  *" "")))
    (foreach x (nth 2 w) (setq msg (strcat msg "\n      ! " x)))
    (if (cadr w) (setq anyProps T))
    (if (setq s (nth 3 w))
      (setq s (strcat "LS " (nth 0 s) " Sec " (nth 1 s) " Twp " (nth 2 s) " Rge " (nth 3 s) " W" (nth 4 s) "M"))
    ) ;_ end of if
    (if (and s (not (member s surs))) (setq surs (append surs (list s))))
  ) ;_ end of foreach
  (if (cadr (setq s (wnh-check-strike (wnh-prop "Strike Area"))))
    (setq msg (strcat msg "\n\n! " (cadr s)))
  ) ;_ end of if
  (if surs
    (setq msg (strcat msg "\n\nSurface: " (car surs)
		      (if (cdr surs) "\n   ! Well centres are in more than one LS - check the surface line." "")))
  ) ;_ end of if
  (if anyProps
    (setq msg (strcat msg "\n\n* Twp/Rge taken from the BH drawing properties (no ATS quarter labels found)."
		      "\n   Check any bottom hole that is in a different township or range."))
  ) ;_ end of if
  (princ (strcat "\n\nWell names:" msg "\n"))
  (if (not WNH_TEST_PROPS)
    (alert (strcat "Well names for page 1:\n" msg "\n\nNext: select the existing well name lines to replace."))
  ) ;_ end of if
) ;_ end of defun


;;;=============================================================================
;;; Replace the selected name lines with the new names and shift what's below.
(defun wnh-write (names ents / anchor top bottom n0 spacing x z base below delta e s y i)
  ;; ents = list of the old name line TEXT enames; sort top first
  (setq	ents   (vl-sort ents (function (lambda (a b) (> (cadr (wnh-tpt a)) (cadr (wnh-tpt b))))))
	anchor (car ents)
	top    (cadr (wnh-tpt anchor))
	bottom (cadr (wnh-tpt (last ents)))
	x      (car (wnh-tpt anchor))
	z      (caddr (wnh-tpt anchor))
	n0     (length ents)
	spacing	(if (> n0 1) (/ (- top bottom) (1- n0)) WNH_DEFAULT_SPACING)
	delta  (* (- (length names) n0) spacing)
  ) ;_ end of setq

  ;; Lines under the names: WELL(S) ... DRILLED, LS ... line, county
  (setq below (wnh-lines-below anchor ents x bottom (* 3.5 spacing)))

  ;; New name lines, copied from the top selected line (minus any field)
  (setq	base (vl-remove-if
	       (function (lambda (p) (member (car p) '(-1 5 330 102 360))))
	       (entget anchor)
	     ) ;_ end of vl-remove-if
	i    0
  ) ;_ end of setq
  (foreach n names
    (setq y (- top (* i spacing)) i (1+ i))
    (entmake (subst (cons 1 n) (assoc 1 base)
		    (subst (list 10 x y z) (assoc 10 base)
			   (subst (list 11 x y z) (assoc 11 base) base))))
  ) ;_ end of foreach
  (foreach e ents (entdel e))

  ;; Move the lines underneath and fix WELL / WELLS
  (foreach e below
    (setq e (entget e))
    (if	(/= delta 0.0)
      (progn
	(setq e (subst (wnh-shift (assoc 10 e) delta) (assoc 10 e) e))
	(if (assoc 11 e) (setq e (subst (wnh-shift (assoc 11 e) delta) (assoc 11 e) e)))
      ) ;_ end of progn
    ) ;_ end of if
    (if	(and (= (wnh-dxf 0 e) "TEXT") (wcmatch (setq s (wnh-dxf 1 e)) "WELL*DRILLED*"))
      (setq e (subst (cons 1 (wnh-well-plural s (length names))) (assoc 1 e) e))
    ) ;_ end of if
    (entmod e)
  ) ;_ end of foreach
  (if (> (length names) n0)
    (princ (strcat "\nHeader grew by " (itoa (- (length names) n0))
		   " line(s) - check it still fits inside the page 1 box."))
  ) ;_ end of if
) ;_ end of defun

;;; Find the page 1 well name lines without the user picking them.
;;; Looks for a "PLAN SHOWING ..." title that sits inside a layout's paper
;;; (template examples parked off the sheet are ignored), then takes the TEXT
;;; lines centred under it in the same style as the first one, top down,
;;; stopping at the first line in another style (the WELL(S) ... DRILLED line).
;;; Current layout is searched first. Returns (layoutName ename ...) or nil.
(defun wnh-find-name-lines (/ lays lay found)
  (setq lays (cons (getvar "CTAB") (vl-remove (getvar "CTAB") (wnh-layout-names))))
  (while (and lays (not found))
    (setq lay (car lays) lays (cdr lays))
    (if (/= lay "Model")
      (setq found (wnh-name-lines-in lay))
    ) ;_ end of if
  ) ;_ end of while
  (if found (cons lay found))
) ;_ end of defun

(defun wnh-layout-names (/ lst)
  (foreach p (dictsearch (namedobjdict) "ACAD_LAYOUT")
    (if (= (car p) 3) (setq lst (cons (cdr p) lst)))
  ) ;_ end of foreach
  (reverse lst)
) ;_ end of defun

;;; Paper limits of a layout: ((minX minY) (maxX maxY))
(defun wnh-layout-limits (lay / d)
  (if (setq d (dictsearch (namedobjdict) "ACAD_LAYOUT"))
    (if (setq d (cdr (assoc 350 (member (cons 3 lay) d))))
      (progn
	(setq d (entget d))
	(list (wnh-2d (wnh-dxf 10 d)) (wnh-2d (wnh-dxf 11 d)))
      ) ;_ end of progn
    ) ;_ end of if
  ) ;_ end of if
) ;_ end of defun

(defun wnh-inside (p lim)
  (and lim
       (>= (car p) (car (car lim))) (<= (car p) (car (cadr lim)))
       (>= (cadr p) (cadr (car lim))) (<= (cadr p) (cadr (cadr lim))))
) ;_ end of defun

(defun wnh-name-lines-in (lay / lim ss i e title tp cands lst prevY style p gap)
  (setq lim (wnh-layout-limits lay))
  (if (setq ss (ssget "_X" (list '(0 . "TEXT") '(1 . "PLAN SHOWING*") (cons 410 lay))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e (ssname ss i) i (1+ i))
	(if (and (not title) (wnh-inside (wnh-tpt e) lim)) (setq title e))
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  (if title
    (progn
      (setq tp (wnh-tpt title))
      ;; TEXT centred on the title, below it, on the sheet
      (setq ss (ssget "_X" (list '(0 . "TEXT") (cons 410 lay))) i 0)
      (while (< i (sslength ss))
	(setq e (ssname ss i) i (1+ i) p (wnh-tpt e))
	(if (and p (not (eq e title)) (equal (car p) (car tp) 1.0)
		 (< (cadr p) (cadr tp)) (wnh-inside p lim))
	  (setq cands (cons e cands))
	) ;_ end of if
      ) ;_ end of while
      (setq cands (vl-sort cands (function (lambda (a b) (> (cadr (wnh-tpt a)) (cadr (wnh-tpt b))))))
	    prevY (cadr tp)
	    gap	  (* 2.0 WNH_DEFAULT_SPACING)
      ) ;_ end of setq
      (foreach e cands
	(setq p (wnh-tpt e))
	(cond ((not gap))			; already stopped
	      ((> (- prevY (cadr p)) gap) (setq gap nil))	; too far down
	      ((null style)
	       (setq style (wnh-dxf 7 (entget e)) lst (list e) prevY (cadr p)
		     gap (* 1.5 WNH_DEFAULT_SPACING)))
	      ((= (wnh-dxf 7 (entget e)) style) (setq lst (cons e lst) prevY (cadr p)))
	      (T (setq gap nil))			; different style - end of names
	) ;_ end of cond
      ) ;_ end of foreach
    ) ;_ end of progn
  ) ;_ end of if
  (reverse lst)
) ;_ end of defun

(defun wnh-ss->list (ss / i lst)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss)) (setq lst (cons (ssname ss i) lst) i (1+ i)))
    ) ;_ end of progn
  ) ;_ end of if
  lst
) ;_ end of defun

;;; Text in the same layout, centred on the same x, within dist under bottom
(defun wnh-lines-below (anchor ents x bottom dist / lay ss i e p lst)
  (setq lay (wnh-dxf 410 (entget anchor)))
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 410 lay))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e (ssname ss i) i (1+ i) p (wnh-tpt e))
	(if (and (not (member e ents))
		 (equal (car p) x 1.0)
		 (< (cadr p) bottom)
		 (> (cadr p) (- bottom dist)))
	  (setq lst (cons e lst))
	) ;_ end of if
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  lst
) ;_ end of defun

(defun wnh-shift (pair d) (list (car pair) (cadr pair) (- (caddr pair) d) (cadddr pair)))

(defun wnh-well-plural (s n)
  (cond	((and (> n 1) (wcmatch s "WELL *")) (strcat "WELLS" (substr s 5)))
	((and (= n 1) (wcmatch s "WELLS *")) (strcat "WELL" (substr s 6)))
	(T s)
  ) ;_ end of cond
) ;_ end of defun

;;; Point the text hangs on: alignment point unless left-justified
(defun wnh-tpt (ename / e)
  (setq e (entget ename))
  (if (and (= (wnh-dxf 0 e) "TEXT")
	   (wnh-dxf 11 e)
	   (or (/= 0 (cond ((wnh-dxf 72 e)) (0))) (/= 0 (cond ((wnh-dxf 73 e)) (0)))))
    (wnh-dxf 11 e)
    (wnh-dxf 10 e)
  ) ;_ end of if
) ;_ end of defun


;;;=============================================================================
;;; Helpers

;;; Drawing property, trimmed. WNH_TEST_PROPS (assoc list) overrides for testing.
(defun wnh-prop (key / r)
  (if WNH_TEST_PROPS
    (vl-string-trim " " (cond ((cdr (assoc key WNH_TEST_PROPS))) ("")))
    (progn
      (setq r (vl-catch-all-apply
		(function
		  (lambda (/ v)
		    (vla-GetCustomByKey
		      (vla-get-SummaryInfo (vla-get-ActiveDocument (vlax-get-acad-object)))
		      key 'v)
		    v
		  ) ;_ end of lambda
		) ;_ end of function
	      ) ;_ end of vl-catch-all-apply
      ) ;_ end of setq
      (if (or (vl-catch-all-error-p r) (null r)) "" (vl-string-trim " " r))
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

(defun wnh-dxf (k e) (cdr (assoc k e)))

;;; Full string of TEXT / MTEXT (MTEXT keeps overflow in group 3)
(defun wnh-text (e / s)
  (setq s "")
  (foreach p e (if (= (car p) 3) (setq s (strcat s (cdr p)))))
  (strcat s (wnh-dxf 1 e))
) ;_ end of defun

(defun wnh-plain (s)
  (vl-string-trim " " (wnh-replace-all (wnh-replace-all s "\\P" " ") "  " " "))
) ;_ end of defun

(defun wnh-split (str delim / pos lst)
  (while (setq pos (vl-string-search delim str))
    (setq lst (cons (substr str 1 pos) lst)
	  str (substr str (+ pos 1 (strlen delim)))
    ) ;_ end of setq
  ) ;_ end of while
  (vl-remove "" (reverse (cons str lst)))
) ;_ end of defun

(defun wnh-replace-all (str old new / pos)
  (setq pos 0)
  (while (setq pos (vl-string-search old str pos))
    (setq str (strcat (substr str 1 pos) new (substr str (+ pos 1 (strlen old))))
	  pos (+ pos (strlen new))
    ) ;_ end of setq
  ) ;_ end of while
  str
) ;_ end of defun

(defun wnh-join (lst / s)
  (setq s "")
  (foreach x lst
    (if	(and x (/= (setq x (vl-string-trim " " x)) ""))
      (setq s (if (= s "") x (strcat s " " x)))
    ) ;_ end of if
  ) ;_ end of foreach
  s
) ;_ end of defun

(prompt "\nLoaded... Well Name Header - type WNH")
(princ)
