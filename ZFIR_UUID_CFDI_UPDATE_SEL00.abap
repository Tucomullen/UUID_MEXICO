*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_SEL00
*&---------------------------------------------------------------------*
*& Lógica de pantalla de selección: F4 help y validaciones
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_F4_FICHERO_CSV
*&---------------------------------------------------------------------*
*& Diálogo F4: abre selector de fichero o carpeta según el modo activo
*&---------------------------------------------------------------------*
FORM frm_f4_fichero_csv.

* AT SELECTION-SCREEN ON VALUE-REQUEST no sincroniza radio buttons a
* variables ABAP antes de dispararse. Leer el valor directamente de la
* pantalla con DYNP_VALUES_READ para saber qué modo está activo.
  DATA: lt_dynp TYPE TABLE OF dynpread,
        ls_dynp TYPE dynpread.

  ls_dynp-fieldname = 'P_CARP'.
  APPEND ls_dynp TO lt_dynp.

  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname     = sy-cprog
      dynumb     = sy-dynnr
    TABLES
      dynpfields = lt_dynp
    EXCEPTIONS
      OTHERS     = 1.

  READ TABLE lt_dynp INTO ls_dynp INDEX 1.
  IF sy-subrc = 0 AND ls_dynp-fieldvalue = 'X'.
    PERFORM frm_f4_carpeta.
  ELSE.
    PERFORM frm_f4_fichero.
  ENDIF.

ENDFORM.                    " FRM_F4_FICHERO_CSV

*&---------------------------------------------------------------------*
*& Form FRM_F4_FICHERO
*&---------------------------------------------------------------------*
*& Diálogo F4 para seleccionar un fichero CSV concreto
*&---------------------------------------------------------------------*
FORM frm_f4_fichero.

  DATA: lt_filetable TYPE filetable,
        ls_file      TYPE file_table,
        lv_rc        TYPE i,
        lv_action    TYPE i.

  CALL METHOD cl_gui_frontend_services=>file_open_dialog
    EXPORTING
      window_title      = 'Seleccionar archivo CSV'
      default_extension = 'CSV'
      file_filter       = 'Archivos CSV (*.csv)|*.csv|Todos los archivos (*.*)|*.*'
    CHANGING
      file_table        = lt_filetable
      rc                = lv_rc
      user_action       = lv_action
    EXCEPTIONS
      file_open_dialog_failed = 1
      cntl_error              = 2
      error_no_gui            = 3
      not_supported_by_gui    = 4
      OTHERS                  = 5.

  IF sy-subrc = 0 AND lv_action = 0.
    READ TABLE lt_filetable INTO ls_file INDEX 1.
    IF sy-subrc = 0.
      p_file = ls_file-filename.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_F4_FICHERO

*&---------------------------------------------------------------------*
*& Form FRM_F4_CARPETA
*&---------------------------------------------------------------------*
*& Diálogo F4 para seleccionar una carpeta (modo lote)
*&---------------------------------------------------------------------*
FORM frm_f4_carpeta.

  DATA: lv_carpeta   TYPE string,
        lv_ini_folder TYPE string.

* Si ya hay algo en el campo, usarlo como punto de partida
  lv_ini_folder = p_file.

  CALL METHOD cl_gui_frontend_services=>directory_browse
    EXPORTING
      window_title         = 'Seleccionar carpeta con archivos CSV'
      initial_folder       = lv_ini_folder
    CHANGING
      selected_folder      = lv_carpeta
    EXCEPTIONS
      cntl_error           = 1
      error_no_gui         = 2
      not_supported_by_gui = 3
      OTHERS               = 4.

  IF sy-subrc = 0 AND lv_carpeta IS NOT INITIAL.
    p_file = lv_carpeta.
  ENDIF.

ENDFORM.                    " FRM_F4_CARPETA

*&---------------------------------------------------------------------*
*& Form FRM_VALIDAR_SELECCION
*&---------------------------------------------------------------------*
*& Validaciones de la pantalla de selección
*&---------------------------------------------------------------------*
FORM frm_validar_seleccion.

  DATA: lv_file_str TYPE string,
        lv_len      TYPE i.

* En modo carpeta no se valida extensión
  IF p_carp = 'X'.
    RETURN.
  ENDIF.

* Verificar que el archivo tiene extensión .csv
  lv_file_str = p_file.
  lv_len = strlen( lv_file_str ).
  IF lv_len > 4.
    DATA: lv_file_c    TYPE char2048,
          lv_ext_c     TYPE char4,
          lv_off       TYPE i.
    lv_file_c = lv_file_str.
    lv_off = lv_len - 4.
    lv_ext_c = lv_file_c+lv_off(4).
    TRANSLATE lv_ext_c TO UPPER CASE.
    IF lv_ext_c <> '.CSV'.
      MESSAGE e398(00) WITH 'El archivo seleccionado'
                            'no tiene extensión .CSV.' '' ''.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_VALIDAR_SELECCION
