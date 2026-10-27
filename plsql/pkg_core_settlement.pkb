-- =====================================================================
-- PKG_CORE_SETTLEMENT - Cuerpo
-- Ejecutar como CORE_DEV DESPUES de pkg_core_settlement.pks. Termina con "/" en linea aparte.
-- Orden de validaciones: parametros -> cuentas distintas -> referencia (idempotencia) ->
-- existencia y bloqueo de cuentas -> estado -> moneda -> saldo. Luego debito, (falla simulada),
-- acreditacion e insert en CORE_TRX. El manejo de errores sigue el patron de PKG_TTEM_CATALOG.
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_core_settlement AS
  c_estado_activa CONSTANT core_account.status%TYPE := 'A';
  FUNCTION es_error_negocio (p_codigo IN PLS_INTEGER) RETURN BOOLEAN IS
  BEGIN
    RETURN p_codigo BETWEEN -20299 AND -20200;
  END es_error_negocio;
  -- Bloquea (FOR UPDATE) y devuelve la cuenta; p_rol solo sirve para el mensaje de error.
  PROCEDURE bloquear_cuenta (
    p_account_no  IN  core_account.account_no%TYPE,
    p_rol         IN  VARCHAR2,
    p_cuenta      OUT core_account%ROWTYPE) IS
  BEGIN
    SELECT * INTO p_cuenta FROM core_account WHERE account_no = p_account_no FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_cuenta_no_existe,
        'La cuenta de ' || p_rol || ' ' || p_account_no || ' no existe');
  END bloquear_cuenta;
  PROCEDURE transferir (
    p_cuenta_origen   IN  core_account.account_no%TYPE,
    p_cuenta_destino  IN  core_account.account_no%TYPE,
    p_monto           IN  NUMBER,
    p_moneda          IN  VARCHAR2,
    p_referencia      IN  VARCHAR2,
    p_descripcion     IN  VARCHAR2 DEFAULT NULL,
    p_simular_falla   IN  VARCHAR2 DEFAULT 'N',
    p_trx_id          OUT core_trx.trx_id%TYPE) IS
    l_origen      core_account%ROWTYPE;
    l_destino     core_account%ROWTYPE;
    l_moneda      core_account.currency%TYPE;
    l_referencia  core_trx.reference%TYPE;
    l_existentes  PLS_INTEGER;
  BEGIN
    SAVEPOINT sp_transferir;
    p_trx_id := NULL;
    -- 1. Parametros
    IF p_monto IS NULL OR p_monto <= 0 OR p_monto <> ROUND(p_monto, 2) THEN
      RAISE_APPLICATION_ERROR(c_err_monto_invalido,
        'El monto debe ser mayor que cero y tener como maximo 2 decimales (recibido: ' ||
        NVL(TO_CHAR(p_monto), 'NULL') || ')');
    END IF;
    l_referencia := TRIM(p_referencia);
    IF l_referencia IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_referencia_obligatoria, 'La referencia es obligatoria');
    END IF;
    l_moneda := UPPER(TRIM(p_moneda));
    IF TRIM(p_cuenta_origen) IS NULL OR TRIM(p_cuenta_destino) IS NULL OR l_moneda IS NULL
       OR NVL(p_simular_falla, 'N') NOT IN ('S', 'N') THEN
      RAISE_APPLICATION_ERROR(c_err_parametro_invalido,
        'Cuenta de origen, cuenta de destino y moneda son obligatorias; p_simular_falla debe ser S o N');
    END IF;
    IF p_cuenta_origen = p_cuenta_destino THEN
      RAISE_APPLICATION_ERROR(c_err_cuentas_iguales,
        'La cuenta de origen y la de destino son la misma (' || p_cuenta_origen || ')');
    END IF;
    -- 2. Idempotencia: la referencia ya usada se rechaza antes de tocar ninguna cuenta.
    SELECT COUNT(*) INTO l_existentes FROM core_trx WHERE reference = l_referencia;
    IF l_existentes > 0 THEN
      RAISE_APPLICATION_ERROR(c_err_referencia_duplicada,
        'Ya existe un movimiento con la referencia ' || l_referencia);
    END IF;
    -- 3. Bloqueo en orden ascendente de numero de cuenta (evita deadlocks entre A->B y B->A).
    IF p_cuenta_origen < p_cuenta_destino THEN
      bloquear_cuenta(p_cuenta_origen, 'origen', l_origen);
      bloquear_cuenta(p_cuenta_destino, 'destino', l_destino);
    ELSE
      bloquear_cuenta(p_cuenta_destino, 'destino', l_destino);
      bloquear_cuenta(p_cuenta_origen, 'origen', l_origen);
    END IF;
    -- 4. Reglas de negocio sobre los datos ya bloqueados (estables hasta el COMMIT del invocador).
    IF l_origen.status <> c_estado_activa THEN
      RAISE_APPLICATION_ERROR(c_err_cuenta_no_activa,
        'La cuenta de origen ' || l_origen.account_no || ' no esta activa (estado ' || l_origen.status || ')');
    END IF;
    IF l_destino.status <> c_estado_activa THEN
      RAISE_APPLICATION_ERROR(c_err_cuenta_no_activa,
        'La cuenta de destino ' || l_destino.account_no || ' no esta activa (estado ' || l_destino.status || ')');
    END IF;
    IF l_origen.currency <> l_moneda OR l_destino.currency <> l_moneda THEN
      RAISE_APPLICATION_ERROR(c_err_moneda_distinta,
        'La moneda ' || l_moneda || ' no coincide con la de las cuentas (origen ' ||
        l_origen.currency || ', destino ' || l_destino.currency || ')');
    END IF;
    IF l_origen.balance < p_monto THEN
      RAISE_APPLICATION_ERROR(c_err_saldo_insuficiente,
        'Saldo insuficiente en ' || l_origen.account_no || ': saldo ' || TO_CHAR(l_origen.balance) ||
        ', monto ' || TO_CHAR(p_monto));
    END IF;
    -- 5. Debito
    UPDATE core_account SET balance = balance - p_monto WHERE account_no = l_origen.account_no;
    -- 6. Falla simulada: despues del debito y antes de la acreditacion
    IF p_simular_falla = 'S' THEN
      RAISE_APPLICATION_ERROR(c_err_falla_simulada,
        'Falla simulada despues del debito y antes de la acreditacion');
    END IF;
    -- 7. Acreditacion
    UPDATE core_account SET balance = balance + p_monto WHERE account_no = l_destino.account_no;
    -- 8. Movimiento contable (partida doble): UNA sola fila
    BEGIN
      INSERT INTO core_trx (trx_id, trx_date, debit_account_no, credit_account_no, amount, currency,
                            trx_type, description, reference, reversal_flag, reversed_trx_id)
      VALUES (seq_core_trx.NEXTVAL, SYSDATE, l_origen.account_no, l_destino.account_no, p_monto,
              l_moneda, 'TRF', TRIM(p_descripcion), l_referencia, 'N', NULL)
      RETURNING trx_id INTO p_trx_id;
    EXCEPTION
      -- Si otra sesion confirmo la misma referencia entre la validacion y el insert, la UK la detiene.
      WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(c_err_referencia_duplicada,
          'Ya existe un movimiento con la referencia ' || l_referencia);
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_transferir;
      p_trx_id := NULL;
      IF es_error_negocio(SQLCODE) THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_tecnico, 'transferir: ' || SQLERRM, TRUE);
      END IF;
  END transferir;
END pkg_core_settlement;
/
