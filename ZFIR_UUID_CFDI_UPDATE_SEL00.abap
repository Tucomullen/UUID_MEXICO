*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_SEL00
*&---------------------------------------------------------------------*
*& Lógica de pantalla de selección: F4 help y validaciones
*& Gestión de visibilidad de campos según modo (local/servidor)
*&---------------------------------------------------------------------*

**********************************************************************
** MOSTRAR/OCULTAR CAMPOS SEGÚN MODO SELECCIONADO                  **
**********************************************************************
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
*   Campos con MODIF ID 'LCL' → solo visibles en modo local (fichero/carpeta)
    IF screen-group1 = 'LCL'.
      IF p_serv = 'X'.
        screen-active = 0.
      ELSE.
        screen-active = 1.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
*   Campos con MODIF ID 'SRV' → solo visibles en modo servidor
    IF screen-group1 = 'SRV'.
      IF p_serv = 'X'.
        screen-active = 1.
      ELSE.
        screen-active = 0.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

*&---------------------------------------------------------------------*
*& F4 HELP — FICHERO CSV O CARPETA LOCAL                             *
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM frm_f4_fichero_csv.

*&---------------------------------------------------------------------*
*& F4 HELP — DIRECTORIO DEL SERVIDOR (AL11)                          *
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_sdir.
  PERFORM frm_f4_servidor.

*&---------------------------------------------------------------------*
*& VALIDACIONES DE PANTALLA                                           *
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.
  PERFORM frm_validar_seleccion.

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
*& Form FRM_F4_SERVIDOR
*&---------------------------------------------------------------------*
*& Diálogo F4 para seleccionar un fichero en el servidor SAP (AL11).
*& Extrae el directorio padre del fichero seleccionado.
*&---------------------------------------------------------------------*
FORM frm_f4_servidor.

  DATA: lv_serverfile TYPE string.

  CALL FUNCTION '/SAPDMC/LSM_F4_SERVER_FILE'
    IMPORTING
      serverfile       = lv_serverfile
    EXCEPTIONS
      canceled_by_user = 1
      OTHERS           = 2.

  IF sy-subrc = 0 AND lv_serverfile IS NOT INITIAL.
*   El F4 del servidor devuelve un fichero: extraemos la carpeta padre.
*   Buscar la última barra (\ o /) para quedarnos con la carpeta.
    DATA: lv_pos  TYPE i VALUE -1,
          lv_off  TYPE i,
          lv_char TYPE c LENGTH 1,
          lv_len  TYPE i.

    lv_len = strlen( lv_serverfile ).
    lv_off = lv_len - 1.
    WHILE lv_off >= 0.
      lv_char = lv_serverfile+lv_off(1).
      IF lv_char = '\' OR lv_char = '/'.
        lv_pos = lv_off.
        EXIT.
      ENDIF.
      lv_off = lv_off - 1.
    ENDWHILE.

    IF lv_pos > 0.
      p_sdir = lv_serverfile(lv_pos).
    ELSE.
      p_sdir = lv_serverfile.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_F4_SERVIDOR

*&---------------------------------------------------------------------*
*& Form FRM_VALIDAR_SELECCION
*&---------------------------------------------------------------------*
*& Validaciones de la pantalla de selección
*&---------------------------------------------------------------------*
FORM frm_validar_seleccion.

  DATA: lv_file_str TYPE string,
        lv_len      TYPE i.

* Solo validar si el usuario pulsa "Ejecutar" (F8) o imprime
  CHECK sy-ucomm = 'ONLI' OR sy-ucomm = 'PRIN'.

* ---- Modo servidor ----

  IF p_serv = 'X'.
    IF p_sdir IS INITIAL.
      MESSAGE e398(00) WITH 'Debe indicar la ruta del directorio'
                            'en el servidor (AL11).' '' ''.
    ENDIF.
    RETURN.
  ENDIF.

* ---- Modo carpeta: solo comprobar que se ha informado ----
  IF p_carp = 'X'.
    IF p_file IS INITIAL.
      MESSAGE e398(00) WITH 'Debe indicar la ruta de la carpeta.' '' '' ''.
    ENDIF.
    RETURN.
  ENDIF.

* ---- Modo fichero individual: extensión .csv ----
  IF p_fich = 'X'.
    IF p_file IS INITIAL.
      MESSAGE e398(00) WITH 'Debe indicar la ruta del fichero CSV.' '' '' ''.
    ENDIF.
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
  ENDIF.

ENDFORM.                    " FRM_VALIDAR_SELECCION
