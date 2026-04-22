*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM01
*&---------------------------------------------------------------------*
*& Localización de documentos contables en BKPF/BSEG
*& Determinación de tipo de factura (Compra/Venta/Intercompany)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_TIPO_FACTURA
*&---------------------------------------------------------------------*
*& Determina el tipo de factura (C/V/I) a partir de los RFC del emisor
*& y receptor, buscando en T001Z (PARTY='MX_RFC') y LFA1/KNA1.
*& Replica la lógica exacta de ZFII_MEXICO_UIID (f02_tipo_factura).
*&---------------------------------------------------------------------*
FORM frm_tipo_factura
  USING    value(ps_datos)    TYPE gty_csv_data
  CHANGING pv_tipo_factura    TYPE c
           pv_emisor          TYPE char10
           pv_receptor        TYPE char10
           pv_error           TYPE c.

  DATA: lv_emisor_grupo_mx   TYPE c,
        lv_receptor_grupo_mx TYPE c,
        lv_bukrs_emisor      TYPE bukrs,
        lv_bukrs_receptor    TYPE bukrs,
        lv_lifnr             TYPE lifnr,
        lv_kunnr             TYPE kunnr.

  CLEAR: pv_tipo_factura, pv_emisor, pv_receptor, pv_error,
         lv_emisor_grupo_mx, lv_receptor_grupo_mx.

* Buscar sociedad emisora en caché T001Z (evita SELECT SINGLE por cada registro)
  DATA: ls_t001z_e TYPE gty_t001z_cache,
        ls_t001z_r TYPE gty_t001z_cache.

  READ TABLE gt_t001z_cache INTO ls_t001z_e
    WITH TABLE KEY paval = ps_datos-rfc_emisor.
  IF sy-subrc = 0.
    lv_bukrs_emisor    = ls_t001z_e-bukrs.
    lv_emisor_grupo_mx = 'X'.
  ENDIF.

* Buscar sociedad receptora en caché T001Z
  READ TABLE gt_t001z_cache INTO ls_t001z_r
    WITH TABLE KEY paval = ps_datos-rfc_receptor.
  IF sy-subrc = 0.
    lv_bukrs_receptor    = ls_t001z_r-bukrs.
    lv_receptor_grupo_mx = 'X'.
  ENDIF.

* Determinar tipo de factura según qué RFC pertenece al grupo
  IF lv_emisor_grupo_mx = 'X' AND lv_receptor_grupo_mx = 'X'.
*   ---- INTERCOMPANY ----
*   Ambos son sociedades Acciona MX
    pv_tipo_factura = gc_tipo_interco.
    pv_emisor   = lv_bukrs_emisor.
    pv_receptor = lv_bukrs_receptor.

  ELSEIF lv_emisor_grupo_mx = '' AND lv_receptor_grupo_mx = 'X'.
*   ---- COMPRA ----
*   Emisor es proveedor externo, receptor es sociedad Acciona
    pv_tipo_factura = gc_tipo_compra.
*   Buscar LIFNR del proveedor por RFC en caché LFA1 (lazy-loading)
    DATA: ls_lfa1_c TYPE gty_lfa1_cache.
    READ TABLE gt_lfa1_cache INTO ls_lfa1_c
      WITH TABLE KEY stcd1 = ps_datos-rfc_emisor.
    IF sy-subrc <> 0.
*     Cache miss: consultar BD y guardar resultado (incluso si no existe)
      SELECT SINGLE lifnr
        FROM lfa1
        INTO ls_lfa1_c-lifnr
        WHERE stcd1 = ps_datos-rfc_emisor.
      ls_lfa1_c-stcd1 = ps_datos-rfc_emisor.
      INSERT ls_lfa1_c INTO TABLE gt_lfa1_cache.
    ENDIF.
    lv_lifnr = ls_lfa1_c-lifnr.
    IF lv_lifnr IS INITIAL.
      sy-subrc = 4.  " Simular "no encontrado" para la lógica siguiente
    ELSE.
      sy-subrc = 0.
    ENDIF.
    IF sy-subrc <> 0.
      pv_error = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'RFC proveedor no encontrado en LFA1:' ps_datos-rfc_emisor
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      RETURN.
    ENDIF.
    pv_emisor   = lv_lifnr.       " LIFNR del proveedor
    pv_receptor = lv_bukrs_receptor. " BUKRS sociedad

*   Verificar que la sociedad se obtuvo correctamente
    IF pv_receptor IS INITIAL.
      pv_error = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'RFC sociedad no encontrado en T001Z:' ps_datos-rfc_receptor
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      RETURN.
    ENDIF.

  ELSEIF lv_emisor_grupo_mx = 'X' AND lv_receptor_grupo_mx = ''.
*   ---- VENTA ----
*   Emisor es sociedad Acciona, receptor es cliente externo
    pv_tipo_factura = gc_tipo_venta.
*   Buscar KUNNR del cliente por RFC en caché KNA1 (lazy-loading)
    DATA: ls_kna1_c TYPE gty_kna1_cache.
    READ TABLE gt_kna1_cache INTO ls_kna1_c
      WITH TABLE KEY stcd1 = ps_datos-rfc_receptor.
    IF sy-subrc <> 0.
*     Cache miss: consultar BD y guardar resultado (incluso si no existe)
      SELECT SINGLE kunnr                                "#EC CI_NOFIELD
        FROM kna1
        INTO ls_kna1_c-kunnr
        WHERE stcd1 = ps_datos-rfc_receptor.
      ls_kna1_c-stcd1 = ps_datos-rfc_receptor.
      INSERT ls_kna1_c INTO TABLE gt_kna1_cache.
    ENDIF.
    lv_kunnr = ls_kna1_c-kunnr.
    IF lv_kunnr IS INITIAL.
      sy-subrc = 4.  " Simular "no encontrado" para la lógica siguiente
    ELSE.
      sy-subrc = 0.
    ENDIF.
    IF sy-subrc <> 0.
      pv_error = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'RFC cliente no encontrado en KNA1:' ps_datos-rfc_receptor
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      RETURN.
    ENDIF.
    pv_emisor   = lv_bukrs_emisor.  " BUKRS sociedad
    pv_receptor = lv_kunnr.         " KUNNR del cliente

*   Verificar que la sociedad se obtuvo correctamente
    IF pv_emisor IS INITIAL.
      pv_error = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'RFC sociedad no encontrado en T001Z:' ps_datos-rfc_emisor
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      RETURN.
    ENDIF.

  ELSE.
*   ---- ERROR ----
*   Ninguno de los dos RFC pertenece al grupo
    pv_error = 'X'.
    CLEAR gs_log.
    gs_log-icon         = gc_icon_err.
    gs_log-rfc_emisor   = ps_datos-rfc_emisor.
    gs_log-rfc_receptor = ps_datos-rfc_receptor.
    gs_log-folio        = ps_datos-folio.
    gs_log-tipo         = ps_datos-tipocomprobante.
    gs_log-uuid         = ps_datos-uuid.
    CONCATENATE 'Sociedad no encontrada con RFC Emisor ni Receptor:'
      ps_datos-rfc_emisor ps_datos-rfc_receptor
      INTO gs_log-mensaje SEPARATED BY space.
    APPEND gs_log TO gt_log.
    RETURN.
  ENDIF.

ENDFORM.                    " FRM_TIPO_FACTURA

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_COMPRA
*&---------------------------------------------------------------------*
*& Busca factura de compra en BKPF/BSEG (KOART='K') y actualiza UUID.
*& Sociedad = receptor, Proveedor = emisor.
*&---------------------------------------------------------------------*
FORM frm_procesar_compra
  USING value(ps_datos)    TYPE gty_csv_data
        value(pv_bukrs)    TYPE bukrs   " Sociedad
        value(pv_lifnr)    TYPE lifnr   " Proveedor
        value(pv_gjahr)    TYPE gjahr
        value(pv_total)    TYPE p.

  DATA: lv_belnr      TYPE belnr_d,
        lv_error      TYPE c,
        lv_error_uuid TYPE c.

* Buscar el documento de compra
  PERFORM frm_obtener_factura_compra
    USING ps_datos pv_bukrs pv_lifnr pv_gjahr pv_total
    CHANGING lv_belnr lv_error lv_error_uuid.

  IF lv_error = '' AND lv_error_uuid = ''.
*   Documento encontrado y sin UUID previo -> actualizar
    PERFORM frm_actualizar_factura_uuid
      USING ps_datos pv_bukrs lv_belnr pv_gjahr.
  ENDIF.

ENDFORM.                    " FRM_PROCESAR_COMPRA

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_VENTA
*&---------------------------------------------------------------------*
*& Busca factura de venta en BKPF/BSEG (KOART='D') y actualiza UUID.
*& Sociedad = emisor, Cliente = receptor.
*&---------------------------------------------------------------------*
FORM frm_procesar_venta
  USING value(ps_datos)    TYPE gty_csv_data
        value(pv_bukrs)    TYPE bukrs   " Sociedad
        value(pv_kunnr)    TYPE kunnr   " Cliente
        value(pv_gjahr)    TYPE gjahr
        value(pv_total)    TYPE p.

  DATA: lv_belnr      TYPE belnr_d,
        lv_error      TYPE c,
        lv_error_uuid TYPE c.

* Buscar el documento de venta
  PERFORM frm_obtener_factura_venta
    USING ps_datos pv_bukrs pv_kunnr pv_gjahr pv_total
    CHANGING lv_belnr lv_error lv_error_uuid.

  IF lv_error = '' AND lv_error_uuid = ''.
*   Documento encontrado y sin UUID previo -> actualizar
    PERFORM frm_actualizar_factura_uuid
      USING ps_datos pv_bukrs lv_belnr pv_gjahr.
  ENDIF.

ENDFORM.                    " FRM_PROCESAR_VENTA

*&---------------------------------------------------------------------*
*& Form FRM_PROCESAR_INTERCOMPANY
*&---------------------------------------------------------------------*
*& Procesamiento Intercompany: localiza y actualiza DOS documentos.
*& - Compra en sociedad receptora (proveedor = V-<bukrs_emisor>)
*& - Venta en sociedad emisora (cliente = C-<bukrs_receptor>)
*&---------------------------------------------------------------------*
FORM frm_procesar_intercompany
  USING value(ps_datos)       TYPE gty_csv_data
        value(pv_bukrs_emi)   TYPE bukrs  " BUKRS emisor
        value(pv_bukrs_rec)   TYPE bukrs  " BUKRS receptor
        value(pv_gjahr)       TYPE gjahr
        value(pv_total)       TYPE p.

  DATA: lv_belnr_c      TYPE belnr_d,  " Doc compra
        lv_belnr_v      TYPE belnr_d,  " Doc venta
        lv_error_c      TYPE c,
        lv_error_v      TYPE c,
        lv_error_uuid_c TYPE c,
        lv_error_uuid_v TYPE c,
        lv_prov_interco TYPE char10,   " Proveedor intercompany
        lv_cli_interco  TYPE char10.   " Cliente intercompany

* Construir acreedor/deudor intercompany
  CONCATENATE 'V-' pv_bukrs_emi INTO lv_prov_interco.
  CONCATENATE 'C-' pv_bukrs_rec INTO lv_cli_interco.

* ---- Lado COMPRA (sociedad receptora) ----
  PERFORM frm_obtener_factura_compra
    USING ps_datos pv_bukrs_rec lv_prov_interco pv_gjahr pv_total
    CHANGING lv_belnr_c lv_error_c lv_error_uuid_c.

  IF lv_error_c = '' AND lv_error_uuid_c = ''.
    PERFORM frm_actualizar_factura_uuid
      USING ps_datos pv_bukrs_rec lv_belnr_c pv_gjahr.
  ENDIF.

* ---- Lado VENTA (sociedad emisora) ----
  PERFORM frm_obtener_factura_venta
    USING ps_datos pv_bukrs_emi lv_cli_interco pv_gjahr pv_total
    CHANGING lv_belnr_v lv_error_v lv_error_uuid_v.

  IF lv_error_v = '' AND lv_error_uuid_v = ''.
    PERFORM frm_actualizar_factura_uuid
      USING ps_datos pv_bukrs_emi lv_belnr_v pv_gjahr.
  ENDIF.

* ---- Gestión de logs intercompany ----
* Si uno tenía discrepancia y el otro no, o si ambos están OK pero uno ya estaba marcado.
* Nota: Los mensajes individuales ya se añadieron en los obtener_factura.
* Solo añadimos mensaje extra si hay discrepancia entre ambos lados.
  IF lv_error_uuid_c = 'X' OR lv_error_uuid_v = 'X'.
    CLEAR gs_log.
    gs_log-icon    = gc_icon_warn.
    gs_log-bukrs   = pv_bukrs_rec.
    gs_log-rfc_emisor   = ps_datos-rfc_emisor.
    gs_log-rfc_receptor = ps_datos-rfc_receptor.
    gs_log-folio   = ps_datos-folio.
    gs_log-tipo_fac = gc_tipo_interco.
    gs_log-uuid    = ps_datos-uuid.
    gs_log-mensaje = 'REVISAR: Operación Intercompany con discrepancia de UUID en algún lado.'.
    APPEND gs_log TO gt_log.
  ENDIF.

ENDFORM. " FRM_PROCESAR_INTERCOMPANY


*&---------------------------------------------------------------------*
*& Form FRM_OBTENER_FACTURA_COMPRA
*&---------------------------------------------------------------------*
*& Busca un documento de compra en BKPF/BSEG por folio, sociedad,
*& proveedor, ejercicio e importe. Replica lógica de ZFII_MEXICO_UIID.
*&---------------------------------------------------------------------*
FORM frm_obtener_factura_compra
  USING    value(ps_datos)  TYPE gty_csv_data
           value(pv_bukrs)  TYPE bukrs
           value(pv_lifnr)  TYPE lifnr
           value(pv_gjahr)  TYPE gjahr
           value(pv_total)  TYPE p
  CHANGING pv_belnr         TYPE belnr_d
           pv_error         TYPE c
           pv_error_uuid    TYPE c.

  DATA: lt_bkpf        TYPE TABLE OF gty_bkpf,
        ls_bkpf        TYPE gty_bkpf,
        lv_importe     TYPE wrbtr,
        lv_importe_bd  TYPE p DECIMALS 0,
        lv_importe_csv TYPE p DECIMALS 0,
        lv_belnr_aux   TYPE belnr_d,
        lv_registros   TYPE i,
        lv_foliolike   TYPE string,
        lv_flag        TYPE c,
        lv_uuid_prev   TYPE char36,
        lt_belnr_match TYPE TABLE OF belnr_d,
        lv_fecha_c     TYPE char30,
        lv_date        TYPE d,
        lv_fallback_m  TYPE c.

  CLEAR: pv_belnr, pv_error, pv_error_uuid, lv_registros, lv_fallback_m, lt_belnr_match.

* Extraer fecha SAP para backup (por si no se localiza por folio)
  lv_fecha_c = ps_datos-fecha.
  CONDENSE lv_fecha_c NO-GAPS.
  IF strlen( lv_fecha_c ) >= 10.
    CONCATENATE lv_fecha_c+6(4) lv_fecha_c+3(2) lv_fecha_c(2) INTO lv_date.
  ENDIF.

* Construir patrón de búsqueda: %FOLIO%
  IF ps_datos-folio IS NOT INITIAL.
    CONCATENATE '%' ps_datos-folio '%' INTO lv_foliolike.
    CONDENSE lv_foliolike NO-GAPS.

*   1. BÚSQUEDA PRIMARIA: POR FOLIO
    SELECT bukrs belnr gjahr xblnr blart budat bldat
      FROM bkpf
      INTO TABLE lt_bkpf
      WHERE gjahr       = pv_gjahr
        AND bukrs       = pv_bukrs
        AND blart       IN s_blart
        AND xblnr       LIKE lv_foliolike
        AND xreversal   <> 1
        AND xreversal   <> 2.

    IF lt_bkpf IS NOT INITIAL.
      lv_importe_csv = pv_total.
      LOOP AT lt_bkpf INTO ls_bkpf.
        SELECT SINGLE belnr wrbtr
          FROM bseg
          INTO (lv_belnr_aux, lv_importe)
          WHERE bukrs = ls_bkpf-bukrs
            AND belnr = ls_bkpf-belnr
            AND gjahr = ls_bkpf-gjahr
            AND koart = 'K'
            AND lifnr = pv_lifnr.
        IF sy-subrc = 0.
          lv_importe_bd = trunc( lv_importe ).
*         Para pagos (P) no se compara importe
          IF lv_importe_bd = lv_importe_csv OR ps_datos-tipocomprobante = 'P'.
            APPEND lv_belnr_aux TO lt_belnr_match.
          ENDIF.
        ENDIF.
      ENDLOOP.
      DESCRIBE TABLE lt_belnr_match LINES lv_registros.
    ENDIF.
  ENDIF.

* 2. BÚSQUEDA ALTERNATIVA: POR FECHA (Si falló la búsqueda por folio o falla en BSEG)
  IF lv_registros = 0 AND lv_date IS NOT INITIAL.
    CLEAR: lt_bkpf, lt_belnr_match.
    SELECT bukrs belnr gjahr xblnr blart budat bldat
      FROM bkpf
      INTO TABLE lt_bkpf
      WHERE gjahr       = pv_gjahr
        AND bukrs       = pv_bukrs
        AND blart       IN s_blart
        AND ( bldat = lv_date OR budat = lv_date )
        AND xreversal   <> 1
        AND xreversal   <> 2.

    IF lt_bkpf IS NOT INITIAL.
      lv_fallback_m = 'X'.
      lv_importe_csv = pv_total.
      LOOP AT lt_bkpf INTO ls_bkpf.
        SELECT SINGLE belnr wrbtr
          FROM bseg
          INTO (lv_belnr_aux, lv_importe)
          WHERE bukrs = ls_bkpf-bukrs
            AND belnr = ls_bkpf-belnr
            AND gjahr = ls_bkpf-gjahr
            AND koart = 'K'
            AND lifnr = pv_lifnr.
        IF sy-subrc = 0.
          lv_importe_bd = trunc( lv_importe ).
          IF lv_importe_bd = lv_importe_csv OR ps_datos-tipocomprobante = 'P'.
            APPEND lv_belnr_aux TO lt_belnr_match.
          ENDIF.
        ENDIF.
      ENDLOOP.
      DESCRIBE TABLE lt_belnr_match LINES lv_registros.
    ENDIF.
  ENDIF.

* Evaluar resultados
  IF lv_registros > 1.
    IF lv_fallback_m = 'X'.
*     Mostrar todos los candidatos sin folio en SAP en el log
      LOOP AT lt_belnr_match INTO lv_belnr_aux.
        CLEAR gs_log.
        gs_log-icon         = gc_icon_warn.
        gs_log-bukrs        = pv_bukrs.
        gs_log-belnr        = lv_belnr_aux.
        gs_log-gjahr        = pv_gjahr.
        gs_log-rfc_emisor   = ps_datos-rfc_emisor.
        gs_log-rfc_receptor = ps_datos-rfc_receptor.
        gs_log-folio        = ps_datos-folio.
        gs_log-tipo         = ps_datos-tipocomprobante.
        gs_log-tipo_fac     = gc_tipo_compra.
        gs_log-uuid         = ps_datos-uuid.
        CONCATENATE 'Candidato sin folio en SAP (Revisión):' pv_bukrs lv_belnr_aux
          INTO gs_log-mensaje SEPARATED BY space.
        APPEND gs_log TO gt_log.
        gv_warning = gv_warning + 1. " Incrementar warnings
      ENDLOOP.
      pv_error = 'X'.
    ELSE.
*     Documento no unívoco con folio en SAP
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-bukrs        = pv_bukrs.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_compra.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'Document no unívoco para folio:' ps_datos-folio
        'Soc:' pv_bukrs 'Prov:' pv_lifnr
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      pv_error = 'X'.
    ENDIF.

  ELSEIF lv_registros = 0.
*   No se encontró documento ni revisando fecha
    CLEAR gs_log.
    gs_log-icon         = gc_icon_err.
    gs_log-bukrs        = pv_bukrs.
    gs_log-gjahr        = pv_gjahr.
    gs_log-rfc_emisor   = ps_datos-rfc_emisor.
    gs_log-rfc_receptor = ps_datos-rfc_receptor.
    gs_log-folio        = ps_datos-folio.
    gs_log-tipo         = ps_datos-tipocomprobante.
    gs_log-tipo_fac     = gc_tipo_compra.
    gs_log-uuid         = ps_datos-uuid.
    CONCATENATE 'No doc compra ni por folio ni fecha. Soc:' pv_bukrs 'Prov:' pv_lifnr 'Año:' pv_gjahr
      INTO gs_log-mensaje SEPARATED BY space.
    APPEND gs_log TO gt_log.
    pv_error = 'X'.

  ELSEIF lv_registros = 1.
*   Documento único encontrado -> verificar UUID existente
    READ TABLE lt_belnr_match INTO pv_belnr INDEX 1.


    DATA: lv_status TYPE c.
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
      CHANGING lv_status lv_uuid_prev.

    IF lv_status = gc_stat_diff.
*     UUID ya existe y es DISTINTO -> warning
      pv_error_uuid = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_warn.
      gs_log-bukrs        = pv_bukrs.
      gs_log-belnr        = pv_belnr.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_compra.
      gs_log-uuid         = ps_datos-uuid.
      gs_log-uuid_previo  = lv_uuid_prev.
      CONCATENATE 'Discrepancia: Documento ya tiene otro UUID:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gs_log-budat     = ls_bkpf-budat.
      gs_log-bldat     = ls_bkpf-bldat.
      gs_log-blart     = ls_bkpf-blart.
      gs_log-monat     = ls_bkpf-budat+4(2).
      gs_log-test_mode = p_test.
      APPEND gs_log TO gt_log.
      gv_warning = gv_warning + 1.
    ELSEIF lv_status = gc_stat_same.
*     UUID ya existe y es el MISMO -> Todo OK, no hacer nada
      pv_error_uuid = 'S'. " Status: Same (No action needed)
      CLEAR gs_log.
      gs_log-icon         = gc_icon_ok.
      gs_log-bukrs        = pv_bukrs.
      gs_log-belnr        = pv_belnr.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_compra.
      gs_log-uuid         = ps_datos-uuid.
      gs_log-mensaje      = 'El documento ya cuenta con el mismo UUID.'.
      gs_log-test_mode    = p_test.
      APPEND gs_log TO gt_log.
      gv_ok = gv_ok + 1.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_OBTENER_FACTURA_COMPRA

*&---------------------------------------------------------------------*
*& Form FRM_OBTENER_FACTURA_VENTA
*&---------------------------------------------------------------------*
*& Busca un documento de venta en BKPF/BSEG por folio, sociedad,
*& cliente, ejercicio e importe. Para pagos busca BLART='DZ' con
*& BELNR LIKE. Si no encuentra con folio directo, intenta variante
*& sin primeros caracteres de serie.
*&---------------------------------------------------------------------*
FORM frm_obtener_factura_venta
  USING    value(ps_datos)  TYPE gty_csv_data
           value(pv_bukrs)  TYPE bukrs
           value(pv_kunnr)  TYPE kunnr
           value(pv_gjahr)  TYPE gjahr
           value(pv_total)  TYPE p
  CHANGING pv_belnr         TYPE belnr_d
           pv_error         TYPE c
           pv_error_uuid    TYPE c.

  DATA: lt_bkpf        TYPE TABLE OF gty_bkpf,
        ls_bkpf        TYPE gty_bkpf,
        lv_importe     TYPE wrbtr,
        lv_importe_bd  TYPE p DECIMALS 0,
        lv_importe_csv TYPE p DECIMALS 0,
        lv_belnr_aux   TYPE belnr_d,
        lv_registros   TYPE i,
        lv_foliolike   TYPE string,
        lv_foliofi     TYPE string,
        lv_flag        TYPE c,
        lv_uuid_prev   TYPE char36,
        lt_belnr_match TYPE TABLE OF belnr_d,
        lv_fecha_c     TYPE char30,
        lv_date        TYPE d,
        lv_fallback_m  TYPE c.

  CLEAR: pv_belnr, pv_error, pv_error_uuid, lv_registros, lv_fallback_m, lt_belnr_match.

* Extraer fecha SAP para backup (por si no se localiza por folio)
  lv_fecha_c = ps_datos-fecha.
  CONDENSE lv_fecha_c NO-GAPS.
  IF strlen( lv_fecha_c ) >= 10.
    CONCATENATE lv_fecha_c+6(4) lv_fecha_c+3(2) lv_fecha_c(2) INTO lv_date.
  ENDIF.

* Construir patrón de búsqueda: %FOLIO%
  IF ps_datos-folio IS NOT INITIAL.
    CONCATENATE '%' ps_datos-folio '%' INTO lv_foliolike.
    CONDENSE lv_foliolike NO-GAPS.

*   1. BÚSQUEDA PRIMARIA: POR FOLIO
*   Para tipo Pago (P): buscar con BLART='DZ' y BELNR LIKE
    IF ps_datos-tipocomprobante = 'P'.
      SELECT bukrs belnr gjahr xblnr blart budat bldat
        FROM bkpf
        INTO TABLE lt_bkpf
        WHERE gjahr       = pv_gjahr
          AND bukrs       = pv_bukrs
          AND blart       = 'DZ'
          AND belnr       LIKE lv_foliolike
          AND xreversal   <> 1
          AND xreversal   <> 2.
    ELSE.
*     Búsqueda estándar por XBLNR
      SELECT bukrs belnr gjahr xblnr blart budat bldat
        FROM bkpf
        INTO TABLE lt_bkpf
        WHERE gjahr       = pv_gjahr
          AND bukrs       = pv_bukrs
          AND blart       IN s_blart
          AND xblnr       LIKE lv_foliolike
          AND xreversal   <> 1
          AND xreversal   <> 2.
    ENDIF.

*   Intento variante del folio
    IF sy-subrc <> 0 OR lt_bkpf IS INITIAL.
      IF ps_datos-tipocomprobante <> 'P'.
        IF strlen( lv_foliolike ) > 5.
          DATA: lv_foliolike_c TYPE char50.
          lv_foliolike_c = lv_foliolike.
          CONCATENATE lv_foliolike_c(1) lv_foliolike_c+5 INTO lv_foliofi.
          SELECT bukrs belnr gjahr xblnr blart budat bldat
            FROM bkpf
            INTO TABLE lt_bkpf
            WHERE gjahr       = pv_gjahr
              AND bukrs       = pv_bukrs
              AND blart       IN s_blart
              AND xblnr       LIKE lv_foliofi
              AND xreversal   <> 1
              AND xreversal   <> 2.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lt_bkpf IS NOT INITIAL.
      lv_importe_csv = pv_total.
      LOOP AT lt_bkpf INTO ls_bkpf.
        SELECT SINGLE belnr wrbtr
          FROM bseg
          INTO (lv_belnr_aux, lv_importe)
          WHERE bukrs = ls_bkpf-bukrs
            AND belnr = ls_bkpf-belnr
            AND gjahr = ls_bkpf-gjahr
            AND koart = 'D'
            AND kunnr = pv_kunnr.
        IF sy-subrc = 0.
          lv_importe_bd = trunc( lv_importe ).
*         Para pagos (P) no se compara importe
          IF lv_importe_bd = lv_importe_csv OR ps_datos-tipocomprobante = 'P'.
            APPEND lv_belnr_aux TO lt_belnr_match.
          ENDIF.
        ENDIF.
      ENDLOOP.
      DESCRIBE TABLE lt_belnr_match LINES lv_registros.
    ENDIF.
  ENDIF.

* 2. BÚSQUEDA ALTERNATIVA: POR FECHA (Si falló la búsqueda por folio o falla en BSEG)
  IF lv_registros = 0 AND lv_date IS NOT INITIAL.
    CLEAR: lt_bkpf, lt_belnr_match.
    SELECT bukrs belnr gjahr xblnr blart budat bldat
      FROM bkpf
      INTO TABLE lt_bkpf
      WHERE gjahr       = pv_gjahr
        AND bukrs       = pv_bukrs
        AND blart       IN s_blart
        AND ( bldat = lv_date OR budat = lv_date )
        AND xreversal   <> 1
        AND xreversal   <> 2.

    IF lt_bkpf IS NOT INITIAL.
      lv_fallback_m = 'X'.
      lv_importe_csv = pv_total.
      LOOP AT lt_bkpf INTO ls_bkpf.
        SELECT SINGLE belnr wrbtr
          FROM bseg
          INTO (lv_belnr_aux, lv_importe)
          WHERE bukrs = ls_bkpf-bukrs
            AND belnr = ls_bkpf-belnr
            AND gjahr = ls_bkpf-gjahr
            AND koart = 'D'
            AND kunnr = pv_kunnr.
        IF sy-subrc = 0.
          lv_importe_bd = trunc( lv_importe ).
          IF lv_importe_bd = lv_importe_csv OR ps_datos-tipocomprobante = 'P'.
            APPEND lv_belnr_aux TO lt_belnr_match.
          ENDIF.
        ENDIF.
      ENDLOOP.
      DESCRIBE TABLE lt_belnr_match LINES lv_registros.
    ENDIF.
  ENDIF.

* Evaluar resultados
  IF lv_registros > 1.
    IF lv_fallback_m = 'X'.
*     Mostrar todos los candidatos sin folio en SAP en el log
      LOOP AT lt_belnr_match INTO lv_belnr_aux.
        CLEAR gs_log.
        gs_log-icon         = gc_icon_warn.
        gs_log-bukrs        = pv_bukrs.
        gs_log-belnr        = lv_belnr_aux.
        gs_log-gjahr        = pv_gjahr.
        gs_log-rfc_emisor   = ps_datos-rfc_emisor.
        gs_log-rfc_receptor = ps_datos-rfc_receptor.
        gs_log-folio        = ps_datos-folio.
        gs_log-tipo         = ps_datos-tipocomprobante.
        gs_log-tipo_fac     = gc_tipo_venta.
        gs_log-uuid         = ps_datos-uuid.
        CONCATENATE 'Candidato sin folio en SAP (Revisión):' pv_bukrs lv_belnr_aux
          INTO gs_log-mensaje SEPARATED BY space.
        APPEND gs_log TO gt_log.
        gv_warning = gv_warning + 1. " Incrementar warnings
      ENDLOOP.
      pv_error = 'X'.
    ELSE.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-bukrs        = pv_bukrs.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_venta.
      gs_log-uuid         = ps_datos-uuid.
      CONCATENATE 'Documento no unívoco para folio:' ps_datos-folio
        'Soc:' pv_bukrs 'Cli:' pv_kunnr
        INTO gs_log-mensaje SEPARATED BY space.
      APPEND gs_log TO gt_log.
      pv_error = 'X'.
    ENDIF.

  ELSEIF lv_registros = 0.
    CLEAR gs_log.
    gs_log-icon         = gc_icon_err.
    gs_log-bukrs        = pv_bukrs.
    gs_log-gjahr        = pv_gjahr.
    gs_log-rfc_emisor   = ps_datos-rfc_emisor.
    gs_log-rfc_receptor = ps_datos-rfc_receptor.
    gs_log-folio        = ps_datos-folio.
    gs_log-tipo         = ps_datos-tipocomprobante.
    gs_log-tipo_fac     = gc_tipo_venta.
    gs_log-uuid         = ps_datos-uuid.
    CONCATENATE 'No doc venta ni por folio ni fecha. Soc:' pv_bukrs 'Cli:' pv_kunnr 'Año:' pv_gjahr
      INTO gs_log-mensaje SEPARATED BY space.
    APPEND gs_log TO gt_log.
    pv_error = 'X'.

  ELSEIF lv_registros = 1.
    READ TABLE lt_belnr_match INTO pv_belnr INDEX 1.

    DATA: lv_status TYPE c.
    PERFORM frm_existe_uuid
      USING pv_bukrs pv_belnr pv_gjahr ps_datos-uuid
      CHANGING lv_status lv_uuid_prev.

    IF lv_status = gc_stat_diff.
*     UUID ya existe y es DISTINTO -> warning
      pv_error_uuid = 'X'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_warn.
      gs_log-bukrs        = pv_bukrs.
      gs_log-belnr        = pv_belnr.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_venta.
      gs_log-uuid         = ps_datos-uuid.
      gs_log-uuid_previo  = lv_uuid_prev.
      CONCATENATE 'Discrepancia: Documento ya tiene otro UUID:' pv_bukrs pv_belnr pv_gjahr
        INTO gs_log-mensaje SEPARATED BY space.
      gs_log-budat     = ls_bkpf-budat.
      gs_log-bldat     = ls_bkpf-bldat.
      gs_log-blart     = ls_bkpf-blart.
      gs_log-monat     = ls_bkpf-budat+4(2).
      gs_log-test_mode = p_test.
      APPEND gs_log TO gt_log.
      gv_warning = gv_warning + 1.
    ELSEIF lv_status = gc_stat_same.
*     UUID ya existe y es el MISMO -> Todo OK
      pv_error_uuid = 'S'.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_ok.
      gs_log-bukrs        = pv_bukrs.
      gs_log-belnr        = pv_belnr.
      gs_log-gjahr        = pv_gjahr.
      gs_log-rfc_emisor   = ps_datos-rfc_emisor.
      gs_log-rfc_receptor = ps_datos-rfc_receptor.
      gs_log-folio        = ps_datos-folio.
      gs_log-tipo         = ps_datos-tipocomprobante.
      gs_log-tipo_fac     = gc_tipo_venta.
      gs_log-uuid         = ps_datos-uuid.
      gs_log-mensaje      = 'El documento ya cuenta con el mismo UUID.'.
      gs_log-test_mode    = p_test.
      APPEND gs_log TO gt_log.
      gv_ok = gv_ok + 1.
    ENDIF.
  ENDIF.

ENDFORM.                    " FRM_OBTENER_FACTURA_VENTA
