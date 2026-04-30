*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM02
*&---------------------------------------------------------------------*
*& Grabación del UUID mediante SAVE_TEXT y Salida ALV estándar
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_EXISTE_UUID
*&---------------------------------------------------------------------*
FORM frm_existe_uuid
  USING    value(pv_bukrs) TYPE bukrs
           value(pv_belnr) TYPE belnr_d
           value(pv_gjahr) TYPE gjahr
           value(pv_uuid_csv) TYPE char36
  CHANGING pv_status       TYPE c
           pv_uuid_previo  TYPE char36.

  DATA: lt_lines    TYPE TABLE OF tline WITH HEADER LINE,
        lv_name_doc TYPE tdobname.

  pv_status = gc_stat_empty.
  CLEAR pv_uuid_previo.

  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_name_doc.
  CONDENSE lv_name_doc NO-GAPS.

  CALL FUNCTION 'READ_TEXT'
    EXPORTING
      id        = gc_tdid
      language  = gc_language
      name      = lv_name_doc
      object    = gc_object
    TABLES
      lines     = lt_lines
    EXCEPTIONS
      OTHERS    = 8.

  IF sy-subrc = 0.
    READ TABLE lt_lines INDEX 1.
    IF sy-subrc = 0 AND lt_lines-tdline IS NOT INITIAL.
      pv_uuid_previo = lt_lines-tdline.
      IF pv_uuid_previo = pv_uuid_csv.
        pv_status = gc_stat_same.
      ELSE.
        pv_status = gc_stat_diff.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_UUID_EXISTE_EN_BD
*&---------------------------------------------------------------------*
*& CONTROL QUIRÚRGICO OPTIMIZADO: Verifica si el UUID ya existe en
*& CUALQUIER otro documento usando la CACHÉ en memoria (gt_uuid_cache).
*& Retorna 'X' si el UUID ya está asignado a otro documento.
*& OPTIMIZACIÓN: Consulta en memoria (instantánea) vs SELECT (97 seg/registro).
*&---------------------------------------------------------------------*
FORM frm_uuid_existe_en_bd
  USING    value(pv_uuid)  TYPE char36
           value(pv_bukrs) TYPE bukrs
           value(pv_belnr) TYPE belnr_d
           value(pv_gjahr) TYPE gjahr
  CHANGING pv_existe       TYPE c
           pv_bukrs_exist  TYPE bukrs
           pv_belnr_exist  TYPE belnr_d
           pv_gjahr_exist  TYPE gjahr.

  DATA: ls_cache TYPE gty_uuid_cache,
        lv_tdname_actual TYPE tdobname.

  CLEAR: pv_existe, pv_bukrs_exist, pv_belnr_exist, pv_gjahr_exist.

* Construir TDNAME del documento actual (para excluirlo de la búsqueda)
  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_tdname_actual.
  CONDENSE lv_tdname_actual NO-GAPS.

* Buscar UUID en la caché (HASHED TABLE = búsqueda instantánea O(1))
  READ TABLE gt_uuid_cache INTO ls_cache
    WITH TABLE KEY uuid = pv_uuid.

  IF sy-subrc = 0.
*   UUID encontrado en caché: verificar que NO sea el documento actual
    IF ls_cache-tdname <> lv_tdname_actual.
*     UUID existe en OTRO documento
      pv_existe      = 'X'.
      pv_bukrs_exist = ls_cache-bukrs.
      pv_belnr_exist = ls_cache-belnr.
      pv_gjahr_exist = ls_cache-gjahr.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_SALVAR_UUID
*&---------------------------------------------------------------------*
FORM frm_salvar_uuid
  USING    value(pv_bukrs) TYPE bukrs
           value(pv_belnr) TYPE belnr_d
           value(pv_gjahr) TYPE gjahr
           value(pv_uuid)  TYPE char36
  CHANGING pv_error        TYPE c.

  DATA: lt_lines  TYPE TABLE OF tline WITH HEADER LINE,
        lv_header TYPE thead,
        lv_ok     TYPE c,
        lv_dummy  TYPE char36,
        ls_cache  TYPE gty_uuid_cache.

  CLEAR pv_error.
  lt_lines-tdformat = '*'.
  lt_lines-tdline   = pv_uuid.
  APPEND lt_lines.

  lv_header-tdobject = gc_object.
  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_header-tdname.
  lv_header-tdid     = gc_tdid.
  lv_header-tdspras  = gc_language.

  CALL FUNCTION 'SAVE_TEXT'
    EXPORTING
      header          = lv_header
      insert          = 'X'
      savemode_direct = 'X'
    TABLES
      lines           = lt_lines
    EXCEPTIONS
      OTHERS          = 5.

  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr pv_uuid
      CHANGING lv_ok lv_dummy.
    IF lv_ok <> gc_stat_same. pv_error = 'X'. ENDIF.

*   ═══════════════════════════════════════════════════════════════
*   ACTUALIZAR CACHÉ: Añadir el nuevo UUID a la caché en memoria
*   ═══════════════════════════════════════════════════════════════
    IF pv_error = ''.
      CLEAR ls_cache.
      ls_cache-uuid   = pv_uuid.
      ls_cache-bukrs  = pv_bukrs.
      ls_cache-belnr  = pv_belnr.
      ls_cache-gjahr  = pv_gjahr.
      CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO ls_cache-tdname.
      CONDENSE ls_cache-tdname NO-GAPS.
      INSERT ls_cache INTO TABLE gt_uuid_cache.
    ENDIF.

  ELSE.
    pv_error = 'X'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_ALV
*&---------------------------------------------------------------------*
FORM frm_mostrar_alv.
  DATA: lo_alv TYPE REF TO cl_salv_table.
  
  IF gt_log IS INITIAL.
    MESSAGE 'No hay registros procesados.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  TRY.
    cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv CHANGING t_table = gt_log ).
    lo_alv->get_functions( )->set_all( ).
    lo_alv->get_columns( )->set_optimize( ).
    lo_alv->display( ).
  CATCH cx_salv_msg.
    MESSAGE 'Error al mostrar ALV' TYPE 'E'.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_ACTUALIZAR_FACTURA_UUID
*&---------------------------------------------------------------------*
*& Coordina la grabación del UUID para un documento encontrado.
*& En modo test (P_TEST = 'X') no graba, solo registra lo que haría.
*&---------------------------------------------------------------------*
FORM frm_actualizar_factura_uuid
  USING value(ps_datos) TYPE gty_csv_data
        value(pv_bukrs) TYPE bukrs
        value(pv_belnr) TYPE belnr_d
        value(pv_gjahr) TYPE gjahr.

  DATA: lv_error      TYPE c,
        lv_budat      TYPE budat,
        lv_bldat      TYPE bldat,
        lv_blart      TYPE blart.

  CLEAR gs_log.
  gs_log-bukrs        = pv_bukrs.
  gs_log-belnr        = pv_belnr.
  gs_log-gjahr        = pv_gjahr.
  gs_log-rfc_emisor   = ps_datos-rfc_emisor.
  gs_log-rfc_receptor = ps_datos-rfc_receptor.
  gs_log-serie        = ps_datos-serie.
  gs_log-folio        = ps_datos-folio.
  gs_log-tipo         = ps_datos-tipocomprobante.
  gs_log-uuid         = ps_datos-uuid.

* Obtener fechas y clase de documento desde BKPF
  SELECT SINGLE budat bldat blart
    FROM bkpf
    INTO (lv_budat, lv_bldat, lv_blart)
    WHERE bukrs = pv_bukrs
      AND belnr = pv_belnr
      AND gjahr = pv_gjahr.
  gs_log-budat     = lv_budat.
  gs_log-bldat     = lv_bldat.
  gs_log-blart     = lv_blart.
  gs_log-monat     = lv_budat+4(2).
  gs_log-test_mode = p_test.

  DATA: lv_status TYPE c,
        lv_uuid_previo TYPE char36,
        lv_uuid_existe TYPE c,
        lv_bukrs_exist TYPE bukrs,
        lv_belnr_exist TYPE belnr_d,
        lv_gjahr_exist TYPE gjahr.

  IF p_test = ''.
*   ---- MODO PRODUCTIVO: Grabar UUID ----
    " 1. Comprobar si el documento actual ya tiene un UUID
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
      CHANGING lv_status lv_uuid_previo.

    IF lv_status = gc_stat_same OR lv_status = gc_stat_diff.
      " El documento YA tiene un UUID asignado (igual o distinto)
      " Tal y como solicitó el negocio, si ya tiene UUID, se da por correcto en reproceso y NO se sobrescribe.
      gs_log-icon = gc_icon_ok.
      CONCATENATE '[REPROCESO] Documento ya tiene UUID, se asume correcto:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gs_log-uuid_previo = lv_uuid_previo.
      gv_ok = gv_ok + 1.
    ELSE.
      " 2. CONTROL QUIRÚRGICO: Verificar que el UUID NO exista en NINGÚN otro documento
      PERFORM frm_uuid_existe_en_bd
        USING ps_datos-uuid pv_bukrs pv_belnr pv_gjahr
        CHANGING lv_uuid_existe lv_bukrs_exist lv_belnr_exist lv_gjahr_exist.

      IF lv_uuid_existe = 'X'.
*       UUID ya existe en otro documento → ERROR CRÍTICO
        gs_log-icon    = gc_icon_err.
        CONCATENATE 'UUID ya existe en otro documento:' lv_bukrs_exist lv_belnr_exist lv_gjahr_exist
          '(No se graba para evitar duplicado)'
          INTO gs_log-mensaje SEPARATED BY space.
        gv_error = gv_error + 1.
      ELSE.
*       UUID no existe en la BD → Proceder a grabar
        PERFORM frm_salvar_uuid
          USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
          CHANGING lv_error.

        IF lv_error = ''.
*         Grabación exitosa
          gs_log-icon    = gc_icon_ok.
          CONCATENATE 'UUID actualizado correctamente:' pv_bukrs pv_belnr pv_gjahr
            INTO gs_log-mensaje SEPARATED BY space.
          gv_ok = gv_ok + 1.
        ELSE.
*         Error en la grabación
          gs_log-icon    = gc_icon_err.
          CONCATENATE 'Error actualizando UUID en documento:' pv_bukrs pv_belnr pv_gjahr
            INTO gs_log-mensaje SEPARATED BY space.
          gv_error = gv_error + 1.
        ENDIF.
      ENDIF.
    ENDIF.

  ELSE.
*   ---- MODO TEST: Solo simular ----
    " En modo test también comprobamos si ya existe
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
      CHANGING lv_status lv_uuid_previo.

    gs_log-icon    = gc_icon_ok.
    IF lv_status = gc_stat_same OR lv_status = gc_stat_diff.
      CONCATENATE 'SIMULACIÓN: Ya tiene UUID, se asumiría correcto:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gs_log-uuid_previo = lv_uuid_previo.
    ELSE.
      CONCATENATE 'SIMULACIÓN: Se actualizaría UUID en:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
    ENDIF.
    gv_ok = gv_ok + 1.
  ENDIF.

  APPEND gs_log TO gt_log.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_ALV_GLOBAL
*&---------------------------------------------------------------------*
*& Muestra el ALV consolidado de TODOS los ficheros procesados.
*&---------------------------------------------------------------------*
FORM frm_mostrar_alv_global.
  DATA: lo_alv TYPE REF TO cl_salv_table.
  
  IF gt_log_global IS INITIAL.
    MESSAGE 'No hay registros consolidados.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  TRY.
    cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv CHANGING t_table = gt_log_global ).
    lo_alv->get_functions( )->set_all( ).
    lo_alv->get_columns( )->set_optimize( ).
    lo_alv->display( ).
  CATCH cx_salv_msg.
    MESSAGE 'Error al mostrar ALV Global' TYPE 'E'.
  ENDTRY.
ENDFORM.
