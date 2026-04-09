*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM02
*&---------------------------------------------------------------------*
*& Grabación del UUID mediante SAVE_TEXT y Salida ALV estándar
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_EXISTE_UUID
*&---------------------------------------------------------------------*
FORM frm_existe_uuid
  USING    value(pv_bukrs) TYPE char10
           value(pv_belnr) TYPE belnr_d
           value(pv_gjahr) TYPE gjahr
  CHANGING pv_existe       TYPE c
           pv_uuid_previo  TYPE char36.

  DATA: lt_lines    TYPE TABLE OF tline WITH HEADER LINE,
        lv_name_doc TYPE tdobname.

  CLEAR: pv_existe, pv_uuid_previo.
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
      pv_existe = 'X'.
      pv_uuid_previo = lt_lines-tdline.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_SALVAR_UUID
*&---------------------------------------------------------------------*
FORM frm_salvar_uuid
  USING    value(pv_bukrs) TYPE char10
           value(pv_belnr) TYPE belnr_d
           value(pv_gjahr) TYPE gjahr
           value(pv_uuid)  TYPE char36
  CHANGING pv_error        TYPE c.

  DATA: lt_lines  TYPE TABLE OF tline WITH HEADER LINE,
        lv_header TYPE thead,
        lv_ok     TYPE c,
        lv_dummy  TYPE char36.

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
    PERFORM frm_existe_uuid USING pv_bukrs pv_belnr pv_gjahr CHANGING lv_ok lv_dummy.
    IF lv_ok = ''. pv_error = 'X'. ENDIF.
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
        value(pv_bukrs) TYPE char10
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

  IF p_test = ''.
*   ---- MODO PRODUCTIVO: Grabar UUID ----
    PERFORM frm_salvar_uuid
      USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
      CHANGING lv_error.

    IF lv_error = ''.
*     Grabación exitosa
      gs_log-icon    = gc_icon_ok.
      CONCATENATE 'UUID actualizado correctamente:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gv_ok = gv_ok + 1.
    ELSE.
*     Error en la grabación
      gs_log-icon    = gc_icon_err.
      CONCATENATE 'Error actualizando UUID en documento:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gv_error = gv_error + 1.
    ENDIF.

  ELSE.
*   ---- MODO TEST: Solo simular ----
    gs_log-icon    = gc_icon_ok.
    CONCATENATE 'SIMULACIÓN: Se actualizaría UUID en:' pv_bukrs pv_belnr pv_gjahr
      INTO gs_log-mensaje SEPARATED BY space.
    gv_ok = gv_ok + 1.
  ENDIF.

  APPEND gs_log TO gt_log.

ENDFORM.
