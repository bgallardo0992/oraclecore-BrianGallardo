# STATUS — Estado real del repositorio

Estados: **Hecho**, **Parcial**, **No hecho**. Última actualización: 2026-10-26 (hasta la Fase C).

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
| C Transferencia bancaria | Hecho | SQL*Plus + DBeaver (prueba automática) | `PKG_CORE_SETTLEMENT.transferir` implementado: validaciones, `FOR UPDATE` en orden ascendente, `SAVEPOINT`, referencia única, falla simulada tras el débito. `test_c_transferencias.sql` (todas OK) y los 6 casos del enunciado (`casos_c_manual.sql`) verificados por la IA en SQL*Plus. `test_c_transferencias.sql` además OK en DBeaver (todas las líneas, con el ROLLBACK final); `casos_c_manual.sql` aún no visto en DBeaver. **No probado con dos sesiones concurrentes reales**: la ausencia de deadlock se apoya en el orden de bloqueo, no en una prueba. No hay procedimiento de reversa (opcional). |
| D Propuesta de mejora | No hecho | — | Falta redactarla (máx. 20 líneas) y ponerla en el README. |
| A.5 Carga masiva (BULK COLLECT / FORALL) | No hecho | — | P2, se aborda solo tras C y D. Resultado de control esperado: 5 cargados / 7 rechazados. |
| `TTEM_AUDIT_LOG` (bitácora con valores anteriores, opcional) | No hecho | — | La auditoría actual guarda usuario y fecha en la propia fila (trigger), sin valores anteriores. |
| README, AI-LOG, STATUS, `connection.env.example` | Parcial | — | Creados. El README no tiene aún ejemplos de transferencia ni la Sección D; el AI-LOG se actualiza en cada fase. |
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
