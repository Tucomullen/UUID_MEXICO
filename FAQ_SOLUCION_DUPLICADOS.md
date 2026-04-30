# ❓ FAQ - Solución UUIDs Duplicados

## Preguntas Frecuentes sobre la Solución

---

### **1. ¿Por qué se duplicaron los UUIDs?**

**Respuesta:**
Las facturas **Intercompany** (donde tanto emisor como receptor son sociedades Acciona MX) se procesaban **dos veces**:
- Una vez como **VENTA** (en la sociedad emisora)
- Una vez como **COMPRA** (en la sociedad receptora)

Ambos documentos recibían el **mismo UUID**, causando duplicados.

---

### **2. ¿Cómo sabe el programa cuál UUID borrar y cuál conservar?**

**Respuesta:**
El programa usa el campo `XBLNR` (referencia) de la tabla `BKPF`:
- **Lado CORRECTO**: El documento que tiene folio en `XBLNR` → **CONSERVAR**
- **Lado INCORRECTO**: El documento sin folio en `XBLNR` → **BORRAR**

Ejemplo:
```
Documento 1: XBLNR = "F-12345" → CONSERVAR ✅
Documento 2: XBLNR = ""        → BORRAR ❌
```

---

### **3. ¿Qué pasa si ambos documentos tienen XBLNR?**

**Respuesta:**
El programa conserva el que tiene el `XBLNR` **más largo** (más específico):
```
Documento 1: XBLNR = "F-12345"     → CONSERVAR ✅ (7 caracteres)
Documento 2: XBLNR = "F-123"       → BORRAR ❌ (5 caracteres)
```

---

### **4. ¿Qué pasa si ninguno tiene XBLNR?**

**Respuesta:**
Se borran **ambos** UUIDs (caso anómalo que requiere revisión manual).

---

### **5. ¿El programa borra TODOS los duplicados o solo los de Intercompany?**

**Respuesta:**
El programa aplica **lógica diferente** según el caso:

| Caso | Acción |
|------|--------|
| **2 documentos + ambas sociedades MX** | Lógica inteligente (conservar lado correcto) |
| **2 documentos + NO ambas sociedades MX** | Borrar ambos |
| **Más de 2 documentos** | Borrar todos |

---

### **6. ¿Es seguro ejecutar el programa?**

**Respuesta:**
**SÍ**, por varias razones:
1. ✅ Tiene **MODO TEST** (simulación sin borrar)
2. ✅ Muestra **ALV detallado** antes de borrar
3. ✅ Solo borra UUIDs **duplicados** (no afecta a los únicos)
4. ✅ Conserva el UUID **correcto** (no borra todo)

**Recomendación:** Ejecutar primero en MODO TEST para verificar.

---

### **7. ¿Qué pasa con las facturas Intercompany en futuros reprocesos?**

**Respuesta:**
Con la corrección en `ZFIR_UUID_CFDI_UPDATE_FRM01`:
- Las facturas Intercompany se **OMITEN** (no se procesan)
- Se registra un **WARNING** en el log
- **NO se generan nuevos duplicados**

---

### **8. ¿Puedo ejecutar el programa varias veces?**

**Respuesta:**
**SÍ**, el programa es **idempotente**:
- Si ejecutas 2 veces, la segunda vez **no encontrará duplicados** (ya fueron borrados)
- No causa errores ni efectos secundarios

---

### **9. ¿Cómo verifico que funcionó correctamente?**

**Respuesta:**
Ejecuta esta consulta SQL:

```sql
SELECT uuid, COUNT(*) as cnt
FROM ztt_uuid_log
WHERE uuid <> ''
GROUP BY uuid
HAVING COUNT(*) > 1
ORDER BY cnt DESC
```

**Resultado esperado:** `0 filas` (sin duplicados)

---

### **10. ¿Qué hago si el programa encuentra más de 2 documentos con el mismo UUID?**

**Respuesta:**
Eso indica un **error más grave** (no es Intercompany):
- El programa **borrará todos** los UUIDs de esos documentos
- Deberás **investigar manualmente** por qué se duplicaron
- Posibles causas:
  - Ejecuciones múltiples del programa
  - Datos incorrectos en los CSV
  - Errores en la lógica de búsqueda

---

### **11. ¿Puedo filtrar por sociedad o ejercicio?**

**Respuesta:**
**SÍ**, el programa tiene filtros opcionales:
```
S_BUKRS: Filtrar por sociedad (ej: AES1, AMG1)
S_GJAHR: Filtrar por ejercicio (ej: 2018, 2019)
```

Si no pones filtros, procesa **todas** las sociedades y ejercicios.

---

### **12. ¿Cuánto tarda en ejecutar?**

**Respuesta:**
Depende del número de duplicados:
- **Pocos duplicados** (< 1,000): 1-2 minutos
- **Muchos duplicados** (> 10,000): 5-10 minutos
- **Modo TEST**: Más rápido (no borra, solo lee)

---

### **13. ¿Qué significa cada icono en el ALV?**

**Respuesta:**

| Icono | Color | Significado |
|-------|-------|-------------|
| 🟢 | Verde | UUID conservado (lado correcto) |
| 🟢 | Verde | UUID borrado correctamente |
| 🟡 | Amarillo | Simulación (MODO TEST) |
| 🔴 | Rojo | Error al borrar |

---

### **14. ¿Puedo deshacer el borrado?**

**Respuesta:**
**NO directamente**, pero:
- Los UUIDs están en los **archivos CSV originales**
- Puedes **reejecutar** `ZFIR_UUID_CFDI_UPDATE` para volver a grabarlos
- **Recomendación:** Hacer backup de `STXH` y `STXL` antes de ejecutar en productivo

---

### **15. ¿Qué pasa si ejecuto el programa ANTES de corregir ZFIR_UUID_CFDI_UPDATE?**

**Respuesta:**
- El programa **borrará los duplicados** correctamente
- PERO si vuelves a ejecutar `ZFIR_UUID_CFDI_UPDATE` **sin la corrección**, se volverán a duplicar
- **Recomendación:** Corregir ambos programas antes de ejecutar

---

### **16. ¿El programa afecta a los documentos contables en SAP?**

**Respuesta:**
**NO**, el programa solo borra los **textos UUID** (tablas `STXH` y `STXL`):
- **NO modifica** `BKPF` (cabecera de documentos)
- **NO modifica** `BSEG` (posiciones de documentos)
- **NO afecta** la contabilidad

---

### **17. ¿Qué hago si el programa muestra errores?**

**Respuesta:**
Revisa el ALV:
- **Icono rojo**: Error al borrar
- **Mensaje**: Descripción del error

Posibles causas:
- Falta de autorización para borrar textos
- Documento bloqueado por otro usuario
- Error de base de datos

**Solución:** Contactar con el administrador SAP.

---

### **18. ¿Puedo ejecutar el programa en fondo (SM36)?**

**Respuesta:**
**SÍ**, pero:
- El ALV **no se mostrará** (solo en ejecución online)
- Los resultados se escriben en el **spool** (SM37)
- **Recomendación:** Ejecutar primero online en MODO TEST, luego en fondo en PRODUCTIVO

---

### **19. ¿Qué pasa con los registros en ZTT_UUID_LOG?**

**Respuesta:**
El programa **NO modifica** `ZTT_UUID_LOG`:
- Solo borra UUIDs de `STXH` y `STXL` (textos SAP)
- Los logs históricos se mantienen
- **Recomendación:** Borrar histórico del dashboard después de limpiar duplicados

---

### **20. ¿Necesito activar el programa después de modificarlo?**

**Respuesta:**
**SÍ**, después de cualquier modificación:
1. Guardar el programa (Ctrl+S)
2. **Activar** el programa (Ctrl+F3 o icono de activación)
3. Verificar que no hay errores de sintaxis

---

## 🆘 Soporte

Si tienes más preguntas:
- **Desarrollador:** xlgarcia (Acciona TIC)
- **Repositorio:** https://github.com/Tucomullen/UUID_MEXICO.git
- **Documentación:** Ver archivos `.md` en el proyecto

---

## ✅ Checklist Rápido

Antes de ejecutar, verifica:
- [ ] Programa `ZFIR_UUID_DELETE_DUPLICATES` modificado y activado
- [ ] Programa `ZFIR_UUID_CFDI_UPDATE_FRM01` modificado y activado
- [ ] Ejecutar primero en **MODO TEST**
- [ ] Revisar ALV (conservados vs borrados)
- [ ] Si todo OK, ejecutar en **MODO PRODUCTIVO**
- [ ] Verificar con consulta SQL (0 duplicados)
- [ ] Borrar histórico del dashboard
- [ ] Reejecutar carga masiva

---

**¿Listo para empezar?** 🚀
