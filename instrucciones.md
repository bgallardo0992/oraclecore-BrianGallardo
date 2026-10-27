# INSTRUCCIONES — Prueba Técnica Oracle Core Bancario

> Guía paso a paso. Se actualiza al terminar cada etapa.
> **Cliente SQL:** DBeaver · **Etapa actual:** FASE 0 (análisis y preparación del entorno)
> **Columna "Tiempo":** duración estimada del paso. **Columna "Hora real":** complétala tú (inicio–fin).
> Ningún script de este archivo se ha ejecutado todavía: se marcará como verificado solo cuando me compartas el resultado.

---

## FASE 0 — Análisis y preparación

### A. Objetivo
Entender el alcance, fijar la arquitectura y dejar Oracle listo con los datos del core. Aún no se crea ningún objeto `TTEM_*` ni ningún package.

### B. Resumen de requisitos (según el PDF/MD v4)

| Prior. | Ref. | Qué se pide | Tiempo de examen |
|---|---|---|---|
| P0 | A.1 | Tablas `TTEM_CATALOG` y `TTEM_ITEM`, auditoría, constraints (Anexo C), datos iniciales | 15 min |
| P0 | A.2 | `PKG_TTEM_CATALOG` (spec + body) con Object Type y colección; **debe compilar antes del min 25** | 25 min |
| P0 | A.3 | Validaciones y excepciones propias (-20000 a -20999); prohibido `WHEN OTHERS THEN NULL` | 15 min |
| P0 | A.4 | Procedimiento JSON por `ItemId` → `CLOB` OUT con `JSON_OBJECT` | 15 min |
| P0 | B | Consulta de cliente por cuenta (1 fila por cuenta, `LISTAGG`, `CASE`, `TRIM`) | 15 min |
| P1 | C | Transferencia con atomicidad y falla simulada | 30 min |
| P1 | D | Propuesta de mejora (máx. 20 líneas, sin código) | 10 min |
| P2 | A.5 | Carga masiva `BULK COLLECT` + `FORALL SAVE EXCEPTIONS` (resultado: 5 cargados / 7 rechazados) | 15 min |
| — | Docs | README, AI-LOG, STATUS, `connection.env.example` | 25 min |

### C. Dependencias entre objetos

```
CORE_CUSTOMER ──< CORE_ACCOUNT ──< CORE_TRX      (core: NO se modifica)
      └──────────< OLB_USER                      SEQ_CORE_TRX (inicia en 1000)
TTEM_ITEM_STG  (staging, solo para A.5)

TTEM_CATALOG ──< TTEM_ITEM            (nuevo, A.1)
SEQ_TTEM_CATALOG, SEQ_TTEM_ITEM       (nuevo, A.1)
TYP_TTEM_ITEM → TYP_TTEM_ITEM_TAB → PKG_TTEM_CATALOG   (A.2–A.4)
CORE_ACCOUNT + CORE_TRX → PKG_CORE_SETTLEMENT          (C)
TTEM_CATALOG + TTEM_ITEM + TTEM_ITEM_STG → carga A.5   (opcional)
```

Orden de creación: core (Anexo B) → tablas TTEM → tipos → packages → pruebas.

### D. Arquitectura propuesta y estructura de carpetas

```
CoreTest/
├── setup/     00_setup_usuario.sql, 01_core_ddl.sql, 02_core_datos.sql   (Anexo B, sin modificar)
├── ddl/       tablas TTEM_*, constraints, secuencias, tipos, datos iniciales
├── plsql/     PKG_TTEM_CATALOG, PKG_CORE_SETTLEMENT (spec y body)
├── scripts/   consulta de la Sección B y casos de prueba
├── README.md · AI-LOG.md · STATUS.md · connection.env.example · .gitignore
```

Las carpetas `setup/ ddl/ plsql/ scripts/` ya están creadas y los tres scripts del Anexo B ya están en `setup/` (extraídos del documento; no los edites).

### E. Decisiones técnicas que habrá que justificar (se resolverán en su fase)

| Decisión | Fase | Inclinación inicial |
|---|---|---|
| Auditoría: API PL/SQL vs triggers | A.1 | Trigger `TRG_*_AUD` (no se puede saltar) — lo confirmamos contigo |
| Eliminación lógica vs física | A.2 | Lógica (estado `I`) para conservar trazabilidad |
| Rango de códigos de error | A.3 | -20100 a -20199 catálogos, -20200 a -20299 transferencias |
| Quién hace `COMMIT` en la transferencia | C | El invocador; el procedimiento solo usa `SAVEPOINT` |
| Cuenta inexistente en consulta B | B | Cero filas (documentado en README) |
| Orden de bloqueo `FOR UPDATE` | C | Por número de cuenta ascendente |

### F. Pruebas de aceptación (resumen)
- Cantidades iniciales: `CORE_CUSTOMER` 6, `CORE_ACCOUNT` 9, `OLB_USER` 4, `CORE_TRX` 11, `TTEM_ITEM_STG` 12.
- 6 casos de transferencia de la Sección C. 5 cuentas de la Sección B. Lote A.5: 5 cargados / 7 rechazados.

---

## PASOS DE PREPARACIÓN DEL ENTORNO

| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| 0.1 | 5 min | | Leer secciones B–F de este archivo |
| 0.2 | 5 min | | Verificar requisitos previos (paso 0.2 abajo) |
| 0.3 | 10 min* | | Levantar Oracle en Docker |
| 0.4 | 3 min | | Crear usuario `CORE_DEV` |
| 0.5 | 5 min | | Crear tablas del core |
| 0.6 | 3 min | | Cargar datos del core |
| 0.7 | 5 min | | Configurar la conexión en DBeaver |
| 0.8 | 3 min | | Verificar cantidades |
| 0.9 | 5 min | | Preparar Git |

\* la primera descarga de la imagen y el arranque pueden tardar más.

### Paso 0.2 — Requisitos previos (5 min)
Ejecuta en PowerShell y anota los resultados:
```powershell
docker --version
git --version
```
Si ya tienes Oracle instalado de forma nativa (sin Docker), **dímelo** y ajustamos los pasos 0.3–0.4.

### Paso 0.3 — Levantar Oracle 23ai Free (10 min)
Sustituye `<clave_admin>` por una contraseña tuya (no la escribas en ningún archivo del repo):
```powershell
docker run -d --name oracle-core -p 1521:1521 -e ORACLE_PASSWORD=<clave_admin> gvenzl/oracle-free:23.9
docker logs -f oracle-core
```
Espera hasta ver `DATABASE IS READY TO USE!` y sal con `Ctrl+C`.
Usa exactamente la etiqueta `23.9` (no `latest`).

### Paso 0.4 — Crear el usuario CORE_DEV (3 min)
El script usa `ACCEPT ... HIDE`, que DBeaver no interpreta; por eso se ejecuta con SQL*Plus dentro del contenedor:
```powershell
docker cp setup/00_setup_usuario.sql oracle-core:/tmp/
docker exec -it oracle-core sqlplus system@//localhost:1521/FREEPDB1
```
En el prompt de SQL*Plus (te pedirá la clave de `SYSTEM`):
```
@/tmp/00_setup_usuario.sql
EXIT
```
Te pedirá la contraseña de `CORE_DEV` (elige una y guárdala). Resultado esperado: `Usuario CORE_DEV creado correctamente.`

### Paso 0.5 y 0.6 — Tablas y datos del core (8 min)
Opción recomendada (evita diferencias de cliente): SQL*Plus en el contenedor, ya como `CORE_DEV`.
```powershell
docker cp setup/01_core_ddl.sql oracle-core:/tmp/
docker cp setup/02_core_datos.sql oracle-core:/tmp/
docker exec -it oracle-core sqlplus core_dev@//localhost:1521/FREEPDB1
```
```
@/tmp/01_core_ddl.sql
@/tmp/02_core_datos.sql
EXIT
```
Resultado esperado: `Modelo del core creado correctamente.` y la tabla de verificación del paso 0.8.

### Paso 0.7 — Conexión en DBeaver (5 min)
1. *Nueva conexión* → **Oracle**.
2. Host `localhost` · Puerto `1521` · **Service name** `FREEPDB1` (no SID).
3. Usuario `CORE_DEV` · la contraseña del paso 0.4.
4. Descarga el driver si DBeaver lo pide → *Test Connection*.

Notas para DBeaver durante todo el proyecto:
- **Alt+X** ejecuta el archivo como script (usa esto para DDL y packages). **Ctrl+Enter** solo ejecuta una sentencia.
- Los packages terminan con `/` en línea aparte; en script mode DBeaver los separa correctamente.
- Para ver errores de compilación: `SELECT * FROM user_errors WHERE name = '...' ORDER BY sequence;`
- Activa *Auto-commit* o haz commit manual según te indique cada etapa (en la Fase C será importante).

### Paso 0.8 — Verificar cantidades (3 min)
En DBeaver, conectado como `CORE_DEV`:
```sql
SELECT 'CORE_CUSTOMER (6)' AS tabla, COUNT(*) AS filas FROM core_customer
UNION ALL SELECT 'CORE_ACCOUNT (9)',   COUNT(*) FROM core_account
UNION ALL SELECT 'OLB_USER (4)',       COUNT(*) FROM olb_user
UNION ALL SELECT 'CORE_TRX (11)',      COUNT(*) FROM core_trx
UNION ALL SELECT 'TTEM_ITEM_STG (12)', COUNT(*) FROM ttem_item_stg;
```
Y confirma la versión:
```sql
SELECT banner_full FROM v$version;
```

### Paso 0.9 — Preparar Git (5 min)
```powershell
cd C:\Users\BSGA\Desktop\CoreTest
git init
git config user.name "<tu nombre>"
git config user.email "<tu correo>"
```
Todavía **no** hagas commit: lo recomendaré al cerrar la fase.

### Diagnóstico
| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `docker: command not found` | Docker Desktop no instalado/iniciado | Instalar/iniciar; en Windows requiere WSL 2 |
| Puerto 1521 ocupado | Otro Oracle o contenedor previo | `docker ps -a`; cambia a `-p 1522:1521` y usa ese puerto en DBeaver |
| `ORA-12514` | Service name incorrecto | Usa `FREEPDB1`, no SID |
| `ORA-01017` | Clave errónea | Revisa mayúsculas/minúsculas de la clave |
| `ORA-00955` al ejecutar 01 | El script ya se ejecutó | Avísame; no ejecutes DROP sin consultarme |
| `ORA-00001` al ejecutar 02 | Datos ya cargados | Avísame y revisamos el estado |

### I. Lista de verificación de la Fase 0
- [x] Contenedor `oracle-core` en ejecución
- [ ] Conexión DBeaver como `CORE_DEV` exitosa
- [x] Cantidades 6 / 9 / 4 / 11 / 12
- [x] Repositorio Git inicializado
- [ ] Decisiones de la tabla E revisadas (opinas o las apruebas)

### Commit recomendado (cuando confirmes todo)
`Inicio del examen: scripts del core (Anexo B) y estructura de carpetas`

### J. Qué debes enviarme para continuar
1. Salida de `docker --version`, `git --version` y el resultado de `SELECT banner_full FROM v$version;`
2. La tabla de cantidades del paso 0.8.
3. Cualquier error (texto completo).
4. Tu opinión sobre las decisiones de la sección E (si no, las doy por aprobadas).

Cuando lo tenga, escribiré aquí la **FASE A.1 — Modelo de catálogos**.

---

## FASE A.1 — Modelo de catálogos (P0 · 15 min de examen)

### A. Objetivo
Crear `TTEM_CATALOG` y `TTEM_ITEM` con constraints nombrados (Anexo C), auditoría y los datos iniciales obligatorios.

### B. Decisiones de diseño
| Tema | Decisión | Por qué |
|---|---|---|
| Auditoría | **Trigger** `TRG_TTEM_*_AUD` (BEFORE INSERT OR UPDATE) | La API PL/SQL puede saltarse con un `UPDATE` directo (p. ej. un script manual en producción, el problema de la Sección D). El trigger lo cubre siempre y además impide alterar `created_*`. Limitación: sin bitácora de valores anteriores; `TTEM_AUDIT_LOG` (opcional) queda para más adelante. |
| Auditoría obligatoria | `created_by/at` y `updated_by/at` son NOT NULL; en el alta `updated_* = created_*` | Siempre se sabe quién y cuándo tocó cada fila. |
| IDs | Secuencias `SEQ_TTEM_CATALOG` y `SEQ_TTEM_ITEM`, asignadas por la API/inserts (no por trigger) | Explícito y fácil de explicar. |
| Códigos | CHECK `codigo = UPPER(TRIM(codigo))` | La BD rechaza códigos sin normalizar; coherente con A.5. |
| Vigencia | `CK_TTEM_ITEM_VALID_TO`: `valid_to IS NULL OR valid_to >= valid_from`; `valid_from` NOT NULL | Regla pedida por el enunciado. **`valid_from` obligatorio es decisión mía** (el enunciado no lo precisa). |
| Índice FK | No se crea `IX_TTEM_ITEM_CATALOG_ID` | `UK_TTEM_ITEM_CATALOG_CODE (catalog_id, item_code)` ya lo cubre como prefijo. |
| Valor de `COM_MANT` | `'12.50'` | **Supuesto mío**: el enunciado no da valor; tomé 12.50 de las comisiones en `CORE_TRX` (REF-0006/0010). Dime si prefieres NULL. |
| Nombres de ítems | PEN "Sol peruano", USD "Dolar estadounidense" (ejemplo del enunciado) | Sin tildes, como el resto de datos. |

### C. Archivos (todos creados)
| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `ddl/01_ttem_tablas.sql` | Secuencias, tablas, PK/FK/UK/CK |
| 2 | `ddl/02_ttem_triggers.sql` | Triggers de auditoría |
| 3 | `ddl/03_ttem_datos_iniciales.sql` | MONEDA (PEN, USD) y TIPO_COMISION (COM_MANT) |
| 4 | `scripts/test_a1_integridad.sql` | 10 pruebas de integridad (termina con ROLLBACK) |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| A1.1 | 2 min | | Revisar los 4 archivos y entender cada constraint |
| A1.2 | 3 min | | DBeaver (`CORE_DEV`): abrir `ddl/01_ttem_tablas.sql` y ejecutar con **Alt+X** |
| A1.3 | 2 min | | Ejecutar `ddl/02_ttem_triggers.sql` (Alt+X) |
| A1.4 | 2 min | | Ejecutar `ddl/03_ttem_datos_iniciales.sql` (Alt+X) |
| A1.5 | 4 min | | Ejecutar `scripts/test_a1_integridad.sql` (Alt+X) y abrir el panel *Output* |
| A1.6 | 2 min | | Verificar con las consultas de abajo |

> **Importante:** ya ejecuté estos scripts en tu contenedor con SQL*Plus (resultados abajo). Si los corres de nuevo en DBeaver dará `ORA-00955` en el paso A1.2. En ese caso **no repitas A1.2–A1.4**: ve directo a A1.5 y A1.6 desde DBeaver, que solo leen o hacen rollback.

### Resultados obtenidos (SQL*Plus, Oracle 23.9)
- 2 secuencias, 2 tablas y 2 triggers (VALID) creados sin errores.
- Datos: `MONEDA` (id 1) con PEN (item 1) y USD (item 2); `TIPO_COMISION` (id 2) con COM_MANT (item 3). `created_by = CORE_DEV`.
- Pruebas T1–T10 **OK**; conteo posterior: 2 catálogos, 3 ítems.

### Consultas de verificación (DBeaver)
```sql
SELECT c.catalog_code, i.item_id, i.item_code, i.item_name, i.item_value, i.status,
       i.valid_from, i.valid_to, i.created_by, i.updated_by
  FROM ttem_catalog c JOIN ttem_item i ON i.catalog_id = c.catalog_id
 ORDER BY c.catalog_id, i.display_order;

SELECT table_name, constraint_name, constraint_type FROM user_constraints
 WHERE table_name LIKE 'TTEM_C%' OR table_name = 'TTEM_ITEM' ORDER BY table_name, constraint_type;
```
Esperado: 3 filas de datos; PK/UK/CK/FK con los nombres del Anexo C (se ignoran las de `TTEM_ITEM_STG`).

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `ORA-00955` | Objeto ya creado | No recrear; verifica con `user_objects` |
| `ORA-02291` al cargar datos | Catálogo no insertado | Ejecuta el script 03 completo, no por partes |
| Triggers con errores | Bloque partido por DBeaver | Alt+X (script), no Ctrl+Enter; `SELECT * FROM user_errors` |
| No se ve `OK T1...` | Panel Output cerrado | *Ver → Output* (Ctrl+Shift+O) |

### I. Lista de verificación
- [ ] Decisiones de la sección B aprobadas (sobre todo `COM_MANT = '12.50'` y `valid_from` obligatorio)
- [ ] Consulta de verificación muestra 3 ítems
- [ ] T1–T10 muestran OK en tu DBeaver
- [ ] Puedes explicar cada constraint

### Git y documentación
Commit sugerido (1): `Inicio del examen: scripts del core (Anexo B) y estructura de carpetas`
Commit sugerido (2): `A.1: tablas TTEM_CATALOG y TTEM_ITEM con auditoría por trigger y datos iniciales`
Pendiente para AI-LOG: decisión auditoría por trigger; incidencia de líneas en blanco al extraer los scripts del Anexo B.

### J. Qué debes enviarme
1. Resultado de la primera consulta de verificación.
2. Las líneas `OK/FALLA` de las pruebas T1–T10 ejecutadas en DBeaver.
3. Tu aprobación (o cambios) de la sección B.

Luego escribiré la **FASE A.2 — Object Types y package**.

---

## NOTA DE ESTRUCTURA Y DBEAVER (actualizada)
- **Raíz de trabajo del repositorio:** `oraclecore-BrianGallardo/`. Todas las rutas `ddl/`, `plsql/`, `scripts/`, `setup/` son relativas a esa carpeta. `instrucciones.md`, `context.md` y el enunciado quedan fuera del repo.
- **Corrección A.1:** DBeaver enviaba `SET SERVEROUTPUT ON` y `SET DEFINE OFF` a Oracle y fallaba con `ORA-00922`. Los quité (y los `PROMPT`) de `ddl/*.sql` y `scripts/test_a1_integridad.sql`; DBeaver muestra DBMS_OUTPUT en el panel *Output* sin necesidad de `SET`. Prueba repetida en SQL*Plus: T1–T10 OK. **Pendiente de confirmar en tu DBeaver.**
- Los scripts de `setup/` conservan sus `SET`/`PROMPT` (son originales y se ejecutan con SQL*Plus).
- Desde ahora, ningún script mío usará comandos exclusivos de SQL*Plus.

---

## FASE A.1 — CERRADA
Validada en DBeaver: T1–T10 OK, conteo 2 catálogos / 3 ítems tras el ROLLBACK. Se quitó la línea `/` del script de pruebas (ORA-00900 en DBeaver). **Commit pendiente de A.1** (ver abajo).

---

## FASE A.2 — Object Types y package (P0 · 25 min de examen)

### A. Objetivo
Crear `TYP_TTEM_ITEM` / `TYP_TTEM_ITEM_TAB` y `PKG_TTEM_CATALOG` (spec + body) con insertar, actualizar, eliminar y listar. **Regla clave del examen:** el esqueleto debe compilar desde temprano; yo ya lo compilé primero con cuerpos que solo lanzan `-20999 no implementado` y después implementé las operaciones.

### B. Decisiones de diseño
| Tema | Decisión | Por qué |
|---|---|---|
| Object Type | `TYP_TTEM_ITEM` con 9 atributos (los de `TTEM_ITEM` sin auditoría) | La auditoría la pone el trigger; la API no debe aceptarla del llamador. |
| Colección | `TYP_TTEM_ITEM_TAB` como **retorno** de `listar_items` | Cumple "usar el tipo en la API". El tipo de objeto es además **entrada** de insertar/actualizar. |
| Eliminación | **Lógica** (`status = 'I'`) | Conserva trazabilidad y no rompe referencias futuras; es reversible (se reactiva con `actualizar_item`). Implicación: los items inactivos siguen ocupando su código (no se puede reinsertar el mismo). |
| Transacción | El package **no hace COMMIT ni ROLLBACK** | Lo controla el invocador (se mantiene para la Sección C). |
| Normalización | `UPPER(TRIM(codigo))` y `TRIM(nombre)` al insertar | Coherente con los CHECK de A.1 y con A.5. |
| Actualizar | No cambia catálogo ni código; `NULL` en orden/estado/valid_from = "no cambiar"; `valid_to` se asigna tal cual (permite quitarlo) | Evita que un campo vacío borre datos obligatorios. |
| Operaciones de catálogo | **No** las incluyo | Los catálogos iniciales van por DDL; no son requisito. Se pueden añadir si las pides. |
| Errores | Por ahora se propagan los de integridad (ORA-00001, etc.); si el id no existe, `NO_DATA_FOUND` **provisional** | A.3 los reemplaza por excepciones propias con código. |

### C. Archivos (creados en `oraclecore-BrianGallardo/`)
| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `ddl/04_ttem_tipos.sql` | Los 2 tipos |
| 2 | `plsql/pkg_ttem_catalog.pks` | Especificación |
| 3 | `plsql/pkg_ttem_catalog.pkb` | Cuerpo |
| 4 | `scripts/test_a2_package.sql` | 5 pruebas (ROLLBACK al final) |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| A2.1 | 3 min | | Leer el spec y entender cada firma |
| A2.2 | 2 min | | DBeaver (`CORE_DEV`): ejecutar `ddl/04_ttem_tipos.sql` con **Alt+X** |
| A2.3 | 2 min | | Ejecutar `plsql/pkg_ttem_catalog.pks` (Alt+X) |
| A2.4 | 2 min | | Ejecutar `plsql/pkg_ttem_catalog.pkb` (Alt+X) |
| A2.5 | 2 min | | Comprobar compilación (consulta 1) |
| A2.6 | 4 min | | Ejecutar `scripts/test_a2_package.sql` (Alt+X) y abrir el panel *Salida* |
| A2.7 | 2 min | | Comprobar que no quedaron datos (consulta 2) |

> Ya ejecuté estos archivos en tu contenedor con SQL*Plus. Son `CREATE OR REPLACE`: puedes volver a correrlos sin problema.

### Consultas de verificación
```sql
-- 1) Esperado: 4 filas VALID y 0 errores
SELECT object_name, object_type, status FROM user_objects
 WHERE object_name IN ('TYP_TTEM_ITEM','TYP_TTEM_ITEM_TAB','PKG_TTEM_CATALOG') ORDER BY 1,2;
SELECT * FROM user_errors;
-- 2) Esperado: 3
SELECT COUNT(*) FROM ttem_item;
-- 3) Uso de la función con la colección
SELECT * FROM TABLE(pkg_ttem_catalog.listar_items(1));
```

### Resultados obtenidos (SQL*Plus, Oracle 23.9)
- Esqueleto: tipos y package compilaron, 0 errores.
- Cuerpo completo: compila, `PACKAGE` y `PACKAGE BODY` VALID, 0 errores.
- Pruebas P1–P5 **OK**; conteo posterior 3.
- Observación: `item_id = 34` en P1. Las secuencias **no se revierten** con ROLLBACK (y `NOCACHE` no evita huecos), por eso los ids no son consecutivos. Los ids reales serán distintos en cada entorno; no dependas de números fijos.

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `PLS-00201` / `ORA-04043` | Orden de ejecución incorrecto | Tipos → spec → body |
| `ORA-02303` al recrear tipos | Tipos con dependientes | No uses `DROP TYPE`; `CREATE OR REPLACE` basta mientras no cambien atributos |
| Package "con errores de compilación" | Body ejecutado antes del spec | `SELECT * FROM user_errors WHERE name='PKG_TTEM_CATALOG'` |
| `ORA-00900` en DBeaver | `/` tras el bloque anónimo de pruebas | Ese script no la lleva; los CREATE de tipos/package sí |

### I. Lista de verificación
- [ ] Consulta 1: 4 objetos VALID y 0 errores
- [ ] P1–P5 con OK en tu DBeaver
- [ ] `SELECT * FROM TABLE(pkg_ttem_catalog.listar_items(1))` devuelve PEN y USD
- [ ] Puedes explicar por qué la eliminación es lógica y por qué no hay COMMIT en el package

### Git y documentación
Commit 1 (A.1): `A.1: tablas TTEM_CATALOG y TTEM_ITEM con auditoría por trigger y datos iniciales`
Commit 2 (A.2): `A.2: Object Types y PKG_TTEM_CATALOG con insertar, actualizar, eliminar lógico y listar`
Para AI-LOG: orden esqueleto→implementación; eliminación lógica; el error de `/` y `SET` en DBeaver (corrección de código generado por IA).

### J. Qué debes enviarme
1. Resultado de la consulta 1 y de la consulta 3.
2. Las líneas OK/FALLA de P1–P5 en tu DBeaver.
3. Tu aprobación (o cambios) de la sección B.

Luego escribiré la **FASE A.3 — Validaciones y excepciones propias**.

---

## FASE A.2 — CERRADA
Validada en DBeaver: objetos VALID, 0 errores, P1–P5 OK, conteo 3. Commits hechos: `c91c2cc` (A.1) y `d2f02c8` (A.2).

---

## FASE A.3 — Validaciones y excepciones propias (P0 · 15 min de examen)

### A. Objetivo
Reemplazar los errores de integridad "crudos" por excepciones de negocio con código propio, y documentar la tabla de códigos. **Se modifican** `plsql/pkg_ttem_catalog.pks` y `.pkb`, y se **actualiza** la prueba P5 de A.2 (ahora el duplicado sale como -20102 en lugar de ORA-00001).

### B. Tabla de códigos de error
| Código | Excepción | Significado | Lo generan |
|---|---|---|---|
| -20100 | `e_catalogo_no_existe` | El catálogo no existe | insertar_item, listar_items |
| -20101 | `e_item_no_existe` | El ítem no existe | actualizar_item, eliminar_item |
| -20102 | `e_item_duplicado` | El código ya existe en ese catálogo | insertar_item |
| -20103 | `e_nombre_obligatorio` | Nombre nulo o solo espacios | insertar_item, actualizar_item |
| -20104 | `e_codigo_obligatorio` | Código nulo o solo espacios | insertar_item |
| -20105 | `e_vigencia_invalida` | Falta "desde" (al insertar) o "hasta" < "desde" | insertar_item, actualizar_item |
| -20106 | `e_estado_invalido` | Estado distinto de A / I | insertar_item, actualizar_item |
| -20900 | `e_error_tecnico` | Error inesperado envuelto, con el original (`SQLERRM`) en el mensaje | insertar_item, actualizar_item, eliminar_item |

Rango elegido: **-20100 a -20199** negocio del catálogo, **-20900** técnico. Se reserva -20200 a -20299 para las transferencias (Fase C).

### C. Decisiones de diseño
| Tema | Decisión | Por qué |
|---|---|---|
| Negocio vs técnico | Los de negocio salen con su código; todo lo demás se envuelve en -20900 con `RAISE_APPLICATION_ERROR(..., TRUE)` | Quien llama distingue "dato mal enviado" de "falla del sistema" y no se pierde el error Oracle original. |
| `WHEN OTHERS` | Solo en las 3 operaciones de escritura, y **siempre** hace `ROLLBACK TO` y relanza | Cumple la regla del enunciado (nunca oculta el error). |
| Duplicados | Se captura `DUP_VAL_ON_INDEX` de la UK y se traduce; **no** hay consulta previa | La UK es la única garantía correcta ante concurrencia (un `SELECT` previo tiene condición de carrera). |
| Savepoint | Cada operación abre su `SAVEPOINT`; el rollback llega solo hasta ahí | No revierte el trabajo previo del invocador (probado en V14). **Implicación:** el package nunca confirma; el invocador decide `COMMIT`/`ROLLBACK`. |
| Bloqueo | `actualizar_item` y `eliminar_item` hacen `SELECT ... FOR UPDATE` de la fila | Validan sobre datos estables y evitan actualizaciones perdidas. |
| Vigencia al actualizar | Se valida con el "desde" efectivo (el enviado o el actual) | Evita que un "hasta" nuevo contradiga el "desde" guardado. |
| Catálogo inactivo | **No** bloquea insertar ítems | El enunciado no lo pide. Dime si lo quieres como regla. |
| Prueba del -20900 | Script aparte que agota `SEQ_TTEM_ITEM` y la restaura | Con el Object Type ninguna entrada válida provoca un error técnico (primer intento con valor de 250 caracteres falló al construir el objeto: error mío en la prueba). |

### D. Archivos
| Archivo | Acción |
|---|---|
| `plsql/pkg_ttem_catalog.pks` | Modificado (excepciones, constantes y tabla de códigos) |
| `plsql/pkg_ttem_catalog.pkb` | Modificado (validaciones y manejo de errores) |
| `scripts/test_a2_package.sql` | Modificado (P5) |
| `scripts/test_a3_validaciones.sql` | Nuevo: V1–V12, V14, V15 |
| `scripts/test_a3_error_tecnico.sql` | Nuevo: error técnico |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| A3.1 | 3 min | | Leer la tabla de códigos y el body modificado |
| A3.2 | 2 min | | DBeaver: ejecutar `plsql/pkg_ttem_catalog.pks` (Alt+X) |
| A3.3 | 2 min | | Ejecutar `plsql/pkg_ttem_catalog.pkb` (Alt+X) |
| A3.4 | 1 min | | `SELECT * FROM user_errors;` → 0 filas |
| A3.5 | 2 min | | Ejecutar `scripts/test_a2_package.sql` (P5 debe dar OK con ORA-20102) |
| A3.6 | 4 min | | Ejecutar `scripts/test_a3_validaciones.sql` (panel Salida) |
| A3.7 | 3 min | | Ejecutar `scripts/test_a3_error_tecnico.sql` y confirmar que `max_value` queda en 1E+28 |

> Ya ejecuté todo esto en tu contenedor con SQL*Plus. Los CREATE son re-ejecutables.
> **Aviso:** `test_a3_error_tecnico.sql` hace `ALTER SEQUENCE` (commit implícito). Ejecútalo sin trabajo pendiente.

### Resultados obtenidos (SQL*Plus, Oracle 23.9)
- Spec y body compilan: VALID, 0 errores.
- A.2 P1–P5 OK (P5 ahora ORA-20102).
- A.3 V1–V12, V14, V15 OK; T-TEC OK; secuencia restaurada; conteo final 3.

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `PLS-00302` / `PLS-00201` al correr pruebas | Spec antiguo | Recompilar el `.pks` antes del `.pkb` |
| P5 sale `FALLA` o `ORA-00001` | Body antiguo en la BD | Re-ejecutar el `.pkb` |
| Error técnico `ORA-08004` persiste en inserts | Quedó la secuencia con MAXVALUE bajo | `ALTER SEQUENCE seq_ttem_item NOMAXVALUE;` |
| `ORA-04061` / objeto inválido tras recompilar | Sesión DBeaver con estado antiguo del package | Desconectar y reconectar |

### I. Lista de verificación
- [ ] `user_errors` vacío
- [ ] P5 OK con ORA-20102
- [ ] V1–V12, V14, V15 OK en tu DBeaver
- [ ] T-TEC OK y `max_value` = 1.0000E+28
- [ ] Puedes explicar por qué el `WHEN OTHERS` es válido aquí (rollback + relanza) y por qué no hay consulta previa de duplicados

### Git y documentación
Commit sugerido: `A.3: excepciones propias (-20100..-20106, -20900), validaciones y manejo transaccional con savepoint`
Para AI-LOG: prueba V13 original incorrecta (valor de 250 caracteres no cabe en el Object Type), corregida con prueba de falla de entorno; decisión de no hacer SELECT previo para duplicados.

### J. Qué debes enviarme
1. Las líneas OK/FALLA de A3.5, A3.6 y A3.7 en tu DBeaver.
2. Tu aprobación (o cambios) de la sección C, sobre todo "catálogo inactivo no bloquea".

Luego escribiré la **FASE A.4 — Consulta JSON por ItemId**.

---

### A.3 — Ajuste aprobado: regla de catálogo inactivo
- **Decisión:** un catálogo con `status = 'I'` **no admite ítems nuevos**. Aplica solo a `insertar_item`; `listar_items`, `actualizar_item` y `eliminar_item` siguen funcionando.
- **Nuevo código:** `-20107` / `e_catalogo_inactivo` (constante `c_err_catalogo_inactivo`). Si el catálogo no existe sigue siendo `-20100`.
- **Archivos tocados:** `plsql/pkg_ttem_catalog.pks`, `plsql/pkg_ttem_catalog.pkb` (procedimiento privado `validar_catalogo_activo`), `scripts/test_a3_validaciones.sql` (pruebas V16 y V17).
- **Verificado en SQL*Plus:** V1–V12, V14–V17 OK; P1–P5 OK; catálogos siguen activos; 3 ítems.
- **Qué debes hacer:** volver a ejecutar en DBeaver (Alt+X) el `.pks`, el `.pkb` y `scripts/test_a3_validaciones.sql`, y confirmar en el panel *Salida* V16 y V17 con OK.
- Tus capturas de A.3 mostraron conteo 3 y la secuencia restaurada (`max_value` = 9.999…), pero no el panel *Salida*; por eso las líneas OK de V1–V15 están verificadas por mí en SQL*Plus, no vistas aún en tu DBeaver.

### Fase A.3 — CERRADA (commit hecho)
Siguiente: **FASE A.4 — Consulta JSON por ItemId**.

---

## FASE A.3 — CERRADA
Validada en DBeaver: V1–V12 y V14–V17 OK con ROLLBACK, conteo 3. Commit `048ec4d`.

---

## FASE A.4 — Consulta JSON por ItemId (P0 · 15 min de examen)

### A. Objetivo
`PKG_TTEM_CATALOG.obtener_item_json(p_item_id IN, p_json OUT CLOB)` devuelve el ítem como JSON con funciones nativas de Oracle. Se **modifican** `plsql/pkg_ttem_catalog.pks` y `.pkb` y se crea `scripts/test_a4_json.sql`.

### B. Decisiones técnicas
| Tema | Decisión | Por qué |
|---|---|---|
| Construcción | `JSON_OBJECT(... NULL ON NULL RETURNING CLOB)` | Función nativa; escapa comillas y barras por sí sola (probado en J5). Sin concatenar texto. |
| Nulos | `NULL ON NULL` | La clave se mantiene y el valor sale como `null` JSON (J3, J4). |
| Fechas | `TO_CHAR(fecha, 'YYYY-MM-DD')` | El contrato pide texto con ese formato. |
| Ítem inexistente | Reutiliza `-20101 e_item_no_existe` | Ya documentado en A.3; no se devuelve JSON vacío ni CLOB nulo. |
| Errores técnicos | Sin `WHEN OTHERS` | Es solo lectura: no hay savepoint que deshacer, y el error original se propaga intacto. |
| Ubicación | Dentro de `PKG_TTEM_CATALOG` | Es parte de la API del catálogo. |
| Compatibilidad | `JSON_OBJECT ... RETURNING CLOB` y `IS JSON` verificados en **23.9** | Funcionan desde 12.2 / 18c; no usa nada exclusivo de 23ai (no uso JSON_SERIALIZE ni el tipo JSON). |

### C. Archivos
| Archivo | Acción |
|---|---|
| `plsql/pkg_ttem_catalog.pks` | Modificado: firma de `obtener_item_json` y tabla de códigos |
| `plsql/pkg_ttem_catalog.pkb` | Modificado: implementación |
| `scripts/test_a4_json.sql` | Nuevo: J1–J6 |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| A4.1 | 2 min | | Leer la firma y la consulta JSON |
| A4.2 | 2 min | | DBeaver: ejecutar `plsql/pkg_ttem_catalog.pks` (Alt+X) |
| A4.3 | 2 min | | Ejecutar `plsql/pkg_ttem_catalog.pkb` (Alt+X) |
| A4.4 | 1 min | | `SELECT * FROM user_errors;` → 0 filas |
| A4.5 | 4 min | | Ejecutar `scripts/test_a4_json.sql` (Alt+X) y revisar el panel *Salida* |
| A4.6 | 3 min | | Bloques de ejemplo (abajo): ítem existente e inexistente |

### Bloques de ejemplo (A4.6)
```sql
-- Item existente: cambia 2 por el item_id de USD en tu BD (SELECT item_id FROM ttem_item WHERE item_code='USD')
DECLARE
  l_json CLOB;
BEGIN
  pkg_ttem_catalog.obtener_item_json(2, l_json);
  DBMS_OUTPUT.PUT_LINE(l_json);
END;
```
```sql
-- Item inexistente: debe fallar con ORA-20101
DECLARE
  l_json CLOB;
BEGIN
  pkg_ttem_catalog.obtener_item_json(-999, l_json);
  DBMS_OUTPUT.PUT_LINE(l_json);
END;
```
Para ejecutar cada bloque por separado en DBeaver, selecciónalo y usa **Ctrl+Enter**.

### Resultado obtenido (SQL*Plus, Oracle 23.9)
- Compila: 0 errores.
- Salida real para USD: `{"itemId":2,"catalogId":1,"catalogCode":"MONEDA","itemCode":"USD","name":"Dolar estadounidense","value":"USD","status":"A","validFrom":"2026-01-01","validTo":null}` (idéntica al ejemplo del enunciado).
- J1–J6 **OK**; no quedan datos (ROLLBACK).
- Error mío corregido: en J6 el `OUT` conservaba el JSON anterior porque Oracle no copia parámetros `OUT` cuando hay excepción; la prueba ahora lo pone en nulo antes de llamar. Implicación para quien consuma el procedimiento: ante `ORA-20101` no debe leer `p_json`.

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `PLS-00302: obtener_item_json must be declared` | Spec antiguo en la BD | Ejecutar primero el `.pks` |
| `ORA-40478` / `ORA-00907` en JSON_OBJECT | Versión sin soporte o sintaxis | Confirma `SELECT banner_full FROM v$version` (debe ser 23ai/21c) |
| `ORA-20101` en el ejemplo | El id no existe | Consulta el `item_id` real; los ids no son consecutivos |

### I. Lista de verificación
- [ ] `user_errors` vacío
- [ ] J1–J6 OK en tu DBeaver
- [ ] El JSON de USD tiene las 9 claves y `"validTo":null`
- [ ] Ítem inexistente → `ORA-20101`
- [ ] Puedes explicar `NULL ON NULL` y por qué no se concatena texto

### Git y documentación
Commit sugerido: `A.4: obtener_item_json con JSON_OBJECT (nulos como null, fechas YYYY-MM-DD)`
README: añadir el ejemplo de salida JSON y que `ORA-20101` indica ítem inexistente.

### J. Qué debes enviarme
1. Líneas OK/FALLA de J1–J6 (y el `JSON:` impreso) en tu DBeaver.
2. Confirmación de que los bloques de ejemplo funcionan.

Luego escribiré la **FASE B — Consulta de cliente por cuenta**.

---

## FASE A.4 — CERRADA
Validada en DBeaver: J1–J6 OK con el JSON impreso, tras activar la salida del servidor. Commit `6c96337`.

---

## FASE B — Consulta de cliente por cuenta (P0 · 15 min de examen)

### A. Objetivo
Una consulta SQL con bind variable `:account_no` que devuelve **una fila por cuenta** con datos de cuenta, cliente, fecha de referencia y usuarios de Banca en Línea.

### B. Decisiones de diseño
| Tema | Decisión | Por qué |
|---|---|---|
| Una fila por cuenta | Los usuarios se agregan en un subquery (`GROUP BY customer_id`) y se unen con `LEFT JOIN` | Si unieras `olb_user` directo y agruparas, tendrías que repetir todas las columnas en el `GROUP BY`; así no se multiplican filas. |
| Nombre normalizado | Natural: `INITCAP(TRIM(REGEXP_REPLACE(TRIM(nombres) \|\| ' ' \|\| TRIM(apellidos), '\s+', ' ')))`; Jurídica: razón social con `TRIM` y espacios dobles colapsados, **sin** `INITCAP` | `'  jose luis '` + `'RAMIREZ  TORRES'` → `Jose Luis Ramirez Torres`. La razón social conserva su capitalización (`S.A.C.`, `E.I.R.L.`). Limitación: `INITCAP` pone `De`/`Del` en mayúscula en nombres compuestos. |
| Fecha de referencia | `CASE person_type`: nacimiento (N) o constitución (J); tipo `Nacimiento` / `Constitución` / `No registrada` si es NULL | Cumple el enunciado: fecha vacía y tipo «No registrada». |
| Usuarios | `LISTAGG(username \|\| ' (' \|\| estado \|\| ')', ', ') WITHIN GROUP (ORDER BY username)`; `NULL` si no tiene | El estado se muestra como Activo / Bloqueado / Inactivo. `ON OVERFLOW TRUNCATE` evita `ORA-01489` si la lista supera 4000 caracteres. |
| Estado de cuenta | Código (`account_status`) y descripción (`account_status_desc`) | Útil para ver la cuenta bloqueada de un vistazo. |
| **Cuenta inexistente** | **Devuelve 0 filas, sin error** | Es el comportamiento natural de un `SELECT`; el consumidor decide qué hacer con "sin resultados". Va al README. |
| Usuarios por cliente | Los usuarios son del **cliente**, no de la cuenta: un cliente con 2 cuentas muestra los mismos usuarios en ambas | `OLB_USER` solo se relaciona con `CORE_CUSTOMER`. |
| Tildes | `Jurídica` y `Constitución` con tilde, archivos UTF-8 | El enunciado pide «Jurídica». Si en tu DBeaver se ven mal, avísame y los paso a ASCII. |
| Prueba | Un solo `SELECT` con resultado OK/FALLA en la grilla, sin `DBMS_OUTPUT` | Evita el problema de la salida que tuviste en DBeaver. |

### C. Archivos
| Archivo | Contenido |
|---|---|
| `scripts/consulta_cliente_por_cuenta.sql` | La consulta de la Sección B (bind `:account_no`) |
| `scripts/test_b_cuentas.sql` | Misma consulta con `IN (...)` para las 5 cuentas, comparada con los valores esperados |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| B.1 | 3 min | | Leer la consulta y entender cada `CASE` y el `LISTAGG` |
| B.2 | 3 min | | DBeaver: abrir `scripts/test_b_cuentas.sql` y ejecutar con **Ctrl+Enter** (es una sola sentencia) |
| B.3 | 2 min | | Comprobar que las 5 filas tienen `RESULTADO = OK` |
| B.4 | 4 min | | Abrir `scripts/consulta_cliente_por_cuenta.sql`, ejecutar con Ctrl+Enter; DBeaver pide `account_no`: probar las 5 cuentas una por una |
| B.5 | 3 min | | Comparar con la tabla de resultados esperados |

### Resultados esperados
| Cuenta | Caso | Esperado |
|---|---|---|
| `1910001000011` | Natural con nacimiento | `Maria Fernanda Quispe Rojas`, `1988-04-12`, `Nacimiento`, `mquispe (Activo)` |
| `1910002000017` | Natural sin fecha, sin usuarios, nombre sucio | `Jose Luis Ramirez Torres`, fecha NULL, `No registrada`, usuarios NULL |
| `1910003000013` | Jurídica con 2 usuarios | `Inversiones Andinas S.A.C.`, `2010-08-03`, `Constitución`, `invandinas.admin (Activo), invandinas.tesoreria (Bloqueado)` |
| `1910004000019` | Jurídica sin fecha, cuenta bloqueada | `Comercial Lima Norte E.I.R.L.`, fecha NULL, `No registrada`, estado `B` / `Bloqueada` |
| `9999999999999` | Inexistente | 0 filas |

### Resultado obtenido (SQL*Plus, Oracle 23.9)
- `test_b_cuentas.sql`: las 5 filas con `RESULTADO = OK` (la inexistente con 0 filas).
- Consulta con `1910003000013`: 1 fila, `CTE`, `PEN`, saldo 48900, `Activa`, `Jurídica`, `RUC 20512345671`, usuarios consolidados. Con `9999999999999`: `no rows selected`.

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `ORA-01008: not all variables bound` | No se dio valor a `:account_no` | En DBeaver rellena el diálogo; en SQL*Plus usa `EXEC :account_no := '...'` |
| `ORA-00933` en `ON OVERFLOW` | Versión anterior a 12.2 | Confirmado 23.9; no debería ocurrir |
| `Jurídica` se ve como `JurÃdica` | Codificación del cliente | Abre el archivo como UTF-8 / revisa la codificación del editor |
| Más de una fila por cuenta | Se unió `olb_user` sin agregar | Usa el subquery con `LISTAGG`, como en el archivo |

### I. Lista de verificación
- [ ] `test_b_cuentas.sql`: 5 filas OK en DBeaver
- [ ] La consulta con bind funciona con las 5 cuentas
- [ ] La cuenta inexistente devuelve 0 filas
- [ ] Puedes explicar por qué `INITCAP` solo en personas naturales y por qué `LEFT JOIN` + subquery

### Git y documentación
Commit sugerido: `B: consulta de cliente por cuenta (una fila por cuenta, LISTAGG de usuarios OLB)`
README: documentar «cuenta inexistente → 0 filas» y el ejemplo de salida.

### J. Qué debes enviarme
1. La grilla de `test_b_cuentas.sql` en tu DBeaver (con la columna `RESULTADO`).
2. El resultado de una cuenta con la consulta con bind (por ejemplo `1910003000013`).
3. Cómo se ven `Jurídica` y `Constitución` en tu DBeaver.

Luego escribiré la **FASE C — Transferencia bancaria**.

---

## FASE B — CERRADA
Validada en DBeaver: `test_b_cuentas.sql` con las 5 filas `RESULTADO = OK` (y `Constitución` con tilde bien codificada). Commit `b75dc94`. Documentación (README, STATUS, AI-LOG, `connection.env.example`) en el commit `5ee01ff`. Nota: el repositorio ahora tiene ramas (`develop`, `feature/changes`); el trabajo continúa en `feature/changes`.

---

## FASE C — Transferencia bancaria (P1 · 30 min de examen)

### A. Objetivo
`PKG_CORE_SETTLEMENT.transferir`: débito + acreditación + una fila en `CORE_TRX`, con validaciones, bloqueo ordenado, idempotencia y **atomicidad ante falla**.

### B. Decisiones de diseño
| Tema | Decisión | Por qué |
|---|---|---|
| Ubicación | Package propio `PKG_CORE_SETTLEMENT` | Opera sobre las tablas del core, no sobre `TTEM_*`; el enunciado lo sugiere. |
| **Quién controla la transacción** | **El invocador.** El procedimiento no hace `COMMIT` | Un `COMMIT` interno confirmaría sin querer el trabajo previo del invocador. |
| **SAVEPOINT** | `sp_transferir` al entrar; ante error `ROLLBACK TO sp_transferir` y se relanza | Alcance: solo lo hecho por esa llamada (débito, acreditación, insert). Implicación: libera los bloqueos tomados después del savepoint y **no** revierte nada anterior del invocador. |
| Bloqueo | Dos `SELECT ... FOR UPDATE`, primero la cuenta con menor número | `A→B` y `B→A` simultáneas piden los bloqueos en el mismo orden: sin deadlock. (Un solo `SELECT ... ORDER BY ... FOR UPDATE` no garantiza el orden de bloqueo.) |
| Orden de validaciones | Parámetros → cuentas distintas → referencia → existencia/bloqueo → estado → moneda → saldo | La repetición de una referencia se rechaza sin tocar cuentas (idempotencia). |
| Referencia | Consulta previa **y** traducción de `DUP_VAL_ON_INDEX` en el insert | La consulta da un rechazo limpio; la UK cubre la carrera entre sesiones. |
| Falla simulada | `-20208` justo después del débito y antes de la acreditación | Se deshace todo con `ROLLBACK TO` (probado). |
| Secuencia | `SEQ_CORE_TRX` se pide recién al insertar | En la falla simulada no se consume; en todo caso, **una secuencia nunca se revierte**: tras un rollback pueden quedar huecos. |
| Montos | `p_monto > 0` y `p_monto = ROUND(p_monto, 2)` | Rechaza 0, negativos y 3 decimales. |
| Moneda | Se normaliza (`UPPER(TRIM)`) | `usd` equivale a `USD`. |
| Códigos | -20200 a -20209 negocio, -20901 técnico | Separados de los del catálogo. |

### C. Archivos
| Archivo | Contenido |
|---|---|
| `plsql/pkg_core_settlement.pks` / `.pkb` | Package (con la tabla de códigos en la cabecera del `.pks`) |
| `scripts/test_c_transferencias.sql` | 16 casos automáticos con comprobación de saldos y `CORE_TRX`; termina con `ROLLBACK` |
| `scripts/casos_c_manual.sql` | **Los 6 casos del enunciado**: preparación, ejecución y verificación de saldos y `CORE_TRX`. **Modifica datos** |
| `scripts/restablecer_casos_c.sql` | Devuelve los datos al estado original |

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| C.1 | 5 min | | Leer el `.pks` y el `.pkb` (sobre todo el orden de validaciones y el manejador de errores) |
| C.2 | 2 min | | DBeaver: ejecutar `plsql/pkg_core_settlement.pks` (Alt+X) |
| C.3 | 2 min | | Ejecutar `plsql/pkg_core_settlement.pkb` (Alt+X) y `SELECT * FROM user_errors;` → 0 filas |
| C.4 | 5 min | | Ejecutar `scripts/test_c_transferencias.sql` (Alt+X); revisar el panel Salida |
| C.5 | 10 min | | Ejecutar `scripts/casos_c_manual.sql` (Alt+X) y comparar cada caso con la tabla de abajo |
| C.6 | 3 min | | Ejecutar `scripts/restablecer_casos_c.sql` y confirmar 11 movimientos y saldos 5250 / 350.5 |

> **Auto-commit de DBeaver:** si está activo (es lo habitual), cada bloque se confirma al terminar. No afecta a los casos 2 a 6, que no dejan cambios. Con modo manual, el script ya incluye el `COMMIT` del caso 1.
> **Antes de C.5**, el estado debe ser el original (11 movimientos, 5250 / 350.5). Yo ya probé el script manual y lo restablecí, así que lo está.

### Los 6 casos (ejecución, resultado esperado y verificación)
| # | Preparación | Ejecución | Resultado esperado | Verificar saldos | Verificar `CORE_TRX` |
|---|---|---|---|---|---|
| 1 | 5250,00 / 350,50 | `1910001000011`→`1910002000017`, 100,00 PEN, `REF-T001` | Éxito | 5150,00 / 450,50 | 1 fila TRF, Debe `...011`, Haber `...017`, `N` |
| 2 | 5150,00 / 450,50 | Repetir con `REF-T001` | `ORA-20206` | Sin cambios | Sigue 1 sola fila `REF-T001` |
| 3 | 5150,00 / 450,50 | `...017`→`...011`, 5 000,00 PEN | `ORA-20205` | Sin cambios | Sin fila |
| 4 | 5150,00 / 1200,00 USD | `...011`→`...029`, 10,00 PEN | `ORA-20204` | Sin cambios | Sin fila |
| 5 | 48900,00 / 0 (estado B) | `1910003000013`→`1910004000019`, 50,00 PEN | `ORA-20203` | Sin cambios | Sin fila |
| 6 | 5150,00 / 450,50 | `...011`→`...017`, 100,00 PEN, `REF-T002`, falla simulada | `ORA-20208` | **Sin cambios** (el débito se deshizo) | **Ninguna** fila `REF-T002` |

Conclusión por caso: 1 confirma el flujo correcto; 2 prueba idempotencia; 3 a 5 prueban las reglas de negocio sin efectos laterales; **6 prueba la atomicidad**: el error ocurre con el débito ya hecho y aun así no queda ni saldo modificado ni movimiento.

### Resultados obtenidos (SQL*Plus, Oracle 23.9)
- Package compila: VALID, 0 errores.
- `test_c_transferencias.sql`: todas las líneas `OK` (C1 a C16, el chequeo "sin cambios" tras cada rechazo y el ROLLBACK final que restablece el estado).
- `casos_c_manual.sql`: los 6 casos dieron el resultado de la tabla (por ejemplo, caso 3: `Saldo insuficiente en 1910002000017: saldo 450.5, monto 5000`; caso 6: `Falla simulada despues del debito y antes de la acreditacion`, con saldos 5150 / 450.5 y 0 filas `REF-T002`).
- `restablecer_casos_c.sql`: 11 movimientos, saldos 5250 / 350.5.
- `trx_id` del caso 1 en mi ejecución: **1002**; el tuyo será distinto (la secuencia no se revierte).

### Lo que NO está probado
- **Concurrencia real** (dos sesiones a la vez): la ausencia de deadlock se apoya en el orden de bloqueo, no en una prueba con dos conexiones. Si quieres, lo probamos con dos pestañas de DBeaver.
- El procedimiento de reversa (opcional) no se implementó.

### Diagnóstico
| Error | Causa | Solución |
|---|---|---|
| `ORA-20206` en el caso 1 | Ya se ejecutó antes `REF-T001` | Ejecuta `restablecer_casos_c.sql` y repite |
| `PLS-00201: PKG_CORE_SETTLEMENT must be declared` | No se compiló el package | Ejecuta primero el `.pks`, luego el `.pkb` |
| Los saldos de los casos no coinciden con la tabla | Quedaron datos de una ejecución previa | `restablecer_casos_c.sql` |
| `ORA-00054` o el script se queda esperando | Otra sesión (otra pestaña) tiene una transacción sin confirmar sobre la cuenta | Haz `COMMIT` o `ROLLBACK` en esa sesión |
| `ORA-20901` | Error técnico inesperado | El mensaje trae el error Oracle original |

### I. Lista de verificación
- [ ] `user_errors` vacío para `PKG_CORE_SETTLEMENT`
- [ ] `test_c_transferencias.sql`: todo `OK` en tu DBeaver
- [ ] Los 6 casos coinciden con la tabla (sobre todo el 6: saldos y `CORE_TRX` intactos)
- [ ] Tras `restablecer_casos_c.sql`: 11 movimientos y saldos 5250 / 350.5
- [ ] Puedes explicar: quién hace el `COMMIT`, qué revierte `ROLLBACK TO SAVEPOINT`, por qué el orden de bloqueo evita deadlocks y por qué la secuencia no se revierte

### Git y documentación
Commit sugerido: `C: PKG_CORE_SETTLEMENT.transferir con bloqueo ordenado, idempotencia y falla simulada atomica`
README, STATUS y AI-LOG ya se actualizaron con la Fase C (STATUS la marca **Parcial** hasta que la ejecutes en DBeaver).

### J. Qué debes enviarme
1. El panel Salida de `test_c_transferencias.sql`.
2. Para cada caso de `casos_c_manual.sql`: las líneas `CASO n OK...` y las grillas de saldos y `CORE_TRX`.
3. El resultado de `restablecer_casos_c.sql`.

Luego escribiré la **FASE D — Propuesta de mejora** (sin código, máx. 20 líneas).

---

### Corrección en la Fase C (DBeaver)
`scripts/test_c_transferencias.sql` falló en DBeaver con `ORA-06550 / PLS-00103` (línea 39, `END saldo;`): DBeaver cortó el bloque por tener varias funciones y procedimientos locales. **Se reescribió sin subprogramas locales** (bucle sobre una tabla de casos). Vuelve a ejecutarlo con Alt+X desde el archivo actualizado del repositorio. Resultado esperado en el panel Salida: todas las líneas `OK` (C1 a C16, cada rechazo con su línea "saldos y CORE_TRX sin cambios", y el ROLLBACK final). Verificado por mí en SQL*Plus; falta tu ejecución en DBeaver. Nota: en mi ejecución el `trx_id` de C1 fue 1003; el tuyo será otro.

---

## FASE C — CERRADA
Validada en DBeaver: `test_c_transferencias.sql` (todas las líneas `OK`), los 6 casos de `casos_c_manual.sql` y `restablecer_casos_c.sql`. Commits `4fc3c11` y `6a95483`.

---

## FASE D — Propuesta de mejora (P1 · 10 min de examen)

### A. Objetivo
Responder, sin código y en **máximo 20 líneas**, cómo automatizar el mantenimiento de catálogos. Ya está escrita en `README.md`, sección «Sección D: propuesta de mejora» (11 puntos, cada uno de una línea lógica).

### B. Qué cubre y cómo se apoya en lo ya construido
| Requisito del enunciado | Punto del README | Se apoya en |
|---|---|---|
| Qué automatizar primero y qué problema resuelve | 1 | Los incidentes del escenario (vigencias y trazabilidad) |
| Pasos y componentes | 2 a 5 | `TYP_TTEM_ITEM`, `PKG_TTEM_CATALOG` y sus validaciones de A.3 |
| Aprobación por un segundo responsable | 4 | `CHECK` solicitante ≠ aprobador |
| Auditoría | 6 | Triggers actuales y `TTEM_AUDIT_LOG` (la bitácora opcional de A.1, aún no creada) |
| Reversión | 7 | Eliminación lógica de A.2 |
| Riesgos, dependencias, factibilidad | 8 a 10 | Esfuerzo aproximado y apoyo de DBA, Seguridad, Negocio y Mesa de servicios |
| Cómo medir | 11 | Indicadores con metas |

### C. Decisiones y supuestos
- La propuesta **no está implementada**: `TTEM_CHANGE_REQUEST`, `PKG_TTEM_CHANGE` y `TTEM_AUDIT_LOG` son diseño, no código del repositorio.
- Los plazos (3 semanas) y las metas son **estimaciones iniciales mías**; ajústalos a tu criterio y a tu contexto real.
- La validación «en seco» usa savepoint y rollback; las secuencias consumidas por esa validación no se revierten (huecos de numeración), un costo aceptable que podría mencionarse si te lo preguntan.

### Pasos
| # | Tiempo | Hora real | Instrucción |
|---|---|---|---|
| D.1 | 5 min | | Leer la sección D del README completa |
| D.2 | 5 min | | Ajustar plazos, metas y apoyos a lo que tú consideres realista |
| D.3 | 2 min | | Contar las líneas: debe haber **20 como máximo** |
| D.4 | 3 min | | Preparar la explicación oral: por qué este proceso primero y por qué un segundo aprobador |

### I. Lista de verificación
- [ ] La propuesta no pasa de 20 líneas
- [ ] Incluye: qué automatizar primero, flujo, segundo aprobador, auditoría, reversión, riesgos y dependencias, esfuerzo y apoyo, indicadores
- [ ] Es coherente con la arquitectura construida (reutiliza el package, los tipos, los triggers y la eliminación lógica)
- [ ] Puedes defenderla sin leerla

### Git y documentación
Commit sugerido: `D: propuesta de mejora para automatizar el mantenimiento de catalogos`
README, STATUS y AI-LOG ya están actualizados con la Fase D.

### J. Qué debes enviarme
1. Tu revisión: qué cambiarías (plazos, metas, riesgos, apoyos).
2. Confirmación para hacer el commit.

Luego queda la **FASE A.5** (opcional, P2: carga masiva) y el cierre: revisión integral, README final y publicación en GitHub.
