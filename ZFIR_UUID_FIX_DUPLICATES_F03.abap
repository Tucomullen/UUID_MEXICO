*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLICATES_F03
*&---------------------------------------------------------------------*
*& Fase C: Resolución — determina qué hacer con cada doc duplicado.
*& Fase D: Aplicación — ejecuta las acciones en paquetes seguros.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_FIX_RESOLVER
*&---------------------------------------------------------------------*
*& Para cada documento duplicado busca en gt_csv_idx la coincidencia
*& por (rfc_emisor, rfc_receptor, folio, gjahr, total_num).
*& Determina la acción: REASIGNADO / OK_GANADOR / AMBIGUO / HUERFANO.
*&---------------------------------------------------------------------*
FORM frm_fix_resolver.

  DATA: ls_doc     TYPE gty_dup_doc,
        ls_accion  TYPE gty_accion,
        lt_match   TYPE TABLE OF gty_csv_idx,
        ls_match   TYPE gty_csv_idx.

  WRITE: / 'Resolviendo', lines( gt_dup_docs ), 'documentos duplicados...'.

  LOOP AT gt_dup_docs INTO ls_doc.
    CLEAR ls_accion.
    ls_accion-bukrs        = ls_doc-bukrs.
    ls_accion-belnr        = ls_doc-belnr.
    ls_accion-gjahr        = ls_doc-gjahr.
    ls_accion-tdname       = ls_doc-tdname.
    ls_accion-uuid_act     = ls_doc-uuid_act.
    ls_accion-rfc_emisor   = ls_doc-rfc_emisor.
    ls_accion-rfc_receptor = ls_doc-rfc_receptor.
    ls_accion-folio        = ls_doc-folio.
    ls_accion-tipo_fac     = ls_doc-tipo_fac.
    ls_accion-tipo_cfdi    = ls_doc-tipo_cfdi.
    ls_accion-budat        = ls_doc-budat.
    ls_accion-blart        = ls_doc-blart.

*   Buscar candidatos en el índice CSV por la clave de búsqueda primaria
    REFRESH lt_match.
    PERFORM frm_fix_buscar_csv
      USING    ls_doc
      CHANGING lt_match.

*   Evaluar resultados de la búsqueda
    DESCRIBE TABLE lt_match LINES DATA(lv_n_match).

    IF lv_n_match = 0.
*     Sin match en CSV → Huérfano: borrar UUID
      ls_accion-accion  = gc_acc_huerf.
      ls_accion-uuid_nuevo = space.
      ls_accion-mensaje = 'Sin coincidencia en CSV. UUID se borrará de SAP.'.
      gv_n_huerfano = gv_n_huerfano + 1.

    ELSEIF lv_n_match = 1.
      READ TABLE lt_match INTO ls_match INDEX 1.
      IF ls_match-uuid = ls_doc-uuid_act.
*       El CSV confirma el UUID actual → este doc es el GANADOR, no tocar
        ls_accion-accion    = gc_acc_ganador.
        ls_accion-uuid_nuevo = ls_match-uuid.
        ls_accion-mensaje   = 'CSV confirma UUID actual. Doc ganador, sin cambio.'.
        gv_n_ok_win = gv_n_ok_win + 1.
      ELSE.
*       El CSV asigna un UUID distinto → Reasignar
        ls_accion-accion    = gc_acc_reasig.
        ls_accion-uuid_nuevo = ls_match-uuid.
        CONCATENATE 'UUID incorrecto. CSV asigna:'
          ls_match-uuid INTO ls_accion-mensaje SEPARATED BY space.
        gv_n_reasig = gv_n_reasig + 1.
      ENDIF.

    ELSE.
*     Varios candidatos: comprobar si todos tienen el mismo UUID
      DATA: lv_uuid_ref  TYPE char36,
            lv_ambiguo   TYPE c.
      CLEAR lv_ambiguo.
      READ TABLE lt_match INTO ls_match INDEX 1.
      lv_uuid_ref = ls_match-uuid.

      LOOP AT lt_match INTO ls_match FROM 2.
        IF ls_match-uuid <> lv_uuid_ref.
          lv_ambiguo = 'X'.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF lv_ambiguo = 'X'.
*       Varios candidatos con UUID distintos: no decidir automáticamente
        ls_accion-accion    = gc_acc_ambig.
        ls_accion-uuid_nuevo = space.
        CONCATENATE 'AMBIGUO:', lv_n_match,
          'líneas CSV con UUID distintos para este documento.'
          INTO ls_accion-mensaje SEPARATED BY space.
        gv_n_ambig = gv_n_ambig + 1.
      ELSE.
*       Varios candidatos pero todos con el mismo UUID: situación válida
        IF lv_uuid_ref = ls_doc-uuid_act.
          ls_accion-accion    = gc_acc_ganador.
          ls_accion-uuid_nuevo = lv_uuid_ref.
          ls_accion-mensaje   = 'CSV confirma UUID actual (varios candidatos coincidentes).'.
          gv_n_ok_win = gv_n_ok_win + 1.
        ELSE.
          ls_accion-accion    = gc_acc_reasig.
          ls_accion-uuid_nuevo = lv_uuid_ref.
          CONCATENATE 'UUID incorrecto (varios CSV coincidentes). CSV asigna:'
            lv_uuid_ref INTO ls_accion-mensaje SEPARATED BY space.
          gv_n_reasig = gv_n_reasig + 1.
        ENDIF.
      ENDIF.
    ENDIF.

    APPEND ls_accion TO gt_acciones.
    FREE lt_match.

  ENDLOOP.

  WRITE: / 'Resolución completada:',
           'Reasignar:', gv_n_reasig,
           '/ Ganadores:', gv_n_ok_win,
           '/ Huérfanos:', gv_n_huerfano,
           '/ Ambiguos:', gv_n_ambig.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_BUSCAR_CSV
*&---------------------------------------------------------------------*
*& Busca en gt_csv_idx las líneas CSV que coincidan con el documento.
*& Lógica idéntica al programa principal:
*&   - Clave primaria: rfc_emisor + rfc_receptor + folio + gjahr
*&   - Filtro de importe: trunc(total_csv) = trunc(wrbtr)
*&                        excepto para tipo_cfdi = 'P' (pagos: sin filtro)
*&   - Si clave directa falla: intenta también con receptor/emisor invertidos
*&     (para interco donde ambas son sociedades MX)
*&---------------------------------------------------------------------*
FORM frm_fix_buscar_csv
  USING    ps_doc    TYPE gty_dup_doc
  CHANGING pt_match  TYPE ANY TABLE.

  DATA: ls_csv   TYPE gty_csv_idx,
        ls_match TYPE gty_csv_idx.

  FIELD-SYMBOLS: <pt> TYPE ANY TABLE.
  ASSIGN pt_match TO <pt>.

*  Búsqueda directa: rfc_emisor=CSV.rfc_emisor Y rfc_receptor=CSV.rfc_receptor
  LOOP AT gt_csv_idx INTO ls_csv
    WHERE rfc_emisor   = ps_doc-rfc_emisor
      AND rfc_receptor = ps_doc-rfc_receptor
      AND folio        = ps_doc-folio
      AND gjahr        = ps_doc-gjahr.

*   Filtro de importe (salvo pagos)
    IF ls_csv-tipocomprobante = 'P'
    OR ps_doc-tipo_cfdi       = 'P'
    OR ls_csv-total_num       = ps_doc-total_num
    OR ps_doc-total_num       = 0.     " Si no tenemos importe, aceptar
      APPEND ls_csv TO <pt>.
    ENDIF.
  ENDLOOP.

  IF <pt> IS NOT INITIAL. RETURN. ENDIF.

* Búsqueda alternativa con folio parcial: quitar los primeros caracteres de serie
* (replica la variante del programa principal para ventas)
  IF strlen( ps_doc-folio ) > 4.
    DATA: lv_folio_c   TYPE char20,
          lv_folio_alt TYPE char20.
    lv_folio_c   = ps_doc-folio.
    lv_folio_alt = lv_folio_c+4.
    CONDENSE lv_folio_alt NO-GAPS.

    IF lv_folio_alt IS NOT INITIAL AND lv_folio_alt <> ps_doc-folio.
      LOOP AT gt_csv_idx INTO ls_csv
        WHERE rfc_emisor   = ps_doc-rfc_emisor
          AND rfc_receptor = ps_doc-rfc_receptor
          AND folio        = lv_folio_alt
          AND gjahr        = ps_doc-gjahr.

        IF ls_csv-tipocomprobante = 'P'
        OR ps_doc-tipo_cfdi       = 'P'
        OR ls_csv-total_num       = ps_doc-total_num
        OR ps_doc-total_num       = 0.
          APPEND ls_csv TO <pt>.
        ENDIF.
      ENDLOOP.

      IF <pt> IS NOT INITIAL. RETURN. ENDIF.
    ENDIF.
  ENDIF.

* Si sigue vacío: para interco, probar con RFCs invertidos
  IF ps_doc-tipo_fac = 'I'.
    LOOP AT gt_csv_idx INTO ls_csv
      WHERE rfc_emisor   = ps_doc-rfc_receptor
        AND rfc_receptor = ps_doc-rfc_emisor
        AND folio        = ps_doc-folio
        AND gjahr        = ps_doc-gjahr.

      IF ls_csv-tipocomprobante = 'P'
      OR ps_doc-tipo_cfdi       = 'P'
      OR ls_csv-total_num       = ps_doc-total_num
      OR ps_doc-total_num       = 0.
        APPEND ls_csv TO <pt>.
      ENDIF.
    ENDLOOP.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_APLICAR
*&---------------------------------------------------------------------*
*& Aplica las acciones determinadas en frm_fix_resolver.
*& Procesamiento en paquetes de P_COMMIT con WAIT entre ellos.
*& Por cada paquete:
*&   - REASIGNADO:  SAVE_TEXT con nuevo UUID
*&   - HUERFANO:    DELETE STXH + STXL para ese tdname
*&   - OK_GANADOR:  Sin cambio en SAP, solo actualizar log
*&   - AMBIGUO:     Sin cambio en SAP, log como warning
*&   - ERROR_ESCRIT: registrar en log
*& Al final de cada paquete: UPDATE ZTT_UUID_LOG + COMMIT.
*&---------------------------------------------------------------------*
FORM frm_fix_aplicar.

  DATA: ls_accion    TYPE gty_accion,
        lv_error     TYPE c,
        lt_pkg       TYPE TABLE OF gty_accion,
        lv_from      TYPE i VALUE 1,
        lv_to        TYPE i,
        lv_total_acc TYPE i,
        lv_pkg_idx   TYPE i,
        lt_zlog_upd  TYPE TABLE OF ztt_uuid_log,
        ls_zlog      TYPE ztt_uuid_log,
        lt_del_names TYPE RANGE OF tdobname,
        ls_tdname    LIKE LINE OF lt_del_names.

  lv_total_acc = lines( gt_acciones ).
  WRITE: / 'Aplicando', lv_total_acc, 'acciones en paquetes de', p_commit, '...'.

  DO.
    REFRESH: lt_pkg, lt_zlog_upd, lt_del_names.
    lv_to = lv_from + p_commit - 1.
    IF lv_from > lv_total_acc. EXIT. ENDIF.

    APPEND LINES OF gt_acciones FROM lv_from TO lv_to TO lt_pkg.
    lv_pkg_idx = lv_pkg_idx + 1.
    WRITE: / '  Paquete', lv_pkg_idx, '(acciones', lv_from, '-',
             lv_to MIN lv_total_acc, ')'.

*   ── Procesar cada acción del paquete ─────────────────────────────
    LOOP AT lt_pkg INTO ls_accion.
      CLEAR: lv_error.

      CASE ls_accion-accion.

        WHEN gc_acc_reasig.
*         Reasignar: grabar nuevo UUID con SAVE_TEXT
          IF p_test IS INITIAL.
            PERFORM frm_fix_salvar_uuid
              USING    ls_accion-bukrs ls_accion-belnr ls_accion-gjahr ls_accion-uuid_nuevo
              CHANGING lv_error.
            IF lv_error = 'X'.
              ls_accion-accion  = gc_acc_errw.
              CONCATENATE '[ERROR] No se pudo grabar UUID:' ls_accion-mensaje
                INTO ls_accion-mensaje SEPARATED BY space.
              gv_n_reasig = gv_n_reasig - 1.
              gv_n_error  = gv_n_error  + 1.
            ENDIF.
          ENDIF.

        WHEN gc_acc_huerf.
*         Huérfano: borrar UUID. Acumular tdname para DELETE masivo al final del paquete.
          IF p_test IS INITIAL.
            ls_tdname-sign   = 'I'.
            ls_tdname-option = 'EQ'.
            ls_tdname-low    = ls_accion-tdname.
            APPEND ls_tdname TO lt_del_names.
            gv_n_borrado = gv_n_borrado + 1.
          ENDIF.

        WHEN gc_acc_ganador.
*         Ganador: sin cambio en SAP
          " Nada que hacer en SAP; solo se actualiza el log

        WHEN gc_acc_ambig.
*         Ambiguo: sin cambio en SAP, log como warning
          " Nada que hacer en SAP

        WHEN gc_acc_errw.
          " Ya contabilizado

      ENDCASE.

*     Preparar entrada de ZTT_UUID_LOG para actualizar
      PERFORM frm_fix_preparar_zlog_upd
        USING    ls_accion
        CHANGING ls_zlog.
      APPEND ls_zlog TO lt_zlog_upd.

*     Registro para ALV
      PERFORM frm_fix_append_resultado USING ls_accion.

      MODIFY lt_pkg FROM ls_accion.
    ENDLOOP.

*   ── DELETE masivo de STXH/STXL para huérfanos del paquete ────────
    IF lt_del_names IS NOT INITIAL AND p_test IS INITIAL.
      DELETE FROM stxh
        WHERE tdobject = gc_object
          AND tdid     = gc_tdid
          AND tdspras  = gc_language
          AND tdname   IN lt_del_names.

      DELETE FROM stxl
        WHERE tdobject = gc_object
          AND tdid     = gc_tdid
          AND tdspras  = gc_language
          AND tdname   IN lt_del_names.
    ENDIF.

*   ── UPDATE ZTT_UUID_LOG ──────────────────────────────────────────
    IF lt_zlog_upd IS NOT INITIAL AND p_test IS INITIAL.
      MODIFY ztt_uuid_log FROM TABLE lt_zlog_upd.
    ENDIF.

*   ── COMMIT por paquete ───────────────────────────────────────────
    IF p_test IS INITIAL.
      COMMIT WORK AND WAIT.
    ENDIF.

    FREE: lt_pkg, lt_zlog_upd, lt_del_names.

    IF p_wait > 0.
      WAIT UP TO p_wait SECONDS.
    ENDIF.

    lv_from = lv_from + p_commit.
  ENDDO.

  WRITE: / 'Aplicación completada.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_SALVAR_UUID
*&---------------------------------------------------------------------*
*& Graba un UUID en STXH/STXL mediante SAVE_TEXT (INSERT='X').
*& Si ya existe, lo sobreescribe. Verifica con READ_TEXT después.
*&---------------------------------------------------------------------*
FORM frm_fix_salvar_uuid
  USING    pv_bukrs TYPE bukrs
           pv_belnr TYPE belnr_d
           pv_gjahr TYPE gjahr
           pv_uuid  TYPE char36
  CHANGING pv_error TYPE c.

  DATA: lt_lines TYPE TABLE OF tline WITH HEADER LINE,
        lv_hdr   TYPE thead,
        lv_dummy TYPE char36,
        lv_ok    TYPE c.

  CLEAR pv_error.

  lt_lines-tdformat = '*'.
  lt_lines-tdline   = pv_uuid.
  APPEND lt_lines.

  lv_hdr-tdobject = gc_object.
  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_hdr-tdname.
  CONDENSE lv_hdr-tdname NO-GAPS.
  lv_hdr-tdid   = gc_tdid.
  lv_hdr-tdspras = gc_language.

  CALL FUNCTION 'SAVE_TEXT'
    EXPORTING
      header          = lv_hdr
      insert          = 'X'
      savemode_direct = 'X'
    TABLES
      lines           = lt_lines
    EXCEPTIONS
      OTHERS          = 5.

  IF sy-subrc <> 0.
    pv_error = 'X'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_PREPARAR_ZLOG_UPD
*&---------------------------------------------------------------------*
*& Construye la fila de ZTT_UUID_LOG a actualizar con el resultado.
*&---------------------------------------------------------------------*
FORM frm_fix_preparar_zlog_upd
  USING    ps_acc  TYPE gty_accion
  CHANGING ps_zlog TYPE ztt_uuid_log.

  CLEAR ps_zlog.
  ps_zlog-fichero      = |FIX_DUPL_{ sy-datum }|.
  ps_zlog-bukrs        = ps_acc-bukrs.
  ps_zlog-belnr        = ps_acc-belnr.
  ps_zlog-gjahr        = ps_acc-gjahr.
  ps_zlog-datum_proc   = sy-datum.
  ps_zlog-uzeit_proc   = sy-uzeit.
  ps_zlog-uname        = sy-uname.
  ps_zlog-rfc_emisor   = ps_acc-rfc_emisor.
  ps_zlog-rfc_receptor = ps_acc-rfc_receptor.
  ps_zlog-folio        = ps_acc-folio.
  ps_zlog-tipo_fac     = ps_acc-tipo_fac.
  ps_zlog-tipo         = ps_acc-tipo_cfdi.
  ps_zlog-budat        = ps_acc-budat.
  ps_zlog-blart        = ps_acc-blart.
  ps_zlog-monat        = ps_acc-budat+4(2).
  ps_zlog-uuid         = ps_acc-uuid_nuevo.
  ps_zlog-uuid_previo  = ps_acc-uuid_act.

  CASE ps_acc-accion.
    WHEN gc_acc_reasig.
      ps_zlog-icon_status = gc_icon_ok.
      CONCATENATE '[FIX_DUPL] UUID corregido desde CSV:' ps_acc-uuid_nuevo
        INTO ps_zlog-mensaje SEPARATED BY space.
    WHEN gc_acc_ganador.
      ps_zlog-icon_status = gc_icon_ok.
      ps_zlog-uuid        = ps_acc-uuid_act.   " Se mantiene el actual
      ps_zlog-mensaje     = '[FIX_DUPL] UUID correcto confirmado por CSV (ganador).'.
    WHEN gc_acc_huerf.
      ps_zlog-icon_status = gc_icon_err.
      ps_zlog-uuid        = space.             " Borrado de SAP
      ps_zlog-mensaje     = '[FIX_DUPL] UUID borrado: sin coincidencia en CSV (huérfano).'.
    WHEN gc_acc_ambig.
      ps_zlog-icon_status = gc_icon_warn.
      ps_zlog-uuid        = ps_acc-uuid_act.   " No modificado
      ps_zlog-mensaje     = '[FIX_DUPL] AMBIGUO: varios UUID distintos en CSV. Revisión manual.'.
    WHEN gc_acc_errw.
      ps_zlog-icon_status = gc_icon_err.
      ps_zlog-uuid        = ps_acc-uuid_act.
      ps_zlog-mensaje     = ps_acc-mensaje.
  ENDCASE.

  IF p_test = 'X'.
    CONCATENATE '[SIM]' ps_zlog-mensaje INTO ps_zlog-mensaje SEPARATED BY space.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_APPEND_RESULTADO
*&---------------------------------------------------------------------*
FORM frm_fix_append_resultado
  USING ps_acc TYPE gty_accion.

  DATA: ls_res TYPE gty_resultado.
  CLEAR ls_res.

  ls_res-bukrs         = ps_acc-bukrs.
  ls_res-belnr         = ps_acc-belnr.
  ls_res-gjahr         = ps_acc-gjahr.
  ls_res-uuid_anterior = ps_acc-uuid_act.
  ls_res-uuid_nuevo    = ps_acc-uuid_nuevo.
  ls_res-accion        = ps_acc-accion.
  ls_res-tipo_fac      = ps_acc-tipo_fac.
  ls_res-tipo_cfdi     = ps_acc-tipo_cfdi.
  ls_res-rfc_emisor    = ps_acc-rfc_emisor.
  ls_res-rfc_receptor  = ps_acc-rfc_receptor.
  ls_res-folio         = ps_acc-folio.
  ls_res-budat         = ps_acc-budat.
  ls_res-blart         = ps_acc-blart.
  ls_res-mensaje       = ps_acc-mensaje.

  CASE ps_acc-accion.
    WHEN gc_acc_reasig.   ls_res-icon = gc_icon_ok.
    WHEN gc_acc_ganador.  ls_res-icon = gc_icon_ok.
    WHEN gc_acc_huerf.    ls_res-icon = gc_icon_warn.
    WHEN gc_acc_ambig.    ls_res-icon = gc_icon_warn.
    WHEN gc_acc_errw.     ls_res-icon = gc_icon_err.
    WHEN OTHERS.          ls_res-icon = gc_icon_warn.
  ENDCASE.

  APPEND ls_res TO gt_resultado.

ENDFORM.
