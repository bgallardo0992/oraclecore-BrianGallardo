# STATUS — Estado real del repositorio

Estados: **Hecho**, **Parcial**, **No hecho**. Última actualización: 2026-10-26 (hasta A.5 e instalación desde cero).

**Cómo se verificó cada punto** (se indica en la columna *Verificación*):
- **SQL*Plus**: ejecutado por la IA (Claude Code) contra el contenedor `oracle-core` del candidato, con salida revisada.
- **DBeaver**: ejecutado por el candidato en su DBeaver; verificado con las capturas que compartió.

| Requisito | Estado | Verificación | Nota |
|---|---|---|---|
| Entorno y datos del core (Anexo B) | Hecho | SQL*Plus + DBeaver | Cantidades 6 / 9 / 4 / 11 / 12. Commit `ff8b81b`. |
| A.1 Modelo de catálogos | Hecho | SQL*Plus + DBeaver | Tablas, PK/FK/UK/CK (Anexo C), auditoría por trigger, datos iniciales. Pruebas T1–T10 OK. Commit `c91c2cc`. |
| Esqueleto funcional (package compilable) | Hecho | SQL*Plus | Se compiló primero un esqueleto con cuerpos «no implementado» (`-20999`) antes del CRUD. No quedó commit propio del esqueleto: fue un paso previo al commit de A.2. |
| A.2 Package + Object Types | Hecho | SQL*Plus + DBeaver | `PKG_TTEM_CATALOG`, `TYP_TTEM_ITEM`, `TYP_TTEM_ITEM_TAB`. Eliminación lógica. Commit `d2f02c8`. |
| A.3 Validaciones y excepciones propias | Hecho | SQL*Plus + DBeaver | Códigos -20100 a -20107 y -20900. V1–V12, V14–V17 OK en DBeaver. `test_a3_error_tecnico.sql` también OK en DBeaver (T-TEC: `-20900` con `ORA-08004` en el mensaje; secuencia restaurada). Commit `048ec4d`. |
| A.4 JSON por ItemId | Hecho | SQL*Plus + DBeaver | `obtener_item_json`, 9 claves, nulos como `null`, ítem inexistente → `-20101`. J1–J6 OK en DBeaver. Commit `6c96337`. |
| B Consulta de cliente por cuenta | Hecho | SQL*Plus + DBeaver | Una fila por cuenta; `LISTAGG`; cuenta inexistente → 0 filas. 5 cuentas OK en DBeaver. Commit `b75dc94`. |
| C Transferencia bancaria | Hecho | SQL*Plus + DBeaver | `PKG_CORE_SETTLEMENT.transferir` implementado: validaciones, `FOR UPDATE` en orden ascendente, `SAVEPOINT`, referencia única, falla simulada tras el débito. `test_c_transferencias.sql` (todas OK) y los 6 casos del enunciado (`casos_c_manual.sql`) verificados por la IA en SQL*Plus. `test_c_transferencias.sql` además OK en DBeaver (todas las líneas, con el ROLLBACK final); `casos_c_manual.sql` (los 6 casos del enunciado) y `restablecer_casos_c.sql` también OK en DBeaver. **No probado con dos sesiones concurrentes reales**: la ausencia de deadlock se apoya en el orden de bloqueo, no en una prueba. No hay procedimiento de reversa (opcional). |
| D Propuesta de mejora | Hecho | Revisada y aprobada por el candidato | Redactada en el README (11 puntos, dentro del máximo de 20 líneas, sin código). Ajustada tras la revisión del candidato: validación solo lectura (sin savepoint) y reversión compensatoria con auditoría de solo inserción. Los plazos y metas son estimaciones iniciales a confirmar con el equipo. |
| A.5 Carga masiva (BULK COLLECT / FORALL) | Hecho | SQL*Plus + DBeaver (test y restablecimiento) | `PKG_TTEM_LOAD.cargar_lote` con `BULK COLLECT ... LIMIT` y `FORALL ... SAVE EXCEPTIONS`, tabla `TTEM_LOAD_ERROR`. Resultado de control **5 cargados / 7 rechazados** con `LIMIT 4` y `LIMIT 200`; idempotente; bloqueo `NOWAIT` comprobado con dos sesiones reales (`ORA-20310`). `scripts/test_a5_carga.sql` OK en DBeaver (todas las líneas) y `restablecer_a5.sql` OK en DBeaver (3 ítems, 0 errores, 12 pendientes); la carga real (`cargar_lote_a5.sql`) la verificó la IA en SQL*Plus y no se ha visto aún en DBeaver. Los criterios de validación del lote duplican los de `PKG_TTEM_CATALOG` (no se reutilizan para no insertar fila a fila). |
| `TTEM_AUDIT_LOG` (bitácora con valores anteriores, opcional) | No hecho | — | La auditoría actual guarda usuario y fecha en la propia fila (trigger), sin valores anteriores. |
| README, AI-LOG, STATUS, `connection.env.example` | Parcial | — | Creados. El README no tiene aún ejemplos de transferencia ni la Sección D; el AI-LOG se actualiza en cada fase. |
| Instalación desde cero | Hecho | Contenedor limpio (`gvenzl/oracle-free:23.9`, puerto 1522), SQL*Plus | Siguiendo el orden del README: `setup/` (cantidades 6 / 9 / 4 / 11 / 12), `ddl/` y `plsql/` sin errores ni avisos (3 packages, 2 tipos, 2 triggers, 8 tablas: todo `VALID`, `user_errors` = 0). Todas las pruebas en `OK` y 0 `FALLA`: A.1 (10), A.2 (5), A.3 (16 + error técnico), A.4 (6), B (5 filas `OK`), C (34 líneas y los 6 casos del enunciado), A.5 (14 y carga real 5 cargados / 7 rechazados). Tras los scripts de restablecimiento el estado queda como el inicial. Limitaciones de la prueba: se hizo por SQL*Plus (el candidato usa DBeaver) y el script `00_setup_usuario.sql` se probó sin la palabra `HIDE` de `ACCEPT`, porque exige una terminal interactiva real que el entorno de pruebas no tiene. |
| Publicación en GitHub | No hecho | — | Repositorio local sin remoto: no se ha hecho `push`. |

## Supuestos y decisiones pendientes de ratificar por el candidato
- `valid_from` es obligatorio en `TTEM_ITEM` (el enunciado no lo precisa).
- `COM_MANT` tiene valor `'12.50'`, tomado de las comisiones del histórico de `CORE_TRX` (el enunciado no da valor).
- Un catálogo inactivo no admite ítems nuevos (regla pedida por el candidato, código `-20107`).

## Limitaciones conocidas
- `INITCAP` en la consulta B pone `De`/`Del` en mayúscula en nombres compuestos.
- Los usuarios de Banca en Línea pertenecen al cliente, no a la cuenta: un cliente con varias cuentas muestra los mismos usuarios en todas.
- Los identificadores de ítems no son consecutivos (las secuencias no se revierten con `ROLLBACK`).
- Los scripts de `setup/` conservan sus sentencias originales, pero se les quitaron las líneas en blanco (producto de la extracción desde el documento) y no se ejecutan en DBeaver por usar comandos de SQL*Plus.
