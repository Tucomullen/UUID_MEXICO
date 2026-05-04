**********************************************************************
** Programa: ZFIR_UUID_FIX_DUPLICATES                              **
**------------------------------------------------------------------**
** Descripción: Corrección de UUIDs duplicados en STXH/STXL y     **
**              sincronización de ZTT_UUID_LOG con la realidad de  **
**              SAP. El UUID correcto lo determina el CSV de AL11. **
**              Premisa: 1 UUID único por documento contable.       **
**------------------------------------------------------------------**
** Autor:      Acciona TIC - Desarrollo ABAP                       **
** Fecha:      04/05/2026                                          **
** Versión:    1.0                                                  **
**------------------------------------------------------------------**
** Rendimiento: paquetizado, libera memoria entre paquetes.        **
**              Compatible SM36 (batch sin GUI).                    **
**              Parámetros P_PKG/P_COMMIT/P_WAIT controlan carga.  **
**------------------------------------------------------------------**
** Dependencias:                                                    **
**   - Tablas Z: ZTT_UUID_LOG, ZTT_UUID_EXEC                       **
**   - STXH / STXL (BELEG/YUUD)                                    **
**   - BKPF / BSEG / LFA1 / KNA1 / T001Z                          **
**   - Function modules: READ_TEXT, SAVE_TEXT                       **
**   - Programa relacionado: ZFIR_UUID_CFDI_UPDATE                  **
**********************************************************************
REPORT zfir_uuid_fix_duplicates LINE-SIZE 250.

INCLUDE zfir_uuid_fix_duplicates_top.  " Tipos, datos globales, pantalla
INCLUDE zfir_uuid_fix_duplicates_f01.  " Detección duplicados + enriquecimiento
INCLUDE zfir_uuid_fix_duplicates_f02.  " Carga indexada de CSVs desde AL11
INCLUDE zfir_uuid_fix_duplicates_f03.  " Resolución: match CSV → acción
INCLUDE zfir_uuid_fix_duplicates_f04.  " Aplicación + sync ZTT_UUID_LOG + ALV

**********************************************************************
** INICIALIZACIÓN                                                   **
**********************************************************************
INITIALIZATION.
  p_pkg    = 500.
  p_commit = 100.
  p_wait   = 1.

AT SELECTION-SCREEN.
  IF p_sdir IS INITIAL.
    MESSAGE e398(00) WITH 'Debe indicar el directorio raíz en servidor (AL11).' '' '' ''.
  ENDIF.
  IF p_pkg <= 0.    p_pkg    = 500. ENDIF.
  IF p_commit <= 0. p_commit = 100. ENDIF.

**********************************************************************
** EJECUCIÓN PRINCIPAL                                              **
**********************************************************************
START-OF-SELECTION.

  WRITE: / '================================================'.
  WRITE: / 'ZFIR_UUID_FIX_DUPLICATES - INICIO'.
  WRITE: / 'Fecha:', sy-datum, 'Hora:', sy-uzeit.
  WRITE: / 'Modo:', COND string( WHEN p_test = 'X' THEN 'SIMULACIÓN' ELSE 'PRODUCTIVO' ).
  WRITE: / 'Directorio CSV:', p_sdir.
  WRITE: / 'Paquete detección:', p_pkg,
         ' Commit cada:', p_commit,
         ' Pausa entre paquetes:', p_wait, 'seg'.
  WRITE: / '================================================'.

* 1. Cargar cachés de tablas maestras (T001Z, LFA1/KNA1 lazy)
  PERFORM frm_fix_init_cache.

* 2. Detectar documentos con UUID duplicado en STXH (vía ZTT_UUID_LOG + READ_TEXT)
  PERFORM frm_fix_detectar_duplicados.

  IF gt_dup_docs IS INITIAL.
    WRITE: / 'No se encontraron documentos con UUID duplicado. Fin.'.
    IF p_resync = 'X'.
*     Sincronizar log para todos los documentos OK (sin duplicados)
      PERFORM frm_fix_resync_log_completo.
    ENDIF.
    PERFORM frm_fix_mostrar_alv.
    RETURN.
  ENDIF.

  WRITE: / 'Documentos duplicados a resolver:', lines( gt_dup_docs ).

* 3. Cargar CSVs del servidor en índice de búsqueda (filtrado por RFCs relevantes)
  PERFORM frm_fix_cargar_csvs.

* 4. Resolver: determinar acción para cada documento duplicado
  PERFORM frm_fix_resolver.

* 5. Aplicar acciones: SAVE_TEXT / DELETE STXH/STXL / UPDATE ZTT_UUID_LOG
  PERFORM frm_fix_aplicar.

* 6. Sincronizar ZTT_UUID_LOG también para documentos no duplicados (opcional)
  IF p_resync = 'X'.
    PERFORM frm_fix_resync_log_completo.
  ENDIF.

* 7. Registrar ejecución en ZTT_UUID_EXEC
  PERFORM frm_fix_save_exec_log.

* 8. Mostrar ALV
  PERFORM frm_fix_mostrar_alv.

  WRITE: / '================================================'.
  WRITE: / 'FIN. Reasignados:', gv_n_reasig,
         ' Borrados:', gv_n_borrado,
         ' Ganadores:', gv_n_ok_win.
  WRITE: / 'Ambiguos:', gv_n_ambig,
         ' Huérfanos:', gv_n_huerfano,
         ' Errores escritura:', gv_n_error.
  WRITE: / '================================================'.
