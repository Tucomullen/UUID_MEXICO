*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_FIX_DUPLIC_FRM00
*&---------------------------------------------------------------------*
*& Fase 0: Inicialización de cachés de maestros
*& Fase 1a: Carga de CSVs del servidor (exploración recursiva + parseo)
*& Fase 1b: Detección de UUID duplicados vía JOIN STXH+STXL (1 SELECT)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_INIT_CACHES
*&---------------------------------------------------------------------*
*& Carga completa de T001Z (RFC→BUKRS). LFA1 y KNA1: lazy en FRM01.
*&---------------------------------------------------------------------*
FORM frm_init_caches.

  DATA: ls_entry TYPE gty_t001z_cache.

  REFRESH gt_t001z_cache.

  SELECT paval, bukrs
    FROM t001z
    INTO TABLE @DATA(lt_t001z)
    WHERE party = @gc_party.

  LOOP AT lt_t001z INTO DATA(ls).
    ls_entry-paval = ls-paval.
    ls_entry-bukrs = ls-bukrs.
    INSERT ls_entry INTO TABLE gt_t001z_cache.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_CARGAR_CSVS_SERVIDOR
*&---------------------------------------------------------------------*
*& Explora el directorio recursivamente y lee todos los CSV.
*& Construye gt_csv_by_uuid (hash, búsqueda directa) y
*& gt_csv_all (todos los registros, para búsqueda inversa).
*& Ambas tablas se construyen UNA SOLA VEZ al inicio.
*&---------------------------------------------------------------------*
FORM frm_cargar_csvs_servidor.

  DATA: lt_files TYPE TABLE OF string,
        lv_file  TYPE string.

  REFRESH: gt_csv_by_uuid, gt_csv_all.

  PERFORM frm_explorar_dir_recursivo
    USING    p_sdir
    CHANGING lt_files.

  IF lt_files IS INITIAL.
    MESSAGE s398(00) WITH 'No se encontraron ficheros CSV'
                          'en el directorio indicado.' '' ''.
    RETURN.
  ENDIF.

  LOOP AT lt_files INTO lv_file.
    PERFORM frm_leer_csv_archivo USING lv_file.
  ENDLOOP.

  WRITE: / |CSV cargados en memoria: { lines( gt_csv_all ) } registros de { lines( lt_files ) } ficheros.|.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_EXPLORAR_DIR_RECURSIVO
*&---------------------------------------------------------------------*
*& Usa llamadas al kernel (C_DIR_READ_*) para listar CSV recursivamente.
*& Idéntica lógica al programa de carga para garantizar compatibilidad.
*&---------------------------------------------------------------------*
FORM frm_explorar_dir_recursivo
  USING    pv_dir   TYPE clike
  CHANGING pt_files TYPE string_table.

  DATA: lv_dirname  TYPE char255,
        lv_name     TYPE char255,
        lv_type     TYPE c,
        lv_len      TYPE i,
        lv_err      TYPE i,
        lv_errmsg   TYPE char80,
        lv_fullpath TYPE string,
        lv_sep      TYPE c LENGTH 1,
        lt_subdirs  TYPE TABLE OF string,
        lv_subdir   TYPE string,
        lv_fn_c     TYPE char255,
        lv_fn_len   TYPE i,
        lv_fn_off   TYPE i,
        lv_ext      TYPE string.

  IF pv_dir CS '\'.
    lv_sep = '\'.
  ELSE.
    lv_sep = '/'.
  ENDIF.

  lv_dirname = pv_dir.

* Eliminar barra final si existe
  DATA(lv_dlen) = strlen( lv_dirname ).
  IF lv_dlen > 0.
    DATA(lv_last) = lv_dlen - 1.
    IF lv_dirname+lv_last(1) = '\' OR lv_dirname+lv_last(1) = '/'.
      lv_dirname = lv_dirname(lv_last).
    ENDIF.
  ENDIF.

  CALL 'C_DIR_READ_START' ID 'DIR'    FIELD lv_dirname
                          ID 'FILE'   FIELD space
                          ID 'ERRNO'  FIELD lv_err
                          ID 'ERRMSG' FIELD lv_errmsg.
  IF sy-subrc <> 0. RETURN. ENDIF.

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

    ELSEIF lv_type = 'F' OR lv_type = 'f'
        OR lv_type = ' ' OR lv_type = '-'.
      lv_fn_len = strlen( lv_name ).
      IF lv_fn_len > 4.
        lv_fn_off = lv_fn_len - 4.
        lv_fn_c   = lv_name.
        lv_ext    = lv_fn_c+lv_fn_off(4).
        TRANSLATE lv_ext TO UPPER CASE.
        IF lv_ext = '.CSV'.
          APPEND lv_fullpath TO pt_files.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDDO.

  CALL 'C_DIR_READ_FINISH' ID 'ERRNO'  FIELD lv_err
                           ID 'ERRMSG' FIELD lv_errmsg.

* Recursión: procesar subdirectorios DESPUÉS de cerrar el handle actual
  LOOP AT lt_subdirs INTO lv_subdir.
    PERFORM frm_explorar_dir_recursivo USING lv_subdir CHANGING pt_files.
  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_LEER_CSV_ARCHIVO
*&---------------------------------------------------------------------*
*& Lee un CSV del servidor con OPEN DATASET y parsea cada línea.
*& El separador puede ser ';' o '|'. La primera línea es cabecera.
*& Añade cada registro a:
*&   gt_csv_all     → tabla completa para búsqueda inversa
*&   gt_csv_by_uuid → tabla hash para lookup O(1) por UUID
*&---------------------------------------------------------------------*
FORM frm_leer_csv_archivo
  USING pv_path TYPE string.

  DATA: lv_line   TYPE string,
        ls_datos  TYPE gty_csv_rec,
        lv_tipo   TYPE char10,
        lv_first  TYPE c VALUE 'X'.

  OPEN DATASET pv_path FOR INPUT IN TEXT MODE ENCODING UTF-8.
  IF sy-subrc <> 0. RETURN. ENDIF.

  DO.
    READ DATASET pv_path INTO lv_line.
    IF sy-subrc <> 0. EXIT. ENDIF.

    IF lv_first = 'X'. CLEAR lv_first. CONTINUE. ENDIF.  " Cabecera
    IF lv_line IS INITIAL. CONTINUE. ENDIF.

    CLEAR ls_datos.
    REPLACE ALL OCCURRENCES OF '|' IN lv_line WITH ';'.
    SPLIT lv_line AT ';' INTO
      ls_datos-rfc_emisor
      ls_datos-rfc_receptor
      ls_datos-serie
      ls_datos-folio
      ls_datos-fecha
      ls_datos-total
      lv_tipo
      ls_datos-uuid.

    CONDENSE ls_datos-rfc_emisor   NO-GAPS.
    CONDENSE ls_datos-rfc_receptor NO-GAPS.
    CONDENSE ls_datos-folio        NO-GAPS.
    CONDENSE ls_datos-uuid         NO-GAPS.
    TRANSLATE ls_datos-uuid TO UPPER CASE.
    ls_datos-tipo    = lv_tipo(1).
    ls_datos-fichero = pv_path.

    IF ls_datos-uuid IS INITIAL
    OR strlen( ls_datos-uuid ) <> 36.
      CONTINUE.
    ENDIF.

    APPEND ls_datos TO gt_csv_all.
    INSERT ls_datos INTO TABLE gt_csv_by_uuid.  " Ignora duplicados UUID

  ENDDO.

  CLOSE DATASET pv_path.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_DETECTAR_DUPLICADOS_STXH
*&---------------------------------------------------------------------*
*& NOTA: STXL almacena los textos comprimidos en CLUSTD, no como campo
*& legible TDLINE. Por tanto se usa READ_TEXT por cada entrada de STXH.
*&
*& Algoritmo:
*&   1. SELECT STXH → lista de TDNAME (documentos con UUID asignado).
*&   2. Para cada TDNAME: READ_TEXT → UUID real del documento.
*&   3. Contar ocurrencias por UUID en memoria (tabla hash).
*&   4. Extraer a gt_duplic_docs solo los documentos cuyo UUID
*&      aparece en más de un documento SAP.
*&---------------------------------------------------------------------*
FORM frm_detectar_duplicados_stxh.

  TYPES: BEGIN OF lty_uuid_cnt,
           uuid  TYPE char36,
           count TYPE i,
         END OF lty_uuid_cnt.

  DATA: ls_uuid      TYPE gty_uuid_sap,
        lt_uuid_sap  TYPE TABLE OF gty_uuid_sap,
        lt_cnt       TYPE HASHED TABLE OF lty_uuid_cnt
                     WITH UNIQUE KEY uuid,
        ls_cnt       TYPE lty_uuid_cnt,
        lt_dup_uuids TYPE HASHED TABLE OF char36
                     WITH UNIQUE KEY table_line,
        lt_tlines    TYPE TABLE OF tline,
        ls_tline     TYPE tline,
        lv_uuid      TYPE char36,
        lv_bukrs     TYPE bukrs,
        lv_belnr     TYPE belnr_d,
        lv_gjahr     TYPE gjahr,
        lv_total_stxh TYPE i.

  REFRESH: gt_duplic_docs.
  CLEAR: gv_n_duplic_uuids.

* ── 1. Leer todos los TDNAME de STXH (1 SELECT, sin leer UUID aún) ───
  SELECT tdname
    FROM stxh
    WHERE tdobject = @gc_object
      AND tdid     = @gc_tdid
      AND tdspras  = @gc_language
    INTO TABLE @DATA(lt_stxh).

  IF sy-subrc <> 0 OR lt_stxh IS INITIAL.
    WRITE: / 'No se encontraron textos UUID en STXH.'.
    RETURN.
  ENDIF.

  lv_total_stxh = lines( lt_stxh ).
  WRITE: / |Entradas STXH encontradas: { lv_total_stxh }. Leyendo UUIDs...|.

* ── 2. Para cada TDNAME: parsear PK, filtrar y leer UUID con READ_TEXT ─
  LOOP AT lt_stxh INTO DATA(ls_stxh).

*   Parsear TDNAME → BUKRS(4) + BELNR(10) + GJAHR(4)
    lv_bukrs = ls_stxh-tdname(4).
    lv_belnr = ls_stxh-tdname+4(10).
    lv_gjahr = ls_stxh-tdname+14(4).

    IF s_bukrs IS NOT INITIAL AND lv_bukrs NOT IN s_bukrs. CONTINUE. ENDIF.
    IF s_gjahr IS NOT INITIAL AND lv_gjahr NOT IN s_gjahr. CONTINUE. ENDIF.

*   Leer UUID real (STXL almacena comprimido; READ_TEXT descomprime)
    REFRESH lt_tlines.
    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        client   = sy-mandt
        id       = gc_tdid
        language = gc_language
        name     = ls_stxh-tdname
        object   = gc_object
      TABLES
        lines    = lt_tlines
      EXCEPTIONS
        OTHERS   = 8.

    IF sy-subrc <> 0. CONTINUE. ENDIF.

    READ TABLE lt_tlines INTO ls_tline INDEX 1.
    IF sy-subrc <> 0. CONTINUE. ENDIF.

    lv_uuid = ls_tline-tdline.
    CONDENSE lv_uuid NO-GAPS.
    TRANSLATE lv_uuid TO UPPER CASE.
    IF lv_uuid IS INITIAL OR strlen( lv_uuid ) <> 36. CONTINUE. ENDIF.

    ls_uuid-uuid  = lv_uuid.
    ls_uuid-bukrs = lv_bukrs.
    ls_uuid-belnr = lv_belnr.
    ls_uuid-gjahr = lv_gjahr.
    APPEND ls_uuid TO lt_uuid_sap.

  ENDLOOP.

  IF lt_uuid_sap IS INITIAL.
    WRITE: / 'No hay documentos con UUID para los filtros indicados.'.
    RETURN.
  ENDIF.

* ── 3. Contar ocurrencias por UUID en memoria ─────────────────────────
  LOOP AT lt_uuid_sap INTO DATA(ls_u).
    READ TABLE lt_cnt INTO ls_cnt WITH TABLE KEY uuid = ls_u-uuid.
    IF sy-subrc = 0.
      ls_cnt-count = ls_cnt-count + 1.
      MODIFY TABLE lt_cnt FROM ls_cnt.
    ELSE.
      ls_cnt-uuid  = ls_u-uuid.
      ls_cnt-count = 1.
      INSERT ls_cnt INTO TABLE lt_cnt.
    ENDIF.
  ENDLOOP.

* ── 4. Construir tabla de UUIDs duplicados y documentos afectados ─────
  LOOP AT lt_cnt INTO ls_cnt WHERE count > 1.
    INSERT ls_cnt-uuid INTO TABLE lt_dup_uuids.
    gv_n_duplic_uuids = gv_n_duplic_uuids + 1.
  ENDLOOP.

  LOOP AT lt_uuid_sap INTO ls_uuid.
    IF line_exists( lt_dup_uuids[ table_line = ls_uuid-uuid ] ).
      APPEND ls_uuid TO gt_duplic_docs.
    ENDIF.
  ENDLOOP.

  FREE lt_uuid_sap.

  WRITE: / |UUID duplicados detectados: { gv_n_duplic_uuids }|.
  WRITE: / |Documentos afectados:       { lines( gt_duplic_docs ) }|.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form FRM_CONVERTIR_TOTAL_NUM
*&---------------------------------------------------------------------*
*& Convierte el campo Total del CSV a numérico (misma lógica que
*& el programa de carga ZFIR_UUID_CFDI_UPDATE).
*& Soporta formato europeo "26.640,80" y formato CFDI "41.760.000.000".
*&---------------------------------------------------------------------*
FORM frm_convertir_total_num
  USING    pv_str TYPE char25
  CHANGING pv_num TYPE p.

  DATA: lv_str TYPE string,
        lv_dec TYPE p DECIMALS 2,
        lv_raw TYPE p LENGTH 9 DECIMALS 0,
        lv_6   TYPE p LENGTH 9 DECIMALS 6.

  CLEAR pv_num.
  lv_str = pv_str.
  CONDENSE lv_str NO-GAPS.

  IF lv_str CA ','.
*   Formato europeo: coma = decimal, punto = miles
    REPLACE ALL OCCURRENCES OF ',' IN lv_str WITH '#'.
    REPLACE ALL OCCURRENCES OF '.' IN lv_str WITH ''.
    REPLACE ALL OCCURRENCES OF '#' IN lv_str WITH '.'.
    IF lv_str CO '0123456789.'.
      lv_dec = lv_str.
      pv_num = trunc( lv_dec ).
    ENDIF.
  ELSE.
*   Formato CFDI: sin coma, puntos en posiciones de miles incluyendo 6 decimales
    REPLACE ALL OCCURRENCES OF '.' IN lv_str WITH ''.
    IF lv_str CO '0123456789'.
      lv_raw = lv_str.
      lv_6   = lv_raw / 1000000.
      pv_num = trunc( lv_6 ).
    ENDIF.
  ENDIF.

ENDFORM.
