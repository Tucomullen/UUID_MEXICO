*&---------------------------------------------------------------------*
*& Report ZFIR_UUID_BUSCAR_POR_UUID
*&---------------------------------------------------------------------*
*& Busca documentos contables que tengan asignado uno o varios UUID
*& consultando directamente los textos SAPscript (STXH/STXL)
*& donde el programa ZFIR_UUID_CFDI_UPDATE graba los UUID.
*&---------------------------------------------------------------------*
REPORT zfir_uuid_buscar_por_uuid.

TYPES: BEGIN OF ty_result,
         bukrs TYPE bukrs,
         belnr TYPE belnr_d,
         gjahr TYPE gjahr,
         uuid  TYPE char36,
       END OF ty_result.

DATA: lv_uuid_sel TYPE char36.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
  SELECTION-SCREEN COMMENT /1(40) TEXT-001.
  SELECT-OPTIONS: so_uuid  FOR lv_uuid_sel NO INTERVALS,
                  so_bukrs FOR t001-bukrs,
                  so_gjahr FOR bkpf-gjahr.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  TEXT-001 = 'Sociedad y Ejercicio son opcionales'.

START-OF-SELECTION.

  IF so_uuid IS INITIAL.
    MESSAGE 'Indique al menos un UUID.' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  DATA: lt_stxh          TYPE TABLE OF stxh,
        ls_stxh          TYPE stxh,
        lt_lines         TYPE TABLE OF tline WITH HEADER LINE,
        lt_result        TYPE TABLE OF ty_result,
        ls_result        TYPE ty_result,
        lv_uuid          TYPE char36,
        lt_tdname_filter TYPE RANGE OF tdobname,
        ls_tdname_filter LIKE LINE OF lt_tdname_filter.

  " Construir filtro de TDNAME a partir de sociedad y/o ejercicio
  " TDNAME = BUKRS(4) + BELNR(10) + GJAHR(4)
  IF so_bukrs IS NOT INITIAL AND so_gjahr IS NOT INITIAL.
    " Ambos filtros: patrón '<BUKRS>**********<GJAHR>'
    LOOP AT so_bukrs INTO DATA(ls_bukrs).
      LOOP AT so_gjahr INTO DATA(ls_gjahr).
        ls_tdname_filter-sign   = 'I'.
        ls_tdname_filter-option = 'CP'.
        ls_tdname_filter-low    = ls_bukrs-low && '**********' && ls_gjahr-low.
        APPEND ls_tdname_filter TO lt_tdname_filter.
      ENDLOOP.
    ENDLOOP.
  ELSEIF so_bukrs IS NOT INITIAL.
    " Solo sociedad: patrón '<BUKRS>*'
    LOOP AT so_bukrs INTO ls_bukrs.
      ls_tdname_filter-sign   = 'I'.
      ls_tdname_filter-option = 'CP'.
      ls_tdname_filter-low    = ls_bukrs-low && '*'.
      APPEND ls_tdname_filter TO lt_tdname_filter.
    ENDLOOP.
  ELSEIF so_gjahr IS NOT INITIAL.
    " Solo ejercicio: patrón '**************<GJAHR>'
    LOOP AT so_gjahr INTO DATA(ls_gjahr2).
      ls_tdname_filter-sign   = 'I'.
      ls_tdname_filter-option = 'CP'.
      ls_tdname_filter-low    = '**************' && ls_gjahr2-low.
      APPEND ls_tdname_filter TO lt_tdname_filter.
    ENDLOOP.
  ENDIF.

  " Leer cabeceras de texto filtrando por TDNAME si hay filtros de sociedad/ejercicio
  IF lt_tdname_filter IS NOT INITIAL.
    SELECT * FROM stxh INTO TABLE lt_stxh
      WHERE tdobject = 'BELEG'
        AND tdid     = 'YUUD'
        AND tdspras  = 'S'
        AND tdname   IN lt_tdname_filter.
  ELSE.
    SELECT * FROM stxh INTO TABLE lt_stxh
      WHERE tdobject = 'BELEG'
        AND tdid     = 'YUUD'
        AND tdspras  = 'S'.
  ENDIF.

  IF sy-subrc <> 0.
    MESSAGE 'No existen textos UUID para los filtros indicados.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Indicador de progreso
  DATA: lv_total  TYPE i,
        lv_actual TYPE i.
  lv_total = lines( lt_stxh ).

  LOOP AT lt_stxh INTO ls_stxh.
    lv_actual = lv_actual + 1.
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = CONV i( lv_actual * 100 / lv_total )
        text       = |Procesando { lv_actual } de { lv_total }...|.

    REFRESH lt_lines.
    CLEAR lv_uuid.

    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        id       = 'YUUD'
        language = 'S'
        name     = ls_stxh-tdname
        object   = 'BELEG'
      TABLES
        lines    = lt_lines
      EXCEPTIONS
        OTHERS   = 8.

    IF sy-subrc = 0.
      READ TABLE lt_lines INDEX 1.
      IF sy-subrc = 0 AND lt_lines-tdline IS NOT INITIAL.
        lv_uuid = lt_lines-tdline.
        IF lv_uuid IN so_uuid.
          ls_result-bukrs = ls_stxh-tdname(4).
          ls_result-belnr = ls_stxh-tdname+4(10).
          ls_result-gjahr = ls_stxh-tdname+14(4).
          ls_result-uuid  = lv_uuid.
          APPEND ls_result TO lt_result.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Mostrar resultados
  IF lt_result IS INITIAL.
    MESSAGE 'No se encontró ningún documento con los UUID indicados.' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  DATA: lo_alv TYPE REF TO cl_salv_table.
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_result ).

    DATA(lo_cols) = lo_alv->get_columns( ).
    lo_cols->set_optimize( ).

    CAST cl_salv_column_table( lo_cols->get_column( 'BUKRS' ) )->set_long_text( 'Sociedad' ).
    CAST cl_salv_column_table( lo_cols->get_column( 'BELNR' ) )->set_long_text( 'Nº Documento' ).
    CAST cl_salv_column_table( lo_cols->get_column( 'GJAHR' ) )->set_long_text( 'Ejercicio' ).
    CAST cl_salv_column_table( lo_cols->get_column( 'UUID'  ) )->set_long_text( 'UUID' ).

    lo_alv->get_functions( )->set_all( ).
    lo_alv->display( ).

  CATCH cx_salv_msg cx_salv_not_found cx_salv_data_error.
    MESSAGE 'Error al mostrar los resultados.' TYPE 'E'.
  ENDTRY.
