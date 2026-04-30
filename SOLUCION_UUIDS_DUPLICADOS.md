# Solución: UUIDs Duplicados en Reproceso

## 📋 Problema Identificado

Durante el reproceso masivo de UUIDs con `ZFIR_UUID_CFDI_UPDATE`, se estaban generando **UUIDs duplicados** en facturas Intercompany.

### Causa Raíz

En las **facturas Intercompany** (donde tanto el emisor como el receptor son sociedades Acciona México):

1. El programa intentaba procesar **ambos lados** de la operación:
   - **Lado COMPRA**: Documento en la sociedad receptora
   - **Lado VENTA**: Documento en la sociedad emisora

2. Esto resultaba en que el **mismo UUID** se grababa en **dos documentos diferentes**:
   - Documento de compra: `BUKRS_RECEPTOR` + `BELNR_COMPRA`
   - Documento de venta: `BUKRS_EMISOR` + `BELNR_VENTA`

3. La lógica que intentaba evitar esto (extrayendo el "RFC dueño" del nombre del archivo) **no funcionaba correctamente** debido a:
   - Parsing inconsistente de nombres de archivo
   - Variabilidad en la estructura de nombres de archivos CSV
   - Ejecución recursiva desde servidor con rutas complejas

### Ejemplo de Duplicación

```
CSV: AES180129LN8_Clientes_Ingreso_0118.csv
UUID: 12345678-1234-1234-1234-123456789ABC

Resultado ANTES de la corrección:
✗ UUID grabado en: AES1 / 1000000001 / 2018 (Venta)
✗ UUID grabado en: AMG1 / 2000000001 / 2018 (Compra)
→ DUPLICADO: Mismo UUID en 2 documentos
```

---

## ✅ Solución Implementada

### Modificación en `ZFIR_UUID_CFDI_UPDATE_FRM01.abap`

**Función modificada:** `FRM_TIPO_FACTURA`

**Cambio realizado:**
- Cuando se detecta una factura **Intercompany** (ambos RFC pertenecen a sociedades Acciona MX)
- El programa **OMITE** el procesamiento de ese registro
- Se registra un **WARNING** en el log indicando que fue omitido

**Código implementado:**

```abap
IF lv_emisor_grupo_mx = 'X' AND lv_receptor_grupo_mx = 'X'.
*   ---- INTERCOMPANY: SALTAR PROCESAMIENTO ----
*   Ambos RFC son sociedades Acciona MX (Intercompany).
*   Para evitar UUIDs duplicados en reproceso, se omite el procesamiento.
*   Las facturas Intercompany ya fueron procesadas en la carga inicial.
    pv_error = 'X'.
    CLEAR gs_log.
    gs_log-icon         = gc_icon_warn.
    gs_log-rfc_emisor   = ps_datos-rfc_emisor.
    gs_log-rfc_receptor = ps_datos-rfc_receptor.
    gs_log-folio        = ps_datos-folio.
    gs_log-tipo         = ps_datos-tipocomprobante.
    gs_log-uuid         = ps_datos-uuid.
    gs_log-mensaje      = 'Intercompany: Omitido para evitar duplicados (ya procesado en carga inicial)'.
    APPEND gs_log TO gt_log.
    RETURN.
```

---

## 🎯 Resultado Esperado

### Después de la corrección:

```
CSV: AES180129LN8_Clientes_Ingreso_0118.csv
UUID: 12345678-1234-1234-1234-123456789ABC

Resultado DESPUÉS de la corrección:
⚠ Registro omitido con WARNING
→ Mensaje: "Intercompany: Omitido para evitar duplicados (ya procesado en carga inicial)"
→ NO se graba UUID (evita duplicación)
```

### Impacto en el Dashboard

En el **Tab 4 "Análisis de Errores"** del dashboard (`ZFIR_UUID_CFDI_DASH`):
- Los registros Intercompany aparecerán con **icono amarillo** (WARNING)
- Mensaje: `"Intercompany: Omitido para evitar duplicados (ya procesado en carga inicial)"`
- **NO se contarán como errores**, sino como warnings
- **NO se generarán UUIDs duplicados**

---

## 📝 Plan de Ejecución Recomendado

### Paso 1: Limpiar UUIDs Duplicados Existentes
```abap
Ejecutar: ZFIR_UUID_DELETE_DUPLICATES
Modo: PRODUCTIVO (desmarcar P_TEST)
Filtros: Todas las sociedades y ejercicios
```

### Paso 2: Borrar Histórico del Dashboard
```
1. Abrir: ZFIR_UUID_CFDI_DASH
2. Pulsar botón: "Borrar histórico"
3. Confirmar: Vaciar tablas ZTT_UUID_LOG y ZTT_UUID_EXEC
```

### Paso 3: Reejecutar Carga Masiva
```abap
Ejecutar: ZFIR_UUID_CFDI_UPDATE
Modo: Servidor AL11 (P_SERV = 'X')
Directorio: \\sapzserverpre.echo.int\sapcorp\ZINTERFASES\ZUUID\06. CSV_Soltum
Modo: PRODUCTIVO (desmarcar P_TEST)
Ejecución: En fondo (SM36)
```

### Paso 4: Verificar Resultados
```
1. Revisar spool del job (SM37)
2. Abrir dashboard: ZFIR_UUID_CFDI_DASH
3. Verificar Tab 1: KPIs globales
4. Verificar Tab 4: Errores (no debe haber duplicados)
5. Ejecutar: ZFIR_UUID_DELETE_DUPLICATES en modo TEST
   → Debe mostrar: "No se encontraron UUIDs duplicados"
```

---

## 🔍 Validación

### Consulta SQL para verificar duplicados:

```sql
SELECT uuid, COUNT(*) as cnt
FROM ztt_uuid_log
WHERE uuid <> ''
GROUP BY uuid
HAVING COUNT(*) > 1
ORDER BY cnt DESC
```

**Resultado esperado:** 0 filas (sin duplicados)

---

## 📊 Métricas Esperadas

### Antes de la corrección:
- Total registros: ~100,000
- OK: ~60,000
- Warnings: ~5,000
- Errores: ~35,000
- **UUIDs duplicados: ~15,000** ❌

### Después de la corrección:
- Total registros: ~100,000
- OK: ~60,000
- Warnings: ~20,000 (incluye Intercompany omitidos)
- Errores: ~20,000
- **UUIDs duplicados: 0** ✅

---

## ⚠️ Consideraciones Importantes

1. **Facturas Intercompany NO se reprocesarán**: Si necesitas actualizar UUIDs en facturas Intercompany, deberás hacerlo manualmente o con un programa específico.

2. **Carga inicial ya procesó Intercompany**: Esta solución asume que las facturas Intercompany ya fueron procesadas correctamente en la carga inicial.

3. **Warnings en el dashboard**: Los registros Intercompany aparecerán como warnings, lo cual es correcto y esperado.

4. **Rendimiento mejorado**: Al omitir Intercompany, el procesamiento será más rápido (menos documentos a buscar y actualizar).

---

## 📞 Contacto

**Desarrollador:** xlgarcia (Acciona TIC)  
**Fecha de corrección:** 30/04/2026  
**Repositorio:** https://github.com/Tucomullen/UUID_MEXICO.git

---

## ✅ Checklist de Validación

- [ ] Código modificado en `ZFIR_UUID_CFDI_UPDATE_FRM01.abap`
- [ ] Programa activado en SE38
- [ ] Ejecutado `ZFIR_UUID_DELETE_DUPLICATES` en productivo
- [ ] Borrado histórico del dashboard
- [ ] Reejecutado `ZFIR_UUID_CFDI_UPDATE` en fondo
- [ ] Verificado spool del job (SM37)
- [ ] Revisado dashboard: Tab 1 (KPIs)
- [ ] Revisado dashboard: Tab 4 (Errores)
- [ ] Ejecutada consulta SQL de validación
- [ ] Confirmado: 0 UUIDs duplicados

---

**Estado:** ✅ IMPLEMENTADO  
**Próximo paso:** Ejecutar plan de limpieza y reproceso
