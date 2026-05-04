*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLICATES_F02
*&---------------------------------------------------------------------*
*& Fase B: Carga del índice CSV desde el servidor AL11.
*&
*& Estrategia de bajo impacto en memoria:
*&   - Exploración recursiva del directorio (igual que el programa principal)
*&   - Lectura CSV línea a línea con OPEN DATASET (sin GUI, compatible batch)
*&   - Filtro inmediato: solo las líneas cuyos RFC están en gt_rfcs_rel
*&   - gt_rfcs_rel se construyó en F01 con solo los RFC implicados en duplicados
*&   - El índice resultante gt_csv_idx es una fracción mínima del total de CSV
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_FIX_CARGAR_CSVS
*&---------------------------------------------------------------------*
*& Punto de entrada de la fase B.
*& Lista CSVs recursivamente y los procesa uno a uno.
*&---------------------------------------------------------------------*
FORM frm_fix_cargar_csvs.

  DATA: lt_files TYPE TABLE OF gty_server_file_fx,
        ls_file  TYPE gty_server_file_fx,
        lv_nfich TYPE i,
        lv_idx   TYPE i.

  IF gt_rfcs_rel IS INITIAL.
    WRITE: / 'Aviso: no hay RFCs relevantes, se omite carga de CSV.'.
    RETURN.
  ENDIF.

  WRITE: / 'Explorando CSVs en servidor:', p_sdir.

  PERFORM frm_fix_listar_csv_serv USING p_sdir
                                  CHANGING lt_files.

  lv_nfich = lines( lt_files ).
  WRITE: / '  CSV encontrados:', lv_nfich.

  IF lv_nfich = 0.
    WRITE: / 'No se encontraron CSV en el servidor.'.
    RETURN.
  ENDIF.

  LOOP AT lt_files INTO ls_file.
    lv_idx = lv_idx + 1.
    IF lv_idx MOD 50 = 0 OR lv_idx = lv_nfich.
      WRITE: / '  Indexando CSV', lv_idx, '/', lv_nfich, ':', ls_file-filename.
    ENDIF.
    PERFORM frm_fix_indexar_csv USING ls_file-fullpath.
    IF p_wait > 0 AND lv_idx MOD 100 = 0.
      WAIT UP TO p_wait SECONDS.
    ENDIF.
  ENDLOOP.

  WRITE: / '  Índice CSV construido:', lines( gt_csv_idx ), 'entradas relevantes.'.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_LISTAR_CSV_SERV
*&---------------------------------------------------------------------*
*& Exploración recursiva del servidor: igual lógica que FRM00 del
*& programa principal pero usando tipos locales (sin INCLUDE de aquel).
*&---------------------------------------------------------------------*
FORM frm_fix_listar_csv_serv
  USING    pv_dir    TYPE char255
  CHANGING pt_files  TYPE ANY TABLE.

  DATA: lv_dirname     TYPE char255,
        lv_name        TYPE char255,
        lv_type        TYPE c,
        lv_len         TYPE i,
        lv_err         TYPE i,
        lv_errmsg      TYPE char80,
        lv_fullpath    TYPE char255,
        lv_sep         TYPE c LENGTH 1,
        lv_dirname_len TYPE i,
        lt_subdirs     TYPE TABLE OF char255,
        lv_subdir      TYPE char255.

  IF pv_dir CS '\'. lv_sep = '\'. ELSE. lv_sep = '/'. ENDIF.

  lv_dirname = pv_dir.
  lv_dirname_len = strlen( lv_dirname ).
  IF lv_dirname_len > 0.
    DATA: lv_last TYPE i.
    lv_last = lv_dirname_len - 1.
    IF lv_dirname+lv_last(1) = '\' OR lv_dirname+lv_last(1) = '/'.
      lv_dirname = lv_dirname(lv_last).
    ENDIF.
  ENDIF.

  CALL 'C_DIR_READ_START' ID 'DIR'    FIELD lv_dirname
                          ID 'FILE'   FIELD space
                          ID 'ERRNO'  FIELD lv_err
                          ID 'ERRMSG' FIELD lv_errmsg.
  IF sy-subrc <> 0.
    WRITE: / 'Aviso: no se pudo leer directorio:', lv_dirname.
    RETURN.
  ENDIF.

  DO.
    CALL 'C_DIR_READ_NEXT' ID 'TYPE'   FIELD lv_type
                           ID 'NAME'   FIELD lv_name
                           ID 'LEN'    FIELD lv_len
                           ID 'ERRNO'  FIELD lv_err
                           ID 'ERRMSG' FIELD lv_errmsg.
    IF sy-subrc <> 0 OR lv_name IS INITIAL. EXIT. ENDIF.
    IF lv_name = '.' OR lv_name = '..'. CONTINUE. ENDIF.

    CONCATENATE lv_dirname lv_sep lv_name INTO lv_fullpath.

    IF lv_type = 'D' OR lv_type = 'd'.
      APPEND lv_fullpath TO lt_subdirs.
    ELSEIF lv_type = 'F' OR lv_type = 'f' OR lv_type = ' ' OR lv_type = '-'.
      DATA: lv_fn_len TYPE i,
            lv_fn_off TYPE i,
            lv_fn_c   TYPE char255,
            lv_ext    TYPE string.
      lv_fn_len = strlen( lv_name ).
      IF lv_fn_len > 4.
        lv_fn_off = lv_fn_len - 4.
        lv_fn_c = lv_name.
        lv_ext = lv_fn_c+lv_fn_off(4).
        TRANSLATE lv_ext TO UPPER CASE.
        IF lv_ext = '.CSV'.
          APPEND VALUE gty_server_file_fx(
            fullpath = lv_fullpath
            filename = lv_name ) TO pt_files.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDDO.

  CALL 'C_DIR_READ_FINISH' ID 'ERRNO'  FIELD lv_err
                           ID 'ERRMSG' FIELD lv_errmsg.

  LOOP AT lt_subdirs INTO lv_subdir.
    PERFORM frm_fix_listar_csv_serv USING lv_subdir CHANGING pt_files.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_INDEXAR_CSV
*&---------------------------------------------------------------------*
*& Lee un CSV del servidor línea a línea (OPEN DATASET).
*& Por cada línea: parsea campos → verifica si rfc_emisor o rfc_receptor
*& están en gt_rfcs_rel → si sí, inserta en gt_csv_idx.
*& Descarta inmediatamente las líneas no relevantes (mínima memoria).
*&---------------------------------------------------------------------*
FORM frm_fix_indexar_csv
  USING pv_path TYPE string.

  DATA: lv_line    TYPE string,
        ls_idx     TYPE gty_csv_idx,
        lv_is_hdr  TYPE c VALUE 'X',   " Flag primera línea (cabecera)
        lv_total_s TYPE char25.

  OPEN DATASET pv_path FOR INPUT IN TEXT MODE ENCODING UTF-8.
  IF sy-subrc <> 0.
    WRITE: / '  Aviso: no se pudo abrir CSV:', pv_path.
    RETURN.
  ENDIF.

  DO.
    READ DATASET pv_path INTO lv_line.
    IF sy-subrc <> 0. EXIT. ENDIF.

*   Saltar cabecera (primera línea)
    IF lv_is_hdr = 'X'.
      CLEAR lv_is_hdr.
      CONTINUE.
    ENDIF.

    IF lv_line IS INITIAL. CONTINUE. ENDIF.

*   Parsear: formato RFC_EMI;RFC_REC;SERIE;FOLIO;FECHA;TOTAL;TIPO;UUID
    CLEAR: ls_idx, lv_total_s.
    REPLACE ALL OCCURRENCES OF '|' IN lv_line WITH ';'.

    DATA: lv_serie  TYPE char10,
          lv_fecha  TYPE char30.

    SPLIT lv_line AT ';' INTO
      ls_idx-rfc_emisor
      ls_idx-rfc_receptor
      lv_serie
      ls_idx-folio
      lv_fecha
      lv_total_s
      ls_idx-tipocomprobante
      ls_idx-uuid.

    CONDENSE ls_idx-rfc_emisor   NO-GAPS.
    CONDENSE ls_idx-rfc_receptor NO-GAPS.
    CONDENSE ls_idx-folio        NO-GAPS.
    CONDENSE ls_idx-uuid         NO-GAPS.
    CONDENSE ls_idx-tipocomprobante NO-GAPS.
    TRANSLATE ls_idx-uuid            TO UPPER CASE.
    TRANSLATE ls_idx-tipocomprobante TO UPPER CASE.

    IF ls_idx-uuid IS INITIAL OR strlen( ls_idx-uuid ) <> 36. CONTINUE. ENDIF.

*   Filtro de relevancia: al menos uno de los RFCs debe estar en gt_rfcs_rel
    IF NOT ( line_exists( gt_rfcs_rel[ table_line = ls_idx-rfc_emisor ] )
          OR line_exists( gt_rfcs_rel[ table_line = ls_idx-rfc_receptor ] ) ).
      CONTINUE.
    ENDIF.

*   Extraer año de la fecha
    CONDENSE lv_fecha NO-GAPS.
    IF strlen( lv_fecha ) >= 10.
      DATA: lv_fecha_c TYPE char30.
      lv_fecha_c = lv_fecha.
      DATA: lv_anio_s TYPE string.
      lv_anio_s = lv_fecha_c+6(4).
      IF lv_anio_s CO '0123456789'.
        ls_idx-gjahr = lv_anio_s.
      ENDIF.
    ENDIF.

*   Convertir total a numérico entero truncado
    CONDENSE lv_total_s NO-GAPS.
    PERFORM frm_fix_convertir_total
      USING    lv_total_s
      CHANGING ls_idx-total_num.

*   Insertar en índice (SORTED: acepta duplicados con NON-UNIQUE KEY)
    INSERT ls_idx INTO TABLE gt_csv_idx.

  ENDDO.

  CLOSE DATASET pv_path.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_FIX_CONVERTIR_TOTAL
*&---------------------------------------------------------------------*
*& Replica exacta de FRM_CONVERTIR_TOTAL del programa principal.
*& Convierte el campo Total del CSV a entero truncado.
*&---------------------------------------------------------------------*
FORM frm_fix_convertir_total
  USING    pv_total_str TYPE char25
  CHANGING pv_total_num TYPE p.

  DATA: lv_str   TYPE string,
        lv_dec   TYPE p DECIMALS 2,
        lv_raw   TYPE p LENGTH 9 DECIMALS 0,
        lv_6dec  TYPE p LENGTH 9 DECIMALS 6.

  CLEAR pv_total_num.
  lv_str = pv_total_str.
  CONDENSE lv_str NO-GAPS.

  IF lv_str CA ','.
    REPLACE ALL OCCURRENCES OF ',' IN lv_str WITH '#'.
    REPLACE ALL OCCURRENCES OF '.' IN lv_str WITH ''.
    REPLACE ALL OCCURRENCES OF '#' IN lv_str WITH '.'.
    IF lv_str CO '0123456789.'.
      lv_dec = lv_str.
      pv_total_num = trunc( lv_dec ).
    ENDIF.
  ELSE.
    REPLACE ALL OCCURRENCES OF '.' IN lv_str WITH ''.
    IF lv_str CO '0123456789'.
      lv_raw = lv_str.
      lv_6dec = lv_raw / 1000000.
      pv_total_num = trunc( lv_6dec ).
    ENDIF.
  ENDIF.

ENDFORM.
