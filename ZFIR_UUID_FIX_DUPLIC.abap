*&---------------------------------------------------------------------*
*& Report ZFIR_UUID_FIX_DUPLIC
*&---------------------------------------------------------------------*
*& Detección y corrección de UUID duplicados en documentos contables.
*&
*& FUENTE DE VERDAD: STXH/STXL (textos SAPscript donde SAVE_TEXT graba
*&   el UUID). No se confía en ztt_uuid_log como fuente primaria.
*&
*& LÓGICA:
*&   1. Lee todos los UUID de STXH/STXL en un solo JOIN (sin bucles N×FM).
*&   2. Detecta en memoria los UUIDs que aparecen en más de 1 documento.
*&   3. Carga todos los CSV del servidor en dos índices hash en memoria.
*&   4. Para cada UUID duplicado:
*&      a) Busca el CSV con ese UUID.
*&      b) Verifica cuál candidato (BKPF+BSEG por PK) coincide folio+RFC.
*&      c) Ese es el documento correcto → se bloquea.
*&      d) Para los incorrectos: búsqueda inversa en CSVs por folio+RFC
*&         para encontrar su UUID correcto.
*&      e) Corrige: SAVE_TEXT (UUID correcto) o DELETE_TEXT (sin UUID).
*&   5. Actualiza ztt_uuid_log y graba auditoría en ZTT_UUID_CORREC.
*&
*& MODO SIMULACIÓN (P_TEST = 'X'): no modifica nada, solo informa.
*&---------------------------------------------------------------------*
REPORT zfir_uuid_fix_duplic.

INCLUDE zfir_uuid_fix_duplic_top.
INCLUDE zfir_uuid_fix_duplic_frm00.
INCLUDE zfir_uuid_fix_duplic_frm01.
INCLUDE zfir_uuid_fix_duplic_frm02.

*&---------------------------------------------------------------------*
INITIALIZATION.
*&---------------------------------------------------------------------*
  gv_t1 = 'Configuracion del analisis'.
  gv_t2 = 'Filtros (opcionales)'.
  p_test = 'X'.

*&---------------------------------------------------------------------*
AT SELECTION-SCREEN.
*&---------------------------------------------------------------------*
  IF p_sdir IS INITIAL.
    MESSAGE 'Indique el directorio servidor con los CSV.' TYPE 'E'.
  ENDIF.

*&---------------------------------------------------------------------*
START-OF-SELECTION.
*&---------------------------------------------------------------------*

* Fase 0: Cachés de tablas maestras (T001Z completo; LFA1/KNA1 lazy)
  PERFORM frm_init_caches.

* Fase 1a: Leer todos los CSV del servidor → dos índices en memoria
  PERFORM frm_cargar_csvs_servidor.

* Fase 1b: Detectar UUID duplicados en STXH/STXL (1 JOIN, sin FM loop)
  PERFORM frm_detectar_duplicados_stxh.

  IF gt_duplic_docs IS INITIAL.
    MESSAGE s398(00) WITH 'No se encontraron UUID duplicados en SAP.'
                          '' '' ''.
    RETURN.
  ENDIF.

* Fase 2+3: Verificar candidatos y ejecutar correcciones
  PERFORM frm_procesar_duplicados.

* Fase 4: Mostrar ALV consolidado
  PERFORM frm_mostrar_resultado_alv.
