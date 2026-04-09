**********************************************************************
** Programa: ZFIR_UUID_CFDI_UPDATE                                  **
**------------------------------------------------------------------**
** Descripción: Actualización masiva de UUID (CFDI) en facturas     **
**              SAP ECC 6.0 a partir de archivos CSV.               **
**              Compatible con ZFII_MEXICO_UIID (ZFI271).           **
**------------------------------------------------------------------**
** Autor:      Acciona TIC - Desarrollo ABAP                       **
** Fecha:      03/04/2026                                           **
** Versión:    1.0                                                  **
**------------------------------------------------------------------**
** Dependencias:                                                    **
**   - Text ID 'YUUD' para objeto 'BELEG' (ya existente)           **
**   - Tabla T001Z con PARTY = 'MX_RFC' (mapeo RFC <-> BUKRS)      **
**   - Tablas estándar: LFA1, KNA1, BKPF, BSEG                    **
**   - Objeto autorización F_BKPF_BUK                              **
**   - Programa relacionado: ZFII_MEXICO_UIID (transacción ZFI271) **
**------------------------------------------------------------------**
** Historial de cambios:                                            **
**   V1.0  03/04/2026  Versión inicial                              **
**********************************************************************
REPORT zfir_uuid_cfdi_update LINE-SIZE 250.

**********************************************************************
** INCLUDES                                                         **
**********************************************************************
INCLUDE zfir_uuid_cfdi_update_top.   " Tipos, datos globales, pantalla
INCLUDE zfir_uuid_cfdi_update_sel00. " Lógica pantalla selección (F4)
INCLUDE zfir_uuid_cfdi_update_frm00. " Lectura y parseo CSV
INCLUDE zfir_uuid_cfdi_update_frm01. " Localización documentos BKPF/BSEG
INCLUDE zfir_uuid_cfdi_update_frm02. " Grabación UUID y salida ALV

**********************************************************************
** MATCH-CODE PARA FICHERO CSV (F4)                                 **
**********************************************************************
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM frm_f4_fichero_csv.

**********************************************************************
** VALIDACIONES DE PANTALLA DE SELECCIÓN                            **
**********************************************************************
AT SELECTION-SCREEN.
  PERFORM frm_validar_seleccion.

**********************************************************************
** EJECUCIÓN PRINCIPAL                                              **
**********************************************************************
START-OF-SELECTION.

  IF p_carp = 'X'.
*   ---- MODO CARPETA: procesar todos los CSV de la carpeta ----
    PERFORM frm_procesar_carpeta.

  ELSE.
*   ---- MODO FICHERO: un único CSV (comportamiento original) ----

*   1. Leer y parsear el fichero CSV desde equipo local
    gv_fichero_actual = p_file.
    PERFORM frm_leer_csv_local.

*   2. Si hay datos, procesar cada registro
    IF gt_csv_data IS NOT INITIAL.
      PERFORM frm_procesar_registros.
    ELSE.
      MESSAGE s398(00) WITH 'No se encontraron registros'
                            'válidos en el archivo CSV.' '' ''
                            DISPLAY LIKE 'E'.
    ENDIF.

*   3. Persistir log en tablas Z
    PERFORM frm_save_log_ztable.

*   4. Mostrar log ALV con resultados del fichero
    PERFORM frm_mostrar_alv.

  ENDIF.
