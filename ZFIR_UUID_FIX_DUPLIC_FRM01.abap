*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLIC_FRM01
*&---------------------------------------------------------------------*
*& Fase 2: Verificación de candidatos y planificación de correcciones.
*&
*& Para cada UUID duplicado:
*&   - Se busca su registro CSV (fuente de verdad del CFDI).
*&   - Se leen los candidatos (BKPF+BSEG) por CLAVE PRIMARIA (sin LIKE).
*&   - Se determina cuál es el documento correcto (folio + RFC).
*&   - Los incorrectos pasan por búsqueda inversa para encontrar su UUID.
*&   - Se delega la corrección a FRM02.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_DUPLICADOS
*&---------------------------------------------------------------------*
FORM frm_procesar_duplicados.

  DATA: lt_uuids_dup TYPE HASHED TABLE OF char36
                     WITH UNIQUE KEY table_line,
        lt_grupo     TYPE tt_uuid_sap.

* Obtener lista de UUIDs únicos duplicados
  LOOP AT gt_duplic_docs INTO DATA(ls_d).
    INSERT ls_d-uuid INTO TABLE lt_uuids_dup.
  ENDLOOP.

* Procesar cada UUID duplicado con su grupo de documentos
  LOOP AT lt_uuids_dup INTO DATA(lv_uuid_dup).

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = CONV i( sy-tabix * 100 / lines( lt_uuids_dup ) )
        text       = |UUID { sy-tabix }/{ lines( lt_uuids_dup ) }: { lv_uuid_dup }|.

    CLEAR lt_grupo.
    LOOP AT gt_duplic_docs INTO DATA(ls_doc) WHERE uuid = lv_uuid_dup.
      APPEND ls_doc TO lt_grupo.
    ENDLOOP.

    PERFORM frm_verificar_grupo
      USING lv_uuid_dup lt_grupo.

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_VERIFICAR_GRUPO
*&---------------------------------------------------------------------*
*& Para un UUID duplicado (iv_uuid) y sus documentos candidatos (it_cands):
*&
*&  1. Busca el CSV con ese UUID.
*&  2. Para cada candidato: lee BKPF+BSEG por PK, verifica folio+RFC.
*&  3. Si exactamente 1 coincide → documento correcto.
*&  4. Para los incorrectos: búsqueda inversa en CSVs.
*&  5. Delega corrección a frm_corregir_documento (FRM02).
*&---------------------------------------------------------------------*
FORM frm_verificar_grupo
  USING iv_uuid  TYPE char36
        it_cands TYPE tt_uuid_sap.

  TYPES: BEGIN OF lty_check,
           bukrs      TYPE bukrs,
           belnr      TYPE belnr_d,
           gjahr      TYPE gjahr,
           folio_ok   TYPE c,
           rfc_ok     TYPE c,
           score      TYPE i,
         END OF lty_check.

  DATA: ls_csv       TYPE gty_csv_rec,
        lt_check     TYPE TABLE OF lty_check,
        ls_check     TYPE lty_check,
        lv_xblnr     TYPE xblnr1,
        lv_blart     TYPE blart,
        lv_koart     TYPE koart,
        lv_lifnr     TYPE lifnr,
        lv_kunnr     TYPE kunnr,
        lv_wrbtr     TYPE wrbtr,
        lv_err_doc   TYPE c,
        lv_folio_ok  TYPE c,
        lv_rfc_ok    TYPE c,
        lv_total_csv TYPE p DECIMALS 0,
        lv_total_bd  TYPE p DECIMALS 0,
        lv_n_correct TYPE i,
        lv_bukrs_ok  TYPE bukrs,
        lv_belnr_ok  TYPE belnr_d,
        lv_gjahr_ok  TYPE gjahr.

* ── 1. Buscar CSV para este UUID ──────────────────────────────────────
  READ TABLE gt_csv_by_uuid INTO ls_csv WITH TABLE KEY uuid = iv_uuid.
  IF sy-subrc <> 0.
*   Sin CSV → no podemos determinar cuál es el correcto
    gv_sin_csv = gv_sin_csv + 1.
    LOOP AT it_cands INTO DATA(ls_c).
      CLEAR gs_resultado.
      gs_resultado-icon        = gc_icon_warn.
      gs_resultado-uuid        = iv_uuid.
      gs_resultado-bukrs_ko    = ls_c-bukrs.
      gs_resultado-belnr_ko    = ls_c-belnr.
      gs_resultado-gjahr_ko    = ls_c-gjahr.
      gs_resultado-accion      = 'MANUAL'.
      gs_resultado-mensaje     = 'UUID sin respaldo en CSV del servidor. Revisión manual.'.
      gs_resultado-test_mode   = p_test.
      APPEND gs_resultado TO gt_resultado.
    ENDLOOP.
    gv_manual = gv_manual + 1.
    RETURN.
  ENDIF.

* ── 2. Convertir total CSV para comparación de importes ───────────────
  PERFORM frm_convertir_total_num
    USING    ls_csv-total
    CHANGING lv_total_csv.

* ── 3. Verificar cada candidato por clave primaria ────────────────────
* RENDIMIENTO: SELECT por PK (bukrs+belnr+gjahr) en lugar de LIKE.
  LOOP AT it_cands INTO DATA(ls_cand).
    CLEAR ls_check.
    ls_check-bukrs = ls_cand-bukrs.
    ls_check-belnr = ls_cand-belnr.
    ls_check-gjahr = ls_cand-gjahr.

    PERFORM frm_leer_doc_sap
      USING    ls_cand-bukrs ls_cand-belnr ls_cand-gjahr
      CHANGING lv_xblnr lv_blart lv_koart
               lv_lifnr lv_kunnr lv_wrbtr lv_err_doc.

    IF lv_err_doc = 'X'.
      APPEND ls_check TO lt_check.
      CONTINUE.
    ENDIF.

*   Check folio: el folio del CSV debe estar contenido en XBLNR o viceversa
    IF ls_csv-folio IS NOT INITIAL
    AND ( lv_xblnr CS ls_csv-folio OR ls_csv-folio CS lv_xblnr ).
      ls_check-folio_ok = 'X'.
      ls_check-score    = ls_check-score + 2.
    ENDIF.

*   Check RFC: verificar que el RFC del CSV coincide con LIFNR/KUNNR del doc
    PERFORM frm_check_rfc
      USING    ls_csv-rfc_emisor ls_csv-rfc_receptor
               ls_cand-bukrs lv_lifnr lv_kunnr lv_koart
      CHANGING ls_check-rfc_ok.

    IF ls_check-rfc_ok = 'X'.
      ls_check-score = ls_check-score + 3.
    ENDIF.

*   Check importe (no aplicar para pagos tipo 'P')
    lv_total_bd = trunc( lv_wrbtr ).
    IF ( lv_total_bd = lv_total_csv OR ls_csv-tipo = 'P' )
    AND lv_total_csv > 0.
      ls_check-score = ls_check-score + 1.
    ENDIF.

    APPEND ls_check TO lt_check.
  ENDLOOP.

* ── 4. Determinar documento correcto (folio Y rfc ambos OK) ──────────
  SORT lt_check BY score DESCENDING.
  CLEAR: lv_n_correct, lv_bukrs_ok, lv_belnr_ok, lv_gjahr_ok.

  LOOP AT lt_check INTO ls_check
    WHERE folio_ok = 'X' AND rfc_ok = 'X'.
    lv_n_correct = lv_n_correct + 1.
    IF lv_n_correct = 1.
      lv_bukrs_ok = ls_check-bukrs.
      lv_belnr_ok = ls_check-belnr.
      lv_gjahr_ok = ls_check-gjahr.
    ENDIF.
  ENDLOOP.

* ── 5. Casos sin resolución automática ───────────────────────────────
  IF lv_n_correct = 0 OR lv_n_correct > 1.

    DATA(lv_msg_manual) = COND char255(
      WHEN lv_n_correct = 0
        THEN 'Ningún candidato cumple folio+RFC. Revisión manual.'
        ELSE 'Múltiples candidatos válidos. Revisión manual.' ).

    LOOP AT it_cands INTO DATA(ls_ca).
      CLEAR gs_resultado.
      gs_resultado-icon        = gc_icon_warn.
      gs_resultado-uuid        = iv_uuid.
      gs_resultado-bukrs_ko    = ls_ca-bukrs.
      gs_resultado-belnr_ko    = ls_ca-belnr.
      gs_resultado-gjahr_ko    = ls_ca-gjahr.
      gs_resultado-accion      = 'MANUAL'.
      gs_resultado-fichero_csv = ls_csv-fichero.
      gs_resultado-mensaje     = lv_msg_manual.
      gs_resultado-test_mode   = p_test.
      APPEND gs_resultado TO gt_resultado.
    ENDLOOP.
    gv_manual = gv_manual + 1.
    RETURN.
  ENDIF.

* ── 6. Exactamente 1 correcto ─────────────────────────────────────────
* Registrar el documento correcto en el ALV y en ztt_uuid_log
  CLEAR gs_resultado.
  gs_resultado-icon        = gc_icon_ok.
  gs_resultado-uuid        = iv_uuid.
  gs_resultado-bukrs_ok    = lv_bukrs_ok.
  gs_resultado-belnr_ok    = lv_belnr_ok.
  gs_resultado-gjahr_ok    = lv_gjahr_ok.
  gs_resultado-accion      = 'CORRECTO'.
  gs_resultado-fichero_csv = ls_csv-fichero.
  gs_resultado-mensaje     = 'Documento correcto: UUID verificado.'.
  gs_resultado-test_mode   = p_test.
  APPEND gs_resultado TO gt_resultado.

  IF p_test = ''.
    PERFORM frm_actualizar_log_ok
      USING iv_uuid lv_bukrs_ok lv_belnr_ok lv_gjahr_ok ls_csv-fichero.
  ENDIF.

* Procesar los documentos incorrectos del grupo
  DATA: lv_xblnr_ko   TYPE xblnr1,
        lv_blart_ko   TYPE blart,
        lv_koart_ko   TYPE koart,
        lv_lifnr_ko   TYPE lifnr,
        lv_kunnr_ko   TYPE kunnr,
        lv_wrbtr_ko   TYPE wrbtr,
        lv_err_ko     TYPE c,
        lv_uuid_nuevo TYPE char36,
        lv_fich_nuevo TYPE string,
        lv_found_new  TYPE c.

  LOOP AT it_cands INTO DATA(ls_ko).
    IF ls_ko-bukrs = lv_bukrs_ok
   AND ls_ko-belnr = lv_belnr_ok
   AND ls_ko-gjahr = lv_gjahr_ok.
      CONTINUE.
    ENDIF.

*   Leer datos del doc incorrecto para la búsqueda inversa
    CLEAR: lv_xblnr_ko, lv_blart_ko, lv_koart_ko,
           lv_lifnr_ko, lv_kunnr_ko, lv_wrbtr_ko, lv_err_ko.

    PERFORM frm_leer_doc_sap
      USING    ls_ko-bukrs ls_ko-belnr ls_ko-gjahr
      CHANGING lv_xblnr_ko lv_blart_ko lv_koart_ko
               lv_lifnr_ko lv_kunnr_ko lv_wrbtr_ko lv_err_ko.

    CLEAR: lv_uuid_nuevo, lv_fich_nuevo, lv_found_new.

    IF lv_err_ko = ''.
*     Búsqueda inversa: buscar en CSVs el UUID correcto para este doc
      PERFORM frm_buscar_uuid_para_doc
        USING    ls_ko-bukrs ls_ko-belnr ls_ko-gjahr
                 lv_xblnr_ko lv_koart_ko lv_lifnr_ko lv_kunnr_ko
                 iv_uuid         " UUID a excluir (el incorrecto)
        CHANGING lv_uuid_nuevo lv_fich_nuevo lv_found_new.
    ENDIF.

*   Ejecutar corrección (o simular si P_TEST = 'X')
    PERFORM frm_corregir_documento
      USING    iv_uuid
               ls_ko-bukrs  ls_ko-belnr  ls_ko-gjahr
               lv_bukrs_ok  lv_belnr_ok  lv_gjahr_ok
               lv_uuid_nuevo lv_fich_nuevo lv_found_new
               ls_csv-fichero.

  ENDLOOP.

  gv_corr_auto = gv_corr_auto + 1.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_LEER_DOC_SAP
*&---------------------------------------------------------------------*
*& Lee BKPF y BSEG por CLAVE PRIMARIA (sin LIKE, sin full scan).
*& Intenta primero KOART='K' (compra), luego KOART='D' (venta).
*&---------------------------------------------------------------------*
FORM frm_leer_doc_sap
  USING    iv_bukrs TYPE bukrs
           iv_belnr TYPE belnr_d
           iv_gjahr TYPE gjahr
  CHANGING pv_xblnr TYPE xblnr1
           pv_blart TYPE blart
           pv_koart TYPE koart
           pv_lifnr TYPE lifnr
           pv_kunnr TYPE kunnr
           pv_wrbtr TYPE wrbtr
           pv_error TYPE c.

  CLEAR: pv_xblnr, pv_blart, pv_koart, pv_lifnr,
         pv_kunnr, pv_wrbtr, pv_error.

  SELECT SINGLE xblnr, blart
    FROM bkpf
    INTO (@pv_xblnr, @pv_blart)
    WHERE bukrs = @iv_bukrs
      AND belnr = @iv_belnr
      AND gjahr = @iv_gjahr.

  IF sy-subrc <> 0.
    pv_error = 'X'.
    RETURN.
  ENDIF.

* Buscar línea de proveedor (Compra: KOART = 'K')
  SELECT SINGLE koart, lifnr, wrbtr
    FROM bseg
    INTO (@pv_koart, @pv_lifnr, @pv_wrbtr)
    WHERE bukrs = @iv_bukrs
      AND belnr = @iv_belnr
      AND gjahr = @iv_gjahr
      AND koart = 'K'.

  IF sy-subrc <> 0.
*   Buscar línea de cliente (Venta: KOART = 'D')
    SELECT SINGLE koart, kunnr, wrbtr
      FROM bseg
      INTO (@pv_koart, @pv_kunnr, @pv_wrbtr)
      WHERE bukrs = @iv_bukrs
        AND belnr = @iv_belnr
        AND gjahr = @iv_gjahr
        AND koart = 'D'.

    IF sy-subrc <> 0.
      pv_error = 'X'.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_CHECK_RFC
*&---------------------------------------------------------------------*
*& Verifica que los RFC del CSV coinciden con los datos del documento:
*&   Compra (KOART='K'): receptor=sociedad (T001Z), emisor=proveedor (LFA1)
*&   Venta  (KOART='D'): emisor=sociedad  (T001Z), receptor=cliente  (KNA1)
*& Cachés LFA1 y KNA1 se llenan lazy (solo si no están en memoria).
*&---------------------------------------------------------------------*
FORM frm_check_rfc
  USING    iv_rfc_emi TYPE char13
           iv_rfc_rec TYPE char13
           iv_bukrs   TYPE bukrs
           iv_lifnr   TYPE lifnr
           iv_kunnr   TYPE kunnr
           iv_koart   TYPE koart
  CHANGING pv_rfc_ok  TYPE c.

  DATA: ls_t001z TYPE gty_t001z_cache,
        ls_lfa1  TYPE gty_lfa1_cache,
        ls_kna1  TYPE gty_kna1_cache.

  CLEAR pv_rfc_ok.

  IF iv_koart = 'K'.
*   Compra: RFC receptor debe mapear a BUKRS del documento
    READ TABLE gt_t001z_cache INTO ls_t001z
      WITH TABLE KEY paval = iv_rfc_rec.
    IF sy-subrc <> 0 OR ls_t001z-bukrs <> iv_bukrs. RETURN. ENDIF.

*   RFC emisor debe mapear a LIFNR del documento (lazy cache)
    READ TABLE gt_lfa1_cache INTO ls_lfa1
      WITH TABLE KEY stcd1 = iv_rfc_emi.
    IF sy-subrc <> 0.
      SELECT SINGLE lifnr FROM lfa1 INTO @ls_lfa1-lifnr
        WHERE stcd1 = @iv_rfc_emi.
      ls_lfa1-stcd1 = iv_rfc_emi.
      INSERT ls_lfa1 INTO TABLE gt_lfa1_cache.
    ENDIF.

    IF ls_lfa1-lifnr IS NOT INITIAL AND ls_lfa1-lifnr = iv_lifnr.
      pv_rfc_ok = 'X'.
    ENDIF.

  ELSEIF iv_koart = 'D'.
*   Venta: RFC emisor debe mapear a BUKRS del documento
    READ TABLE gt_t001z_cache INTO ls_t001z
      WITH TABLE KEY paval = iv_rfc_emi.
    IF sy-subrc <> 0 OR ls_t001z-bukrs <> iv_bukrs. RETURN. ENDIF.

*   RFC receptor debe mapear a KUNNR del documento (lazy cache)
    READ TABLE gt_kna1_cache INTO ls_kna1
      WITH TABLE KEY stcd1 = iv_rfc_rec.
    IF sy-subrc <> 0.
      SELECT SINGLE kunnr FROM kna1 INTO @ls_kna1-kunnr
        WHERE stcd1 = @iv_rfc_rec.
      ls_kna1-stcd1 = iv_rfc_rec.
      INSERT ls_kna1 INTO TABLE gt_kna1_cache.
    ENDIF.

    IF ls_kna1-kunnr IS NOT INITIAL AND ls_kna1-kunnr = iv_kunnr.
      pv_rfc_ok = 'X'.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_BUSCAR_UUID_PARA_DOC
*&---------------------------------------------------------------------*
*& Búsqueda inversa: dado un documento que ha perdido su UUID,
*& recorre gt_csv_all buscando el CSV que apunta a ese documento.
*& Criterio: folio del CSV contenido en XBLNR del documento Y RFC ok.
*& Excluye iv_uuid_exc (el UUID incorrecto que ya sabemos que no es).
*&
*& Resultado:
*&   ev_found = 'X' → encontrado un único candidato (ev_uuid = UUID correcto)
*&   ev_found = 'M' → múltiples candidatos, ambiguo
*&   ev_found = '' → no encontrado
*&---------------------------------------------------------------------*
FORM frm_buscar_uuid_para_doc
  USING    iv_bukrs    TYPE bukrs
           iv_belnr    TYPE belnr_d
           iv_gjahr    TYPE gjahr
           iv_xblnr    TYPE xblnr1
           iv_koart    TYPE koart
           iv_lifnr    TYPE lifnr
           iv_kunnr    TYPE kunnr
           iv_uuid_exc TYPE char36
  CHANGING ev_uuid     TYPE char36
           ev_fichero  TYPE string
           ev_found    TYPE c.

  DATA: ls_csv      TYPE gty_csv_rec,
        lv_rfc_ok   TYPE c,
        lv_matches  TYPE i.

  CLEAR: ev_uuid, ev_fichero, ev_found, lv_matches.

  LOOP AT gt_csv_all INTO ls_csv.

    IF ls_csv-uuid = iv_uuid_exc. CONTINUE. ENDIF.
    IF ls_csv-uuid IS INITIAL.    CONTINUE. ENDIF.

*   El folio del CSV debe estar contenido en el XBLNR del documento
    IF iv_xblnr IS INITIAL
    OR ls_csv-folio IS INITIAL
    OR ( NOT ( iv_xblnr CS ls_csv-folio )
         AND NOT ( ls_csv-folio CS iv_xblnr ) ).
      CONTINUE.
    ENDIF.

*   Verificar RFC
    CLEAR lv_rfc_ok.
    PERFORM frm_check_rfc
      USING    ls_csv-rfc_emisor ls_csv-rfc_receptor
               iv_bukrs iv_lifnr iv_kunnr iv_koart
      CHANGING lv_rfc_ok.

    IF lv_rfc_ok = 'X'.
      lv_matches = lv_matches + 1.
      IF lv_matches = 1.
        ev_uuid    = ls_csv-uuid.
        ev_fichero = ls_csv-fichero.
      ELSE.
*       Múltiples candidatos → no podemos decidir automáticamente
        CLEAR: ev_uuid, ev_fichero.
        ev_found = 'M'.
        RETURN.
      ENDIF.
    ENDIF.

  ENDLOOP.

  IF lv_matches = 1.
    ev_found = 'X'.
  ENDIF.

ENDFORM.
