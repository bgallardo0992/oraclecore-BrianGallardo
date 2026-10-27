-- =====================================================================
-- PKG_TTEM_LOAD - Especificacion (A.5: carga masiva de items desde TTEM_ITEM_STG)
-- Ejecutar como CORE_DEV. Termina con "/" en linea aparte.
--
-- Transaccion: el package NO hace COMMIT; tiene SAVEPOINT propio (sp_cargar_lote) y ante error
-- hace ROLLBACK TO y relanza. Decide el invocador. Procesa solo registros con processed_flag = 'N'.
-- Motivos de rechazo guardados en TTEM_LOAD_ERROR.error_code:
--   CATALOGO_VACIO, CATALOGO_INEXISTENTE, CATALOGO_INACTIVO, CODIGO_VACIO, NOMBRE_VACIO,
--   FECHA_DESDE_INVALIDA, FECHA_HASTA_INVALIDA, VIGENCIA_INCOHERENTE,
--   DUPLICADO_LOTE (repetido dentro del lote), DUPLICADO_EXISTENTE (ya existe en TTEM_ITEM),
--   ERROR_INSERCION (otro error Oracle al insertar; el mensaje trae el original).
-- CODIGOS DE ERROR DEL PROCEDIMIENTO (rango -20300..-20399 negocio; -20902 tecnico)
--   -20310 e_lote_en_proceso    Otra sesion tiene bloqueadas las filas pendientes del lote.
--   -20311 e_lote_no_existe     No hay ningun registro de staging con ese lote (o lote nulo).
--   -20312 e_limite_invalido    p_limit nulo o menor que 1.
--   -20902 e_error_tecnico_carga Error inesperado envuelto con el error Oracle original.
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_ttem_load AS
  c_err_lote_en_proceso  CONSTANT PLS_INTEGER := -20310;
  c_err_lote_no_existe   CONSTANT PLS_INTEGER := -20311;
  c_err_limite_invalido  CONSTANT PLS_INTEGER := -20312;
  c_err_tecnico          CONSTANT PLS_INTEGER := -20902;
  e_lote_en_proceso      EXCEPTION;
  e_lote_no_existe       EXCEPTION;
  e_limite_invalido      EXCEPTION;
  e_error_tecnico_carga  EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_lote_en_proceso,     -20310);
  PRAGMA EXCEPTION_INIT(e_lote_no_existe,      -20311);
  PRAGMA EXCEPTION_INIT(e_limite_invalido,     -20312);
  PRAGMA EXCEPTION_INIT(e_error_tecnico_carga, -20902);
  -- Carga el lote: normaliza (TRIM en todo, UPPER en codigos), valida, inserta con
  -- FORALL ... SAVE EXCEPTIONS, registra cada rechazo y marca el staging como S (cargado) o E (error).
  -- p_limit = tamano de cada bloque de BULK COLLECT ... LIMIT. Un lote ya procesado devuelve 0 / 0.
  PROCEDURE cargar_lote (
    p_load_batch   IN  ttem_item_stg.load_batch%TYPE,
    p_limit        IN  PLS_INTEGER DEFAULT 200,
    p_cargados     OUT PLS_INTEGER,
    p_rechazados   OUT PLS_INTEGER);
END pkg_ttem_load;
/
