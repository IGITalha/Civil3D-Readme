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
;;;   Existing wells on the pad        -> AER survey lines ("ERCB Wells -
;;;   (clients with Existing = T)         Directional_Lines") starting on the
;;;                                       pad; listed under the new ones, black
;;;   UWI                              -> nearby "Bottom Hole 102/5-18" label or
;;;                                       (not the UWI property); wells ending
;;;                                       in the same LSD get 100, 102, 103...
;;;                                       (existing wells first)
;;;   Strike area per well             -> looked up from the bottom hole
;;;                                       section in "Well Name Header -
;;;                                       Strike Areas.txt" (AER order data,
;;;                                       field wins); property if not found
;;;   Line order                       -> Move Up / Down in the dialog;
;;;                                       listed as on page 1 when every well
;;;                                       is already there; else new wells in
;;;                                       the ELEVATIONS note order (else
;;;                                       wellhead north to south), then
;;;                                       existing wells
;;; Fallbacks: no drill paths -> "Bottom Hole" labels (Twp/Rge from ATS
;;; quarter labels or BH props); nothing at all -> one line from BH props.
;;;
;;; Warnings in the list: point within 25 m of an LSD line, drawing label
;;; disagrees, AER bottom hole already in the LSD (UWI may need 102), well
;;; centres in more than one LS.
;;;
;;; Usage: type WNH (from any tab). A dialog lists the names with any notes;
;;; use Move Up / Move Down to change the order, then Write to page 1.
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
;;; Fit the header to the space on page 1 (shrink names if they'd run into
;;; what's below). nil = off: names keep page 1's current height and spacing.
(setq WNH_FIT nil)
(setq WNH_NAME_HEIGHT 5.0)			; name text height on Wellsite.dwt
(setq WNH_DEFAULT_SPACING 7.919)		; gap between name lines on Wellsite.dwt
(setq WNH_MIN_SCALE 0.6)			; never shrink names below 60% (3.0 high)
(setq WNH_FIT_MARGIN 2.0)			; keep the header this far above what's below it
(setq WNH_SIDE_MARGIN 12.0)			; keep names this far inside the sheet edges
(setq WNH_BH_LAYER "Drill Path Text")
(setq WNH_ATS_LAYER "ATS Labels Quarter")
(setq WNH_PATH_LAYER "Drill Path")		; well centre -> bottom hole polylines
(setq WNH_SECTION_LAYER "10-Section Labels")	; "18" over "59-24-5" at section centres
(setq WNH_EDGE_WARN 25.0)			; warn if a point is this close (m) to an LSD line

;;; ---- Clients ----------------------------------------------------------------
;;; One line per client. The Operator drawing property is matched against the
;;; first column (or the short form). A client not listed gets the defaults:
;;; no 100, new wells only, no short form.
;;;
;;;   Show 100   T = first well in the LSD shows 100  (CVE 100 HZ BERLRW ...)
;;;              nil = 100 left out, 102 / 103 shown (TOURMALINE HZ SMOKY ...)
;;;   Existing   T = existing wells on the pad are listed under the new ones,
;;;              in black
;;;   Short      AER-accepted short form, used only if a name is over 36
;;;
;;; Checked against the AER ST37 well list (wells spudded 2022 on, Nov 2026):
;;;   CVE         HZ wells: about half show 100; the IGI sheet says always
;;;   TOURMALINE  never shows 100 (0 of 609); 102/103 shown
;;;   WHITECAP    never shows 100 (0 of 471); WCP also used by the AER
;;;   ACERTA      never shows 100; AOC until 2024, ACERTA on 2026 licences
;;;
;;;  Operator       Show 100  Existing  Short
(setq WNH_CLIENTS
  '(("CVE"          T         nil       nil)
    ("TOURMALINE"   nil       T         nil)
    ("WHITECAP"     nil       nil       "WCP")
    ("ACERTA"       nil       nil       "AOC")
   )
) ;_ end of setq

;;; Existing wells (for clients with Existing = T): AER directional survey
;;; lines that start within WNH_PAD_RADIUS of a new well centre.
(setq WNH_EXISTING_LAYERS '("ERCB Wells - Directional_Lines" "well_bore"))
(setq WNH_PAD_RADIUS 100.0)

;;; Strike area lookup file. nil = look next to this .lsp / on the support
;;; path / on O:. Set a full path here if you keep it somewhere else.
(setq WNH_STRIKE_FILE nil)

;;; Strike area short forms, only used when a name is over the limit.
;;; ("FULL" . "SHORT")
(setq WNH_STRIKE_ABBR '())


;;;=============================================================================
;;; Main command
(defun c:WNH (/ *error* wells names ss msg res)
  (defun *error* (msg)
    (if	(not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nWNH error: " msg))
    ) ;_ end of if
    (command-s "_.UNDO" "_END")
    (princ)
  ) ;_ end of defun

  (setvar "CMDECHO" 0)
  (setq *wnh-strike-file* nil *wnh-page1* nil)
  (wnh-ensure-props)

  ;; Show the names in a dialog: reorder with Move Up / Down, then Write or
  ;; Cancel. If the dialog can't open, fall back to an alert + command line.
  (setq	wells (wnh-get-wells)
	msg   (wnh-report wells)
	res   (if WNH_TEST_PROPS 'nodlg (wnh-order-dialog wells))
  ) ;_ end of setq
  (cond	((null res) (princ "\nWNH cancelled - page 1 not changed.") (exit))
	((= res 'nodlg)
	 (if (not WNH_TEST_PROPS)
	   (alert (strcat "Well names for page 1:\n" msg
			  "\n\nNext, on the command line: type the order for page 1, top to bottom"
			  "\n(e.g. 2 1 3), or press Enter to keep this order. Esc cancels."))
	 ) ;_ end of if
	 (setq wells (wnh-ask-order wells)))
	(T (setq wells res))
  ) ;_ end of cond
  (setq names (mapcar 'car wells))

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
      (wnh-write wells ss)
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
;;; Each well: (name twpRgeFromProps warnings surfaceLegal bhLegal existing)
;;;   legal = (ls sec twp rge mer), nil when not worked out from the drawing
;;;
;;; Sources, best first:
;;;   1. Drill Path polylines + section labels (fully automatic), plus the
;;;      existing wells on the pad (AER survey lines) for clients with Existing = T
;;;   2. "Bottom Hole 100/5-18" labels
;;;   3. BH drawing properties (one well)
;;; Strike area: looked up per bottom hole section (wnh-strike-for).
(defun wnh-get-wells (/ op typ strike paths secs bhs ats out tr fromProps smap s sl)
  (setq	op     (wnh-prop "Operator")
	typ    (wnh-prop "HZ or DD")
	strike (car (wnh-check-strike (wnh-prop "Strike Area")))	; full name -> AER abbreviation
	paths  (wnh-drill-paths)
	secs   (wnh-section-labels)
	*wnh-header* (wnh-header-texts)
	smap   (wnh-header-strikes *wnh-header*)
  ) ;_ end of setq

  (cond
    ((and paths secs)
     ;; Existing wells always count for 100/102 numbering; they're only
     ;; listed on page 1 for clients with Existing = T
     (setq bhs (wnh-assign-uwis (append (wnh-wells-from-paths paths secs)
					(wnh-existing-wells paths secs))
				secs))
     (if (not (wnh-client-opt op 2))
       (setq bhs (vl-remove-if (function (lambda (w) (nth 10 w))) bhs))
     ) ;_ end of if
     (setq bhs (wnh-order-wells bhs)))
    ((setq bhs (wnh-get-bottom-holes))
     (setq bhs (wnh-order-wells bhs)))
    (T
     (setq bhs (list (list "" (wnh-prop "UWI") (wnh-prop "BH LS") (wnh-prop "BH Sec")
			   (wnh-prop "BH Twp") (wnh-prop "BH Rge") '(0.0 0.0 0.0)))))
  ) ;_ end of cond

  (setq ats (if (not (and paths secs)) (wnh-get-ats-labels)))
  (foreach bh bhs	; bh = (key uwi ls sec twp rge point [warnings sur bhLegal existing surPoint])
    (setq fromProps nil)
    (cond ((and (nth 4 bh) (nth 5 bh)) (setq tr (list (nth 4 bh) (nth 5 bh))))
	  ((and ats (setq tr (wnh-twp-rge-at (nth 6 bh) ats))))
	  (T (setq tr (list (wnh-prop "BH Twp") (wnh-prop "BH Rge")) fromProps T))
    ) ;_ end of cond
    (setq sl (wnh-strike-for bh tr strike smap)
	  s  (car sl)
    ) ;_ end of setq
    (setq out (cons (list (wnh-build-name op (cond ((nth 1 bh)) ("100")) typ s
					  (strcat (nth 2 bh) "-" (nth 3 bh) "-" (car tr) "-" (cadr tr)))
			  fromProps
			  (append (nth 7 bh) (cdr sl))
			  (nth 8 bh)
			  (nth 9 bh)
			  (nth 10 bh))
		    out))
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun


;;;=============================================================================
;;; Strike area for one well: (abbreviation warning...)
;;;   1. the AER order data for the bottom hole section (field wins over
;;;      strike area); a split section takes the page 1 choice if it's one
;;;      of the areas, else the first, with a warning
;;;   2. page 1, when it already shows more than one strike area
;;;   3. the Strike Area drawing property
(defun wnh-strike-for (bh tr strike smap / skey mer look prev)
  (setq	skey (strcat (nth 3 bh) "-" (car tr) "-" (cadr tr))
	mer  (cond ((if (nth 9 bh) (nth 4 (nth 9 bh)))) ((wnh-prop "Mer")))
	look (wnh-tract-strikes (nth 3 bh) (car tr) (cadr tr) mer)
	prev (cdr (assoc skey smap))
  ) ;_ end of setq
  (cond	((= (length look) 1) (list (car look)))
	(look
	 (list (if (member prev look) prev (car look))
	       (strcat "Sec " skey " is split between " (wnh-join look)
		       " - check the strike area map; fix the name on page 1 if needed"
		       " (WNH keeps it next time)")))
	(prev (list prev))
	(T (list strike))
  ) ;_ end of cond
) ;_ end of defun


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
;;; (key uwi ls sec twp rge bhPoint warnings surLegal bhLegal existing surPoint)
;;; uwi is nil unless a Bottom Hole label gives one; wnh-assign-uwis
;;; fills in the rest.
(defun wnh-wells-from-paths (paths secs / labels out bh sur lab uwi warn)
  (setq labels (wnh-get-bottom-holes))
  (foreach p paths
    (setq sur  (wnh-legal-at (car p) secs)
	  bh   (wnh-legal-at (cadr p) secs)
	  warn nil
	  lab  (wnh-nearest-label (cadr p) labels 600.0)
	  ;; Only a "Bottom Hole 102/..." label sets the UWI here. The UWI drawing
	  ;; property is one value for the whole drawing, so on a multi-well pad
	  ;; it would put 102 on every well - wnh-assign-uwis works it out instead.
	  uwi  (cadr lab)
    ) ;_ end of setq
    (setq warn (wnh-edge-warning bh))
    (if	(and lab (not (and (= (nth 2 lab) (car bh)) (= (nth 3 lab) (cadr bh)))))
      (setq warn (cons (strcat "label on the drawing says " (car lab)) warn))
    ) ;_ end of if
    (setq out (cons (list nil uwi (car bh) (cadr bh) (caddr bh) (cadddr bh) (cadr p)
			  (reverse warn) sur bh nil (car p))
		    out))
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

(defun wnh-edge-warning (bh)
  (if (< (nth 5 bh) WNH_EDGE_WARN)
    (list (strcat "bottom hole is only " (rtos (nth 5 bh) 2 0)
		  " m from an LSD line - check the LS (or road allowance)"))
  ) ;_ end of if
) ;_ end of defun


;;;=============================================================================
;;; Existing wells on the pad, from the AER directional survey lines.
;;; A line counts when one end is within WNH_PAD_RADIUS of a new well centre.
;;;   - copies of the same line are dropped
;;;   - lines that are one of the new wells (AER already has it) are dropped
;;;   - a hand-drawn path (2-3 vertices) and an AER survey line leaving the
;;;     same spot in the same direction are one well: the drawn path's end is
;;;     used (it is the licensed bottom hole) and the survey end is mentioned.
;;; Returns well records like wnh-wells-from-paths, with existing = T.
(defun wnh-existing-wells (paths secs / lines kept dropped notes out sur bh warn n)
  (setq lines (wnh-existing-lines paths))
  (foreach l lines
    (if	(not (or (vl-some (function (lambda (k) (and (< (distance (car k) (car l)) 1.0)	; copies are exact;
						     (< (distance (cadr k) (cadr l)) 1.0))))	; twin wells are ~5 m apart
			  kept)
		 (vl-some (function (lambda (p) (and (< (distance (car p) (car l)) 10.0)
						     (< (distance (cadr p) (cadr l)) 100.0))))
			  paths)))
      (setq kept (append kept (list l)))
    ) ;_ end of if
  ) ;_ end of foreach
  (foreach pl kept
    (if (<= (caddr pl) 3)
      (foreach m kept
	(if (and (> (caddr m) 3)
		 (not (member m dropped))
		 (< (distance (car pl) (car m)) 10.0)
		 (< (wnh-angle-diff pl m) (/ pi 12.0)))	; 15 degrees
	  (setq dropped (cons m dropped) notes (cons (cons pl m) notes))
	) ;_ end of if
      ) ;_ end of foreach
    ) ;_ end of if
  ) ;_ end of foreach
  (foreach l kept
    (if (not (member l dropped))
      (progn
	(setq sur  (wnh-legal-at (car l) secs)
	      bh   (wnh-legal-at (cadr l) secs)
	      warn (wnh-edge-warning bh)
	) ;_ end of setq
	(foreach x notes
	  (if (equal (car x) l)
	    (progn
	      (setq n (wnh-legal-at (cadr (cdr x)) secs))
	      (if (not (and (= (car n) (car bh)) (= (cadr n) (cadr bh))))
		(setq warn (cons (strcat "AER survey line ends in " (car n) "-" (cadr n)
					 ", the drawn path in " (car bh) "-" (cadr bh) " - check which is licensed")
				 warn))
	      ) ;_ end of if
	    ) ;_ end of progn
	  ) ;_ end of if
	) ;_ end of foreach
	(setq out (cons (list nil nil (car bh) (cadr bh) (caddr bh) (cadddr bh) (cadr l)
			      warn sur bh T (car l))
			out))
      ) ;_ end of progn
    ) ;_ end of if
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

;;; (surfacePoint bottomHolePoint vertexCount) for each AER well line that
;;; starts on the pad
(defun wnh-existing-lines (paths / centres ss i e v f l df dl lst)
  (setq centres (mapcar 'car paths))
  (foreach lay WNH_EXISTING_LAYERS
    (if (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 lay) '(410 . "Model"))))
      (progn
	(setq i 0)
	(while (< i (sslength ss))
	  (setq e (entget (ssname ss i)) i (1+ i) v nil)
	  (foreach p e (if (= (car p) 10) (setq v (cons (wnh-2d (cdr p)) v))))
	  (setq v  (reverse v)
		f  (car v)
		l  (last v)
		df (wnh-min-dist f centres)
		dl (wnh-min-dist l centres)
	  ) ;_ end of setq
	  (if (and (<= (min df dl) WNH_PAD_RADIUS) (> (distance f l) 20.0))
	    (setq lst (cons (if (<= df dl) (list f l (length v)) (list l f (length v))) lst))
	  ) ;_ end of if
	) ;_ end of while
      ) ;_ end of progn
    ) ;_ end of if
  ) ;_ end of foreach
  (reverse lst)
) ;_ end of defun

(defun wnh-min-dist (pt pts / bd)
  (setq bd 1e99)
  (foreach p pts (setq bd (min bd (distance pt p))))
  bd
) ;_ end of defun

(defun wnh-angle-diff (a b / d)
  (setq d (abs (- (angle (car a) (cadr a)) (angle (car b) (cadr b)))))
  (if (> d pi) (- (* 2.0 pi) d) d)
) ;_ end of defun


;;;=============================================================================
;;; UWI for each well: wells ending in the same LSD get 100, 102, 103 ...
;;; Existing wells take theirs first (they were licensed first), ordered by
;;; wellhead south to north; then the new wells. A UWI from a "Bottom Hole
;;; 102/..." label is kept. Sets the key (uwi/ls-sec) used for ordering.
(defun wnh-assign-uwis (wells secs / aer taken lsd used uwi warn out)
  (setq aer (wnh-aer-bottom-holes))
  (foreach w (append (wnh-sort-by-y (vl-remove-if-not (function (lambda (w) (nth 10 w))) wells) T)
		     (vl-remove-if (function (lambda (w) (nth 10 w))) wells))
    (setq lsd  (strcat (nth 2 w) "-" (nth 3 w) "-" (nth 4 w) "-" (nth 5 w))
	  used (cdr (assoc lsd taken))
	  uwi  (nth 1 w)
	  warn (nth 7 w)
    ) ;_ end of setq
    (cond
      ((and uwi (member uwi used))
       (setq warn (append warn (list (strcat "UWI " uwi " is also used by another well ending in this LSD")))))
      (uwi)
      (T
       (setq uwi (car (vl-remove-if (function (lambda (u) (member u used)))
				    '("100" "102" "103" "104" "105" "106" "107" "108" "109"))))
       (if (and (not (nth 10 w)) (/= uwi "100"))
	 (setq warn (append warn (list (strcat "UWI " uwi " - an existing well on this pad also ends in "
					       (nth 2 w) "-" (nth 3 w)))))
       ) ;_ end of if
      )
    ) ;_ end of cond
    (if	(and (not (nth 10 w)) (= uwi "100") (nth 9 w) (wnh-aer-well-in-lsd (nth 9 w) aer secs))
      (setq warn (append warn (list "an AER bottom hole is already in this LSD - UWI may need to be 102")))
    ) ;_ end of if
    (setq taken	(cons (cons lsd (cons uwi used)) (vl-remove (assoc lsd taken) taken))
	  out	(cons (append (list (strcat uwi "/" (nth 2 w) "-" (nth 3 w)) uwi)
			      (wnh-sublist w 2 5)
			      (list warn)
			      (wnh-sublist w 8 nil))
		      out)
    ) ;_ end of setq
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

;;; Wells sorted by wellhead (surface point, else bottom hole) y
(defun wnh-sort-by-y (wells up)
  (vl-sort wells
	   (function (lambda (a b / ya yb)
		       (setq ya (cadr (cond ((nth 11 a)) ((nth 6 a))))
			     yb (cadr (cond ((nth 11 b)) ((nth 6 b)))))
		       (if up (< ya yb) (> ya yb))
		     ) ;_ end of lambda
	   ) ;_ end of function
  ) ;_ end of vl-sort
) ;_ end of defun

;;; Elements start .. start+len-1 of lst (len nil = to the end)
(defun wnh-sublist (lst start len / out i)
  (setq i 0)
  (foreach x lst
    (if (and (>= i start) (or (null len) (< i (+ start len))))
      (setq out (cons x out))
    ) ;_ end of if
    (setq i (1+ i))
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
(defun wnh-update-props (wells / sur bh toks)
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
      (setq toks (wnh-split (car (car wells)) " "))
      (if (wnh-strike-known-p (nth (- (length toks) 2) toks))	; first well's strike area
	(wnh-set-prop "Strike Area" (nth (- (length toks) 2) toks))
      ) ;_ end of if
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
    (if (setq v (wnh-first-bh-strike))
      (progn
	(wnh-set-prop "Strike Area" v)
	(princ (strcat "\n  Strike Area set to " v " from the AER order data for the first bottom hole."))
      ) ;_ end of progn
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
    ) ;_ end of if (looked up / asked)
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
;;; AER field / strike area list - WNH_STRIKE_AREAS, at the bottom of this
;;; file (from AER Map-94), so there is only one file to load.
;;; OGCR 13.020(2)(c): use the designated field name, or the strike area name
;;; if not in/next to a field - or the AER-approved abbreviation.
(defun wnh-load-strike-areas () WNH_STRIKE_AREAS)

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

;;;=============================================================================
;;; Strike area lookup file: "Well Name Header - Strike Areas.txt"
;;; (built from the AER Order System data by tools/build_strike_tracts.py).
;;; One line per township:  60-3-6|1-17=RESTHA|18=SMOKY|19-29=RESTHA|...
;;; WNH looks for it, in order: WNH_STRIKE_FILE, the support path / drawing
;;; folder, the folder that Well Name Header.lsp is found in, the O: copy.

(defun wnh-strike-file (/ f)
  (if (null *wnh-strike-file*)
    (setq *wnh-strike-file*
	   (cond ((if WNH_STRIKE_FILE (findfile WNH_STRIKE_FILE)))	; (and ...) would return T, not the path
		 ((findfile "Well Name Header - Strike Areas.txt"))
		 ((if (setq f (findfile "Well Name Header.lsp"))
		    (findfile (strcat (vl-filename-directory f) "\\Well Name Header - Strike Areas.txt"))))
		 ((findfile "O:/IGI/Cad Support/Visual LISP Development/Well Name Header - Strike Areas.txt"))
		 ("")					; not found - don't search again
	   ) ;_ end of cond
    ) ;_ end of setq
  ) ;_ end of if
  (if (/= *wnh-strike-file* "") *wnh-strike-file*)
) ;_ end of defun

;;; The township's line from the file (cached), or nil
(defun wnh-strike-line (key / path fh ln found)
  (cond	((assoc key *wnh-strike-cache*) (cdr (assoc key *wnh-strike-cache*)))
	((setq path (wnh-strike-file))
	 (setq fh (open path "r"))
	 (while (and (not found) (setq ln (read-line fh)))
	   (cond ((wcmatch ln "DATE|*") (setq *wnh-strike-date* (substr ln 6)))
		 ((= (substr ln 1 (1+ (strlen key))) (strcat key "|")) (setq found ln))
	   ) ;_ end of cond
	 ) ;_ end of while
	 (close fh)
	 (setq *wnh-strike-cache* (cons (cons key found) *wnh-strike-cache*))
	 found)
  ) ;_ end of cond
) ;_ end of defun

;;; Field / strike area(s) of a section. Returns a list of abbreviations: one
;;; normally, two where the section is split between areas, nil if unknown.
(defun wnh-tract-strikes (sec twp rge mer / ln n r a b found)
  (if (and sec twp rge mer
	   (setq ln (wnh-strike-line (strcat (itoa (atoi twp)) "-" (itoa (atoi rge)) "-" (itoa (atoi mer))))))
    (progn
      (setq n (atoi sec))
      (foreach part (cdr (wnh-split ln "|"))		; "19-29=RESTHA"
	(if (and (not found) (setq r (vl-string-search "=" part)))
	  (progn
	    (setq a (wnh-split (substr part 1 r) "-")
		  b (atoi (last a))
		  a (atoi (car a))
	    ) ;_ end of setq
	    (if (<= a n b) (setq found (wnh-split (substr part (+ r 2)) "+")))
	  ) ;_ end of progn
	) ;_ end of if
      ) ;_ end of foreach
      found
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;; Strike area of the first drill path's bottom hole, or nil
(defun wnh-first-bh-strike (/ paths secs bh look)
  (if (and (setq paths (wnh-drill-paths))
	   (setq secs (wnh-section-labels))
	   (setq bh (wnh-legal-at (cadr (car paths)) secs))
	   (setq look (wnh-tract-strikes (nth 1 bh) (nth 2 bh) (nth 3 bh) (nth 4 bh))))
    (car look)
  ) ;_ end of if
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
;;; The WNH_CLIENTS line for an operator (matched on name or short form), or
;;; nil for a client not in the table (defaults: no 100, no existing wells).
(defun wnh-client (op)
  (setq op (strcase (vl-string-trim " " op)))
  (vl-some (function (lambda (c) (if (or (= (strcase (car c)) op)
					 (and (nth 3 c) (= (strcase (nth 3 c)) op)))
				   c)))
	   WNH_CLIENTS)
) ;_ end of defun

;;; One column of the client's line (1 = show 100, 2 = existing, 3 = short),
;;; nil for a client not in the table
(defun wnh-client-opt (op n / c)
  (if (setq c (wnh-client op)) (nth n c))
) ;_ end of defun

;;; Operator UWI HZ Strike LS-SEC-TWP-RGE, abbreviating if over the limit
(defun wnh-build-name (op uwi typ strike loc / abbr name)
  (setq op (strcase op))
  (if (not (or (wnh-client-opt op 1) (/= uwi "100")))
    (setq uwi "")
  ) ;_ end of if
  (setq name (wnh-join (list op uwi typ strike loc)))
  (if (and (> (strlen name) WNH_MAX_LENGTH)
	   (setq abbr (wnh-client-opt op 3))
	   (/= (strcase abbr) (strcase op)))
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
;;; Order of the lines:
;;;   - if every well is already on page 1, keep that order (so a hand-fixed
;;;     order survives running WNH again)
;;;   - otherwise new wells first, in the order of the page 1 ELEVATIONS note,
;;;     else wellhead north to south; then existing wells, wellhead south to north
(defun wnh-order-wells (wells / ranked new old)
  (setq ranked (wnh-header-ranks wells *wnh-header*))
  (if (and ranked
	   (not (member nil (mapcar 'car ranked)))
	   (not (wnh-has-repeats *wnh-header*)))		; a doubled line makes the order unreliable
    (mapcar 'cdr (vl-sort ranked (function (lambda (a b) (< (car a) (car b))))))
    (progn
      (setq new	(wnh-order-new (vl-remove-if (function (lambda (w) (nth 10 w))) wells))
	    old	(wnh-sort-by-y (vl-remove-if-not (function (lambda (w) (nth 10 w))) wells) T)
      ) ;_ end of setq
      (append new old)
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;; ((lineIndex . well) ...): where each well already is on page 1, nil if not.
;;; A line matches on its LS-SEC-TWP-RGE and on its UWI (102 ... or none).
(defun wnh-header-ranks	(wells lines / claimed out i idx loc uwi)
  (foreach w wells
    (setq loc (strcat (nth 2 w) "-" (nth 3 w) "-" (nth 4 w) "-" (nth 5 w))
	  uwi (nth 1 w)
	  i   0
	  idx nil
    ) ;_ end of setq
    (foreach l lines
      (if (and (not idx)
	       (not (member i claimed))
	       (wcmatch l (strcat "* " loc))
	       (if (= uwi "100")
		 (not (wcmatch l "*10[2-9] *"))
		 (vl-string-search (strcat uwi " ") l)))
	(setq idx i claimed (cons i claimed))
      ) ;_ end of if
      (setq i (1+ i))
    ) ;_ end of foreach
    (setq out (cons (cons idx w) out))
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

(defun wnh-has-repeats (lst)
  (and lst (or (member (car lst) (cdr lst)) (wnh-has-repeats (cdr lst))))
) ;_ end of defun

;;; Text of the current page 1 name lines, spaces tidied
(defun wnh-header-texts	()
  (mapcar (function (lambda (e) (wnh-join (wnh-split (wnh-dxf 1 (entget e)) " "))))
	  (cdr (wnh-find-name-lines)))
) ;_ end of defun

;;; Strike area per section ("SEC-TWP-RGE" . "ABBR") read off the page 1
;;; names - only when page 1 already uses more than one strike area, so a
;;; corrected Strike Area property still wins on a single-strike pad.
(defun wnh-header-strikes (lines / toks loc s lst)
  (foreach l lines
    (setq toks (wnh-split l " "))
    (if	(and (>= (length toks) 3)
	     (= (length (setq loc (wnh-split (last toks) "-"))) 4)
	     (wnh-strike-known-p (setq s (nth (- (length toks) 2) toks))))
      (setq lst (cons (cons (strcat (nth 1 loc) "-" (nth 2 loc) "-" (nth 3 loc)) s) lst))
    ) ;_ end of if
  ) ;_ end of foreach
  (if (vl-some (function (lambda (p) (/= (cdr p) (cdr (car lst))))) lst)
    (reverse lst)
  ) ;_ end of if
) ;_ end of defun

;;; Ask for the order of the lines on page 1. The names are listed numbered
;;; (see wnh-report); type the numbers top to bottom, e.g. "3 1 2" or "3,1,2".
;;; Enter keeps the order shown. Numbers left out follow in their shown order.
(defun wnh-ask-order (wells / n s nums ok out)
  (setq n (length wells))
  (if (or (< n 2) WNH_TEST_PROPS)
    wells
    (progn
      (while (not ok)
	(setq s (getstring T (strcat "
Order of the names on page 1, top to bottom - type the numbers"
				      " (e.g. 2 1 3), Enter = as shown: ")))
	(setq nums (wnh-parse-order s n))
	(if (= nums 'bad)
	  (princ (strcat "
Use each number 1-" (itoa n) " once, separated by spaces or commas."))
	  (setq ok T)
	) ;_ end of if
      ) ;_ end of while
      (if nums
	(progn
	  (setq out (mapcar (function (lambda (i) (nth (1- i) wells))) nums))
	  (foreach w wells (if (not (member w out)) (setq out (append out (list w)))))
	  (princ "
New order:")
	  (foreach w out (princ (strcat "
   " (car w))))
	  out
	) ;_ end of progn
	wells
      ) ;_ end of if
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

;;; "3 1, 2" -> (3 1 2);  "" -> nil;  anything invalid -> 'bad
(defun wnh-parse-order (s n / toks nums bad i)
  (setq toks (wnh-split (vl-string-trim " " (wnh-replace-all s "," " ")) " "))
  (foreach tk toks
    (setq i (atoi tk))
    (if (or (/= tk (itoa i)) (< i 1) (> i n) (member i nums))
      (setq bad T)
      (setq nums (append nums (list i)))
    ) ;_ end of if
  ) ;_ end of foreach
  (if bad 'bad nums)
) ;_ end of defun

;;; New wells: order of the page 1 ELEVATIONS note, else wellhead north first.
(defun wnh-order-new (wells / ss i s e)
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
		     (T (> (cadr (cond ((nth 11 a)) ((nth 6 a))))
			   (cadr (cond ((nth 11 b)) ((nth 6 b))))))
	       ) ;_ end of cond
	     ) ;_ end of lambda
	   ) ;_ end of function
  ) ;_ end of vl-sort
) ;_ end of defun

;;; Position of key ("102/5-31") in s, or for a 100 well also the bare LS-SEC
;;; ("16-36") as notes often leave the 100/ off. Returns nil if not found.
(defun wnh-find-key (s key)
  (cond	((wnh-find-word s key))
	((wcmatch key "100/*") (wnh-find-word s (substr key 5)))
  ) ;_ end of cond
) ;_ end of defun

;;; Position of word in s where it isn't part of a longer number (so 5-1
;;; doesn't match 5-18, 102/5-18 or 15-1).
(defun wnh-find-word (s word / pos nxt prv found)
  (setq pos 0)
  (while (and (not found) (setq pos (vl-string-search word s pos)))
    (setq nxt (substr s (+ pos (strlen word) 1) 1)
	  prv (if (> pos 0) (substr s pos 1) "")
    ) ;_ end of setq
    (if	(or (wcmatch nxt "#") (wcmatch prv "#,/,-"))
      (setq pos (1+ pos))
      (setq found pos)
    ) ;_ end of if
  ) ;_ end of while
  found
) ;_ end of defun


;;;=============================================================================
;;; Report and order dialog
;;; One row of the name list: name, length and flags
(defun wnh-name-row (w / n)
  (setq n (car w))
  (strcat n "   (" (itoa (strlen n)) ")"
	  (if (nth 5 w) "  existing" "")
	  (if (and (/= (wnh-prop "Operator") "")
		   (/= (car (wnh-split n " ")) (strcase (wnh-prop "Operator"))))
	    "  (short form - full name over 36)" "")
	  (if (> (strlen n) WNH_MAX_LENGTH) "  <-- OVER 36!" "")
	  (if (cadr w) "  *" ""))
) ;_ end of defun

;;; Notes for the list: each well's warnings, then general notes
(defun wnh-notes (wells / lst anyProps surs s)
  (foreach w wells
    (foreach x (nth 2 w) (setq lst (append lst (list (strcat "! " (car w) ": " x)))))
    (if (cadr w) (setq anyProps T))
    (if (setq s (nth 3 w))
      (setq s (strcat "LS " (nth 0 s) " Sec " (nth 1 s) " Twp " (nth 2 s) " Rge " (nth 3 s) " W" (nth 4 s) "M"))
    ) ;_ end of if
    (if (and s (not (member s surs))) (setq surs (append surs (list s))))
  ) ;_ end of foreach
  (if (cadr (setq s (wnh-check-strike (wnh-prop "Strike Area"))))
    (setq lst (append lst (list (strcat "! " (cadr s)))))
  ) ;_ end of if
  (if (and (/= (wnh-prop "Operator") "") (not (wnh-client (wnh-prop "Operator"))))
    (setq lst (append lst (list (strcat "! Operator " (wnh-prop "Operator")
					" isn't in the client table (WNH_CLIENTS) - using defaults: no 100, new wells only."))))
  ) ;_ end of if
  (setq lst (append lst
		    (list (if (wnh-strike-file)
			    (strcat "Strike areas looked up from each bottom hole section (AER order data "
				    (cond (*wnh-strike-date*) ("")) ").")
			    "Strike area lookup file (Well Name Header - Strike Areas.txt) not found - using the Strike Area property."))))
  (if surs
    (setq lst (append lst (list (strcat "Surface: " (car surs)))
		      (if (cdr surs) (list "! Well centres are in more than one LS - check the surface line."))))
  ) ;_ end of if
  (if anyProps
    (setq lst (append lst (list "* Twp/Rge taken from the BH drawing properties (no ATS quarter labels found)."
				"  Check any bottom hole that is in a different township or range.")))
  ) ;_ end of if
  lst
) ;_ end of defun

;;; Print the numbered list and notes on the command line; returns the text
(defun wnh-report (wells / msg k)
  (setq msg "" k 0)
  (foreach w wells
    (setq msg (strcat msg "\n" (itoa (setq k (1+ k))) ".  " (wnh-name-row w)))
  ) ;_ end of foreach
  (setq msg (strcat msg "\n"))
  (foreach x (wnh-notes wells) (setq msg (strcat msg "\n" x)))
  (princ (strcat "\n\nWell names:" msg "\n"))
  msg
) ;_ end of defun

;;; The page 1 dialog: names in order with Move Up / Move Down, the notes
;;; underneath, and Write to page 1 / Cancel. Returns the wells in the chosen
;;; order, nil if cancelled, or 'nodlg if the dialog couldn't be shown.
;;; The .dcl is written to a temp file each time, so there's only the .lsp.
(defun wnh-order-dialog (wells / fn id res)
  (setq	*wnh-dlg-wells*	wells
	fn		(wnh-dcl-file)
	id		(if fn (vl-catch-all-apply 'load_dialog (list fn)))
  ) ;_ end of setq
  (if (and (numberp id) (> id 0) (new_dialog "wnh_order" id))
    (progn
      (wnh-dlg-fill 0)
      (start_list "notes")
      (mapcar 'add_list (wnh-notes wells))
      (end_list)
      (action_tile "up" "(wnh-dlg-move -1)")
      (action_tile "down" "(wnh-dlg-move 1)")
      (action_tile "accept" "(done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (setq res (start_dialog))
      (unload_dialog id)
      (vl-file-delete fn)
      (if (= res 1) *wnh-dlg-wells*)
    ) ;_ end of progn
    (progn
      (if (and (numberp id) (> id 0)) (unload_dialog id))
      (if fn (vl-file-delete fn))
      'nodlg
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

(defun wnh-dlg-fill (sel / k)
  (setq k 0)
  (start_list "names")
  (foreach w *wnh-dlg-wells* (add_list (strcat (itoa (setq k (1+ k))) ". " (wnh-name-row w))))
  (end_list)
  (set_tile "names" (itoa sel))
) ;_ end of defun

;;; Move the selected line up (d = -1) or down (d = 1)
(defun wnh-dlg-move (d / s sel to)
  (setq s (get_tile "names"))
  (if (/= s "")
    (progn
      (setq sel	(atoi s)
	    to	(+ sel d)
      ) ;_ end of setq
      (if (and (>= to 0) (< to (length *wnh-dlg-wells*)))
	(progn
	  (setq *wnh-dlg-wells* (wnh-swap *wnh-dlg-wells* sel to))
	  (wnh-dlg-fill to)
	) ;_ end of progn
      ) ;_ end of if
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun

(defun wnh-swap (lst i j / k out)
  (setq k 0)
  (foreach x lst
    (setq out (cons (cond ((= k i) (nth j lst)) ((= k j) (nth i lst)) (T x)) out)
	  k   (1+ k)
    ) ;_ end of setq
  ) ;_ end of foreach
  (reverse out)
) ;_ end of defun

;;; Write the dialog definition to a temp .dcl and return its path
(defun wnh-dcl-file (/ fn fh)
  (if (and (setq fn (vl-filename-mktemp "wnh" nil ".dcl"))
	   (setq fh (open fn "w")))
    (progn
      (foreach l
	'("wnh_order : dialog {"
	  "  label = \"Well Name Header - page 1\";"
	  "  : text { value = \"Well names, top to bottom.  Pick a line and use Move Up / Move Down to change the order.\"; }"
	  "  : row {"
	  "    : list_box { key = \"names\"; width = 72; height = 14; fixed_width_font = true; }"
	  "    : column { fixed_height = true;"
	  "      : button { key = \"up\"; label = \"Move &Up\"; width = 14; fixed_width = true; }"
	  "      : button { key = \"down\"; label = \"Move &Down\"; width = 14; fixed_width = true; }"
	  "    }"
	  "  }"
	  "  : text { value = \"Notes\"; }"
	  "  : list_box { key = \"notes\"; width = 90; height = 9; fixed_width_font = true; }"
	  "  : row { alignment = centered; fixed_width = true;"
	  "    : button { key = \"accept\"; label = \"&Write to page 1\"; is_default = true; width = 20; fixed_width = true; }"
	  "    : button { key = \"cancel\"; label = \"Cancel\"; is_cancel = true; width = 12; fixed_width = true; }"
	  "  }"
	  "}")
	(write-line l fh)
      ) ;_ end of foreach
      (close fh)
      fn
    ) ;_ end of progn
  ) ;_ end of if
) ;_ end of defun


;;;=============================================================================
;;; Replace the name lines with the new names and shift what's below.
;;; wells = list from wnh-get-wells; existing wells are written ByLayer (black).
;;;
;;; Fitting: the names start at the standard size (WNH_NAME_HEIGHT, spaced
;;; WNH_DEFAULT_SPACING). If the whole header - names plus the WELL(S)
;;; DRILLED / LS / county lines - would run into whatever is below it on the
;;; sheet (legend, tables, viewport ...), or a name is wider than the sheet,
;;; text height and spacing are shrunk together to fit, down to WNH_MIN_SCALE.
(defun wnh-write (wells ents / names anchor top bottom n0 oldsp x z base below delta e s y i b
		  lay oldH topEdge blk floor room scale h sp wmax lim avail tight)
  ;; ents = list of the old name line TEXT enames; sort top first
  (setq	names  (mapcar 'car wells)
	ents   (vl-sort ents (function (lambda (a b) (> (cadr (wnh-tpt a)) (cadr (wnh-tpt b))))))
	anchor (car ents)
	top    (cadr (wnh-tpt anchor))
	bottom (cadr (wnh-tpt (last ents)))
	x      (car (wnh-tpt anchor))
	z      (caddr (wnh-tpt anchor))
	n0     (length ents)
	oldsp  (wnh-line-spacing ents)
  ) ;_ end of setq

  ;; Lines under the names: WELL(S) ... DRILLED, LS ... line, county
  (setq below (wnh-lines-below anchor ents x bottom (* 1.5 WNH_DEFAULT_SPACING)))

  ;; New name lines, copied from the top line with a colour set (the new
  ;; well colour), minus any field
  (setq	base	(vl-remove-if
		  (function (lambda (p) (member (car p) '(-1 5 330 102 360))))
		  (entget (cond ((vl-some (function (lambda (e) (if (assoc 62 (entget e)) e))) ents))
				(anchor)))
		) ;_ end of vl-remove-if
	lay	(wnh-dxf 410 base)
	oldH	(cond ((wnh-dxf 40 (entget anchor))) (WNH_NAME_HEIGHT))
  ) ;_ end of setq
  ;; entdel only works on the current tab
  (if (/= (getvar "CTAB") lay) (setvar "CTAB" lay))
  (setq
	topEdge	(+ top (/ oldH 2.0))			; top of the first name stays put
	blk	(wnh-block-bottom below (- bottom (/ oldH 2.0)))	; bottom of the whole header now
	floor	(wnh-floor lay (append ents below) blk)
	scale	1.0
  ) ;_ end of setq

  ;; Height: lines below keep their distance from the last name's bottom edge,
  ;; so the header bottom = topEdge - (n-1)*sp - h - (gap from last name to blk)
  (if floor
    (progn
      (setq room (- topEdge (- (- bottom (/ oldH 2.0)) blk) floor WNH_FIT_MARGIN)
	    scale (min scale (/ room (+ WNH_NAME_HEIGHT (* (1- (length names)) WNH_DEFAULT_SPACING))))
      ) ;_ end of setq
    ) ;_ end of progn
  ) ;_ end of if
  ;; Width: the widest name must fit across the sheet
  (setq	wmax  (apply 'max (mapcar (function (lambda (n) (wnh-text-width n base WNH_NAME_HEIGHT))) names))
	lim   (wnh-layout-limits lay)
  ) ;_ end of setq
  (if (and lim wmax (> wmax 0.0))
    (progn
      (setq avail (- (* 2.0 (min (- x (car (car lim))) (- (car (cadr lim)) x))) (* 2.0 WNH_SIDE_MARGIN)))
      (if (> wmax avail) (setq scale (min scale (/ avail wmax))))
    ) ;_ end of progn
  ) ;_ end of if
  (if (< scale WNH_MIN_SCALE) (setq scale WNH_MIN_SCALE tight T))
  (if WNH_FIT
    (setq h  (* WNH_NAME_HEIGHT scale)
	  sp (* WNH_DEFAULT_SPACING scale))
    (setq h	oldH				; fitting off: keep page 1's size
	  sp	oldsp
	  scale	1.0
	  tight	nil)
  ) ;_ end of if
  (setq
	top   (- topEdge (/ h 2.0))
	delta (+ (- bottom (- top (* (1- (length names)) sp))) (/ (- h oldH) 2.0))	; how far the lines below move down
	i     0
  ) ;_ end of setq

  (foreach w wells
    (setq y (- top (* i sp))
	  i (1+ i)
	  b (if (nth 5 w) (vl-remove (assoc 62 base) base) base)
	  b (subst (cons 40 h) (assoc 40 b) b)
    ) ;_ end of setq
    (entmake (subst (cons 1 (car w)) (assoc 1 b)
		    (subst (list 10 x y z) (assoc 10 b)
			   (subst (list 11 x y z) (assoc 11 b) b))))
  ) ;_ end of foreach
  (foreach e ents (entdel e))
  (setq *wnh-fit* (list scale h tight floor blk))

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
  (cond	(tight
	 (princ (strcat "\nWNH: names shrunk to the smallest allowed size (" (rtos h 2 2)
			") and the header still doesn't fit - check page 1."))
	 (if (not WNH_TEST_PROPS)
	   (alert (strcat "The well names are at the smallest size (" (rtos h 2 2) " high) and the header\n"
			  "still runs into what's below it on page 1.\n\n"
			  "Move the table / legend under the header down, or use the Multi Well page 1,\n"
			  "then run WNH again - it will make the names as big as the space allows."))
	 ) ;_ end of if
	)
	((< scale 0.999)
	 (princ (strcat "\nWNH: names set to height " (rtos h 2 2) " (" (itoa (fix (+ 0.5 (* 100 scale))))
			"% of standard) to fit the space on page 1.")))
  ) ;_ end of cond
) ;_ end of defun

;;; Lowest edge of the header block: the lowest line underneath, or the
;;; bottom of the names if there's nothing underneath
(defun wnh-block-bottom	(below namesBottom / lo e)
  (setq lo namesBottom)
  (foreach en below
    (setq e  (entget en)
	  lo (min lo (- (cadr (wnh-tpt en)) (cond ((wnh-dxf 40 e)) (0.0))))
    ) ;_ end of setq
  ) ;_ end of foreach
  lo
) ;_ end of defun

;;; The highest thing on the sheet that sits below the header (legend, tables,
;;; boxes, viewports, notes ...): the floor the header must stay above.
;;; Returns its top y, or nil if nothing is below.
(defun wnh-floor (lay skip ceiling / ss i en e typ top lst floor lim)
  (setq lim (wnh-layout-limits lay))
  (if (setq ss (ssget "_X" (list (cons 410 lay))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq en (ssname ss i) i (1+ i) e (entget en) typ (wnh-dxf 0 e) top nil)
	(if (and (not (member en skip))
		 (or (null lim) (null (wnh-dxf 10 e))	; notes parked off the sheet don't count
		     (wnh-inside (wnh-2d (wnh-dxf 10 e)) lim))
		 (wnh-layer-prints-p (wnh-dxf 8 e)))	; nor do No Plot / off / frozen layers
	  (cond	((= typ "VIEWPORT")
		 (if (/= (wnh-dxf 69 e) 1)		; 1 = the sheet itself
		   (setq top (+ (cadr (wnh-dxf 10 e)) (/ (wnh-dxf 41 e) 2.0)))))
		((member typ '("TEXT" "MTEXT"))
		 (setq top (+ (cadr (wnh-tpt en)) (cond ((wnh-dxf 40 e)) (0.0)))))
		((member typ '("LINE" "LWPOLYLINE"))
		 (setq lst nil)
		 (foreach p e (if (member (car p) '(10 11)) (setq lst (cons (caddr p) lst))))
		 (if lst (setq top (apply 'max lst))))
		((member typ '("INSERT" "ACAD_TABLE" "POINT"))
		 (setq top (cadr (wnh-dxf 10 e))))
	  ) ;_ end of cond
	) ;_ end of if
	;; only things wholly below the header count
	(if (and top (< top ceiling) (or (null floor) (> top floor)))
	  (setq floor top *wnh-floor-ent* en)		; remembered for checking
	) ;_ end of if
      ) ;_ end of while
    ) ;_ end of progn
  ) ;_ end of if
  floor
) ;_ end of defun

;;; Does this layer show up on the printed plan? Not if it's off, frozen, set
;;; not to plot, Defpoints, or named like "No Plot".
(defun wnh-layer-prints-p (name / e)
  (and name
       (not (wcmatch (strcase name) "DEFPOINTS,*NO PLOT*,*NOPLOT*,*NON-PLOT*"))
       (setq e (tblobjname "LAYER" name))
       (setq e (entget e))
       (= 0 (logand 1 (cond ((wnh-dxf 70 e)) (0))))	; not frozen
       (> (cond ((wnh-dxf 62 e)) (7)) 0)		; not off
       (/= 0 (cond ((wnh-dxf 290 e)) (1)))		; plottable
  ) ;_ end of and
) ;_ end of defun

;;; Width of a name at height h in the name lines' text style
(defun wnh-text-width (str base h / tb)
  (if (setq tb (textbox (list (cons 1 str) (cons 40 h)
			      (cons 7 (cond ((wnh-dxf 7 base)) ("STANDARD")))
			      (cons 41 (cond ((wnh-dxf 41 base)) (1.0))))))
    (- (car (cadr tb)) (car (car tb)))
    0.0
  ) ;_ end of if
) ;_ end of defun

;;; Typical gap between the name lines (median, so a stray duplicate line
;;; doesn't squash the header); the template spacing for a single line.
(defun wnh-line-spacing	(ents / ys gaps g)
  (setq ys (mapcar (function (lambda (e) (cadr (wnh-tpt e)))) ents))
  (while (cdr ys)
    (setq gaps (cons (- (car ys) (cadr ys)) gaps) ys (cdr ys))
  ) ;_ end of while
  (setq gaps (mapcar (function (lambda (i) (nth i gaps))) (vl-sort-i gaps '<)))	; vl-sort drops repeats
  (if (and gaps
	   (setq g (nth (/ (length gaps) 2) gaps))
	   (> g (* 0.5 WNH_DEFAULT_SPACING)))
    g
    WNH_DEFAULT_SPACING
  ) ;_ end of if
) ;_ end of defun

;;; Find the page 1 well name lines without the user picking them.
;;; Looks for a "PLAN SHOWING ..." title that sits inside a layout's paper
;;; (template examples parked off the sheet are ignored), then takes the TEXT
;;; lines centred under it in the same style as the first one, top down,
;;; stopping at the first line in another style (the WELL(S) ... DRILLED line).
;;; Which layout: the current one if it's a page 1; else the only page 1; else
;;; (a fresh template has several - Crown/Freehold, Single/Multi ...) you pick
;;; from a numbered list, once per WNH run. Returns (layoutName ename ...) or nil.
(defun wnh-find-name-lines (/ lay found cands n k)
  (cond	((and *wnh-page1* (setq found (wnh-name-lines-in *wnh-page1*)))
	 (setq lay *wnh-page1*))
	((and (/= (getvar "CTAB") "Model") (setq found (wnh-name-lines-in (getvar "CTAB"))))
	 (setq lay (getvar "CTAB")))
	(T
	 (foreach l (wnh-layout-names)
	   (if (and (/= l "Model") (wnh-name-lines-in l)) (setq cands (append cands (list l))))
	 ) ;_ end of foreach
	 (cond ((null cands))
	       ((or (null (cdr cands)) WNH_TEST_PROPS) (setq lay (car cands)))
	       (T
		(princ "\nMore than one page 1 layout in this drawing:")
		(setq n 0)
		(foreach l cands (princ (strcat "\n  " (itoa (setq n (1+ n))) ". " l)))
		(setq k 0)
		(while (not (<= 1 k n))
		  (initget 6)			; no zero / negative
		  (setq k (cond ((getint (strcat "\nWhich one gets the well names? [1-" (itoa n) "] <1>: "))) (1)))
		  (if (> k n) (princ "\nPick a number from the list."))
		) ;_ end of while
		(setq lay (nth (1- k) cands)))
	 ) ;_ end of cond
	 (if lay (setq found (wnh-name-lines-in lay)))
	)
  ) ;_ end of cond
  (if found (progn (setq *wnh-page1* lay) (cons lay found)))
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
	      ((not (wnh-name-line-p (wnh-dxf 1 (entget e)))) (setq gap nil))	; not a well name
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

;;; Does this text look like a well name line? It must end in a location
;;; (5-18-59-24) or the template placeholder (X-XX-XX-XX). Keeps WNH off
;;; other "PLAN SHOWING" pages such as the Participant Involvement Map.
(defun wnh-name-line-p (s)
  (and s (wcmatch (strcase (vl-string-trim " " s)) "*#-#*-#*-#*,*X-XX-XX-XX"))
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

;;; Text in the same layout, centred on the same x, under the names: followed
;;; down line by line (WELL(S) DRILLED, LS line, county), stopping at the first
;;; gap bigger than dist - so it works whatever size the names are.
(defun wnh-lines-below (anchor ents x bottom dist / lay ss i e p cands prevY lst)
  (setq lay (wnh-dxf 410 (entget anchor)))
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 410 lay))))
    (progn
      (setq i 0)
      (while (< i (sslength ss))
	(setq e (ssname ss i) i (1+ i) p (wnh-tpt e))
	(if (and (not (member e ents))
		 (equal (car p) x 1.0)
		 (< (cadr p) bottom))
	  (setq cands (cons e cands))
	) ;_ end of if
      ) ;_ end of while
      (setq prevY bottom)
      (foreach e (vl-sort cands (function (lambda (a b) (> (cadr (wnh-tpt a)) (cadr (wnh-tpt b))))))
	(if (and prevY (<= (- prevY (cadr (wnh-tpt e))) dist))
	  (setq lst (cons e lst) prevY (cadr (wnh-tpt e)))
	  (setq prevY nil)				; gap too big - stop
	) ;_ end of if
      ) ;_ end of foreach
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

;;;=============================================================================
;;; AER Strike Areas - official field / strike area names and abbreviations
;;; Source: AER Map-94 "Map of Alberta Strike Areas", Field Strike ListsYE2026.xlsx
;;;         https://www.aer.ca/documents/catalog/Map94_Strike_Areas.zip (downloaded 2026-11-25)
;;; Each entry: ("ABBREVIATION" "FULL NAME" twp rge mer) - twp/rge/mer is the
;;; reference township AER lists for the field, NOT its full extent.
;;; Where AER's own sheets disagree on an abbreviation, both spellings are listed.
;;; Regenerate yearly from the new Map-94 zip.
;;;=============================================================================

(setq WNH_STRIKE_AREAS
  '(
    ("ABEE" "ABEE" 61 22 4)
    ("ACADIA" "ACADIA" 26 4 4)
    ("ACH" "ACHESON" 52 26 4)
    ("ACHE" "ACHESON EAST" 52 25 4)
    ("ADAMS" "ADAMS" 71 8 5)
    ("ADEN" "ADEN" 1 9 4)
    ("AERIAL" "AERIAL" 29 18 4)
    ("AETNA" "AETNA" 2 25 4)
    ("AKUINU" "AKUINU" 66 3 5)
    ("ALBERS" "ALBERS" 42 7 4)
    ("ALCOM" "ALCOMDALE" 57 26 4)
    ("ALDSON" "ALDERSON" 15 11 4)
    ("ALEX" "ALEXANDER" 56 27 4)
    ("ALIX" "ALIX" 40 23 4)
    ("ALKALI" "ALKALI" 24 5 4)
    ("ALPEN" "ALPEN" 63 19 4)
    ("ALSASK" "ALSASK" 27 1 4)
    ("ALSIKE" "ALSIKE" 49 2 5)
    ("ALTARIO" "ALTARIO" 35 1 4)
    ("AMADOU" "AMADOU" 73 20 4)
    ("AMBER" "AMBER" 115 7 6)
    ("AMELIA" "AMELIA" 10 27 4)
    ("AMIGO" "AMIGO" 119 8 6)
    ("ANATOLE" "ANATOLE" 31 3 4)
    ("ANDERSN" "ANDERSON" 50 23 5)
    ("ANKER" "ANKERTON" 44 15 4)
    ("ANNA" "ANNA" 120 10 6)
    ("ANSELL" "ANSELL" 52 20 5)
    ("ANTEN" "ANTE CREEK NORTH" 67 23 5)
    ("ANTLOP" "ANTELOPE" 30 1 4)
    ("ANTHONY" "ANTHONY" 83 24 5)
    ("ANTLER" "ANTLER" 48 24 5)
    ("APHRODTS" "APHRODITES" 14 1 5)
    ("ARMADA" "ARMADA" 16 19 4)
    ("ARM" "ARMISIE" 52 25 4)
    ("ARMIT" "ARMITAGE" 74 13 4)
    ("ARNESON" "ARNESON" 25 2 4)
    ("ARTLAND" "ARTLAND" 44 2 4)
    ("ARVILLA" "ARVILLA" 58 27 4)
    ("ASH" "ASHMONT" 60 11 4)
    ("ASTOTIN" "ASTOTIN" 55 18 4)
    ("ATHA" "ATHABASCA" 66 23 4)
    ("ATHAE" "ATHABASCA EAST" 66 22 4)
    ("ATIK" "ATIKAMIK" 84 6 5)
    ("ATIM" "ATIM" 54 26 4)
    ("ATL-BUFF" "ATLEE-BUFFALO" 21 6 4)
    ("ATMORE" "ATMORE" 67 17 4)
    ("BADGER" "BADGER" 16 18 4)
    ("BAIN" "BAIN" 3 4 4)
    ("BANTRY" "BANTRY" 18 13 4)
    ("BAPTI" "BAPTISTE" 67 22 4)
    ("BARE" "BARE" 3 3 4)
    ("BARK" "BARK" 121 7 6)
    ("BARNEY" "BARNEY" 80 20 4)
    ("BARONS" "BARONS" 12 23 4)
    ("BARRH" "BARRHEAD" 58 5 5)
    ("BART" "BARTMAN" 25 9 4)
    ("BASHAW" "BASHAW" 42 22 4)
    ("BASING" "BASING" 48 20 5)
    ("BATTLE" "BATTLE" 46 20 4)
    ("BATTLEN" "BATTLE NORTH" 46 20 4)
    ("BEATON" "BEATON" 88 2 6)
    ("BVALN" "BEAUVALLON" 53 10 4)
    ("BEAVX" "BEAVER CROSSING" 62 1 4)
    ("BVHL" "BEAVERHILL LAKE" 52 19 4)
    ("BELLIS" "BELLIS" 59 15 4)
    ("BELLOY" "BELLOY" 78 1 6)
    ("BELL" "BELLSHILL LAKE" 41 12 4)
    ("BENTLEY" "BENTLEY" 58 7 4)
    ("BENTON" "BENTON" 28 3 4)
    ("BERLR" "BERLAND RIVER" 59 23 5)
    ("BERLRW" "BERLAND RIVER WEST" 58 25 5)
    ("BERRY" "BERRY" 27 12 4)
    ("BERWYN" "BERWYN" 82 25 5)
    ("BESSIE" "BESSIE" 62 15 5)
    ("BEZAN" "BEZANSON" 71 3 6)
    ("BIGA" "BIG ARROW" 99 5 6)
    ("BIGB" "BIG BEND" 66 27 4)
    ("BIGCO" "BIG COULEE" 67 23 4)
    ("BIGHORN" "BIGHORN" 43 17 5)
    ("BIGORAY" "BIGORAY" 51 8 5)
    ("BIGSTONE" "BIGSTONE" 61 22 5)
    ("BILAW" "BILAWCHUK" 80 9 6)
    ("BIND" "BINDLOSS" 23 4 4)
    ("BIRCH" "BIRCH" 50 11 4)
    ("BISONLK" "BISON LAKE" 95 15 5)
    ("BISTCHO" "BISTCHO" 122 4 6)
    ("BITTRNLK" "BITTERN LAKE" 46 22 4)
    ("BLACK" "BLACK" 110 9 6)
    ("BLKDIAM" "BLACK DIAMOND" 20 2 5)
    ("BLACKFT" "BLACKFOOT" 22 23 4)
    ("BLKST" "BLACKSTONE" 45 16 5)
    ("BLANSKY" "BLANSKY" 1 2 4)
    ("BLOOD" "BLOOD" 6 22 4)
    ("BLUEB" "BLUEBERRY" 82 7 6)
    ("BLUERDGE" "BLUERIDGE" 59 10 5)
    ("BOGGY" "BOGGY LAKE" 30 6 5)
    ("BOLLOQUE" "BOLLOQUE" 64 26 4)
    ("BONANZA" "BONANZA" 81 12 6)
    ("BONDISS" "BONDISS" 64 15 4)
    ("BGLEN" "BONNIE GLEN" 47 27 4)
    ("BVILLE" "BONNYVILLE" 60 5 4)
    ("BORDER" "BORDER" 42 5 4)
    ("BDAILE" "BORRADAILE" 51 5 4)
    ("BOTHA" "BOTHA" 98 5 6)
    ("BOTTREL" "BOTTREL" 28 5 5)
    ("BOUCHER" "BOUCHER" 79 4 6)
    ("BDYLKS" "BOUNDARY LAKE SOUTH" 84 12 6)
    ("BOUVIER" "BOUVIER" 70 24 4)
    ("BI" "BOW ISLAND" 11 11 4)
    ("BOYER" "BOYER" 103 22 5)
    ("BRANCH" "BRANCH" 2 19 4)
    ("BRAZR" "BRAZEAU RIVER" 45 13 5)
    ("BREMNER" "BREMNER" 78 4 6)
    ("BRIDGE" "BRIDGE" 57 7 5)
    ("BRIKER" "BRIKER" 46 3 4)
    ("BRINT" "BRINTNELL" 81 23 4)
    ("BRITTS" "BRITTS" 96 17 5)
    ("BRONSON" "BRONSON" 57 17 5)
    ("BROOKS" "BROOKS" 18 14 4)
    ("BROWNCK" "BROWN CREEK" 44 17 5)
    ("BRUCE" "BRUCE" 47 16 4)
    ("BRULE" "BRULE" 50 26 5)
    ("BUCHNN" "BUCHANAN CREEK" 91 21 5)
    ("BUFFLK" "BUFFALO LAKE" 39 21 4)
    ("BUICK" "BUICK" 90 2 6)
    ("BURDETT" "BURDETT" 9 10 4)
    ("BURMIS" "BURMIS" 7 3 5)
    ("BURNT" "BURNT TIMBER" 31 9 5)
    ("CABINCK" "CABIN CREEK" 55 3 6)
    ("CACHE" "CACHE" 58 12 4)
    ("CADOTTE" "CADOTTE" 86 19 5)
    ("CALAIS" "CALAIS" 70 25 5)
    ("CALL LK" "CALLING LAKE" 71 18 4)
    ("CALLS" "CALLING LAKE SOUTH" 70 22 4)
    ("CALLW" "CALLING LAKE WEST" 71 20 4)
    ("CAMERH" "CAMERON HILLS" 124 23 5)
    ("CAMAO" "CAMPBELL-NAMAO" 54 25 4)
    ("CANAL" "CANAL" 70 23 4)
    ("CANARD" "CANARD" 57 9 4)
    ("CAPRON" "CAPRON" 26 2 4)
    ("CAJOU" "CARCAJOU" 102 14 5)
    ("CARDIFF" "CARDIFF" 54 2 5)
    ("CARIBOU" "CARIBOU" 62 10 5)
    ("CARIBLK" "CARIBOU LAKE" 117 13 5)
    ("CARM" "CARMANGAY" 13 22 4)
    ("CAROL" "CAROLINE" 35 6 5)
    ("CARROT" "CARROT CREEK" 52 12 5)
    ("CARSON" "CARSON CREEK" 61 12 5)
    ("CARSONN" "CARSON CREEK NORTH" 62 12 5)
    ("CARVEL" "CARVEL" 53 2 5)
    ("CASLAN" "CASLAN" 65 17 4)
    ("CAVALIER" "CAVALIER" 24 23 4)
    ("CECIL" "CECIL" 84 8 6)
    ("CEREAL" "CEREAL" 26 7 4)
    ("CESS" "CESSFORD" 25 13 4)
    ("CHAIN" "CHAIN" 33 17 4)
    ("CHAMBRLAN" "CHAMBERLAIN" 52 23 4)
    ("CHMBRLAN" "CHAMBERLAIN" 52 23 4)
    ("CHAMBERS" "CHAMBERS" 41 10 5)
    ("CHANDLER" "CHANDLER" 59 2 4)
    ("CHARD" "CHARD" 79 6 4)
    ("CHARLIE" "CHARLIE" 89 5 6)
    ("CHARL LK" "CHARLOTTE LAKE" 60 4 4)
    ("CHARM" "CHARM" 103 9 6)
    ("CHARRON" "CHARRON" 69 16 4)
    ("CHANCY" "CHAUNCEY" 15 24 4)
    ("CHAUVIN" "CHAUVIN" 43 1 4)
    ("CHAUVINS" "CHAUVIN SOUTH" 42 2 4)
    ("CHERHILL" "CHERHILL" 56 5 5)
    ("CHERPETA" "CHERPETA" 74 19 4)
    ("CHERRY" "CHERRY" 9 13 4)
    ("CHESTER" "CHESTER" 96 20 5)
    ("CHICKDEE" "CHICKADEE" 62 16 5)
    ("CHIGWELL" "CHIGWELL" 41 24 4)
    ("CHIGWL N" "CHIGWELL NORTH" 42 24 4)
    ("CHIME" "CHIME" 61 5 6)
    ("CHINCO" "CHIN COULEE" 7 14 4)
    ("CHNCHAGA" "CHINCHAGA" 97 6 6)
    ("CHINIKI" "CHINIKI" 24 7 5)
    ("CHINOOK" "CHINOOK" 29 8 4)
    ("CHINOOKR" "CHINOOK" 29 8 4)
    ("CHINOOKR" "CHINOOK RIDGE" 65 13 6)
    ("CHISHOLM" "CHISHOLM" 68 1 5)
    ("CHOKIO" "CHOKIO" 6 27 4)
    ("CINDY" "CINDY" 77 1 6)
    ("CLAIR" "CLAIR" 73 5 6)
    ("CLARES" "CLARESHOLM" 13 26 4)
    ("CLAY" "CLAY" 59 14 4)
    ("CLAYHRST" "CLAYHURST" 83 5 6)
    ("CLAYHURST" "CLAYHURST" 83 5 6)
    ("CLEARH" "CLEAR HILLS" 87 11 6)
    ("CLEAR PR" "CLEAR PRAIRIE" 91 12 6)
    ("CLEARW" "CLEARWATER" 35 12 5)
    ("CLIVE" "CLIVE" 40 24 4)
    ("CLYDEN" "CLYDEN" 75 13 4)
    ("COALDALE" "COALDALE" 8 20 4)
    ("COALDL" "COALDALE" 8 20 4)
    ("COCHRANE" "COCHRANE" 26 4 5)
    ("COLDLK" "COLD LAKE" 63 2 4)
    ("COLEMAN" "COLEMAN" 9 4 5)
    ("COLIN" "COLINTON" 64 20 4)
    ("COLORADO" "COLORADO" 90 4 6)
    ("COLUMBIA" "COLUMBIA" 46 16 5)
    ("COMPEER" "COMPEER" 33 2 4)
    ("COMREY" "COMREY" 1 7 4)
    ("CONKLIN" "CONKLIN" 75 7 4)
    ("CONNEMRA" "CONNEMARA" 16 27 4)
    ("CONNORS" "CONNORSVILLE" 25 15 4)
    ("CONRAD" "CONRAD" 5 15 4)
    ("COOKLK" "COOKING LAKE" 52 22 4)
    ("CORBETT" "CORBETT" 61 7 5)
    ("CORNER" "CORNER" 80 9 4)
    ("CORNWALL" "CORNWALL" 70 26 5)
    ("CORRIN" "CORRIN" 61 13 4)
    ("COUNTESS" "COUNTESS" 20 16 4)
    ("COUTTS" "COUTTS" 1 16 4)
    ("COYOTE" "COYOTE" 28 15 4)
    ("CRAIGEND" "CRAIGEND" 64 13 4)
    ("CRAIGND" "CRAIGEND" 64 13 4)
    ("CRAIGML" "CRAIGMYLE" 32 17 4)
    ("CRAN" "CRANBERRY" 96 4 6)
    ("CRESSDAY" "CRESSDAY" 3 1 4)
    ("CROOKED" "CROOKED" 69 23 4)
    ("CRKD RPS" "CROOKED RAPIDS" 89 12 4)
    ("CROSS" "CROSSFIELD" 26 1 5)
    ("CROSSE" "CROSSFIELD EAST" 29 1 5)
    ("CROW" "CROW" 4 12 4)
    ("CULP" "CULP" 79 24 5)
    ("CUTPICK" "CUTPICK" 60 7 6)
    ("CYGNET" "CYGNET" 37 28 4)
    ("CYPRESS" "CYPRESS" 7 1 4)
    ("CZAR" "CZAR" 41 5 4)
    ("DALEHST" "DALEHURST" 53 23 5)
    ("DAPHNE" "DAPHNE" 96 11 4)
    ("DAPP" "DAPP" 62 26 4)
    ("DARWIN" "DARWIN" 94 18 5)
    ("DAVEY" "DAVEY" 34 27 4)
    ("DAWN" "DAWN" 80 26 5)
    ("DAWSON" "DAWSON" 80 16 5)
    ("DEADW" "DEADWOOD" 91 23 5)
    ("DEANNE" "DEANNE" 38 11 5)
    ("DECRENE" "DECRENE" 71 2 5)
    ("DEDE" "DEDE" 92 5 6)
    ("DEEP" "DEEP" 65 3 5)
    ("DELBON" "DEL BONITA" 1 21 4)
    ("DELIA" "DELIA" 32 18 4)
    ("DEMAY" "DEMAY" 48 19 4)
    ("DERWENT" "DERWENT" 54 7 4)
    ("DESMAR" "DESMARAIS" 80 25 4)
    ("DEVENISH" "DEVENISH" 75 8 4)
    ("DEVIL" "DEVIL" 71 15 5)
    ("DEWBERRY" "DEWBERRY" 53 4 4)
    ("DICKINS" "DICKINS" 120 5 6)
    ("DILLON" "DILLON" 76 2 4)
    ("DIMSD" "DIMSDALE" 71 7 6)
    ("DINA" "DINA" 45 1 4)
    ("DINANT" "DINANT" 47 19 4)
    ("DIVIDE" "DIVIDE" 82 13 4)
    ("DIXONVLE" "DIXONVILLE" 87 1 6)
    ("DIZZY" "DIZZY" 121 20 5)
    ("DOBSON" "DOBSON" 29 9 4)
    ("DOE" "DOE" 81 12 6)
    ("DOIG" "DOIG" 91 11 6)
    ("DOLCY" "DOLCY" 41 4 4)
    ("DONALDA" "DONALDA" 41 18 4)
    ("DOREN" "DORENLEE" 43 20 4)
    ("DORIS" "DORIS" 63 6 5)
    ("DOSBURN" "DOSBURN" 1 3 4)
    ("DOUCET" "DOUCETTE" 78 2 5)
    ("DOVER" "DOVER" 93 12 4)
    ("DOWLK" "DOWLING LAKE" 32 15 4)
    ("DRIFT" "DRIFTPILE" 73 12 5)
    ("DRIFTW" "DRIFTWOOD" 77 22 4)
    ("DUAGH" "DUAGH" 55 23 4)
    ("DUHAMEL" "DUHAMEL" 45 21 4)
    ("DUNCAN" "DUNCAN" 74 15 4)
    ("DUNVEG" "DUNVEGAN" 81 4 6)
    ("DUV" "DUVERNAY" 55 12 4)
    ("DYBERG" "DYBERG" 44 23 4)
    ("DYSON" "DYSON" 18 5 5)
    ("EAGLEB" "EAGLE BUTTE" 7 4 4)
    ("EAGLNEST" "EAGLENEST" 101 13 4)
    ("EAGLE" "EAGLESHAM" 77 25 5)
    ("EAGLEN" "EAGLESHAM NORTH" 78 25 5)
    ("EASTM" "EASTMONT" 12 27 4)
    ("ECONOMY" "ECONOMY" 68 1 6)
    ("EDBERG" "EDBERG" 44 19 4)
    ("EDGER" "EDGERTON" 45 4 4)
    ("EDMONTON" "EDMONTON" 53 23 4)
    ("EDRA" "EDRA" 100 25 4)
    ("EDSON" "EDSON" 52 18 5)
    ("EDWAND" "EDWAND" 60 16 4)
    ("ELIZA" "ELIZA" 55 8 4)
    ("ELKW" "ELKWATER" 8 3 4)
    ("ELLER" "ELLERSLIE" 51 24 4)
    ("ELLS" "ELLS" 95 15 4)
    ("ELSCT" "ELLSCOTT" 64 21 4)
    ("ELM" "ELMWORTH" 70 11 6)
    ("ELNORA" "ELNORA" 35 22 4)
    ("EMPRESS" "EMPRESS" 24 2 4)
    ("ENCHANT" "ENCHANT" 14 16 4)
    ("ENDIANG" "ENDIANG" 35 16 4)
    ("ENSIGN" "ENSIGN" 16 26 4)
    ("ENTICE" "ENTICE" 28 24 4)
    ("ENTWIS" "ENTWISTLE" 54 6 5)
    ("EQUIS" "EQUISETUM" 88 5 5)
    ("ERSKINE" "ERSKINE" 39 21 4)
    ("ESMOND" "ESMOND" 126 20 5)
    ("ESTHER" "ESTHER" 31 2 4)
    ("ETHELLK" "ETHEL LAKE" 64 3 4)
    ("ETZIKOM" "ETZIKOM" 6 8 4)
    ("EUREKA" "EUREKA" 88 3 6)
    ("EVI" "EVI" 87 13 5)
    ("EWINGLK" "EWING LAKE" 37 21 4)
    ("EXCEL" "EXCELSIOR" 56 24 4)
    ("EXPAN" "EXPANSE" 88 4 6)
    ("EYEHILL" "EYEHILL" 41 6 4)
    ("EYRMOR" "EYREMORE" 18 18 4)
    ("FACRES" "FAIRACRES" 89 22 5)
    ("FVIEW" "FAIRVIEW" 83 2 6)
    ("FBA" "FAIRYDELL-BON ACCORD" 57 24 4)
    ("FAITH" "FAITH" 3 13 4)
    ("FARMTON" "FARMINGTON" 80 11 6)
    ("FARRELL" "FARRELL" 34 16 4)
    ("FAUSTS" "FAUST SOUTH" 72 11 5)
    ("FELDON" "FELDON" 1 1 4)
    ("FENNW" "FENN WEST" 36 20 4)
    ("FENNBV" "FENN-BIG VALLEY" 35 20 4)
    ("FERGUSON" "FERGUSON" 3 17 4)
    ("FERIN" "FERINTOSH" 44 21 4)
    ("FERRIER" "FERRIER" 39 8 5)
    ("FBANK" "FERRYBANK" 44 27 4)
    ("FIGURE" "FIGURE LAKE" 63 18 4)
    ("FIN" "FINCASTLE" 9 15 4)
    ("FINDLEY" "FINDLEY" 57 6 6)
    ("FIRE" "FIRE" 113 7 6)
    ("FISHER" "FISHER" 68 5 4)
    ("FLAT" "FLAT" 66 20 4)
    ("FLOOD" "FLOOD" 85 25 5)
    ("FOLEYLK" "FOLEY LAKE" 65 6 5)
    ("FONTAS" "FONTAS" 102 11 6)
    ("FORESTB" "FORESTBURG" 42 15 4)
    ("FORSYTH" "FORSYTH" 62 6 4)
    ("FTASSN" "FORT ASSINIBOINE" 62 4 5)
    ("FT KENT" "FORT KENT" 61 4 4)
    ("FTSASK" "FORT SASKATCHEWAN" 54 22 4)
    ("40MILE" "FORTY MILE" 7 9 4)
    ("FOXCK" "FOX CREEK" 61 18 5)
    ("FRANCIS" "FRANCIS" 73 22 4)
    ("FRENCH" "FRENCH" 64 1 5)
    ("FURNESS" "FURNESS" 48 23 4)
    ("GADSBY" "GADSBY" 37 19 4)
    ("GAGE" "GAGE" 82 3 6)
    ("GALAHAD" "GALAHAD" 40 15 4)
    ("GAMBLER" "GAMBLER" 70 21 4)
    ("GAPLK" "GAP LAKE" 24 9 5)
    ("GARDPL" "GARDEN PLAINS" 33 13 4)
    ("GARDNER" "GARDNER" 90 17 5)
    ("GARR" "GARRINGTON" 34 4 5)
    ("GARTH" "GARTH" 64 6 4)
    ("GARTLEY" "GARTLEY" 31 18 4)
    ("GENESEE" "GENESEE" 50 3 5)
    ("GEORGE" "GEORGE" 82 5 6)
    ("GERE" "GERE" 62 8 5)
    ("GERMAIN" "GERMAIN" 85 22 4)
    ("GETTY" "GETTY" 17 5 5)
    ("GPINE" "GHOST PINE" 31 22 4)
    ("GIFT" "GIFT" 78 10 5)
    ("GILBY" "GILBY" 41 3 5)
    ("GILWOOD" "GILWOOD" 73 18 5)
    ("GIROUXLK" "GIROUX LAKE" 66 21 5)
    ("GVILLEE" "GIROUXVILLE EAST" 77 22 5)
    ("GLEICHEN" "GLEICHEN" 22 22 4)
    ("GLENPK" "GLEN PARK" 49 27 4)
    ("GLENEVIS" "GLENEVIS" 55 4 5)
    ("GLENWD" "GLENWOOD" 5 27 4)
    ("GLOVER" "GLOVER" 75 9 4)
    ("GODIN" "GODIN" 81 1 5)
    ("GOLDEN" "GOLDEN" 86 15 5)
    ("GSPIKE" "GOLDEN SPIKE" 51 27 4)
    ("GOODFISH" "GOODFISH" 91 9 5)
    ("GOODLOW" "GOODLOW" 84 26 4)
    ("GOODWIN" "GOODWIN" 59 13 5)
    ("GOOSER" "GOOSE RIVER" 67 18 5)
    ("GORD" "GORDONDALE" 79 10 6)
    ("GRAHAM" "GRAHAM" 79 4 4)
    ("GRAIN" "GRAINDALE" 26 1 4)
    ("GRDFKS" "GRAND FORKS" 11 13 4)
    ("GRDCACH" "GRANDE CACHE" 59 8 6)
    ("GRANDPR" "GRANDE PRAIRIE" 72 6 6)
    ("GRANOR" "GRANOR" 83 18 4)
    ("GRANT CK" "GRANT CREEK" 5 1 4)
    ("GRANUM" "GRANUM" 11 26 4)
    ("GRASSLND" "GRASSLAND" 67 19 4)
    ("GNCOURT" "GREENCOURT" 59 9 5)
    ("GNCOURTE" "GREENCOURT EAST" 59 6 5)
    ("GREGG" "GREGG" 49 25 5)
    ("GRIMSHAW" "GRIMSHAW" 83 23 5)
    ("GRIZZLY" "GRIZZLY" 62 22 5)
    ("GROAT" "GROAT" 57 16 5)
    ("GROUSE" "GROUSE" 74 12 4)
    ("GUNN" "GUNN" 55 3 5)
    ("GUTAH" "GUTAH" 99 7 6)
    ("GUY" "GUY" 72 21 5)
    ("HAIG" "HAIG" 89 14 5)
    ("HAIRY" "HAIRY HILL" 55 14 4)
    ("HALKIRK" "HALKIRK" 38 16 4)
    ("HALLIDAY" "HALLIDAY" 28 14 4)
    ("HAMBURG" "HAMBURG" 95 11 6)
    ("HAMLIN CK" "HAMELIN CREEK" 80 6 6)
    ("HAMLN CK" "HAMELIN CREEK" 80 6 6)
    ("HANGST" "HANGINGSTONE" 84 9 4)
    ("HANLAN" "HANLAN" 47 17 5)
    ("HANNA" "HANNA" 31 14 4)
    ("HARDY" "HARDY" 76 5 4)
    ("HARME" "HARMATTAN EAST" 32 3 5)
    ("HARM-ELK" "HARMATTAN-ELKTON" 31 4 5)
    ("HARMONV" "HARMON VALLEY" 81 20 5)
    ("HARO" "HARO" 101 3 6)
    ("HARPER" "HARPER" 97 24 4)
    ("HARTELL" "HARTELL" 19 2 5)
    ("HASTINGS" "HASTINGS" 50 20 4)
    ("HAWK" "HAWK" 97 21 5)
    ("HAYNES" "HAYNES" 38 24 4)
    ("HAYS" "HAYS" 13 14 4)
    ("HAYTER" "HAYTER" 41 1 4)
    ("HEARTLK" "HEART LAKE" 69 10 4)
    ("HEARTR" "HEART RIVER" 77 16 5)
    ("HEATHDLE" "HEATHDALE" 27 8 4)
    ("HECTOR" "HECTOR" 16 17 4)
    ("HELDAR" "HELDAR" 58 7 5)
    ("HELMSDLE" "HELMSDALE" 26 6 4)
    ("HELSMDLE" "HELMSDALE" 26 6 4)
    ("HENDERSN" "HENDERSON" 114 22 5)
    ("HERCULES" "HERCULES" 51 23 4)
    ("HERRON" "HERRONTON" 19 26 4)
    ("HILEVEL" "HIGH LEVEL" 110 20 5)
    ("HIGH PR" "HIGH PRAIRIE" 74 16 5)
    ("HIR" "HIGH RIVER" 18 29 4)
    ("HILAND" "HIGHLAND" 29 2 4)
    ("HIGHVALE" "HIGHVALE" 51 4 5)
    ("HIGHWOOD" "HIGHWOOD" 17 2 5)
    ("HILL" "HILL" 85 11 6)
    ("HILLSPR" "HILL SPRING" 3 26 4)
    ("HINTON" "HINTON" 51 25 5)
    ("HOLLOW" "HOLLOW" 61 20 4)
    ("HOLM" "HOLMBERG" 44 17 4)
    ("HOMRIM" "HOMEGLEN-RIMBEY" 43 1 5)
    ("HONDO" "HONDO" 70 27 4)
    ("HONEY" "HONEYSUCKLE" 46 26 4)
    ("HOOLE" "HOOLE" 81 24 4)
    ("HOSELAW" "HOSELAW" 60 6 4)
    ("HOTCHKIS" "HOTCHKISS" 94 1 6)
    ("HOUSE" "HOUSE" 82 15 4)
    ("HOWARD" "HOWARD" 79 5 6)
    ("HUNTER" "HUNTER VALLEY" 29 9 5)
    ("HUSSAR" "HUSSAR" 25 20 4)
    ("HUTCH" "HUTCH" 113 21 5)
    ("HUXLEY" "HUXLEY" 34 24 4)
    ("HYLO" "HYLO" 65 15 4)
    ("INLAND" "INLAND" 51 15 4)
    ("INNIS" "INNISFAIL" 35 1 5)
    ("INVERNESS" "INVERNESS" 68 12 5)
    ("IOSEGUN" "IOSEGUN" 67 20 5)
    ("IPIATIK" "IPIATIK" 72 9 4)
    ("IRONSP" "IRON SPRINGS" 11 20 4)
    ("JACK" "JACK" 85 4 6)
    ("JACKPOT" "JACKPOT" 125 19 5)
    ("JARVIE" "JARVIE" 63 1 5)
    ("JARVIEN" "JARVIE NORTH" 64 2 5)
    ("JASLAN" "JASLAN" 67 21 4)
    ("JEFFREY" "JEFFREY" 59 23 4)
    ("JENNER" "JENNER" 20 9 4)
    ("JENSEN" "JENSEN" 4 21 4)
    ("JILES" "JILES" 63 21 4)
    ("JOAN" "JOAN" 92 10 5)
    ("JOARCAM" "JOARCAM" 48 21 4)
    ("JOFFRE" "JOFFRE" 38 26 4)
    ("JOHNSON" "JOHNSON" 16 14 4)
    ("JOLI FOU" "JOLI FOU" 81 20 4)
    ("JOLIET" "JOLIET" 25 7 4)
    ("JOSEPHNE" "JOSEPHINE" 83 9 6)
    ("JOUSS" "JOUSSARD" 74 14 5)
    ("JUDYCK" "JUDY CREEK" 63 11 5)
    ("JUDYCKS" "JUDY CREEK SOUTH" 62 12 5)
    ("JUMPBUSH" "JUMPBUSH" 19 20 4)
    ("JUMP PD" "JUMPING POUND" 25 4 5)
    ("JUMP PDW" "JUMPING POUND WEST" 25 6 5)
    ("KAHNTAH" "KAHNTAH" 97 17 5)
    ("KAKUT" "KAKUT" 75 3 6)
    ("KAKWA" "KAKWA" 64 5 6)
    ("KARR" "KARR" 65 3 6)
    ("KAYBOB" "KAYBOB" 64 19 5)
    ("KAYBOBS" "KAYBOB SOUTH" 60 18 5)
    ("KEHO" "KEHO" 11 22 4)
    ("KELSEY" "KELSEY" 44 18 4)
    ("KEMP" "KEMP" 98 23 5)
    ("KENT" "KENT" 62 2 4)
    ("KIDNEY" "KIDNEY" 91 4 5)
    ("KILLAM" "KILLAM" 43 10 4)
    ("KILLAMN" "KILLAM NORTH" 44 13 4)
    ("KIM" "KIM" 8 25 4)
    ("KIMIWAN" "KIMIWAN" 79 20 5)
    ("KINGMAN" "KINGMAN" 49 19 4)
    ("KINMUNDY" "KINMUNDY" 25 9 4)
    ("KINUSO" "KINUSO" 74 10 5)
    ("KIPP" "KIPP" 8 23 4)
    ("KIRBY" "KIRBY" 74 5 4)
    ("KIRKWALL" "KIRKWALL" 27 5 4)
    ("KITSIM" "KITSIM" 17 16 4)
    ("KLESK" "KLESKUN" 72 2 6)
    ("KNAPPEN" "KNAPPEN" 1 11 4)
    ("KNELLER" "KNELLER" 49 23 4)
    ("KOTCHO" "KOTCHO" 112 11 6)
    ("LA COREY" "LA COREY" 63 5 4)
    ("LA GLACE" "LA GLACE" 74 8 6)
    ("LA BICHE" "LAC LA BICHE" 67 13 4)
    ("LACOMBE" "LACOMBE" 40 26 4)
    ("LAIT" "LAIT" 1 10 4)
    ("LAMBERT" "LAMBERT" 51 22 5)
    ("LAMONT" "LAMONT" 53 19 4)
    ("LANE" "LANE" 65 7 4)
    ("LFINE" "LANFINE" 25 5 4)
    ("LANGFORD" "LANGFORD" 13 2 5)
    ("LAPP" "LAPP" 99 10 6)
    ("LARNE" "LARNE" 116 3 6)
    ("LATOR" "LATOR" 63 2 6)
    ("LATORNLL" "LATORNELL" 63 1 6)
    ("LAWRNC" "LAWRENCE" 41 12 5)
    ("LEAHST" "LEAHURST" 39 18 4)
    ("LEAHURST" "LEAHURST" 39 18 4)
    ("LEAMAN" "LEAMAN" 55 11 5)
    ("LECKIE" "LECKIE" 19 17 4)
    ("LEDDY" "LEDDY" 84 25 5)
    ("LEDUC OR WOODBEND" "LEDUC-WOODBEND" 50 26 4)
    ("LEDUC-WB" "LEDUC-WOODBEND" 50 26 4)
    ("LEDUC-WD" "LEDUC-WOODBEND" 50 26 4)
    ("LEGAL" "LEGAL" 57 25 4)
    ("LEISMER" "LEISMER" 77 9 4)
    ("LELAND" "LELAND" 59 26 5)
    ("LEMING" "LEMING" 65 4 4)
    ("LEO" "LEO" 35 17 4)
    ("LEOPARD" "LEOPARD" 9 20 4)
    ("LEPINE" "LEPINE" 64 3 5)
    ("LESSARD" "LESSARD" 124 17 5)
    ("LIEGE" "LIEGE" 93 21 4)
    ("LIMESTN" "LIMESTONE" 33 10 5)
    ("LIND" "LINDBERGH" 57 5 4)
    ("LBOW" "LITTLE BOW" 15 19 4)
    ("LHORSE" "LITTLE HORSE" 77 12 5)
    ("LSMOKY" "LITTLE SMOKY" 67 22 5)
    ("LIVINGST" "LIVINGSTONE" 11 3 5)
    ("LLOYD" "LLOYDMINSTER" 50 1 4)
    ("LOCHEND" "LOCHEND" 27 3 5)
    ("LODGE" "LODGE" 9 2 4)
    ("LOGAN" "LOGAN" 72 13 4)
    ("LOMOND" "LOMOND" 18 23 4)
    ("LPINECK" "LONE PINE CREEK" 30 28 4)
    ("LONGCO" "LONG COULEE" 16 21 4)
    ("LOOKOUT" "LOOKOUT BUTTE" 1 28 4)
    ("LOON" "LOON" 85 9 5)
    ("LOST" "LOST" 84 26 5)
    ("LOVETTR" "LOVETT RIVER" 46 18 5)
    ("LUCKY" "LUCKY" 61 18 4)
    ("LUNNFORD" "LUNNFORD" 59 3 5)
    ("LUNNFRD" "LUNNFORD" 59 3 5)
    ("LUTOSE" "LUTOSE" 116 23 5)
    ("LYLE" "LYLE" 73 18 4)
    ("LYNDON" "LYNDON" 13 29 4)
    ("LYNX" "LYNX" 62 9 6)
    ("MAJEAU" "MAJEAU" 56 4 5)
    ("MAJOR" "MAJORVILLE" 18 19 4)
    ("MALMO" "MALMO" 43 22 4)
    ("MANIR" "MANIR" 72 3 6)
    ("MANNING" "MANNING" 90 25 5)
    ("MANN" "MANNVILLE" 51 8 4)
    ("MANNY" "MANNY" 76 21 4)
    ("MANOLA" "MANOLA" 58 2 5)
    ("MANYB" "MANYBERRIES" 5 5 4)
    ("MARIE" "MARIE" 65 2 4)
    ("MARKER" "MARKERVILLE" 36 2 5)
    ("MARLOWE" "MARLOWE" 122 22 5)
    ("MARSH" "MARSH" 54 25 5)
    ("MARTEN" "MARTEN" 77 4 5)
    ("MARTENH" "MARTEN HILLS" 75 25 4)
    ("MARW" "MARWAYNE" 53 3 4)
    ("MATZ" "MATZIWIN" 23 14 4)
    ("MAX" "MAX" 75 19 4)
    ("MCBRI" "MCBRIDE" 6 26 4)
    ("MCGOWAN" "MCGOWAN" 70 16 5)
    ("MCGREG" "MCGREGOR" 17 20 4)
    ("MCGUFFIN" "MCGUFFIN" 66 11 4)
    ("MCKINLEY" "MCKINLEY" 65 22 5)
    ("MCLEANSC" "MCLEANS CREEK" 74 21 5)
    ("MCLEOD" "MCLEOD" 54 14 5)
    ("MEANDER" "MEANDER" 115 21 5)
    ("MEANOOK" "MEANOOK" 63 22 4)
    ("MEARON" "MEARON" 94 13 6)
    ("MEDHAT" "MEDICINE HAT" 13 3 4)
    ("MEDLOD" "MEDICINE LODGE" 52 21 5)
    ("MEDRIV" "MEDICINE RIVER" 39 3 5)
    ("MEEKWAP" "MEEKWAP" 66 15 5)
    ("MEGA" "MEGA" 101 7 6)
    ("MELLOW" "MELLOWDALE" 60 3 5)
    ("MEYER" "MEYER" 70 25 4)
    ("MICHI" "MICHICHI" 30 18 4)
    ("MIKWAN" "MIKWAN" 36 23 4)
    ("MILKR" "MILK RIVER" 2 15 4)
    ("MILLAR" "MILLARVILLE" 21 2 5)
    ("MILLS" "MILLS" 69 11 4)
    ("MILO" "MILO" 19 23 4)
    ("MINEHEAD" "MINEHEAD" 49 19 5)
    ("MINNOW" "MINNOW" 57 5 6)
    ("MIRAGE" "MIRAGE" 79 7 6)
    ("MISTAHAE" "MISTAHAE" 79 1 5)
    ("MITSUE" "MITSUE" 71 4 5)
    ("MOBER" "MOBERLY" 58 4 6)
    ("MONA" "MONA" 8 6 4)
    ("MONTAG" "MONTAG" 84 6 6)
    ("MONTY" "MONTGOMERY" 12 28 4)
    ("MOONEY" "MOONEY" 72 7 5)
    ("MSHINE" "MOONSHINE" 58 1 4)
    ("MOORE" "MOORE" 67 4 4)
    ("MOOSE" "MOOSE" 23 6 5)
    ("MORGAN" "MORGAN" 51 4 4)
    ("MORINV" "MORINVILLE" 55 25 4)
    ("MORLEY" "MORLEY" 26 7 5)
    ("MORNSIDE" "MORNINGSIDE" 42 28 4)
    ("MOSES" "MOSES" 97 12 5)
    ("MOUNTAIN" "MOUNTAIN" 47 22 5)
    ("MULLIGAN" "MULLIGAN" 81 8 6)
    ("MURIELLK" "MURIEL LAKE" 59 4 4)
    ("MUSKWA" "MUSKWA" 85 25 4)
    ("MYSTERY" "MYSTERY" 60 7 5)
    ("NAMPA" "NAMPA" 84 16 5)
    ("NARWAY" "NARRAWAY" 64 12 6)
    ("NAYLOR" "NAYLOR" 97 25 5)
    ("NEERLND" "NEERLANDIA" 61 5 5)
    ("NELSON" "NELSON" 44 25 4)
    ("NESTOW" "NESTOW" 60 24 4)
    ("NETOOK" "NETOOK" 63 10 6)
    ("NEVIS" "NEVIS" 39 22 4)
    ("NEWNOR" "NEW NORWAY" 44 22 4)
    ("NEWBRK" "NEWBROOK" 62 20 4)
    ("NEWBY" "NEWBY" 81 5 4)
    ("NEWELL" "NEWELL" 17 14 4)
    ("NEWTON" "NEWTON" 58 3 5)
    ("NINA" "NINA" 92 20 5)
    ("NINSTO" "NINASTOKO" 5 25 4)
    ("NIPIN" "NIPIN" 74 21 4)
    ("NIPISI" "NIPISI" 79 8 5)
    ("NITON" "NITON" 54 13 5)
    ("NIXON" "NIXON" 72 16 4)
    ("NOLAND" "NOLAND" 9 26 4)
    ("NORDEGG" "NORDEGG" 41 17 5)
    ("NVILLE" "NORMANDVILLE" 80 22 5)
    ("NORRIS" "NORRIS" 53 18 4)
    ("NSTAR" "NORTH STAR" 90 22 5)
    ("NORVAL" "NORTH VALLEY" 22 4 5)
    ("NORVIL" "NORTHVILLE" 52 10 5)
    ("NOSEHILL" "NOSEHILL" 55 20 5)
    ("NOTIK" "NOTIKEWIN" 92 10 6)
    ("OAK" "OAK" 83 6 6)
    ("OCHRE" "OCHRE" 90 16 5)
    ("OGSTON" "OGSTON" 89 10 5)
    ("OKOTOKS" "OKOTOKS" 21 28 4)
    ("OLSON" "OLSON" 56 1 6)
    ("OMEGA" "OMEGA" 46 1 4)
    ("ONEFOUR" "ONE FOUR" 1 4 4)
    ("ORCHID" "ORCHID" 88 20 4)
    ("ORION" "ORION" 7 7 4)
    ("OSBORN" "OSBORN" 89 7 6)
    ("OYEN" "OYEN" 29 5 4)
    ("PADDLER" "PADDLE RIVER" 57 8 5)
    ("PAGEANT" "PAGEANT" 18 21 4)
    ("PAKOWKI" "PAKOWKI LAKE" 4 7 4)
    ("PALLIS" "PALLISER" 62 10 6)
    ("PANNY" "PANNY" 95 5 5)
    ("PANTHER" "PANTHER RIVER" 30 10 5)
    ("PARADISE" "PARADISE" 47 2 4)
    ("PARFLESH" "PARFLESH" 25 22 4)
    ("PARKER" "PARKER" 70 5 5)
    ("PARKLD" "PARKLAND" 15 28 4)
    ("PARKLDNE" "PARKLAND NORTHEAST" 15 27 4)
    ("PAULINE" "PAULINE" 52 1 5)
    ("PAXON" "PAXON" 65 21 4)
    ("PEACOCK" "PEACOCK" 14 26 4)
    ("PEAK" "PEAK" 119 5 6)
    ("PEARCE" "PEARCE" 9 24 4)
    ("PEAVEY" "PEAVEY" 56 24 4)
    ("PECO" "PECO" 47 15 5)
    ("PEDGRE" "PEDIGREE" 100 12 6)
    ("PEDLEY" "PEDLEY" 54 24 5)
    ("PEEL" "PEEL" 102 18 5)
    ("PEERLESS" "PEERLESS" 79 22 4)
    ("PEIGAN" "PEIGAN" 8 8 4)
    ("PELICAN" "PELICAN" 79 24 4)
    ("PEM" "PEMBINA" 48 7 5)
    ("PEMBINA" "PEMBINA" 48 7 5)
    ("PENDOR" "PENDANT D'OREILLE" 4 9 4)
    ("PENHOLD" "PENHOLD" 36 27 4)
    ("PENNY" "PENNY" 8 22 4)
    ("PEORIA" "PEORIA" 76 2 6)
    ("PEPPERS" "PEPPERS" 52 24 5)
    ("PERRY" "PERRYVALE" 64 23 4)
    ("PERT" "PERT" 125 6 6)
    ("PETER" "PETER" 72 1 5)
    ("PETITOT" "PETITOT" 122 10 6)
    ("PHLOMENA" "PHILOMENA" 71 9 4)
    ("PHILP" "PHILP" 2 12 4)
    ("PHOENIX" "PHOENIX" 39 10 5)
    ("PICA" "PICA" 84 5 6)
    ("PINCH CK" "PINCHER CREEK" 4 29 4)
    ("PINE CK" "PINE CREEK" 57 19 5)
    ("PINEDALE" "PINEDALE" 54 16 4)
    ("PINEHRST" "PINEHURST" 66 10 4)
    ("PINGEL" "PINGEL" 81 7 6)
    ("PINTO" "PINTO" 54 2 6)
    ("PLACID" "PLACID" 60 23 5)
    ("PLAIN" "PLAIN" 53 12 4)
    ("PLEASANT" "PLEASANT" 68 20 4)
    ("PLUTO" "PLUTO" 44 15 5)
    ("PLUVS" "PLUVIUS" 87 21 5)
    ("PLOCKV" "POLLOCKVILLE" 25 10 4)
    ("POMME" "POMME" 115 24 5)
    ("PONOKA" "PONOKA" 43 26 4)
    ("PPINEH" "PORCUPINE HILLS" 11 1 5)
    ("PORTAGE" "PORTAGE" 78 17 4)
    ("POTOGO" "POTOGO" 95 21 5)
    ("PCOUPE" "POUCE COUPE" 80 12 6)
    ("PCOUPES" "POUCE COUPE SOUTH" 78 12 6)
    ("PRESTIN" "PRESTIN" 97 13 5)
    ("PREVO" "PREVO" 39 1 5)
    ("PRIN" "PRINCESS" 20 11 4)
    ("PRITCH" "PRITCHARD" 61 1 4)
    ("PROGRESS" "PROGRESS" 77 9 6)
    ("PROVOST" "PROVOST" 37 7 4)
    ("PUSKWA" "PUSKWASKAU" 74 1 6)
    ("PYRAMID" "PYRAMID" 105 10 6)
    ("QUEENSTN" "QUEENSTOWN" 19 21 4)
    ("QUIRK CK" "QUIRK CREEK" 21 4 5)
    ("RACOSTA" "RACOSTA" 31 11 4)
    ("RADWAY" "RADWAY" 59 20 4)
    ("RAINBOW" "RAINBOW" 110 6 6)
    ("RAINBOWS" "RAINBOW SOUTH" 107 9 6)
    ("RAINIER" "RAINIER" 17 15 4)
    ("RAM" "RAM" 37 14 5)
    ("RAMBLING" "RAMBLING" 90 7 6)
    ("RANDELL" "RANDELL" 77 10 5)
    ("RANFURLY" "RANFURLY" 50 12 4)
    ("RASPB" "RASPBERRY" 66 17 5)
    ("RATZ" "RATZ" 126 18 5)
    ("RVNRDG" "RAVEN RIDGE" 93 1 4)
    ("REAGAN" "REAGAN" 1 19 4)
    ("REDEARTH" "RED EARTH" 87 8 5)
    ("REDWILOW" "RED WILLOW" 40 17 4)
    ("REDFISH" "REDFISH" 92 8 5)
    ("REDLAND" "REDLAND" 27 22 4)
    ("REDWATER" "REDWATER" 57 21 4)
    ("REINE" "REINE" 81 22 5)
    ("REITA" "REITA" 59 3 4)
    ("RSDLN" "RESDELN" 82 7 4)
    ("RESTHA" "RESTHAVEN" 60 3 6)
    ("RETLAW" "RETLAW" 12 18 4)
    ("RIBSTONE" "RIBSTONE" 42 4 4)
    ("RICH" "RICH" 35 21 4)
    ("RICHDALE" "RICHDALE" 30 12 4)
    ("RICHMOND" "RICHMOND" 69 19 4)
    ("RICINUS" "RICINUS" 35 8 5)
    ("RICINUSW" "RICINUS WEST" 36 10 5)
    ("RINGS" "RINGS" 80 5 6)
    ("RIVERCRS" "RIVERCOURSE" 47 1 4)
    ("RIVIERE" "RIVIERE" 55 27 4)
    ("ROCHE" "ROCHE" 67 7 5)
    ("ROCHSTR" "ROCHESTER" 62 23 4)
    ("ROCKYFRD" "ROCKYFORD" 26 23 4)
    ("ROFORD" "ROCKYFORD" 26 23 4)
    ("ROMEO" "ROMEO" 25 4 4)
    ("RONALANE" "RONALANE" 13 12 4)
    ("ROSEVEAR" "ROSEVEAR" 54 15 5)
    ("ROSSBEAR" "ROSSBEAR" 94 14 5)
    ("ROUGH" "ROUGH" 38 12 5)
    ("ROUSSEAU" "ROUSSEAU" 90 1 6)
    ("ROWLEY" "ROWLEY" 32 20 4)
    ("ROXANA" "ROXANA" 78 19 5)
    ("ROYAL" "ROYAL" 53 16 4)
    ("ROYCE" "ROYCE" 84 7 6)
    ("RUMSEY" "RUMSEY" 34 21 4)
    ("RUSH" "RUSH" 8 5 4)
    ("RYAN" "RYAN" 96 14 5)
    ("RYCROFT" "RYCROFT" 77 4 6)
    ("SABBATH" "SABBATH" 106 12 6)
    ("SADDLE" "SADDLE HILLS" 76 8 6)
    ("SAGECK" "SAGE CREEK" 2 1 4)
    ("SAKWA" "SAKWATAMAU" 63 14 5)
    ("SALESKI" "SALESKI" 86 18 4)
    ("SALTCK" "SALT CREEK" 75 10 5)
    ("SALTER" "SALTER" 27 8 5)
    ("SAMSON" "SAMSON" 44 24 4)
    ("SANDY" "SANDY" 82 20 4)
    ("SANGUDO" "SANGUDO" 57 6 5)
    ("SAPPHIRE" "SAPPHIRE" 2 5 4)
    ("SARAH" "SARAH" 66 7 5)
    ("SARCEE" "SARCEE" 23 4 5)
    ("SAUNDERS" "SAUNDERS" 40 13 5)
    ("SAVANCK" "SAVANNA CREEK" 14 4 5)
    ("SAWDY" "SAWDY" 69 22 4)
    ("SAWN LK" "SAWN LAKE" 91 12 5)
    ("SAXON" "SAXON" 61 24 5)
    ("SCHELT" "SCHELTENS" 71 1 4)
    ("SCULLY" "SCULLY" 100 20 5)
    ("SEAL" "SEAL" 82 14 5)
    ("SEDALIA" "SEDALIA" 30 5 4)
    ("SEDGE" "SEDGEWICK" 42 12 4)
    ("SEIULK" "SEIU LAKE" 25 18 4)
    ("SENEX" "SENEX" 92 3 5)
    ("SHADOW" "SHADOW" 74 17 5)
    ("SHANE" "SHANE" 77 2 6)
    ("SHANNON" "SHANNON" 26 6 4)
    ("SHAUNICY" "SHAUNICY" 6 3 4)
    ("SHAW" "SHAW" 49 22 5)
    ("SHEKILIE" "SHEKILIE" 117 9 6)
    ("SHEKILW" "SHEKILIE WEST" 117 11 6)
    ("SHELDON" "SHELDON" 73 23 5)
    ("SHETLAND" "SHETLAND" 106 10 6)
    ("SHOAL" "SHOAL" 82 7 5)
    ("SHOLDICE" "SHOULDICE" 20 23 4)
    ("SIBBALD" "SIBBALD" 27 2 4)
    ("SILER" "SILER" 57 7 4)
    ("SILT" "SILT" 126 6 6)
    ("SILVER" "SILVER" 17 28 4)
    ("SIMON" "SIMONETTE" 63 26 5)
    ("SINCLAIR" "SINCLAIR" 74 12 6)
    ("SIPHON" "SIPHON" 86 10 6)
    ("SKARO" "SKARO" 57 19 4)
    ("SLAVE" "SLAVE" 84 14 5)
    ("SMITH" "SMITH" 71 25 4)
    ("SMICO" "SMITH COULEE" 4 11 4)
    ("SMOKY" "SMOKY" 59 3 6)
    ("SNIPELK" "SNIPE LAKE" 71 18 5)
    ("SNOWFALL" "SNOWFALL" 99 8 6)
    ("SOLDAR" "SOLDAR" 93 21 5)
    ("SOLOMON" "SOLOMON" 52 27 5)
    ("SOUND" "SOUNDING" 30 9 4)
    ("SOUSA" "SOUSA" 112 5 6)
    ("SPENCER" "SPENCER" 66 8 4)
    ("SPIERS" "SPIERS" 34 15 4)
    ("SPRINGCO" "SPRING COULEE" 3 23 4)
    ("SPRUCEGR" "SPRUCE GROVE" 52 27 4)
    ("SPUR" "SPUR" 72 2 5)
    ("SQUARE" "SQUARE" 89 9 6)
    ("STAL-BLK" "ST ALBERT-BIG LAKE" 53 26 4)
    ("ST ANNE" "ST ANNE" 54 4 5)
    ("ST PAUL" "ST PAUL" 58 9 4)
    ("STDISH" "STANDISH" 68 7 4)
    ("STDOFF" "STANDOFF" 7 25 4)
    ("STANMORE" "STANMORE" 29 11 4)
    ("STEELE" "STEELE" 66 25 4)
    ("STEEN" "STEEN" 108 1 6)
    ("STEEPBK" "STEEP BANK" 94 7 4)
    ("STETTLER" "STETTLER" 38 20 4)
    ("STETLR N" "STETTLER NORTH" 39 20 4)
    ("STEVE" "STEVE" 59 7 4)
    ("STEWART" "STEWART" 32 28 4)
    ("STIMSON" "STIMSON" 15 2 5)
    ("STIRLING" "STIRLING" 7 19 4)
    ("STOLBERG" "STOLBERG" 42 15 5)
    ("STONY" "STONY PLAIN" 53 1 5)
    ("STOWE" "STOWE" 91 1 6)
    ("STRY" "STRY" 58 13 4)
    ("STUMP" "STUMP" 71 20 5)
    ("STURLK" "STURGEON LAKE" 71 23 5)
    ("STURLKS" "STURGEON LAKE SOUTH" 69 22 5)
    ("SUFFIELD" "SUFFIELD" 18 6 4)
    ("SUGDEN" "SUGDEN" 62 10 4)
    ("SULLVNLK" "SULLIVAN LAKE" 35 13 4)
    ("SUNBURST" "SUNBURST" 1 18 4)
    ("SUNDANCE" "SUNDANCE" 54 21 5)
    ("SUNNYN" "SUNNYNOOK" 26 11 4)
    ("SUNSET" "SUNSET" 69 19 5)
    ("SUPERBA" "SUPERBA" 26 3 4)
    ("SUTTON" "SUTTON" 91 3 6)
    ("SWALWELL" "SWALWELL" 29 24 4)
    ("SWANH" "SWAN HILLS" 68 10 5)
    ("SWEENEY" "SWEENEY" 89 12 6)
    ("SWTGRS" "SWEETGRASS" 1 15 4)
    ("SWIMMING" "SWIMMING" 52 6 4)
    ("SYLAKE" "SYLVAN LAKE" 37 3 5)
    ("TABER" "TABER" 9 17 4)
    ("TABERN" "TABER NORTH" 11 16 4)
    ("TABERS" "TABER SOUTH" 7 16 4)
    ("TABERSE" "TABER SOUTHEAST" 8 15 4)
    ("TALBOTLK" "TALBOT LAKE" 98 12 5)
    ("TANGENT" "TANGENT" 80 24 5)
    ("TANGHE" "TANGHE" 102 10 6)
    ("TAR" "TAR" 99 13 4)
    ("TATE" "TATE" 120 3 6)
    ("TAWAT" "TAWATINAW" 62 22 4)
    ("TEEPEE" "TEEPEE" 73 3 6)
    ("TELFORD" "TELFORDVILLE" 50 2 5)
    ("TEMPLETON" "TEMPLETON" 1 12 4)
    ("THELMACK" "THELMA CREEK" 6 2 4)
    ("THERIEN" "THERIEN" 60 9 4)
    ("THORH" "THORHILD" 59 21 4)
    ("THORNB" "THORNBURY" 78 13 4)
    ("THORSBY" "THORSBY" 49 1 5)
    ("THREEHCK" "THREE HILLS CREEK" 35 25 4)
    ("THUNDER" "THUNDER" 60 6 5)
    ("TIBBS" "TIBBS" 16 2 5)
    ("TIMBERW" "TIMBERWOLF" 107 12 6)
    ("TIMEU" "TIMEU" 63 3 5)
    ("TINDA" "TINDASTOLL" 36 1 5)
    ("TODD" "TODD" 9 2 5)
    ("TOFIELD" "TOFIELD" 50 19 4)
    ("TOMAHAWK" "TOMAHAWK" 52 5 5)
    ("TOMATO" "TOMATO" 72 23 4)
    ("TONY CKN" "TONY CREEK NORTH" 64 21 5)
    ("TOOGA" "TOOGA" 116 10 6)
    ("TOUCHWOOD" "TOUCHWOOD" 68 9 4)
    ("TOWERCK" "TOWER CREEK" 55 27 5)
    ("TRACY" "TRACY" 95 12 5)
    ("TRAP" "TRAP" 17 4 5)
    ("TROCHU" "TROCHU" 33 22 4)
    ("TROUT" "TROUT" 90 3 5)
    ("TROUTCK" "TROUT CREEK" 13 1 5)
    ("TUCKLK" "TUCKER LAKE" 64 5 4)
    ("TV" "TURNER VALLEY" 20 3 5)
    ("TWEEDIE" "TWEEDIE" 69 13 4)
    ("TWINING" "TWINING" 31 24 4)
    ("TWOCK" "TWO CREEK" 63 16 5)
    ("UKALTA" "UKALTA" 57 17 4)
    ("VALHALLA" "VALHALLA" 75 10 6)
    ("VALLEYVW" "VALLEYVIEW" 70 21 5)
    ("VARDIE" "VARDIE" 115 9 6)
    ("VAUX" "VAUXHALL" 12 17 4)
    ("VEGA" "VEGA" 61 3 5)
    ("VENUS" "VENUS" 101 9 6)
    ("VGRIS" "VERDIGRIS" 2 17 4)
    ("VERGER" "VERGER" 22 15 4)
    ("VERMIL" "VERMILION" 50 5 4)
    ("VIK-KINS" "VIKING-KINSELLA" 47 10 4)
    ("VIOLET" "VIOLET" 79 2 4)
    ("VIRG" "VIRGINIA HILLS" 64 13 5)
    ("VIRGO" "VIRGO" 115 6 6)
    ("VOYAGER" "VOYAGER" 45 17 5)
    ("VULCAN" "VULCAN" 16 24 4)
    ("WABASCA" "WABASCA" 85 24 4)
    ("WAINWR" "WAINWRIGHT" 45 6 4)
    ("WALLACE" "WALLACE" 69 13 5)
    ("WALRUS" "WALRUS" 82 17 5)
    ("WAPITI" "WAPITI" 67 10 6)
    ("WAPPAU" "WAPPAU" 74 11 4)
    ("WARNER" "WARNER" 4 19 4)
    ("WARSPITE" "WARSPITE" 60 18 4)
    ("WARWICK" "WARWICK" 52 14 4)
    ("WAHIGAN" "WASKAHIGAN" 64 23 5)
    ("WATELET" "WATELET" 47 26 4)
    ("WATERN" "WATERTON" 4 1 5)
    ("WATTS" "WATTS" 31 16 4)
    ("WAVYLK" "WAVY LAKE" 43 14 4)
    ("WAYNE" "WAYNE-ROSEDALE" 27 19 4)
    ("WEASEL" "WEASEL" 58 19 4)
    ("WEBSTER" "WEBSTER" 74 5 6)
    ("WELLBURN" "WELLBURN" 9 18 4)
    ("WEMBLEY" "WEMBLEY" 73 8 6)
    ("WESCAS" "WEST CASTLE" 4 3 5)
    ("WCOVE" "WEST COVE" 55 6 5)
    ("WPRAIR" "WEST PRAIRIE" 72 16 5)
    ("WROSE" "WESTEROSE" 46 28 4)
    ("WESTLOCK" "WESTLOCK" 59 26 4)
    ("WESTON" "WESTON" 4 15 4)
    ("WESTPEM" "WESTPEM" 49 13 5)
    ("WETWIN" "WETASKIWIN" 45 24 4)
    ("WHISKEY" "WHISKEY" 22 5 5)
    ("WHCOURT" "WHITECOURT" 60 11 5)
    ("WHHORSE" "WHITEHORSE" 49 15 5)
    ("WHITELAW" "WHITELAW" 82 2 6)
    ("WHITEMUD" "WHITEMUD" 51 25 4)
    ("WHITFORD" "WHITFORD" 58 16 4)
    ("WIDEWATER" "WIDEWATER" 73 8 5)
    ("WIDEWATR" "WIDEWATER" 73 8 5)
    ("WILD RIV" "WILD RIVER" 56 24 5)
    ("WCATH" "WILDCAT HILLS" 27 6 5)
    ("WILDHCK" "WILDHORSE CREEK" 31 10 5)
    ("WILDHO" "WILDHORSE CREEK" 31 10 5)
    ("WILDMERE" "WILDMERE" 48 5 4)
    ("WILDUNN" "WILDUNN CREEK" 29 14 4)
    ("WILDWD" "WILDWOOD" 54 9 5)
    ("WILLGR" "WILLESDEN GREEN" 42 7 5)
    ("WILDON" "WILLINGDON" 55 15 4)
    ("WIM" "WIMBORNE" 34 26 4)
    ("WINAGAMI" "WINAGAMI" 77 18 5)
    ("WINCO" "WINCHELL COULEE" 29 6 5)
    ("WIND" "WINDFALL" 60 15 5)
    ("WINTERH" "WINTERING HILLS" 25 17 4)
    ("WIZARDLK" "WIZARD LAKE" 48 27 4)
    ("WOKING" "WOKING" 75 5 6)
    ("WOLVER" "WOLVERINE" 98 15 5)
    ("WOODRIV" "WOOD RIVER" 43 23 4)
    ("WOODENH" "WOODENHOUSE" 87 22 4)
    ("WOODLAND" "WOODLAND" 60 19 4)
    ("WOOLFD" "WOOLFORD" 3 24 4)
    ("WORKMAN" "WORKMAN" 31 26 4)
    ("WORSLEY" "WORSLEY" 87 7 6)
    ("WRENTHAM" "WRENTHAM" 6 16 4)
    ("YELSTONE" "YELLOWSTONE" 71 13 5)
    ("YNGSTN" "YOUNGSTOWN" 31 10 4)
    ("ZAMA" "ZAMA" 118 5 6)
    ("ZEUES" "ZEUES" 120 12 6)
  )
)

(prompt "\nLoaded... Well Name Header - type WNH")
(princ)
