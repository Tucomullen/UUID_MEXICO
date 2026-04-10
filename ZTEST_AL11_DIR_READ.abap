*&---------------------------------------------------------------------*
*& Report  ZTEST_AL11_DIR_READ
*&---------------------------------------------------------------------*
*& Programa de prueba para verificar lectura de directorios y permisos
*& en AL11 / rutas UNC cruzadas. Útil para descartar problemas BASIS.
*&---------------------------------------------------------------------*
REPORT ztest_al11_dir_read LINE-SIZE 200.

PARAMETERS: p_dir  TYPE string LOWER CASE OBLIGATORY,
            p_file TYPE string LOWER CASE.

START-OF-SELECTION.

  WRITE: / '=================================================='.
  WRITE: / 'TEST 1: EPS_GET_DIRECTORY_LISTING (Estándar SAP)'.
  WRITE: / '=================================================='.
  PERFORM test_eps_get USING p_dir.

  SKIP 2.
  WRITE: / '=================================================='.
  WRITE: / 'TEST 2: C_DIR_READ_START / NEXT (Nivel Kernel)'.
  WRITE: / '=================================================='.
  PERFORM test_c_dir USING p_dir.

  SKIP 2.
  WRITE: / '=================================================='.
  WRITE: / 'TEST 3: OPEN DATASET (Lectura directa)'.
  WRITE: / '=================================================='.
  PERFORM test_open_dataset USING p_dir p_file.

*&---------------------------------------------------------------------*
FORM test_eps_get USING pv_dir TYPE string.
  DATA: lt_dir_list  TYPE TABLE OF epsfili,
        ls_dir       TYPE epsfili,
        lv_dir       TYPE epsf-epsdirnam.

  lv_dir = pv_dir.
  CALL FUNCTION 'EPS_GET_DIRECTORY_LISTING'
    EXPORTING
      dir_name               = lv_dir
    TABLES
      dir_list               = lt_dir_list
    EXCEPTIONS
      OTHERS                 = 99.

  IF sy-subrc <> 0.
    WRITE: / 'ERROR: EPS_GET_DIRECTORY_LISTING devolvió sy-subrc =', sy-subrc.
  ELSE.
    WRITE: / 'ÉXITO: Se encontraron', lines( lt_dir_list ), 'elementos.'.
    LOOP AT lt_dir_list INTO ls_dir.
      WRITE: / '-', ls_dir-name.
      IF sy-tabix > 20.
         WRITE: / '... (mostrando solo los primeros 20)'.
         EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
FORM test_c_dir USING pv_dir TYPE string.
  DATA: lv_dirname   TYPE authb-filename,
        lv_name      TYPE authb-filename,
        lv_type      TYPE c,
        lv_len       TYPE i,
        lv_err       TYPE i,
        lv_errmsg    TYPE char80,
        lv_count     TYPE i.

  lv_dirname = pv_dir.
  
  " Eliminar barra final para evitar cuelgues del SO
  DATA: lv_dirname_len TYPE i.
  lv_dirname_len = strlen( lv_dirname ).
  IF lv_dirname_len > 0.
    lv_dirname_len = lv_dirname_len - 1.
    IF lv_dirname+lv_dirname_len(1) = '\' OR lv_dirname+lv_dirname_len(1) = '/'.
      lv_dirname = lv_dirname(lv_dirname_len).
    ENDIF.
  ENDIF.

  WRITE: / 'Directorio evaluado por Kernel:', lv_dirname.

  CALL 'C_DIR_READ_START' ID 'DIR'    FIELD lv_dirname
                          ID 'FILE'   FIELD space
                          ID 'ERRNO'  FIELD lv_err
                          ID 'ERRMSG' FIELD lv_errmsg.
  IF sy-subrc <> 0.
    WRITE: / 'ERROR en C_DIR_READ_START. sy-subrc=', sy-subrc.
    WRITE: / 'Motivo de Sistema Operativo:', lv_err, '-', lv_errmsg.
    RETURN.
  ENDIF.

  DO.
    CALL 'C_DIR_READ_NEXT' ID 'TYPE'   FIELD lv_type
                           ID 'NAME'   FIELD lv_name
                           ID 'LEN'    FIELD lv_len
                           ID 'ERRNO'  FIELD lv_err
                           ID 'ERRMSG' FIELD lv_errmsg.
    IF sy-subrc <> 0 OR lv_name IS INITIAL.
      EXIT.
    ENDIF.

    lv_count = lv_count + 1.
    WRITE: / '[', lv_type, ']', lv_name.
    
    IF lv_count > 30.
      WRITE: / '... (mostrando solo los primeros 30)'.
      EXIT.
    ENDIF.
  ENDDO.

  CALL 'C_DIR_READ_FINISH' ID 'ERRNO'  FIELD lv_err
                           ID 'ERRMSG' FIELD lv_errmsg.

  WRITE: / 'Total elementos listados (mostrados max 30):', lv_count.
ENDFORM.

*&---------------------------------------------------------------------*
FORM test_open_dataset USING pv_dir TYPE string pv_file TYPE string.
  DATA: lv_target TYPE string,
        lv_line   TYPE string.

  IF pv_file IS NOT INITIAL.
    lv_target = pv_file.
  ELSE.
    lv_target = pv_dir.
  ENDIF.

  WRITE: / 'Intentando hacer OPEN DATASET en:', lv_target.

  " Encoding default por si UTF-8 falla de base
  OPEN DATASET lv_target FOR INPUT IN TEXT MODE ENCODING DEFAULT.
  IF sy-subrc = 0.
    WRITE: / 'ÉXITO: OPEN DATASET OK (SY-SUBRC = 0)'.
    READ DATASET lv_target INTO lv_line.
    IF sy-subrc = 0.
       WRITE: / 'Primera línea contenida (truncada a 60 chars):', lv_line(60).
    ELSE.
       WRITE: / 'Aviso: Descriptor abierto, pero READ DATASET devolvió sy-subrc =', sy-subrc.
    ENDIF.
    CLOSE DATASET lv_target.
  ELSE.
    WRITE: / 'ERROR: OPEN DATASET falló (SY-SUBRC =', sy-subrc, ')'.
    WRITE: / 'Esto suele indicar que el SO deniega el permiso explícitamente o el path no existe.'.
  ENDIF.
ENDFORM.
