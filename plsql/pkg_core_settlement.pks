-- =====================================================================
-- PKG_CORE_SETTLEMENT - Especificacion (Seccion C: liquidacion de transferencias)
-- Ejecutar como CORE_DEV. Termina con "/" en linea aparte.
--
-- QUIEN CONTROLA LA TRANSACCION: el INVOCADOR. transferir NO hace COMMIT. Abre un SAVEPOINT
-- propio (sp_transferir) y, ante cualquier error, hace ROLLBACK solo hasta ese savepoint:
-- deshace el debito, la acreditacion y el insert de ESTA llamada (y libera sus bloqueos), pero
-- no toca lo que el invocador hizo antes en su transaccion. Despues relanza el error.
-- Si todo sale bien, el cambio queda pendiente hasta que el invocador haga COMMIT.
-- Nota: los valores de SEQ_CORE_TRX NO se revierten con ROLLBACK (pueden quedar huecos).
--
-- BLOQUEO: SELECT ... FOR UPDATE de ambas cuentas, siempre en orden ascendente de numero de
-- cuenta (LEAST/GREATEST), para que dos transferencias cruzadas (A->B y B->A) no se bloqueen
-- mutuamente (deadlock).
--
-- TABLA DE CODIGOS DE ERROR (rango propio -20200..-20299 negocio; -20901 tecnico)
--   -20200 e_monto_invalido        Monto nulo, <= 0 o con mas de 2 decimales.
--   -20201 e_cuenta_no_existe      La cuenta de origen o de destino no existe.
--   -20202 e_cuentas_iguales       Origen y destino son la misma cuenta.
--   -20203 e_cuenta_no_activa      Origen o destino no tiene estado A.
--   -20204 e_moneda_distinta       La moneda indicada no coincide con la de ambas cuentas.
--   -20205 e_saldo_insuficiente    El saldo de origen es menor que el monto.
--   -20206 e_referencia_duplicada  Ya existe un movimiento con esa referencia (idempotencia).
--   -20207 e_referencia_obligatoria La referencia es nula o vacia.
--   -20208 e_falla_simulada        Falla provocada con p_simular_falla = 'S' tras el debito.
--   -20209 e_parametro_invalido    Cuenta o moneda nula, o p_simular_falla distinto de S/N.
--   -20901 e_error_tecnico_liq     Error inesperado, envuelto con el error Oracle original.
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_core_settlement AS
  c_err_monto_invalido         CONSTANT PLS_INTEGER := -20200;
  c_err_cuenta_no_existe       CONSTANT PLS_INTEGER := -20201;
  c_err_cuentas_iguales        CONSTANT PLS_INTEGER := -20202;
  c_err_cuenta_no_activa       CONSTANT PLS_INTEGER := -20203;
  c_err_moneda_distinta        CONSTANT PLS_INTEGER := -20204;
  c_err_saldo_insuficiente     CONSTANT PLS_INTEGER := -20205;
  c_err_referencia_duplicada   CONSTANT PLS_INTEGER := -20206;
  c_err_referencia_obligatoria CONSTANT PLS_INTEGER := -20207;
  c_err_falla_simulada         CONSTANT PLS_INTEGER := -20208;
  c_err_parametro_invalido     CONSTANT PLS_INTEGER := -20209;
  c_err_tecnico                CONSTANT PLS_INTEGER := -20901;
  e_monto_invalido          EXCEPTION;
  e_cuenta_no_existe        EXCEPTION;
  e_cuentas_iguales         EXCEPTION;
  e_cuenta_no_activa        EXCEPTION;
  e_moneda_distinta         EXCEPTION;
  e_saldo_insuficiente      EXCEPTION;
  e_referencia_duplicada    EXCEPTION;
  e_referencia_obligatoria  EXCEPTION;
  e_falla_simulada          EXCEPTION;
  e_parametro_invalido      EXCEPTION;
  e_error_tecnico_liq       EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_monto_invalido,         -20200);
  PRAGMA EXCEPTION_INIT(e_cuenta_no_existe,       -20201);
  PRAGMA EXCEPTION_INIT(e_cuentas_iguales,        -20202);
  PRAGMA EXCEPTION_INIT(e_cuenta_no_activa,       -20203);
  PRAGMA EXCEPTION_INIT(e_moneda_distinta,        -20204);
  PRAGMA EXCEPTION_INIT(e_saldo_insuficiente,     -20205);
  PRAGMA EXCEPTION_INIT(e_referencia_duplicada,   -20206);
  PRAGMA EXCEPTION_INIT(e_referencia_obligatoria, -20207);
  PRAGMA EXCEPTION_INIT(e_falla_simulada,         -20208);
  PRAGMA EXCEPTION_INIT(e_parametro_invalido,     -20209);
  PRAGMA EXCEPTION_INIT(e_error_tecnico_liq,      -20901);
  -- Transfiere p_monto de p_cuenta_origen a p_cuenta_destino: debita, acredita y registra UNA fila
  -- en CORE_TRX (tipo TRF, Debe = origen, Haber = destino, reversal_flag = 'N').
  -- p_simular_falla = 'S' provoca el error -20208 despues del debito y antes de la acreditacion.
  -- p_trx_id devuelve el id generado con SEQ_CORE_TRX (NULL si la operacion falla).
  PROCEDURE transferir (
    p_cuenta_origen   IN  core_account.account_no%TYPE,
    p_cuenta_destino  IN  core_account.account_no%TYPE,
    p_monto           IN  NUMBER,
    p_moneda          IN  VARCHAR2,
    p_referencia      IN  VARCHAR2,
    p_descripcion     IN  VARCHAR2 DEFAULT NULL,
    p_simular_falla   IN  VARCHAR2 DEFAULT 'N',
    p_trx_id          OUT core_trx.trx_id%TYPE);
END pkg_core_settlement;
/
