*&---------------------------------------------------------------------*
*& Include ZFIR_UUID_CFDI_UPDATE_FRM03
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& Form FRM_REPROCESAR_ERRORES
*&---------------------------------------------------------------------*
*& Reprocesa registros fallidos ignorando importes y forzando UUID en
*& operaciones Intercompany.
*&---------------------------------------------------------------------*
FORM frm_reprocesar_errores.

  DATA: lt_log      TYPE TABLE OF ztt_uuid_log,
        ls_log_db   TYPE ztt_uuid_log,
        lt_bkpf     TYPE TABLE OF gty_bkpf,
        ls_bkpf     TYPE gty_bkpf,
        lt_bseg     TYPE TABLE OF bseg,
        ls_bseg     TYPE bseg,
        ls_csv_data TYPE gty_csv_data,
        lv_success  TYPE abap_bool.

  " 1. Leer Logs con errores o advertencias
  SELECT * FROM ztt_uuid_log INTO TABLE lt_log
    WHERE icon_status IN ('@09@', '@0A@'). " Amarillo y Rojo

  IF sy-subrc <> 0.
    MESSAGE s398(00) WITH 'No hay registros para reprocesar' '' '' ''.
    RETURN.
  ENDIF.

  " Reset de contadores
  gv_total = lines( lt_log ).
  gv_ok = 0.
  gv_error = 0.
  gv_warning = 0.
  REFRESH gt_log.

  LOOP AT lt_log INTO ls_log_db.
    lv_success = abap_false.
    CLEAR: ls_bkpf, ls_csv_data.
    REFRESH: lt_bkpf, lt_bseg.

    " 2. Preparar datos pseudo-CSV para reutilizar función existente
    ls_csv_data-rfc_emisor      = ls_log_db-rfc_emisor.
    ls_csv_data-rfc_receptor    = ls_log_db-rfc_receptor.
    ls_csv_data-serie           = ls_log_db-serie.
    ls_csv_data-folio           = ls_log_db-folio.
    ls_csv_data-tipocomprobante = ls_log_db-tipo.
    ls_csv_data-uuid            = ls_log_db-uuid.

    " 3. Reglas de negocio según tipo de operación
    IF ls_log_db-tipo_fac = gc_tipo_interco. " Intercompany
      IF ls_log_db-belnr IS NOT INITIAL.
        " Forzar asignación al documento que ya se había detectado
        PERFORM frm_actualizar_factura_uuid USING ls_csv_data ls_log_db-bukrs ls_log_db-belnr ls_log_db-gjahr.
        lv_success = abap_true.
      ELSE.
        " Buscar en BKPF por coincidencia exacta de folio sin validar importe
        SELECT bukrs belnr gjahr xblnr blart budat bldat
          FROM bkpf INTO TABLE lt_bkpf
          WHERE bukrs = ls_log_db-bukrs
            AND gjahr = ls_log_db-gjahr
            AND xblnr = ls_log_db-folio.

        IF sy-subrc = 0.
          READ TABLE lt_bkpf INTO ls_bkpf INDEX 1. " Forzar asignación al primero encontrado
          PERFORM frm_actualizar_factura_uuid USING ls_csv_data ls_bkpf-bukrs ls_bkpf-belnr ls_bkpf-gjahr.
          lv_success = abap_true.
        ENDIF.
      ENDIF.

    ELSE. " Otras operaciones (Venta/Compra)
      " Buscar BKPF por folio exacto en todas las sociedades
      SELECT bukrs belnr gjahr xblnr blart budat bldat
        FROM bkpf INTO TABLE lt_bkpf
        WHERE xblnr = ls_log_db-folio.
        
      IF sy-subrc = 0.
        LOOP AT lt_bkpf INTO ls_bkpf.
          IF ls_log_db-tipo_fac = gc_tipo_compra.
            READ TABLE gt_t001z_cache INTO DATA(ls_cache_c) WITH KEY paval = ls_log_db-rfc_receptor.
            IF sy-subrc = 0 AND ls_cache_c-bukrs = ls_bkpf-bukrs.
              SELECT * FROM bseg INTO TABLE lt_bseg
                WHERE bukrs = ls_bkpf-bukrs
                  AND belnr = ls_bkpf-belnr
                  AND gjahr = ls_bkpf-gjahr
                  AND koart = 'K'.
              LOOP AT lt_bseg INTO ls_bseg.
                READ TABLE gt_lfa1_cache INTO DATA(ls_lfa1) WITH KEY stcd1 = ls_log_db-rfc_emisor.
                IF sy-subrc <> 0.
                  SELECT SINGLE lifnr stcd1 FROM lfa1 INTO ls_lfa1 WHERE stcd1 = ls_log_db-rfc_emisor.
                  IF sy-subrc = 0.
                    INSERT ls_lfa1 INTO TABLE gt_lfa1_cache.
                  ELSE.
                    ls_lfa1-stcd1 = ls_log_db-rfc_emisor.
                    INSERT ls_lfa1 INTO TABLE gt_lfa1_cache.
                  ENDIF.
                ENDIF.
                IF ls_bseg-lifnr = ls_lfa1-lifnr AND ls_bseg-lifnr IS NOT INITIAL.
                  PERFORM frm_actualizar_factura_uuid USING ls_csv_data ls_bkpf-bukrs ls_bkpf-belnr ls_bkpf-gjahr.
                  lv_success = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.
            ENDIF.
          ELSEIF ls_log_db-tipo_fac = gc_tipo_venta.
            READ TABLE gt_t001z_cache INTO DATA(ls_cache_v) WITH KEY paval = ls_log_db-rfc_emisor.
            IF sy-subrc = 0 AND ls_cache_v-bukrs = ls_bkpf-bukrs.
              SELECT * FROM bseg INTO TABLE lt_bseg
                WHERE bukrs = ls_bkpf-bukrs
                  AND belnr = ls_bkpf-belnr
                  AND gjahr = ls_bkpf-gjahr
                  AND koart = 'D'.
              LOOP AT lt_bseg INTO ls_bseg.
                READ TABLE gt_kna1_cache INTO DATA(ls_kna1) WITH KEY stcd1 = ls_log_db-rfc_receptor.
                IF sy-subrc <> 0.
                  SELECT SINGLE kunnr stcd1 FROM kna1 INTO ls_kna1 WHERE stcd1 = ls_log_db-rfc_receptor.
                  IF sy-subrc = 0.
                    INSERT ls_kna1 INTO TABLE gt_kna1_cache.
                  ELSE.
                    ls_kna1-stcd1 = ls_log_db-rfc_receptor.
                    INSERT ls_kna1 INTO TABLE gt_kna1_cache.
                  ENDIF.
                ENDIF.
                IF ls_bseg-kunnr = ls_kna1-kunnr AND ls_bseg-kunnr IS NOT INITIAL.
                  PERFORM frm_actualizar_factura_uuid USING ls_csv_data ls_bkpf-bukrs ls_bkpf-belnr ls_bkpf-gjahr.
                  lv_success = abap_true.
                  EXIT.
                ENDIF.
              ENDLOOP.
            ENDIF.
          ENDIF.
          IF lv_success = abap_true.
            EXIT. " Salir del loop de BKPF
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " 4. Control de Fallos / Log para ALV
    IF lv_success = abap_false.
      CLEAR gs_log.
      gs_log-icon         = gc_icon_err.
      gs_log-mensaje      = 'No se encontró coincidencia exacta de folio y RFC (Reproceso)'.
      gs_log-bukrs        = ls_log_db-bukrs.
      gs_log-gjahr        = ls_log_db-gjahr.
      gs_log-rfc_emisor   = ls_log_db-rfc_emisor.
      gs_log-rfc_receptor = ls_log_db-rfc_receptor.
      gs_log-serie        = ls_log_db-serie.
      gs_log-folio        = ls_log_db-folio.
      gs_log-tipo         = ls_log_db-tipo.
      gs_log-tipo_fac     = ls_log_db-tipo_fac.
      gs_log-uuid         = ls_log_db-uuid.
      APPEND gs_log TO gt_log.
      gv_error = gv_error + 1.
    ELSE.
      " Modificar el mensaje de gs_log que viene de frm_actualizar_factura_uuid
      CONCATENATE '[REPROCESO]' gs_log-mensaje INTO gs_log-mensaje SEPARATED BY space.
    ENDIF.

    " 5. Actualizar la tabla ZTT_UUID_LOG con el resultado final
    ls_log_db-icon_status = gs_log-icon.
    ls_log_db-mensaje     = gs_log-mensaje.
    ls_log_db-bukrs       = gs_log-bukrs.
    ls_log_db-belnr       = gs_log-belnr.
    ls_log_db-gjahr       = gs_log-gjahr.
    ls_log_db-budat       = gs_log-budat.
    ls_log_db-bldat       = gs_log-bldat.
    ls_log_db-monat       = gs_log-monat.
    ls_log_db-blart       = gs_log-blart.

    IF p_test IS INITIAL.
      UPDATE ztt_uuid_log FROM ls_log_db.
    ENDIF.

  ENDLOOP.

  " 5.5 Grabar entrada en log de ejecuciones ZTT_UUID_EXEC
  IF p_test IS INITIAL.
    DATA: ls_exec TYPE ztt_uuid_exec.
    ls_exec-fichero  = |REPROCESO_MASIVO_{ sy-datum }|.
    ls_exec-datum    = sy-datum.
    ls_exec-uzeit    = sy-uzeit.
    ls_exec-uname    = sy-uname.
    ls_exec-tot_reg  = gv_total.
    ls_exec-ok_reg   = gv_ok.
    ls_exec-warn_reg = gv_warning.
    ls_exec-err_reg  = gv_error.
    INSERT ztt_uuid_exec FROM ls_exec.
  ENDIF.

  " 6. Mostrar el resultado por pantalla
  PERFORM frm_mostrar_alv.

ENDFORM.
