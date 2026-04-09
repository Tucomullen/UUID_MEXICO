*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM02
*&---------------------------------------------------------------------*
*& Grabación del UUID mediante SAVE_TEXT (compatible con ZFII_MEXICO_UIID)
*& Verificación con READ_TEXT
*& Salida ALV con CL_SALV_TABLE
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_EXISTE_UUID
*&---------------------------------------------------------------------*
*& Verifica si ya existe un UUID para un documento contable.
*& Usa READ_TEXT con OBJECT='BELEG', ID='YUUD', LANGUAGE='S'.
*& Compatible 100% con ZFII_MEXICO_UIID.
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

* Construir nombre del texto: BUKRS + BELNR + GJAHR (sin separadores)
  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_name_doc.
  CONDENSE lv_name_doc NO-GAPS.

* Leer texto SAPscript
  CALL FUNCTION 'READ_TEXT'
    EXPORTING
      id                      = gc_tdid       " 'YUUD'
      language                = gc_language    " 'S'
      name                    = lv_name_doc
      object                  = gc_object      " 'BELEG'
    TABLES
      lines                   = lt_lines
    EXCEPTIONS
      id                      = 1
      language                = 2
      name                    = 3
      not_found               = 4
      object                  = 5
      reference_check         = 6
      wrong_access_to_archive = 7
      OTHERS                  = 8.

  IF sy-subrc = 0.
    READ TABLE lt_lines INDEX 1.
    IF sy-subrc = 0 AND lt_lines-tdline IS NOT INITIAL.
      pv_existe = 'X'.
      pv_uuid_previo = lt_lines-tdline.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_EXISTE_UUID

*&---------------------------------------------------------------------*
*& Form FRM_SALVAR_UUID
*&---------------------------------------------------------------------*
*& Graba el UUID como texto SAPscript en el documento contable.
*& Usa SAVE_TEXT con OBJECT='BELEG', ID='YUUD', LANGUAGE='S'.
*& Después del COMMIT verifica con READ_TEXT que se grabó correctamente.
*& Compatible 100% con ZFII_MEXICO_UIID.
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

* Verificar autorización para modificar en esta sociedad
  AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
    ID 'BUKRS' FIELD pv_bukrs
    ID 'ACTVT' FIELD gc_actvt_mod.   " '10' = Modificar
  IF sy-subrc <> 0.
    pv_error = 'X'.
    RETURN.
  ENDIF.

* Preparar línea de texto con el UUID
  lt_lines-tdformat = '*'.
  lt_lines-tdline   = pv_uuid.
  APPEND lt_lines.

* Preparar cabecera del texto SAPscript
  lv_header-tdobject = gc_object.     " 'BELEG'
  CONCATENATE pv_bukrs pv_belnr pv_gjahr INTO lv_header-tdname.
  lv_header-tdid     = gc_tdid.       " 'YUUD'
  lv_header-tdspras  = gc_language.   " 'S'

* Grabar el texto
  CALL FUNCTION 'SAVE_TEXT'
    EXPORTING
      header          = lv_header
      insert          = 'X'
      savemode_direct = 'X'
    TABLES
      lines           = lt_lines
    EXCEPTIONS
      id              = 1
      language        = 2
      name            = 3
      object          = 4
      OTHERS          = 5.

  IF sy-subrc = 0.
*   COMMIT individual por registro
    COMMIT WORK AND WAIT.

*   Verificación post-grabación: confirmar que se grabó correctamente
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr
      CHANGING lv_ok lv_dummy.

    IF lv_ok = ''.
*     No se pudo verificar la grabación
      pv_error = 'X'.
    ENDIF.
  ELSE.
*   Error en SAVE_TEXT
    pv_error = 'X'.
  ENDIF.

ENDFORM.                    " FRM_SALVAR_UUID

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

* Determinar tipo de factura para el log
* (se establece según el contexto que llama a esta subrutina)

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
*     Verificar si fue error de autorización
      AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
        ID 'BUKRS' FIELD pv_bukrs
        ID 'ACTVT' FIELD gc_actvt_mod.
      IF sy-subrc <> 0.
        CONCATENATE 'No autorizado para modificar sociedad:' pv_bukrs
          INTO gs_log-mensaje SEPARATED BY space.
      ELSE.
        CONCATENATE 'Error actualizando UUID en documento:' pv_bukrs pv_belnr pv_gjahr
          INTO gs_log-mensaje SEPARATED BY space.
      ENDIF.
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

ENDFORM.                    " FRM_ACTUALIZAR_FACTURA_UUID

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_ALV
*&---------------------------------------------------------------------*
*& Muestra el log de resultados en un ALV usando CL_SALV_TABLE.
*& Incluye semáforos, títulos de columna en español y totales.
*&---------------------------------------------------------------------*
FORM frm_mostrar_alv.

  DATA: lo_alv        TYPE REF TO cl_salv_table,
        lo_columns    TYPE REF TO cl_salv_columns_table,
        lo_column     TYPE REF TO cl_salv_column,
        lo_functions  TYPE REF TO cl_salv_functions_list,
        lo_display    TYPE REF TO cl_salv_display_settings,
        lo_header     TYPE REF TO cl_salv_form_layout_grid,
        lo_flow       TYPE REF TO cl_salv_form_layout_flow,
        lx_msg        TYPE REF TO cx_salv_msg,
        lx_not_found  TYPE REF TO cx_salv_not_found,
        lv_title      TYPE lvc_title,
        lv_text       TYPE char255.

* Si no hay registros en el log, mensaje informativo
  IF gt_log IS INITIAL.
    MESSAGE s398(00) WITH 'No se generaron registros' 'de log.' '' ''.
    RETURN.
  ENDIF.

* Crear instancia ALV
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = gt_log ).
  CATCH cx_salv_msg INTO lx_msg.
    MESSAGE lx_msg TYPE 'E'.
    RETURN.
  ENDTRY.

* Habilitar funciones estándar (filtrar, ordenar, exportar, etc.)
  lo_functions = lo_alv->get_functions( ).
  lo_functions->set_all( abap_true ).

* Configurar display
  lo_display = lo_alv->get_display_settings( ).
  lo_display->set_striped_pattern( abap_true ).

  IF p_test = 'X'.
    lv_title = 'Actualización UUID CFDI — MODO SIMULACIÓN'.
  ELSE.
    lv_title = 'Actualización UUID CFDI — Resultados'.
  ENDIF.
  lo_display->set_list_header( lv_title ).

* Configurar columnas
  lo_columns = lo_alv->get_columns( ).
  lo_columns->set_optimize( abap_true ).

  TRY.
*   Semáforo
    lo_column = lo_columns->get_column( 'ICON' ).
    lo_column->set_short_text( 'Estatus' ).
    lo_column->set_medium_text( 'Estatus' ).
    lo_column->set_long_text( 'Estatus' ).

*   Fichero origen (ocultar en modo fichero único; visible pero informativo)
    lo_column = lo_columns->get_column( 'FICHERO' ).
    lo_column->set_short_text( 'Fichero' ).
    lo_column->set_medium_text( 'Fichero origen' ).
    lo_column->set_long_text( 'Fichero CSV de origen' ).
    lo_column->set_visible( abap_false ).   " Oculto en modo fichero único

*   Sociedad
    lo_column = lo_columns->get_column( 'BUKRS' ).
    lo_column->set_short_text( 'Sociedad' ).
    lo_column->set_medium_text( 'Sociedad' ).
    lo_column->set_long_text( 'Sociedad' ).

*   Documento
    lo_column = lo_columns->get_column( 'BELNR' ).
    lo_column->set_short_text( 'Documento' ).
    lo_column->set_medium_text( 'Nº Documento' ).
    lo_column->set_long_text( 'Número de documento contable' ).

*   Ejercicio
    lo_column = lo_columns->get_column( 'GJAHR' ).
    lo_column->set_short_text( 'Ejerc.' ).
    lo_column->set_medium_text( 'Ejercicio' ).
    lo_column->set_long_text( 'Ejercicio' ).

*   RFC Emisor
    lo_column = lo_columns->get_column( 'RFC_EMISOR' ).
    lo_column->set_short_text( 'RFC Emi.' ).
    lo_column->set_medium_text( 'RFC Emisor' ).
    lo_column->set_long_text( 'RFC Emisor' ).

*   RFC Receptor
    lo_column = lo_columns->get_column( 'RFC_RECEPTOR' ).
    lo_column->set_short_text( 'RFC Rec.' ).
    lo_column->set_medium_text( 'RFC Receptor' ).
    lo_column->set_long_text( 'RFC Receptor' ).

*   Serie
    lo_column = lo_columns->get_column( 'SERIE' ).
    lo_column->set_short_text( 'Serie' ).
    lo_column->set_medium_text( 'Serie' ).
    lo_column->set_long_text( 'Serie del CFDI' ).

*   Folio
    lo_column = lo_columns->get_column( 'FOLIO' ).
    lo_column->set_short_text( 'Folio' ).
    lo_column->set_medium_text( 'Folio' ).
    lo_column->set_long_text( 'Folio del CFDI' ).

*   Tipo comprobante
    lo_column = lo_columns->get_column( 'TIPO' ).
    lo_column->set_short_text( 'TipoCfdi' ).
    lo_column->set_medium_text( 'Tipo Comprob.' ).
    lo_column->set_long_text( 'Tipo de Comprobante CFDI' ).

*   Tipo factura
    lo_column = lo_columns->get_column( 'TIPO_FAC' ).
    lo_column->set_short_text( 'TipoFact' ).
    lo_column->set_medium_text( 'Tipo Factura' ).
    lo_column->set_long_text( 'Tipo Factura (C=Comp V=Vent I=Intr)' ).

*   UUID
    lo_column = lo_columns->get_column( 'UUID' ).
    lo_column->set_short_text( 'UUID' ).
    lo_column->set_medium_text( 'UUID CFDI' ).
    lo_column->set_long_text( 'UUID del CFDI' ).

*   UUID Previo
    lo_column = lo_columns->get_column( 'UUID_PREVIO' ).
    lo_column->set_short_text( 'UUID Prev' ).
    lo_column->set_medium_text( 'UUID Previo' ).
    lo_column->set_long_text( 'UUID previo (si ya existía)' ).

*   Mensaje
    lo_column = lo_columns->get_column( 'MENSAJE' ).
    lo_column->set_short_text( 'Mensaje' ).
    lo_column->set_medium_text( 'Mensaje' ).
    lo_column->set_long_text( 'Descripción del resultado' ).

  CATCH cx_salv_not_found INTO lx_not_found.
*   Si alguna columna no se encuentra, continuar sin error
  ENDTRY.

* Crear cabecera con resumen de contadores
  CREATE OBJECT lo_header.

  IF p_test = 'X'.
    lo_header->create_text(
      row    = 1
      column = 1
      text   = '*** MODO SIMULACIÓN - No se han realizado cambios ***' ).
  ENDIF.

  DATA: lv_text_c TYPE char20.

  WRITE gv_total  TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE 'Total registros procesados:' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = 2 column = 1 text = lv_text ).

  WRITE gv_ok TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE 'Actualizados OK (verde):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = 3 column = 1 text = lv_text ).

  WRITE gv_warning TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE 'UUID ya existente (amarillo):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = 4 column = 1 text = lv_text ).

  WRITE gv_error TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE 'Errores (rojo):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = 5 column = 1 text = lv_text ).

  lo_alv->set_top_of_list( lo_header ).

* Mostrar ALV
  lo_alv->display( ).

ENDFORM.                    " FRM_MOSTRAR_ALV

*&---------------------------------------------------------------------*
*& Form FRM_MOSTRAR_ALV_GLOBAL
*&---------------------------------------------------------------------*
*& Muestra el ALV consolidado de TODOS los ficheros procesados en modo
*& carpeta. Incluye:
*&   - Columna FICHERO visible y destacada (nombre corto del CSV)
*&   - Encabezado con resumen global y desglose por fichero
*&   - Ordenado: errores primero, luego por fichero
*&   - Todas las funciones estándar (filtrar, exportar, etc.)
*&---------------------------------------------------------------------*
FORM frm_mostrar_alv_global.

  DATA: lo_alv        TYPE REF TO cl_salv_table,
        lo_columns    TYPE REF TO cl_salv_columns_table,
        lo_column     TYPE REF TO cl_salv_column,
        lo_functions  TYPE REF TO cl_salv_functions_list,
        lo_display    TYPE REF TO cl_salv_display_settings,
        lo_sorts      TYPE REF TO cl_salv_sorts,
        lo_header     TYPE REF TO cl_salv_form_layout_grid,
        lx_msg        TYPE REF TO cx_salv_msg,
        lx_not_found  TYPE REF TO cx_salv_not_found,
        lx_sort       TYPE REF TO cx_salv_not_found,
        lv_title      TYPE lvc_title,
        lv_text       TYPE char255,
        lv_text_c     TYPE char20,
        lv_row        TYPE i,
        ls_resumen    TYPE gty_resumen_fich.

  IF gt_log_global IS INITIAL.
    MESSAGE s398(00) WITH 'No se generaron registros' 'de log.' '' ''.
    RETURN.
  ENDIF.

* Crear instancia ALV con el log global
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = gt_log_global ).
  CATCH cx_salv_msg INTO lx_msg.
    MESSAGE lx_msg TYPE 'E'.
    RETURN.
  ENDTRY.

* Habilitar funciones estándar (filtrar, ordenar, exportar, etc.)
  lo_functions = lo_alv->get_functions( ).
  lo_functions->set_all( abap_true ).

* Configurar display
  lo_display = lo_alv->get_display_settings( ).
  lo_display->set_striped_pattern( abap_true ).

  IF p_test = 'X'.
    lv_title = 'UUID CFDI — Resultados consolidados — SIMULACIÓN'.
  ELSE.
    lv_title = 'UUID CFDI — Resultados consolidados (todos los ficheros)'.
  ENDIF.
  lo_display->set_list_header( lv_title ).

* Configurar columnas
  lo_columns = lo_alv->get_columns( ).
  lo_columns->set_optimize( abap_true ).

  TRY.
*   Semáforo
    lo_column = lo_columns->get_column( 'ICON' ).
    lo_column->set_short_text( 'Estatus' ).
    lo_column->set_medium_text( 'Estatus' ).
    lo_column->set_long_text( 'Estatus' ).

*   Fichero origen — columna principal visible y amplia
    lo_column = lo_columns->get_column( 'FICHERO' ).
    lo_column->set_short_text( 'Fichero' ).
    lo_column->set_medium_text( 'Fichero CSV' ).
    lo_column->set_long_text( 'Fichero CSV de origen' ).
    lo_column->set_visible( abap_true ).

*   Sociedad
    lo_column = lo_columns->get_column( 'BUKRS' ).
    lo_column->set_short_text( 'Sociedad' ).
    lo_column->set_medium_text( 'Sociedad' ).
    lo_column->set_long_text( 'Sociedad' ).

*   Documento
    lo_column = lo_columns->get_column( 'BELNR' ).
    lo_column->set_short_text( 'Documento' ).
    lo_column->set_medium_text( 'Nº Documento' ).
    lo_column->set_long_text( 'Número de documento contable' ).

*   Ejercicio
    lo_column = lo_columns->get_column( 'GJAHR' ).
    lo_column->set_short_text( 'Ejerc.' ).
    lo_column->set_medium_text( 'Ejercicio' ).
    lo_column->set_long_text( 'Ejercicio' ).

*   RFC Emisor
    lo_column = lo_columns->get_column( 'RFC_EMISOR' ).
    lo_column->set_short_text( 'RFC Emi.' ).
    lo_column->set_medium_text( 'RFC Emisor' ).
    lo_column->set_long_text( 'RFC Emisor' ).

*   RFC Receptor
    lo_column = lo_columns->get_column( 'RFC_RECEPTOR' ).
    lo_column->set_short_text( 'RFC Rec.' ).
    lo_column->set_medium_text( 'RFC Receptor' ).
    lo_column->set_long_text( 'RFC Receptor' ).

*   Serie
    lo_column = lo_columns->get_column( 'SERIE' ).
    lo_column->set_short_text( 'Serie' ).
    lo_column->set_medium_text( 'Serie' ).
    lo_column->set_long_text( 'Serie del CFDI' ).

*   Folio
    lo_column = lo_columns->get_column( 'FOLIO' ).
    lo_column->set_short_text( 'Folio' ).
    lo_column->set_medium_text( 'Folio' ).
    lo_column->set_long_text( 'Folio del CFDI' ).

*   Tipo comprobante
    lo_column = lo_columns->get_column( 'TIPO' ).
    lo_column->set_short_text( 'TipoCfdi' ).
    lo_column->set_medium_text( 'Tipo Comprob.' ).
    lo_column->set_long_text( 'Tipo de Comprobante CFDI' ).

*   Tipo factura
    lo_column = lo_columns->get_column( 'TIPO_FAC' ).
    lo_column->set_short_text( 'TipoFact' ).
    lo_column->set_medium_text( 'Tipo Factura' ).
    lo_column->set_long_text( 'Tipo Factura (C=Comp V=Vent I=Intr)' ).

*   UUID
    lo_column = lo_columns->get_column( 'UUID' ).
    lo_column->set_short_text( 'UUID' ).
    lo_column->set_medium_text( 'UUID CFDI' ).
    lo_column->set_long_text( 'UUID del CFDI' ).

*   UUID Previo
    lo_column = lo_columns->get_column( 'UUID_PREVIO' ).
    lo_column->set_short_text( 'UUID Prev' ).
    lo_column->set_medium_text( 'UUID Previo' ).
    lo_column->set_long_text( 'UUID previo (si ya existía)' ).

*   Mensaje
    lo_column = lo_columns->get_column( 'MENSAJE' ).
    lo_column->set_short_text( 'Mensaje' ).
    lo_column->set_medium_text( 'Mensaje' ).
    lo_column->set_long_text( 'Descripción del resultado' ).

  CATCH cx_salv_not_found INTO lx_not_found.
  ENDTRY.

* Ordenación: icono DESCENDENTE (errores @0A@ primero) + fichero ASCENDENTE
  lo_sorts = lo_alv->get_sorts( ).
  TRY.
    lo_sorts->add_sort( columnname = 'ICON' ).
    lo_sorts->add_sort( columnname = 'FICHERO' ).
  CATCH cx_salv_not_found INTO lx_sort.
  CATCH cx_salv_data_error.
  CATCH cx_salv_existing.
  ENDTRY.

* ----------------------------------------------------------------
* Construir encabezado con resumen global + desglose por fichero
* ----------------------------------------------------------------
  CREATE OBJECT lo_header.
  lv_row = 1.

  IF p_test = 'X'.
    lo_header->create_text(
      row    = lv_row
      column = 1
      text   = '*** MODO SIMULACIÓN — No se han realizado cambios ***' ).
    lv_row = lv_row + 1.
  ENDIF.

* Totales globales
  WRITE gv_g_ficheros TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE '  Ficheros procesados:' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = lv_row column = 1 text = lv_text ).
  lv_row = lv_row + 1.

  WRITE gv_g_total TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE '  Total registros:' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = lv_row column = 1 text = lv_text ).
  lv_row = lv_row + 1.

  WRITE gv_g_ok TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE '  Actualizados OK (verde):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = lv_row column = 1 text = lv_text ).
  lv_row = lv_row + 1.

  WRITE gv_g_warning TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE '  UUID ya existente (amarillo):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = lv_row column = 1 text = lv_text ).
  lv_row = lv_row + 1.

  WRITE gv_g_error TO lv_text_c LEFT-JUSTIFIED.
  lv_text = lv_text_c.
  CONCATENATE '  Errores (rojo):' lv_text INTO lv_text SEPARATED BY space.
  lo_header->create_text( row = lv_row column = 1 text = lv_text ).
  lv_row = lv_row + 1.

* Separador
  lo_header->create_text( row = lv_row column = 1
    text = '  ─────────────────────────────────────────────────────────────' ).
  lv_row = lv_row + 1.

* Cabecera de la tabla de resumen por fichero
  lo_header->create_text( row = lv_row column = 1
    text = '  Fichero                              Total    OK   Warn   Error' ).
  lv_row = lv_row + 1.

* Detalle por fichero
  LOOP AT gt_resumen_fich INTO ls_resumen.
    DATA: lv_c_tot TYPE char6,
          lv_c_ok  TYPE char6,
          lv_c_war TYPE char6,
          lv_c_err TYPE char6.

    WRITE ls_resumen-total   TO lv_c_tot RIGHT-JUSTIFIED.
    WRITE ls_resumen-ok      TO lv_c_ok  RIGHT-JUSTIFIED.
    WRITE ls_resumen-warning TO lv_c_war RIGHT-JUSTIFIED.
    WRITE ls_resumen-error   TO lv_c_err RIGHT-JUSTIFIED.

    CONCATENATE '  ' ls_resumen-fichero(36)
                '   ' lv_c_tot
                '  ' lv_c_ok
                '  ' lv_c_war
                '  ' lv_c_err
      INTO lv_text.

    lo_header->create_text( row = lv_row column = 1 text = lv_text ).
    lv_row = lv_row + 1.
  ENDLOOP.

  lo_alv->set_top_of_list( lo_header ).

* Mostrar ALV consolidado
  lo_alv->display( ).

ENDFORM.                    " FRM_MOSTRAR_ALV_GLOBAL
