**********************************************************************
** Programa: ZFIR_UUID_CFDI_UPDATE                                  **
**------------------------------------------------------------------**
** Descripción: Actualización masiva de UUID (CFDI) en facturas     **
**              SAP ECC 6.0 a partir de archivos CSV.               **
**              Compatible con ZFII_MEXICO_UIID (ZFI271).           **
**------------------------------------------------------------------**
** Autor:      Acciona TIC - Desarrollo ABAP                       **
** Fecha:      03/04/2026                                           **
** Versión:    2.0                                                  **
**------------------------------------------------------------------**
** V1.0  03/04/2026  Versión inicial (fichero local + carpeta)      **
** V2.0  10/04/2026  Modo servidor AL11 recursivo (fondo SM36)      **
**------------------------------------------------------------------**
** Dependencias:                                                    **
**   - Text ID 'YUUD' para objeto 'BELEG' (ya existente)           **
**   - Tabla T001Z con PARTY = 'MX_RFC' (mapeo RFC <-> BUKRS)      **
**   - Tablas estándar: LFA1, KNA1, BKPF, BSEG                    **
**   - Objeto autorización F_BKPF_BUK                              **
**   - Tablas Z: ZTT_UUID_LOG, ZTT_UUID_EXEC (persistencia log)    **
**   - Programa relacionado: ZFII_MEXICO_UIID (transacción ZFI271) **
**********************************************************************
REPORT zfir_uuid_cfdi_update LINE-SIZE 250.

**********************************************************************
** INCLUDES                                                         **
**********************************************************************
INCLUDE zfir_uuid_cfdi_update_top.   " Tipos, datos globales, pantalla
INCLUDE zfir_uuid_cfdi_update_sel00. " Lógica pantalla selección (F4)
INCLUDE zfir_uuid_cfdi_update_frm00. " Lectura/parseo CSV + servidor
INCLUDE zfir_uuid_cfdi_update_frm01. " Localización documentos BKPF/BSEG
INCLUDE zfir_uuid_cfdi_update_frm02. " Grabación UUID y salida ALV
INCLUDE zfir_uuid_cfdi_update_frm03. " Reprocesamiento de errores/warnings

**********************************************************************
** MATCH-CODE PARA FICHERO CSV (F4) — Definido en SEL00             **
**********************************************************************
* Los eventos AT SELECTION-SCREEN están en el include SEL00:
*   - ON VALUE-REQUEST FOR p_file → frm_f4_fichero_csv
*   - ON VALUE-REQUEST FOR p_sdir → frm_f4_servidor
*   - AT SELECTION-SCREEN OUTPUT  → mostrar/ocultar campos
*   - AT SELECTION-SCREEN         → frm_validar_seleccion

**********************************************************************
** INICIALIZACIÓN                                                   **
**********************************************************************
INITIALIZATION.
  g_des_t = 'NAMING CONVENTION (OBLIGATORIO PARA DASHBOARD)'.
  g_des_1 = 'Para que el Reporte de Continuidad identifique los periodos sin registros,'.
  g_des_2 = 'los archivos deben terminar en _MMYY.csv (Ej: _0126.csv para Ene 2026).'.
  g_des_3 = 'El RFC debe estar al inicio: <RFC>_Clientes_Ingreso_0126.csv'.
  g_des_4 = 'Sin este patrón, el Dashboard marcará el mes como "Sin Carga".'.

**********************************************************************
** EJECUCIÓN PRINCIPAL                                              **
**********************************************************************
START-OF-SELECTION.

* Cargar cachés de tablas maestras (T001Z, LFA1, KNA1) una sola vez
  PERFORM frm_init_cache.

  IF p_reproc = 'X'.
    PERFORM frm_reprocesar_errores.
    RETURN.
  ENDIF.

  IF p_serv = 'X'.
*   =====================================================
*   MODO SERVIDOR (AL11): procesamiento recursivo
*   Compatible con ejecución en fondo (SM36)
*   Log → tablas Z + spool (WRITE)
*   =====================================================
    PERFORM frm_procesar_servidor.

  ELSEIF p_carp = 'X'.
*   =====================================================
*   MODO CARPETA LOCAL: procesar todos los CSV de 1 carpeta
*   Requiere SAP GUI (no compatible con fondo)
*   =====================================================
    PERFORM frm_procesar_carpeta.

  ELSE.
*   =====================================================
*   MODO FICHERO: un único CSV desde PC local
*   Requiere SAP GUI (no compatible con fondo)
*   =====================================================

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
