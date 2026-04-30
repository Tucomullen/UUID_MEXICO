# Solución Inteligente: UUIDs Duplicados en Facturas Intercompany

## 🎯 Problema Específico

Ya ejecutaste el programa **2 veces**, por lo que las facturas Intercompany tienen:
- ✅ **Lado CORRECTO**: El documento que tiene el folio en `XBLNR` (referencia)
- ❌ **Lado INCORRECTO**: El otro documento (sin folio o con folio incorrecto)
- 🔴 **Ambos tienen el MISMO UUID** (duplicado)

### Ejemplo Real:

```
UUID: 12345678-1234-1234-1234-123456789ABC

Documento 1 (VENTA):
  BUKRS: AES1
  BELNR: 1000000001
  GJAHR: 2018
  XBLNR: "F-12345"  ← TIENE FOLIO (CORRECTO)
  
Documento 2 (COMPRA):
  BUKRS: AMG1
  BELNR: 2000000001
  GJAHR: 2018
  XBLNR: ""         ← SIN FOLIO (INCORRECTO)

→ Ambos tienen el mismo UUID (DUPLICADO)
```

---

## ✅ Solución Implementada

He modificado `ZFIR_UUID_DELETE_DUPLICATES` para aplicar **lógica inteligente**:

### **Lógica de Decisión:**

#### **1. Detectar si es Intercompany**
- Verifica si ambas sociedades están en `T001Z` con `PARTY = 'MX_RFC'`
- Si ambas son mexicanas → **ES INTERCOMPANY**

#### **2. Identificar el lado CORRECTO**
- **Lado CORRECTO**: El documento cuyo `XBLNR` (referencia) NO está vacío
- **Lado INCORRECTO**: El documento con `XBLNR` vacío

#### **3. Acción**
- ✅ **CONSERVAR** el UUID del lado CORRECTO
- ❌ **BORRAR** el UUID del lado INCORRECTO

#### **4. Casos especiales**

| Caso | Acción |
|------|--------|
| Solo doc1 tiene XBLNR | Conservar doc1, borrar doc2 |
| Solo doc2 tiene XBLNR | Conservar doc2, borrar doc1 |
| Ambos tienen XBLNR | Conservar el que tiene XBLNR más largo (más específico) |
| Ninguno tiene XBLNR | Borrar ambos (caso anómalo) |
| Más de 2 documentos | Borrar todos (no es Intercompany) |

---

## 🔧 Cambios Realizados

### **1. Nuevos campos en estructura `gty_uuid_sap`:**
```abap
xblnr   TYPE xblnr1,  " Referencia (folio)
blart   TYPE blart,   " Clase de documento
```

### **2. Nueva función `FRM_FILTRAR_DUPLICADOS_INTERCO`:**
- Lee todos los documentos con UUID duplicado
- Agrupa por UUID
- Para cada grupo de 2 documentos:
  - Verifica si es Intercompany
  - Identifica el lado correcto (con XBLNR)
  - Marca para borrar solo el lado incorrecto
  - Registra el lado conservado

### **3. Nueva función `FRM_ES_INTERCOMPANY`:**
- Verifica si dos sociedades son ambas mexicanas
- Consulta `T001Z` con `PARTY = 'MX_RFC'`

### **4. Modificación en `FRM_DETECTAR_DUPLICADOS`:**
- Ahora lee también `XBLNR` y `BLART` desde `BKPF`
- Necesarios para la lógica de decisión

### **5. Modificación en `FRM_BORRAR_UUIDS`:**
- Ahora borra solo los documentos en `gt_docs_borrar` (filtrados)
- No borra todos los duplicados indiscriminadamente

---

## 📊 Resultado Esperado

### **Antes de ejecutar:**
```
UUID: 12345678-1234-1234-1234-123456789ABC
  ✗ AES1 / 1000000001 / 2018 (XBLNR: "F-12345")
  ✗ AMG1 / 2000000001 / 2018 (XBLNR: "")
  → DUPLICADO
```

### **Después de ejecutar (MODO TEST):**
```
UUID: 12345678-1234-1234-1234-123456789ABC
  ✅ AES1 / 1000000001 / 2018 (XBLNR: "F-12345") → CONSERVADO
  ❌ AMG1 / 2000000001 / 2018 (XBLNR: "")        → SE BORRARÁ
```

### **Después de ejecutar (MODO PRODUCTIVO):**
```
UUID: 12345678-1234-1234-1234-123456789ABC
  ✅ AES1 / 1000000001 / 2018 (XBLNR: "F-12345") → CONSERVADO
  ✅ AMG1 / 2000000001 / 2018 (SIN UUID)         → UUID BORRADO
  → YA NO HAY DUPLICADO
```

---

## 🚀 Plan de Ejecución Actualizado

### **Paso 1: Ejecutar en MODO TEST (Simulación)**
```abap
Programa: ZFIR_UUID_DELETE_DUPLICATES
P_TEST: ✓ (marcado)
S_BUKRS: (todas)
S_GJAHR: (todos)
```

**Resultado esperado:**
- ALV mostrará:
  - Documentos con acción "CONSERVADO" (verde) → Lado correcto
  - Documentos con acción "BORRADO" (amarillo) → Lado incorrecto
- **NO se borra nada** (solo simulación)
- Revisar que la lógica identifica correctamente los lados

### **Paso 2: Ejecutar en MODO PRODUCTIVO**
```abap
Programa: ZFIR_UUID_DELETE_DUPLICATES
P_TEST: ☐ (desmarcado)
S_BUKRS: (todas)
S_GJAHR: (todos)
```

**Resultado esperado:**
- Se borran los UUIDs del lado INCORRECTO
- Se conservan los UUIDs del lado CORRECTO
- ALV mostrará resumen con:
  - Documentos conservados
  - Documentos borrados

### **Paso 3: Borrar histórico del Dashboard**
```
1. Abrir: ZFIR_UUID_CFDI_DASH
2. Pulsar: "Borrar histórico"
3. Confirmar
```

### **Paso 4: Reejecutar carga masiva**
```abap
Programa: ZFIR_UUID_CFDI_UPDATE
Modo: Servidor AL11 (P_SERV = 'X')
Modo: PRODUCTIVO (P_TEST desmarcado)
Ejecución: En fondo (SM36)
```

**Con la corrección en FRM01:**
- Las facturas Intercompany se **omitirán** (no se procesarán)
- **NO se generarán nuevos duplicados**

### **Paso 5: Verificar resultados**
```sql
-- Verificar que NO hay duplicados
SELECT uuid, COUNT(*) as cnt
FROM ztt_uuid_log
WHERE uuid <> ''
GROUP BY uuid
HAVING COUNT(*) > 1
ORDER BY cnt DESC
```

**Resultado esperado:** 0 filas

---

## 📋 ALV del Programa

El ALV mostrará las siguientes columnas:

| Icono | UUID | Sociedad | Documento | Ejercicio | Referencia | Acción | Detalle |
|-------|------|----------|-----------|-----------|------------|--------|---------|
| 🟢 | 1234... | AES1 | 1000000001 | 2018 | F-12345 | CONSERVADO | Intercompany: Lado correcto (tiene folio en XBLNR) |
| 🟢 | 1234... | AMG1 | 2000000001 | 2018 | | BORRADO | UUID eliminado correctamente. |

---

## 🎯 Ventajas de esta Solución

1. ✅ **Inteligente**: No borra todos los duplicados, solo los incorrectos
2. ✅ **Conserva datos**: Mantiene el UUID en el documento correcto
3. ✅ **Segura**: Modo TEST permite verificar antes de borrar
4. ✅ **Auditable**: ALV muestra qué se conserva y qué se borra
5. ✅ **Específica**: Solo afecta a Intercompany, no a otros duplicados

---

## ⚠️ Consideraciones

1. **Facturas Intercompany futuras**: Con la corrección en `ZFIR_UUID_CFDI_UPDATE_FRM01`, las facturas Intercompany se **omitirán** en futuros reprocesos, evitando nuevos duplicados.

2. **Documentos sin XBLNR**: Si ambos documentos Intercompany tienen `XBLNR` vacío, se borrarán ambos (caso anómalo que requiere revisión manual).

3. **Más de 2 duplicados**: Si un UUID aparece en más de 2 documentos, se borrarán todos (no es Intercompany, es un error más grave).

4. **Backup recomendado**: Aunque el programa es seguro, se recomienda hacer backup de las tablas `STXH` y `STXL` antes de ejecutar en productivo.

---

## 📞 Soporte

**Desarrollador:** xlgarcia (Acciona TIC)  
**Fecha:** 30/04/2026  
**Repositorio:** https://github.com/Tucomullen/UUID_MEXICO.git

---

## ✅ Checklist de Ejecución

- [ ] Código modificado en `ZFIR_UUID_DELETE_DUPLICATES.abap`
- [ ] Programa activado en SE38
- [ ] Ejecutado en MODO TEST (verificar lógica)
- [ ] Revisado ALV (conservados vs borrados)
- [ ] Ejecutado en MODO PRODUCTIVO
- [ ] Verificado: UUIDs duplicados eliminados
- [ ] Borrado histórico del dashboard
- [ ] Reejecutado `ZFIR_UUID_CFDI_UPDATE` en fondo
- [ ] Verificado: 0 nuevos duplicados
- [ ] Consulta SQL: 0 duplicados en ZTT_UUID_LOG

---

**Estado:** ✅ IMPLEMENTADO  
**Próximo paso:** Ejecutar en MODO TEST para validar
