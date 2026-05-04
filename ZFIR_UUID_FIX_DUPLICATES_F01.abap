*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLICATES_F01
*&---------------------------------------------------------------------*
*& Fase A: Detección de documentos con UUID duplicado.
*& Estrategia de dos pasos para minimizar impacto en BD:
*&   1. GROUP BY en ZTT_UUID_LOG → candidatos duplicados (sin READ_TEXT)
*&   2. READ_TEXT solo para los candidatos (universo pequeño) → verdad STXH
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_FIX_INIT_CACHE
*&---------------------------------------------------------------------*
FORM frm_fix_init_cache.

  DATA: lt_t001z TYPE TABLE OF gty_t001z_c,
        ls_t001z TYPE gty_t001z_c.

  WRITE: / 'Cargando caché T001Z (RFC -> BUKRS)...'.

  SELECT paval bukrs
    FROM t001z
    INTO CORRESPONDING FIELDS OF TABLE lt_t001z
    WHERE party = gc_party.

  LOOP AT lt_t001z INTO ls_t001z.
    INSERT ls_t001z INTO TABLE gt_t001z_c.
  ENDLOOP.
  FREE lt_t001z.

  WRITE: / '  T001Z cargada:', lines( gt_t001z_c ), 'entradas.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_DETECTAR_DUPLICADOS
*&---------------------------------------------------------------------*
*& 1. Obtiene de ZTT_UUID_LOG los UUIDs que aparecen en >1 doc (DISTINCT).
*& 2. Para cada doc candidato, llama READ_TEXT y verifica UUID en STXH.
*& 3. Construye gt_dup_docs con los documentos realmente duplicados.
*& 4. Enriquece con metadatos de BKPF/BSEG/ZTT_UUID_LOG.
*& 5. Construye gt_rfcs_rel para filtrar CSVs en Fase B.
*&---------------------------------------------------------------------*
FORM frm_fix_detectar_duplicados.

  TYPES: BEGIN OF lty_uuid_doc,
           uuid  TYPE char36,
           bukrs TYPE bukrs,
           belnr TYPE belnr_d,
           gjahr TYPE gjahr,
         END OF lty_uuid_doc.

* ── 1. Leer (uuid, bukrs, belnr, gjahr) DISTINCT de ZTT_UUID_LOG ────
  DATA: lt_uniq   TYPE TABLE OF lty_uuid_doc,
        ls_u      TYPE lty_uuid_doc.

  WRITE: / 'Consultando ZTT_UUID_LOG para candidatos duplicados...'.

  IF s_bukrs IS NOT INITIAL AND s_gjahr IS NOT INITIAL.
    SELECT DISTINCT uuid bukrs belnr gjahr
      FROM ztt_uuid_log
      INTO CORRESPONDING FIELDS OF TABLE lt_uniq
      WHERE icon_status = gc_icon_ok
        AND bukrs        IN s_bukrs
        AND gjahr        IN s_gjahr.
  ELSEIF s_bukrs IS NOT INITIAL.
    SELECT DISTINCT uuid bukrs belnr gjahr
      FROM ztt_uuid_log
      INTO CORRESPONDING FIELDS OF TABLE lt_uniq
      WHERE icon_status = gc_icon_ok
        AND bukrs        IN s_bukrs.
  ELSEIF s_gjahr IS NOT INITIAL.
    SELECT DISTINCT uuid bukrs belnr gjahr
      FROM ztt_uuid_log
      INTO CORRESPONDING FIELDS OF TABLE lt_uniq
      WHERE icon_status = gc_icon_ok
        AND gjahr        IN s_gjahr.
  ELSE.
    SELECT DISTINCT uuid bukrs belnr gjahr
      FROM ztt_uuid_log
      INTO CORRESPONDING FIELDS OF TABLE lt_uniq
      WHERE icon_status = gc_icon_ok.
  ENDIF.

  IF lt_uniq IS INITIAL.
    WRITE: / 'No hay registros OK en ZTT_UUID_LOG.'.
    FREE lt_uniq.
    RETURN.
  ENDIF.

  WRITE: / '  Combinaciones (uuid+doc) únicas:', lines( lt_uniq ).

* ── 2. Contar docs por UUID y extraer UUIDs duplicados ───────────────
  DATA: lt_dup_uuid  TYPE HASHED TABLE OF char36 WITH UNIQUE KEY table_line,
        lv_prev_uuid TYPE char36,
        lv_acum_cnt  TYPE i.

  SORT lt_uniq BY uuid.
  CLEAR: lv_prev_uuid, lv_acum_cnt.

  LOOP AT lt_uniq INTO ls_u.
    IF ls_u-uuid <> lv_prev_uuid.
      IF lv_acum_cnt > 1 AND lv_prev_uuid IS NOT INITIAL.
        INSERT lv_prev_uuid INTO TABLE lt_dup_uuid.
        gv_n_duplic = gv_n_duplic + 1.
      ENDIF.
      lv_prev_uuid = ls_u-uuid.
      lv_acum_cnt  = 1.
    ELSE.
      lv_acum_cnt = lv_acum_cnt + 1.
    ENDIF.
  ENDLOOP.
  IF lv_acum_cnt > 1 AND lv_prev_uuid IS NOT INITIAL.
    INSERT lv_prev_uuid INTO TABLE lt_dup_uuid.
    gv_n_duplic = gv_n_duplic + 1.
  ENDIF.

  IF lt_dup_uuid IS INITIAL.
    WRITE: / 'No se detectaron UUIDs duplicados en ZTT_UUID_LOG.'.
    FREE: lt_uniq, lt_dup_uuid.
    RETURN.
  ENDIF.

  WRITE: / '  UUIDs candidatos a duplicado:', gv_n_duplic.

* ── 3. Extraer los docs candidatos (solo los de UUIDs duplicados) ────
  DATA: lt_cand  TYPE TABLE OF lty_uuid_doc,
        ls_cand  TYPE lty_uuid_doc.

  LOOP AT lt_uniq INTO ls_u.
    IF line_exists( lt_dup_uuid[ table_line = ls_u-uuid ] ).
      MOVE-CORRESPONDING ls_u TO ls_cand.
      APPEND ls_cand TO lt_cand.
    ENDIF.
  ENDLOOP.
  FREE: lt_uniq, lt_dup_uuid.

  WRITE: / '  Documentos candidatos por verificar en STXH:', lines( lt_cand ).

* ── 4. Verificar via READ_TEXT: confirmar UUID real en STXH ──────────
* Usamos gty_stxh_raw (tipo global del TOP) para lt_ver.
  DATA: lt_ver    TYPE TABLE OF gty_stxh_raw,
        ls_ver    TYPE gty_stxh_raw,
        lt_tlines TYPE TABLE OF tline,
        ls_tline  TYPE tline,
        lv_tdname TYPE tdobname,
        lv_uuid_r TYPE char36,
        lv_idx    TYPE i,
        lv_total  TYPE i.

  lv_total = lines( lt_cand ).

  LOOP AT lt_cand INTO ls_cand.
    lv_idx = sy-tabix.
    CLEAR: lv_tdname, lv_uuid_r.
    REFRESH lt_tlines.

    CONCATENATE ls_cand-bukrs ls_cand-belnr ls_cand-gjahr INTO lv_tdname.
    CONDENSE lv_tdname NO-GAPS.

    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        id        = gc_tdid
        language  = gc_language
        name      = lv_tdname
        object    = gc_object
      TABLES
        lines     = lt_tlines
      EXCEPTIONS
        OTHERS    = 8.

    IF sy-subrc <> 0. CONTINUE. ENDIF.

    READ TABLE lt_tlines INTO ls_tline INDEX 1.
    IF sy-subrc <> 0 OR ls_tline-tdline IS INITIAL. CONTINUE. ENDIF.

    lv_uuid_r = ls_tline-tdline.
    CONDENSE lv_uuid_r NO-GAPS.
    TRANSLATE lv_uuid_r TO UPPER CASE.
    IF lv_uuid_r IS INITIAL OR strlen( lv_uuid_r ) <> 36. CONTINUE. ENDIF.

    CLEAR ls_ver.
    ls_ver-uuid   = lv_uuid_r.
    ls_ver-bukrs  = ls_cand-bukrs.
    ls_ver-belnr  = ls_cand-belnr.
    ls_ver-gjahr  = ls_cand-gjahr.
    ls_ver-tdname = lv_tdname.
    APPEND ls_ver TO lt_ver.

    IF lv_idx MOD 500 = 0 OR lv_idx = lv_total.
      WRITE: / '  READ_TEXT verificados:', lv_idx, '/', lv_total.
    ENDIF.

    IF p_wait > 0 AND lv_idx MOD p_pkg = 0.
      WAIT UP TO p_wait SECONDS.
    ENDIF.

  ENDLOOP.
  FREE lt_cand.

* ── 5. Reidentificar UUIDs que SIGUEN siendo duplicados en STXH ──────
  DATA: lt_dup_stxh TYPE HASHED TABLE OF char36 WITH UNIQUE KEY table_line.

  SORT lt_ver BY uuid.
  CLEAR: lv_prev_uuid, lv_acum_cnt.

  LOOP AT lt_ver INTO ls_ver.
    IF ls_ver-uuid <> lv_prev_uuid.
      IF lv_acum_cnt > 1 AND lv_prev_uuid IS NOT INITIAL.
        INSERT lv_prev_uuid INTO TABLE lt_dup_stxh.
      ENDIF.
      lv_prev_uuid = ls_ver-uuid.
      lv_acum_cnt  = 1.
    ELSE.
      lv_acum_cnt = lv_acum_cnt + 1.
    ENDIF.
  ENDLOOP.
  IF lv_acum_cnt > 1 AND lv_prev_uuid IS NOT INITIAL.
    INSERT lv_prev_uuid INTO TABLE lt_dup_stxh.
  ENDIF.

  IF lt_dup_stxh IS INITIAL.
    WRITE: / 'ZTT_UUID_LOG tenía candidatos pero STXH no confirma duplicados.'.
    FREE: lt_ver, lt_dup_stxh.
    RETURN.
  ENDIF.

  WRITE: / '  UUIDs duplicados confirmados en STXH:', lines( lt_dup_stxh ).

* ── 6. Quedarnos solo con los docs de UUIDs verdaderamente duplicados ─
* Usamos gty_stxh_raw (tipo global) para lt_dup_raw → se puede pasar tipado al FORM.
  DATA: lt_dup_raw TYPE gtt_stxh_raw,
        ls_dup_raw TYPE gty_stxh_raw.

  LOOP AT lt_ver INTO ls_ver.
    IF line_exists( lt_dup_stxh[ table_line = ls_ver-uuid ] ).
      MOVE-CORRESPONDING ls_ver TO ls_dup_raw.
      APPEND ls_dup_raw TO lt_dup_raw.
    ENDIF.
  ENDLOOP.
  FREE: lt_ver, lt_dup_stxh.

  gv_n_docs = lines( lt_dup_raw ).
  WRITE: / '  Documentos a resolver:', gv_n_docs.

* ── 7. Enriquecer con metadatos de ZTT_UUID_LOG + BKPF + BSEG ───────
  PERFORM frm_fix_enriquecer USING lt_dup_raw.
  FREE lt_dup_raw.

  WRITE: / 'Detección completada. gt_dup_docs tiene:', lines( gt_dup_docs ), 'docs.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_ENRIQUECER
*&---------------------------------------------------------------------*
*& Parámetro tipado con TABLE OF gty_stxh_raw (tipo global del TOP).
*& Evita el ANY TABLE que impedía el acceso a componentes del field-symbol.
*&---------------------------------------------------------------------*
FORM frm_fix_enriquecer
  USING pt_dup_raw TYPE gtt_stxh_raw.

  TYPES: BEGIN OF lty_log_meta,
           bukrs        TYPE bukrs,
           belnr        TYPE belnr_d,
           gjahr        TYPE gjahr,
           rfc_emisor   TYPE char13,
           rfc_receptor TYPE char13,
           folio        TYPE char20,
           tipo         TYPE char1,
           tipo_fac     TYPE char1,
           budat        TYPE budat,
           bldat        TYPE bldat,
           blart        TYPE blart,
           datum_proc   TYPE d,
           uzeit_proc   TYPE t,
         END OF lty_log_meta.

  TYPES: BEGIN OF lty_bkpf_meta,
           bukrs  TYPE bukrs,
           belnr  TYPE belnr_d,
           gjahr  TYPE gjahr,
           xblnr  TYPE xblnr1,
           bldat  TYPE bldat,
           budat  TYPE budat,
           blart  TYPE blart,
         END OF lty_bkpf_meta.

  DATA: lt_log_pk  TYPE TABLE OF lty_log_meta,
        lt_bkpf_pk TYPE TABLE OF lty_bkpf_meta,
        ls_log     TYPE lty_log_meta,
        ls_bkpf    TYPE lty_bkpf_meta,
        ls_doc     TYPE gty_dup_doc,
        lt_chunk   TYPE TABLE OF gty_stxh_raw,
        ls_chunk   TYPE gty_stxh_raw,
        lv_idx     TYPE i,
        lv_total   TYPE i,
        lv_from    TYPE i,
        lv_to      TYPE i,
        lv_wrbtr   TYPE wrbtr.

  lv_total = lines( pt_dup_raw ).

  DO.
    REFRESH: lt_chunk, lt_log_pk, lt_bkpf_pk.
    lv_idx  = lv_idx + 1.
    lv_from = ( lv_idx - 1 ) * p_pkg + 1.
    lv_to   = lv_idx * p_pkg.
    IF lv_from > lv_total. EXIT. ENDIF.

*   Extraer paquete de la tabla de entrada
    LOOP AT pt_dup_raw INTO ls_chunk.
      IF sy-tabix >= lv_from AND sy-tabix <= lv_to.
        APPEND ls_chunk TO lt_chunk.
      ENDIF.
      IF sy-tabix > lv_to. EXIT. ENDIF.
    ENDLOOP.

    IF lt_chunk IS INITIAL. EXIT. ENDIF.

*   Leer metadata de ZTT_UUID_LOG (registro más reciente OK por doc)
    SELECT bukrs belnr gjahr rfc_emisor rfc_receptor folio tipo tipo_fac
           budat bldat blart datum_proc uzeit_proc
      FROM ztt_uuid_log
      INTO TABLE lt_log_pk
      FOR ALL ENTRIES IN lt_chunk
      WHERE bukrs = lt_chunk-bukrs
        AND belnr = lt_chunk-belnr
        AND gjahr = lt_chunk-gjahr
        AND icon_status = gc_icon_ok.

*   Leer metadatos BKPF (folio/fechas/clase como fallback)
    SELECT bukrs belnr gjahr xblnr bldat budat blart
      FROM bkpf
      INTO TABLE lt_bkpf_pk
      FOR ALL ENTRIES IN lt_chunk
      WHERE bukrs = lt_chunk-bukrs
        AND belnr = lt_chunk-belnr
        AND gjahr = lt_chunk-gjahr.

*   Combinar metadatos por documento
    SORT lt_log_pk BY bukrs belnr gjahr datum_proc DESCENDING uzeit_proc DESCENDING.

    LOOP AT lt_chunk INTO ls_chunk.
      CLEAR ls_doc.
      ls_doc-uuid_act = ls_chunk-uuid.
      ls_doc-bukrs    = ls_chunk-bukrs.
      ls_doc-belnr    = ls_chunk-belnr.
      ls_doc-gjahr    = ls_chunk-gjahr.
      ls_doc-tdname   = ls_chunk-tdname.

*     Tomar el registro de LOG más reciente para este doc
      READ TABLE lt_log_pk INTO ls_log
        WITH KEY bukrs = ls_chunk-bukrs belnr = ls_chunk-belnr gjahr = ls_chunk-gjahr.
      IF sy-subrc = 0.
        ls_doc-rfc_emisor   = ls_log-rfc_emisor.
        ls_doc-rfc_receptor = ls_log-rfc_receptor.
        ls_doc-folio        = ls_log-folio.
        ls_doc-tipo_fac     = ls_log-tipo_fac.
        ls_doc-tipo_cfdi    = ls_log-tipo.
        ls_doc-budat        = ls_log-budat.
        ls_doc-bldat        = ls_log-bldat.
        ls_doc-blart        = ls_log-blart.
      ENDIF.

*     Completar con BKPF si faltan campos
      READ TABLE lt_bkpf_pk INTO ls_bkpf
        WITH KEY bukrs = ls_chunk-bukrs belnr = ls_chunk-belnr gjahr = ls_chunk-gjahr.
      IF sy-subrc = 0.
        ls_doc-xblnr = ls_bkpf-xblnr.
        IF ls_doc-budat IS INITIAL. ls_doc-budat = ls_bkpf-budat. ENDIF.
        IF ls_doc-bldat IS INITIAL. ls_doc-bldat = ls_bkpf-bldat. ENDIF.
        IF ls_doc-blart IS INITIAL. ls_doc-blart = ls_bkpf-blart. ENDIF.
        IF ls_doc-folio IS INITIAL.
          ls_doc-folio = ls_bkpf-xblnr.
          CONDENSE ls_doc-folio NO-GAPS.
        ENDIF.
      ENDIF.

*     Obtener importe (WRBTR) desde BSEG
      CLEAR lv_wrbtr.
      PERFORM frm_fix_get_wrbtr
        USING  ls_doc-bukrs ls_doc-belnr ls_doc-gjahr
               ls_doc-tipo_fac ls_doc-rfc_emisor ls_doc-rfc_receptor
        CHANGING lv_wrbtr.
      ls_doc-total_num = trunc( lv_wrbtr ).

*     Registrar RFCs en set de relevantes para filtrar CSVs
      IF ls_doc-rfc_emisor IS NOT INITIAL.
        INSERT ls_doc-rfc_emisor INTO TABLE gt_rfcs_rel.
      ENDIF.
      IF ls_doc-rfc_receptor IS NOT INITIAL.
        INSERT ls_doc-rfc_receptor INTO TABLE gt_rfcs_rel.
      ENDIF.

      APPEND ls_doc TO gt_dup_docs.

    ENDLOOP.

    FREE: lt_chunk, lt_log_pk, lt_bkpf_pk.

    IF p_wait > 0.
      WAIT UP TO p_wait SECONDS.
    ENDIF.

  ENDDO.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_GET_WRBTR
*&---------------------------------------------------------------------*
FORM frm_fix_get_wrbtr
  USING    pv_bukrs    TYPE bukrs
           pv_belnr    TYPE belnr_d
           pv_gjahr    TYPE gjahr
           pv_tipo_fac TYPE c
           pv_rfc_emi  TYPE char13
           pv_rfc_rec  TYPE char13
  CHANGING pv_wrbtr    TYPE wrbtr.

  DATA: lv_wrbtr TYPE wrbtr,
        lv_lifnr TYPE lifnr,
        lv_kunnr TYPE kunnr,
        ls_lfa1  TYPE gty_lfa1_c,
        ls_kna1  TYPE gty_kna1_c.

  CLEAR pv_wrbtr.

  CASE pv_tipo_fac.
    WHEN 'C'.
      READ TABLE gt_lfa1_c INTO ls_lfa1 WITH TABLE KEY stcd1 = pv_rfc_emi.
      IF sy-subrc <> 0.
        SELECT SINGLE lifnr FROM lfa1 INTO lv_lifnr WHERE stcd1 = pv_rfc_emi.
        ls_lfa1-stcd1 = pv_rfc_emi.
        ls_lfa1-lifnr = lv_lifnr.
        INSERT ls_lfa1 INTO TABLE gt_lfa1_c.
      ENDIF.
      IF ls_lfa1-lifnr IS NOT INITIAL.
        SELECT SINGLE wrbtr FROM bseg INTO lv_wrbtr
          WHERE bukrs = pv_bukrs AND belnr = pv_belnr AND gjahr = pv_gjahr
            AND koart = 'K' AND lifnr = ls_lfa1-lifnr.
        pv_wrbtr = abs( lv_wrbtr ).
      ENDIF.

    WHEN 'V'.
      READ TABLE gt_kna1_c INTO ls_kna1 WITH TABLE KEY stcd1 = pv_rfc_rec.
      IF sy-subrc <> 0.
        SELECT SINGLE kunnr FROM kna1 INTO lv_kunnr WHERE stcd1 = pv_rfc_rec.
        ls_kna1-stcd1 = pv_rfc_rec.
        ls_kna1-kunnr = lv_kunnr.
        INSERT ls_kna1 INTO TABLE gt_kna1_c.
      ENDIF.
      IF ls_kna1-kunnr IS NOT INITIAL.
        SELECT SINGLE wrbtr FROM bseg INTO lv_wrbtr
          WHERE bukrs = pv_bukrs AND belnr = pv_belnr AND gjahr = pv_gjahr
            AND koart = 'D' AND kunnr = ls_kna1-kunnr.
        pv_wrbtr = abs( lv_wrbtr ).
      ENDIF.

    WHEN 'I'.
      SELECT SINGLE wrbtr FROM bseg INTO lv_wrbtr
        WHERE bukrs = pv_bukrs AND belnr = pv_belnr AND gjahr = pv_gjahr
          AND koart = 'K'.
      IF sy-subrc = 0.
        pv_wrbtr = abs( lv_wrbtr ).
      ELSE.
        SELECT SINGLE wrbtr FROM bseg INTO lv_wrbtr
          WHERE bukrs = pv_bukrs AND belnr = pv_belnr AND gjahr = pv_gjahr
            AND koart = 'D'.
        pv_wrbtr = abs( lv_wrbtr ).
      ENDIF.

    WHEN OTHERS.
      SELECT SINGLE wrbtr FROM bseg INTO lv_wrbtr
        WHERE bukrs = pv_bukrs AND belnr = pv_belnr AND gjahr = pv_gjahr
          AND ( koart = 'K' OR koart = 'D' ).
      pv_wrbtr = abs( lv_wrbtr ).
  ENDCASE.

ENDFORM.
