*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM00
*&---------------------------------------------------------------------*
*& Lectura y parseo del archivo CSV desde equipo local
*& Bucle principal de procesamiento de registros
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_LEER_CSV_LOCAL
*&---------------------------------------------------------------------*
*& Lee el archivo CSV desde el equipo local del usuario usando
*& cl_gui_frontend_services=>gui_upload y parsea cada línea.
*& Maneja BOM UTF-8 y salta la cabecera.
*&---------------------------------------------------------------------*
FORM frm_leer_csv_local.

  DATA: lt_file_t   TYPE TABLE OF string,
        lv_line     TYPE string,
        ls_datos    TYPE gty_csv_data,
        lv_index    TYPE i,
        lv_filename TYPE string.

* Convertir nombre de fichero a string
  lv_filename = p_file.

* Subir el archivo desde equipo local
  CALL METHOD cl_gui_frontend_services=>gui_upload
    EXPORTING
      filename                = lv_filename
    CHANGING
      data_tab                = lt_file_t
    EXCEPTIONS
      file_open_error         = 1
      file_read_error         = 2
      no_batch                = 3
      gui_refuse_filetransfer = 4
      invalid_type            = 5
      no_authority            = 6
      unknown_error           = 7
      bad_data_format         = 8
      header_not_allowed      = 9
      separator_not_allowed   = 10
      header_too_long         = 11
      unknown_dp_error        = 12
      access_denied           = 13
      dp_out_of_memory        = 14
      disk_full               = 15
      dp_timeout              = 16
      not_supported_by_gui    = 17
      error_no_gui            = 18
      OTHERS                  = 19.

  IF sy-subrc <> 0.
    MESSAGE e398(00) WITH 'Error al leer el archivo CSV.'
                          'Verifique la ruta y permisos.' '' ''.
    RETURN.
  ENDIF.

* Verificar que se han leído datos
  IF lt_file_t IS INITIAL.
    MESSAGE s398(00) WITH 'El archivo CSV está vacío.' '' '' ''
                          DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

* Limpiar tabla de datos
  REFRESH gt_csv_data.

* Recorrer las líneas del archivo
  LOOP AT lt_file_t INTO lv_line.
    lv_index = sy-tabix.

*   Primera línea: puede tener BOM UTF-8, siempre es cabecera -> saltar
    IF lv_index = 1.
*     Eliminar BOM UTF-8 si existe (bytes EF BB BF al inicio)
*     En strings ABAP pueden aparecer como caracteres especiales al inicio
      PERFORM frm_eliminar_bom CHANGING lv_line.
      CONTINUE. " Saltar línea de cabecera
    ENDIF.

*   Ignorar líneas vacías
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

*   Parsear la línea CSV (separador: punto y coma o pipe)
    CLEAR ls_datos.
*   Reemplazar pipes por punto y coma para unificar el separador
    REPLACE ALL OCCURRENCES OF '|' IN lv_line WITH ';'.
    SPLIT lv_line AT ';' INTO
      ls_datos-rfc_emisor
      ls_datos-rfc_receptor
      ls_datos-serie
      ls_datos-folio
      ls_datos-fecha
      ls_datos-total
      ls_datos-tipocomprobante
      ls_datos-uuid.

*   Limpiar espacios
    CONDENSE ls_datos-rfc_emisor NO-GAPS.
    CONDENSE ls_datos-rfc_receptor NO-GAPS.
    CONDENSE ls_datos-serie NO-GAPS.
    CONDENSE ls_datos-folio NO-GAPS.
    CONDENSE ls_datos-uuid NO-GAPS.
    CONDENSE ls_datos-tipocomprobante NO-GAPS.

*   Convertir UUID y tipo comprobante a mayúsculas
    TRANSLATE ls_datos-uuid TO UPPER CASE.
    TRANSLATE ls_datos-tipocomprobante TO UPPER CASE.

*   Si no hay UUID, saltar el registro sin error
    IF ls_datos-uuid IS INITIAL.
      CONTINUE.
    ENDIF.

*   Validar formato UUID (36 chars con guiones)
    IF strlen( ls_datos-uuid ) <> 36.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ls_datos-rfc_emisor.
      gs_log-rfc_receptor = ls_datos-rfc_receptor.
      gs_log-serie        = ls_datos-serie.
      gs_log-folio        = ls_datos-folio.
      gs_log-tipo         = ls_datos-tipocomprobante.
      gs_log-uuid         = ls_datos-uuid.
      gs_log-mensaje      = 'UUID con formato incorrecto (debe ser 36 caracteres)'.
      APPEND gs_log TO gt_log.
      gv_error = gv_error + 1.
      CONTINUE.
    ENDIF.

*   Añadir a tabla de datos válidos
    APPEND ls_datos TO gt_csv_data.

  ENDLOOP.

ENDFORM.                    " FRM_LEER_CSV_LOCAL

*&---------------------------------------------------------------------*
*& Form FRM_ELIMINAR_BOM
*&---------------------------------------------------------------------*
*& Elimina el BOM UTF-8 (EF BB BF) del inicio de una línea si existe
*&---------------------------------------------------------------------*
FORM frm_eliminar_bom
  CHANGING pv_line TYPE string.

  DATA: lv_len    TYPE i,
        lv_char1  TYPE x LENGTH 1,
        lv_hex    TYPE xstring,
        lv_first3 TYPE string.

* El BOM en UTF-8 son los bytes EF BB BF. En SAP pueden manifestarse
* como caracteres especiales al inicio del string. Comprobamos si los
* primeros caracteres son no-imprimibles y los eliminamos.
  lv_len = strlen( pv_line ).
  IF lv_len >= 1.
*   Verificar si el primer carácter es un carácter BOM conocido
*   (en codificación interna SAP puede aparecer como FEFF o similar)
    DATA: lv_first TYPE c LENGTH 1,
          lv_line_c TYPE char10.
    lv_line_c = pv_line.
    lv_first = lv_line_c+0(1).
*   Si el primer carácter tiene valor hex > 7F, probablemente es BOM
    DATA: lv_cp TYPE i.
    lv_cp = cl_abap_conv_out_ce=>uccp( lv_first ).
    IF lv_cp = 65279     " FEFF = BOM UTF-16/UTF-8 manifestado
    OR lv_cp = 239.      " EF = primer byte BOM UTF-8
*     Eliminar hasta 3 caracteres BOM del inicio
      IF lv_len >= 3.
        DATA: lv_cp2 TYPE i,
              lv_cp3 TYPE i.
        lv_cp2 = cl_abap_conv_out_ce=>uccp( lv_line_c+1(1) ).
        lv_cp3 = cl_abap_conv_out_ce=>uccp( lv_line_c+2(1) ).
        IF ( lv_cp = 239 AND lv_cp2 = 187 AND lv_cp3 = 191 ). " EF BB BF
          SHIFT pv_line BY 3 PLACES LEFT.
        ELSEIF lv_cp = 65279. " FEFF como un solo carácter
          SHIFT pv_line BY 1 PLACES LEFT.
        ENDIF.
      ELSEIF lv_cp = 65279.
        SHIFT pv_line BY 1 PLACES LEFT.
      ENDIF.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_ELIMINAR_BOM

*&---------------------------------------------------------------------*
*& Form FRM_LISTAR_CSV_CARPETA
*&---------------------------------------------------------------------*
*& Lista todos los ficheros CSV de una carpeta local y devuelve sus
*& rutas completas en pt_files (TYPE filetable).
*&---------------------------------------------------------------------*
FORM frm_listar_csv_carpeta
  USING    pv_carpeta TYPE string
  CHANGING pt_files   TYPE filetable.

  DATA: lv_count   TYPE i,
        ls_file    TYPE file_table,
        lv_sep     TYPE c LENGTH 1,
        lv_base    TYPE string.

  REFRESH pt_files.

* Obtener separador de ruta del SO (\ en Windows, / en Unix)
  CALL METHOD cl_gui_frontend_services=>get_file_separator
    CHANGING
      file_separator = lv_sep
    EXCEPTIONS
      OTHERS         = 1.
  IF lv_sep IS INITIAL.
    lv_sep = '\'.
  ENDIF.

* Listar ficheros CSV en la carpeta
  CALL METHOD cl_gui_frontend_services=>directory_list_files
    EXPORTING
      directory            = pv_carpeta
      filter               = '*.csv'
    CHANGING
      file_table           = pt_files
      count                = lv_count
    EXCEPTIONS
      cntl_error           = 1
      error_no_gui         = 2
      not_supported_by_gui = 3
      OTHERS               = 4.

  IF sy-subrc <> 0 OR lv_count = 0.
    REFRESH pt_files.
    RETURN.
  ENDIF.

* Si directory_list_files devuelve solo nombres (sin ruta), construir ruta completa
* Comprobamos si el primer resultado ya contiene la carpeta; si no, la añadimos
  READ TABLE pt_files INTO ls_file INDEX 1.
  IF sy-subrc = 0 AND ls_file-filename NS pv_carpeta.
*   Los nombres no tienen ruta: añadir carpeta + separador a cada uno
    CONCATENATE pv_carpeta lv_sep INTO lv_base.
    LOOP AT pt_files INTO ls_file.
      CONCATENATE lv_base ls_file-filename INTO ls_file-filename.
      MODIFY pt_files FROM ls_file.
    ENDLOOP.
  ENDIF.

ENDFORM.                    " FRM_LISTAR_CSV_CARPETA

*&---------------------------------------------------------------------*
*& Form FRM_LEER_CSV_FICHERO
*&---------------------------------------------------------------------*
*& Lee y parsea un fichero CSV a partir de la ruta indicada en
*& pv_filename. Equivale a FRM_LEER_CSV_LOCAL pero parametrizado
*& para poder llamarlo desde el modo carpeta.
*&---------------------------------------------------------------------*
FORM frm_leer_csv_fichero
  USING pv_filename TYPE string.

  DATA: lt_file_t   TYPE TABLE OF string,
        lv_line     TYPE string,
        ls_datos    TYPE gty_csv_data,
        lv_index    TYPE i.

* Subir el archivo desde equipo local
  CALL METHOD cl_gui_frontend_services=>gui_upload
    EXPORTING
      filename                = pv_filename
    CHANGING
      data_tab                = lt_file_t
    EXCEPTIONS
      file_open_error         = 1
      file_read_error         = 2
      no_batch                = 3
      gui_refuse_filetransfer = 4
      invalid_type            = 5
      no_authority            = 6
      unknown_error           = 7
      bad_data_format         = 8
      header_not_allowed      = 9
      separator_not_allowed   = 10
      header_too_long         = 11
      unknown_dp_error        = 12
      access_denied           = 13
      dp_out_of_memory        = 14
      disk_full               = 15
      dp_timeout              = 16
      not_supported_by_gui    = 17
      error_no_gui            = 18
      OTHERS                  = 19.

  IF sy-subrc <> 0.
*   Registrar error de lectura en el log (no abortar el lote)
    CLEAR gs_log.
    gs_log-icon    = gc_icon_err.
    gs_log-mensaje = 'Error al leer el fichero CSV (verificar ruta/permisos)'.
    APPEND gs_log TO gt_log.
    gv_error = gv_error + 1.
    RETURN.
  ENDIF.

  IF lt_file_t IS INITIAL.
    CLEAR gs_log.
    gs_log-icon    = gc_icon_warn.
    gs_log-mensaje = 'Fichero CSV vacío, omitido'.
    APPEND gs_log TO gt_log.
    RETURN.
  ENDIF.

* Recorrer líneas del fichero
  LOOP AT lt_file_t INTO lv_line.
    lv_index = sy-tabix.

*   Primera línea: cabecera (con posible BOM UTF-8) -> saltar
    IF lv_index = 1.
      PERFORM frm_eliminar_bom CHANGING lv_line.
      CONTINUE.
    ENDIF.

    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.

*   Parsear línea CSV (separador ; o |)
    CLEAR ls_datos.
    REPLACE ALL OCCURRENCES OF '|' IN lv_line WITH ';'.
    SPLIT lv_line AT ';' INTO
      ls_datos-rfc_emisor
      ls_datos-rfc_receptor
      ls_datos-serie
      ls_datos-folio
      ls_datos-fecha
      ls_datos-total
      ls_datos-tipocomprobante
      ls_datos-uuid.

    CONDENSE ls_datos-rfc_emisor NO-GAPS.
    CONDENSE ls_datos-rfc_receptor NO-GAPS.
    CONDENSE ls_datos-serie NO-GAPS.
    CONDENSE ls_datos-folio NO-GAPS.
    CONDENSE ls_datos-uuid NO-GAPS.
    CONDENSE ls_datos-tipocomprobante NO-GAPS.
    TRANSLATE ls_datos-uuid TO UPPER CASE.
    TRANSLATE ls_datos-tipocomprobante TO UPPER CASE.

    IF ls_datos-uuid IS INITIAL.
      CONTINUE.
    ENDIF.

    IF strlen( ls_datos-uuid ) <> 36.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ls_datos-rfc_emisor.
      gs_log-rfc_receptor = ls_datos-rfc_receptor.
      gs_log-serie        = ls_datos-serie.
      gs_log-folio        = ls_datos-folio.
      gs_log-tipo         = ls_datos-tipocomprobante.
      gs_log-uuid         = ls_datos-uuid.
      gs_log-mensaje      = 'UUID con formato incorrecto (debe ser 36 caracteres)'.
      APPEND gs_log TO gt_log.
      gv_error = gv_error + 1.
      CONTINUE.
    ENDIF.

    APPEND ls_datos TO gt_csv_data.

  ENDLOOP.

ENDFORM.                    " FRM_LEER_CSV_FICHERO

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_CARPETA
*&---------------------------------------------------------------------*
*& Modo carpeta: recorre todos los CSV de la carpeta, procesa cada uno
*& y acumula resultados en gt_log_global para el ALV consolidado.
*&---------------------------------------------------------------------*
FORM frm_procesar_carpeta.

  DATA: lt_files      TYPE filetable,
        ls_file       TYPE file_table,
        lv_carpeta    TYPE string,
        lv_nfich      TYPE i,
        lv_short_name TYPE string,
        lv_parts      TYPE TABLE OF string,
        lv_nparts     TYPE i.

  lv_carpeta = p_file.

* Listar ficheros CSV en la carpeta
  PERFORM frm_listar_csv_carpeta
    USING    lv_carpeta
    CHANGING lt_files.

  lv_nfich = lines( lt_files ).
  IF lv_nfich = 0.
    MESSAGE s398(00) WITH 'No se encontraron ficheros CSV'
                          'en la carpeta indicada.' '' ''
                          DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

* Inicializar acumuladores globales
  CLEAR: gv_g_total, gv_g_ok, gv_g_warning, gv_g_error, gv_g_ficheros.
  REFRESH: gt_log_global, gt_resumen_fich.

* Procesar cada fichero CSV
  LOOP AT lt_files INTO ls_file.
    gv_fichero_actual = ls_file-filename.
    gv_g_ficheros     = gv_g_ficheros + 1.

*   Extraer nombre corto (sin ruta) para mostrar en log y resumen
    SPLIT gv_fichero_actual AT '\' INTO TABLE lv_parts.
    lv_nparts = lines( lv_parts ).
    READ TABLE lv_parts INTO lv_short_name INDEX lv_nparts.
    IF sy-subrc <> 0.
      lv_short_name = gv_fichero_actual.
    ENDIF.

*   Reiniciar datos de este fichero
    REFRESH gt_csv_data.
    REFRESH gt_log.
    CLEAR: gv_total, gv_ok, gv_warning, gv_error.

*   Leer y parsear el CSV
    PERFORM frm_leer_csv_fichero USING gv_fichero_actual.

*   Si hay registros válidos, procesar
    IF gt_csv_data IS NOT INITIAL.
      PERFORM frm_procesar_registros.
    ENDIF.

*   Etiquetar cada entrada del log con el nombre corto y acumular
    LOOP AT gt_log INTO gs_log.
      gs_log-fichero = lv_short_name.
      MODIFY gt_log FROM gs_log.
      APPEND gs_log TO gt_log_global.
    ENDLOOP.

*   Grabar log del fichero actual en tablas Z
    gv_fichero_actual = lv_short_name.
    PERFORM frm_save_log_ztable.

*   Acumular contadores globales
    gv_g_total   = gv_g_total   + gv_total.
    gv_g_ok      = gv_g_ok      + gv_ok.
    gv_g_warning = gv_g_warning + gv_warning.
    gv_g_error   = gv_g_error   + gv_error.

*   Guardar resumen por fichero
    CLEAR gs_resumen_fich.
    gs_resumen_fich-fichero  = lv_short_name.
    gs_resumen_fich-total    = gv_total.
    gs_resumen_fich-ok       = gv_ok.
    gs_resumen_fich-warning  = gv_warning.
    gs_resumen_fich-error    = gv_error.
    APPEND gs_resumen_fich TO gt_resumen_fich.

  ENDLOOP.

* Mostrar ALV consolidado con todos los resultados
  PERFORM frm_mostrar_alv_global.

ENDFORM.                    " FRM_PROCESAR_CARPETA

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_REGISTROS
*&---------------------------------------------------------------------*
*& Bucle principal: para cada registro del CSV determina tipo de
*& factura, localiza el documento y actualiza el UUID.
*&---------------------------------------------------------------------*
FORM frm_procesar_registros.

  DATA: ls_datos      TYPE gty_csv_data,
        lv_tipo_fac   TYPE c,            " C=Compra, V=Venta, I=Interco
        lv_emisor_bk  TYPE char10,       " BUKRS o LIFNR del emisor
        lv_receptor_bk TYPE char10,      " BUKRS o KUNNR del receptor
        lv_gjahr      TYPE gjahr,        " Ejercicio extraído de la fecha
        lv_error      TYPE c,
        lv_total_num  TYPE p DECIMALS 0. " Total numérico para comparación

* Inicializar contadores
  CLEAR: gv_total, gv_ok, gv_warning, gv_error.

* Recorrer cada registro del CSV
  LOOP AT gt_csv_data INTO ls_datos.
    gv_total = gv_total + 1.
    CLEAR: lv_tipo_fac, lv_emisor_bk, lv_receptor_bk, lv_error.

*   Extraer ejercicio (año) de la fecha del CSV
*   Formato: DD/MM/YYYY HH:MM:SS a. m.
    PERFORM frm_extraer_anio
      USING ls_datos-fecha
      CHANGING lv_gjahr.

    IF lv_gjahr IS INITIAL.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ls_datos-rfc_emisor.
      gs_log-rfc_receptor = ls_datos-rfc_receptor.
      gs_log-serie        = ls_datos-serie.
      gs_log-folio        = ls_datos-folio.
      gs_log-tipo         = ls_datos-tipocomprobante.
      gs_log-uuid         = ls_datos-uuid.
      gs_log-mensaje      = 'No se pudo extraer el año de la fecha del CSV'.
      APPEND gs_log TO gt_log.
      gv_error = gv_error + 1.
      CONTINUE.
    ENDIF.

*   Convertir total del CSV a numérico (quitar puntos separadores de miles)
    PERFORM frm_convertir_total
      USING ls_datos-total
      CHANGING lv_total_num.

*   Determinar tipo de factura (Compra/Venta/Intercompany)
    PERFORM frm_tipo_factura
      USING    ls_datos
      CHANGING lv_tipo_fac
               lv_emisor_bk
               lv_receptor_bk
               lv_error.

    IF lv_error = 'X'.
*     Error ya registrado en gt_log dentro de frm_tipo_factura
      gv_error = gv_error + 1.
      CONTINUE.
    ENDIF.

*   Filtro opcional por sociedad (S_BUKRS)
    IF s_bukrs IS NOT INITIAL.
      CASE lv_tipo_fac.
        WHEN gc_tipo_compra.
          IF lv_receptor_bk NOT IN s_bukrs.
            CONTINUE.
          ENDIF.
        WHEN gc_tipo_venta.
          IF lv_emisor_bk NOT IN s_bukrs.
            CONTINUE.
          ENDIF.
        WHEN gc_tipo_interco.
          IF lv_emisor_bk NOT IN s_bukrs AND lv_receptor_bk NOT IN s_bukrs.
            CONTINUE.
          ENDIF.
      ENDCASE.
    ENDIF.

*   Procesar según tipo de factura
    CASE lv_tipo_fac.
      WHEN gc_tipo_compra.
        " Compra: sociedad = receptor, proveedor = emisor
        PERFORM frm_procesar_compra
          USING ls_datos lv_receptor_bk lv_emisor_bk lv_gjahr lv_total_num.

      WHEN gc_tipo_venta.
        " Venta: sociedad = emisor, cliente = receptor
        PERFORM frm_procesar_venta
          USING ls_datos lv_emisor_bk lv_receptor_bk lv_gjahr lv_total_num.

      WHEN gc_tipo_interco.
        " Intercompany: procesar ambos lados
        PERFORM frm_procesar_intercompany
          USING ls_datos lv_emisor_bk lv_receptor_bk lv_gjahr lv_total_num.

    ENDCASE.

  ENDLOOP.

ENDFORM.                    " FRM_PROCESAR_REGISTROS

*&---------------------------------------------------------------------*
*& Form FRM_SAVE_LOG_ZTABLE
*&---------------------------------------------------------------------*
*& Persiste el log del fichero actual en ZTT_UUID_LOG y ZTT_UUID_EXEC
*&---------------------------------------------------------------------*
FORM frm_save_log_ztable.

  DATA: lt_zlog  TYPE TABLE OF ztt_uuid_log,
        ls_zlog  TYPE ztt_uuid_log,
        ls_zexec TYPE ztt_uuid_exec.

  LOOP AT gt_log INTO gs_log.
    CLEAR ls_zlog.
    MOVE-CORRESPONDING gs_log TO ls_zlog.
    ls_zlog-datum_proc  = sy-datum.
    ls_zlog-uzeit_proc  = sy-uzeit.
    ls_zlog-uname       = sy-uname.
    ls_zlog-icon_status = gs_log-icon.
    IF ls_zlog-fichero IS INITIAL.
      ls_zlog-fichero = gv_fichero_actual.
    ENDIF.
    APPEND ls_zlog TO lt_zlog.
  ENDLOOP.

  MODIFY ztt_uuid_log FROM TABLE lt_zlog.

  CLEAR ls_zexec.
  ls_zexec-datum_proc = sy-datum.
  ls_zexec-uzeit_proc = sy-uzeit.
  ls_zexec-uname      = sy-uname.
  ls_zexec-fichero    = gv_fichero_actual.
  ls_zexec-test_mode  = p_test.
  ls_zexec-tot_reg    = gv_total.
  ls_zexec-tot_ok     = gv_ok.
  ls_zexec-tot_warn   = gv_warning.
  ls_zexec-tot_err    = gv_error.
  MODIFY ztt_uuid_exec FROM ls_zexec.

  COMMIT WORK AND WAIT.

ENDFORM.                    " FRM_SAVE_LOG_ZTABLE

*&---------------------------------------------------------------------*
*& Form FRM_EXTRAER_ANIO
*&---------------------------------------------------------------------*
*& Extrae el año (GJAHR) del campo fecha del CSV
*& Formato esperado: DD/MM/YYYY HH:MM:SS a. m.
*&---------------------------------------------------------------------*
FORM frm_extraer_anio
  USING    pv_fecha TYPE char30
  CHANGING pv_gjahr TYPE gjahr.

  DATA: lv_fecha TYPE string,
        lv_anio  TYPE string.

  CLEAR pv_gjahr.
  lv_fecha = pv_fecha.
  CONDENSE lv_fecha NO-GAPS.

* Verificar longitud mínima (DD/MM/YYYY = 10 chars)
  IF strlen( lv_fecha ) >= 10.
*   El año está en las posiciones 6-9 (después de DD/MM/)
    DATA: lv_fecha_c TYPE char30.
    lv_fecha_c = lv_fecha.
    lv_anio = lv_fecha_c+6(4).
*   Verificar que sea numérico
    IF lv_anio CO '0123456789'.
      pv_gjahr = lv_anio.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_EXTRAER_ANIO

*&---------------------------------------------------------------------*
*& Form FRM_CONVERTIR_TOTAL
*&---------------------------------------------------------------------*
*& Convierte el campo Total del CSV a numérico entero (sin decimales).
*&
*& Formato europeo  (tiene coma):   "26.640,80"         -> 26640
*& Formato CFDI XML (sin coma):     "41.760.000.000"    -> 41760
*&
*& El formato CFDI XML proviene del XML SAT que almacena siempre
*& exactamente 6 decimales (p.ej. 41760.000000). La herramienta de
*& exportación malforma ese valor añadiendo puntos como separadores
*& de miles en ambas partes, produciendo "41.760.000.000".
*& Al quitar todos los puntos se obtiene "41760000000" = 41760 * 10^6,
*& por lo que basta dividir entre 10^6 y truncar.
*&---------------------------------------------------------------------*
FORM frm_convertir_total
  USING    pv_total_str TYPE char25
  CHANGING pv_total_num TYPE p.

  DATA: lv_total_str TYPE string,
        lv_total_dec TYPE p DECIMALS 2,
        lv_total_raw TYPE p DECIMALS 0,  " Entero sin decimales (hasta 15 dígitos)
        lv_total_6   TYPE p DECIMALS 6.

  CLEAR pv_total_num.
  lv_total_str = pv_total_str.
  CONDENSE lv_total_str NO-GAPS.

  IF lv_total_str CA ','.
*   ------------------------------------------------------------------
*   FORMATO EUROPEO: tiene coma como separador decimal
*   Ejemplo: "26.640,80" -> "26640.80" -> truncar -> 26640
*   ------------------------------------------------------------------
    REPLACE ALL OCCURRENCES OF ',' IN lv_total_str WITH '#'.
    REPLACE ALL OCCURRENCES OF '.' IN lv_total_str WITH ''.
    REPLACE ALL OCCURRENCES OF '#' IN lv_total_str WITH '.'.

    IF lv_total_str CO '0123456789.'.
      lv_total_dec = lv_total_str.
      pv_total_num = trunc( lv_total_dec ).
    ENDIF.

  ELSE.
*   ------------------------------------------------------------------
*   FORMATO CFDI XML: sin coma, el exportador pone puntos en todas
*   las posiciones de miles (incluyendo los 6 decimales del XML).
*   Ejemplo: "41.760.000.000" -> strip dots -> "41760000000"
*            41760000000 / 10^6 = 41760.000000 -> truncar -> 41760
*   ------------------------------------------------------------------
    REPLACE ALL OCCURRENCES OF '.' IN lv_total_str WITH ''.

    IF lv_total_str CO '0123456789'.
      lv_total_raw = lv_total_str.        " p DECIMALS 0 aguanta hasta 15 dígitos
      lv_total_6   = lv_total_raw / 1000000.
      pv_total_num = trunc( lv_total_6 ).
    ENDIF.

  ENDIF.

ENDFORM.                    " FRM_CONVERTIR_TOTAL
