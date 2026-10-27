-- =====================================================================
-- PKG_TTEM_LOAD - Cuerpo (A.5)
-- Ejecutar como CORE_DEV DESPUES de pkg_ttem_load.pks. Termina con "/" en linea aparte.
-- Flujo por bloque de BULK COLLECT LIMIT: validar cada fila -> FORALL INSERT SAVE EXCEPTIONS de las
-- validas -> FORALL de rechazos en TTEM_LOAD_ERROR -> FORALL UPDATE de processed_flag / processed_at.
-- Requiere Oracle 12.2 o superior (TO_DATE ... DEFAULT NULL ON CONVERSION ERROR); no usa nada exclusivo de 23ai.
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_ttem_load AS
  TYPE t_num_tab   IS TABLE OF NUMBER          INDEX BY PLS_INTEGER;
  TYPE t_code_tab  IS TABLE OF VARCHAR2(30)    INDEX BY PLS_INTEGER;
  TYPE t_text_tab  IS TABLE OF VARCHAR2(200)   INDEX BY PLS_INTEGER;
  TYPE t_msg_tab   IS TABLE OF VARCHAR2(400)   INDEX BY PLS_INTEGER;
  TYPE t_date_tab  IS TABLE OF DATE            INDEX BY PLS_INTEGER;
  TYPE t_cat_id    IS TABLE OF ttem_catalog.catalog_id%TYPE INDEX BY VARCHAR2(30);
  TYPE t_cat_st    IS TABLE OF ttem_catalog.status%TYPE     INDEX BY VARCHAR2(30);
  TYPE t_vistos    IS TABLE OF BOOLEAN         INDEX BY VARCHAR2(80);
  c_estado_activo  CONSTANT ttem_catalog.status%TYPE := 'A';
  e_dml_errores     EXCEPTION;
  e_recurso_ocupado EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_dml_errores, -24381);
  PRAGMA EXCEPTION_INIT(e_recurso_ocupado, -54);
  FUNCTION es_error_negocio (p_codigo IN PLS_INTEGER) RETURN BOOLEAN IS
  BEGIN
    RETURN p_codigo BETWEEN -20399 AND -20300;
  END es_error_negocio;
  PROCEDURE cargar_lote (
    p_load_batch   IN  ttem_item_stg.load_batch%TYPE,
    p_limit        IN  PLS_INTEGER DEFAULT 200,
    p_cargados     OUT PLS_INTEGER,
    p_rechazados   OUT PLS_INTEGER) IS
    -- Normalizacion en el SELECT: TRIM en todos los campos y UPPER en los codigos. Las fechas solo
    -- se convierten si tienen forma estricta YYYY-MM-DD; una fecha imposible (2026-13-01) da NULL.
    CURSOR c_stg (p_batch VARCHAR2) IS
      SELECT s.stg_id,
             UPPER(TRIM(s.catalog_code)) AS catalog_code,
             UPPER(TRIM(s.item_code))    AS item_code,
             TRIM(s.item_name)           AS item_name,
             TRIM(s.item_value)          AS item_value,
             TRIM(s.valid_from_txt)      AS valid_from_txt,
             TRIM(s.valid_to_txt)        AS valid_to_txt,
             CASE WHEN REGEXP_LIKE(TRIM(s.valid_from_txt), '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
                  THEN TO_DATE(TRIM(s.valid_from_txt) DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD') END AS valid_from,
             CASE WHEN REGEXP_LIKE(TRIM(s.valid_to_txt), '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
                  THEN TO_DATE(TRIM(s.valid_to_txt) DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD') END AS valid_to
        FROM ttem_item_stg s
       WHERE s.load_batch = p_batch
         AND s.processed_flag = 'N'
       ORDER BY s.stg_id
         FOR UPDATE NOWAIT;
    TYPE t_filas IS TABLE OF c_stg%ROWTYPE;
    l_filas   t_filas;
    l_cat_id  t_cat_id;
    l_cat_st  t_cat_st;
    l_vistos  t_vistos;
    l_clave   VARCHAR2(80);
    l_motivo  VARCHAR2(30);
    l_mensaje VARCHAR2(400);
    -- Filas validas a insertar (indices densos 1..l_n_ins, requisito de FORALL)
    l_i_stg   t_num_tab;
    l_i_cat   t_num_tab;
    l_i_code  t_code_tab;
    l_i_name  t_text_tab;
    l_i_val   t_text_tab;
    l_i_desde t_date_tab;
    l_i_hasta t_date_tab;
    -- Rechazos y aceptados del bloque
    l_e_stg   t_num_tab;
    l_e_code  t_code_tab;
    l_e_msg   t_msg_tab;
    l_o_stg   t_num_tab;
    l_fallo   t_num_tab;
    l_n_ins   PLS_INTEGER;
    l_n_err   PLS_INTEGER;
    l_n_ok    PLS_INTEGER;
    l_total_ok  PLS_INTEGER := 0;
    l_total_err PLS_INTEGER := 0;
    l_existen   PLS_INTEGER;
  BEGIN
    SAVEPOINT sp_cargar_lote;
    p_cargados := 0;
    p_rechazados := 0;
    IF p_limit IS NULL OR p_limit < 1 THEN
      RAISE_APPLICATION_ERROR(c_err_limite_invalido, 'p_limit debe ser un entero mayor o igual que 1');
    END IF;
    SELECT COUNT(*) INTO l_existen FROM ttem_item_stg WHERE load_batch = p_load_batch;
    IF l_existen = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_lote_no_existe,
        'No existe ningun registro de staging para el lote ' || NVL(p_load_batch, 'NULL'));
    END IF;
    -- Catalogos en memoria: una sola lectura en lugar de una consulta por fila
    FOR r IN (SELECT catalog_code, catalog_id, status FROM ttem_catalog) LOOP
      l_cat_id(r.catalog_code) := r.catalog_id;
      l_cat_st(r.catalog_code) := r.status;
    END LOOP;
    BEGIN
      OPEN c_stg(p_load_batch);
    EXCEPTION
      WHEN e_recurso_ocupado THEN
        RAISE_APPLICATION_ERROR(c_err_lote_en_proceso,
          'El lote ' || p_load_batch || ' esta siendo procesado por otra sesion');
    END;
    LOOP
      FETCH c_stg BULK COLLECT INTO l_filas LIMIT p_limit;
      EXIT WHEN l_filas.COUNT = 0;
      l_n_ins := 0;
      l_n_err := 0;
      l_n_ok  := 0;
      l_fallo.DELETE;
      -- 1. Validacion fila a fila: ninguna fila invalida interrumpe el lote
      FOR i IN 1 .. l_filas.COUNT LOOP
        l_motivo := NULL;
        l_mensaje := NULL;
        IF l_filas(i).catalog_code IS NULL THEN
          l_motivo := 'CATALOGO_VACIO';
          l_mensaje := 'El codigo de catalogo esta vacio';
        ELSIF NOT l_cat_id.EXISTS(l_filas(i).catalog_code) THEN
          l_motivo := 'CATALOGO_INEXISTENTE';
          l_mensaje := 'El catalogo [' || l_filas(i).catalog_code || '] no existe';
        ELSIF l_cat_st(l_filas(i).catalog_code) <> c_estado_activo THEN
          l_motivo := 'CATALOGO_INACTIVO';
          l_mensaje := 'El catalogo [' || l_filas(i).catalog_code || '] esta inactivo y no admite items nuevos';
        ELSIF l_filas(i).item_code IS NULL THEN
          l_motivo := 'CODIGO_VACIO';
          l_mensaje := 'El codigo del item esta vacio';
        ELSIF l_filas(i).item_name IS NULL THEN
          l_motivo := 'NOMBRE_VACIO';
          l_mensaje := 'El nombre del item [' || l_filas(i).item_code || '] esta vacio';
        ELSIF l_filas(i).valid_from IS NULL THEN
          l_motivo := 'FECHA_DESDE_INVALIDA';
          l_mensaje := 'Vigencia desde invalida o vacia: [' || NVL(l_filas(i).valid_from_txt, 'NULL') || ']';
        ELSIF l_filas(i).valid_to_txt IS NOT NULL AND l_filas(i).valid_to IS NULL THEN
          l_motivo := 'FECHA_HASTA_INVALIDA';
          l_mensaje := 'Vigencia hasta invalida: [' || l_filas(i).valid_to_txt || ']';
        ELSIF l_filas(i).valid_to IS NOT NULL AND l_filas(i).valid_to < l_filas(i).valid_from THEN
          l_motivo := 'VIGENCIA_INCOHERENTE';
          l_mensaje := 'La vigencia hasta (' || l_filas(i).valid_to_txt ||
                       ') es anterior a la vigencia desde (' || l_filas(i).valid_from_txt || ')';
        ELSE
          l_clave := l_cat_id(l_filas(i).catalog_code) || '|' || l_filas(i).item_code;
          IF l_vistos.EXISTS(l_clave) THEN
            -- Duplicado dentro del lote: gana la primera fila (menor stg_id); no se actualiza nada.
            l_motivo := 'DUPLICADO_LOTE';
            l_mensaje := 'El codigo [' || l_filas(i).item_code || '] ya aparece antes en el lote para el catalogo [' ||
                         l_filas(i).catalog_code || ']';
          ELSE
            l_vistos(l_clave) := TRUE;
            l_n_ins := l_n_ins + 1;
            l_i_stg(l_n_ins)   := l_filas(i).stg_id;
            l_i_cat(l_n_ins)   := l_cat_id(l_filas(i).catalog_code);
            l_i_code(l_n_ins)  := l_filas(i).item_code;
            l_i_name(l_n_ins)  := l_filas(i).item_name;
            l_i_val(l_n_ins)   := l_filas(i).item_value;
            l_i_desde(l_n_ins) := l_filas(i).valid_from;
            l_i_hasta(l_n_ins) := l_filas(i).valid_to;
          END IF;
        END IF;
        IF l_motivo IS NOT NULL THEN
          l_n_err := l_n_err + 1;
          l_e_stg(l_n_err)  := l_filas(i).stg_id;
          l_e_code(l_n_err) := l_motivo;
          l_e_msg(l_n_err)  := SUBSTR(l_mensaje, 1, 400);
        END IF;
      END LOOP;
      -- 2. Insercion masiva de las validas. Los duplicados contra TTEM_ITEM los detiene la UK.
      IF l_n_ins > 0 THEN
        BEGIN
          FORALL j IN 1 .. l_n_ins SAVE EXCEPTIONS
            INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value, valid_from, valid_to)
            VALUES (seq_ttem_item.NEXTVAL, l_i_cat(j), l_i_code(j), l_i_name(j), l_i_val(j),
                    l_i_desde(j), l_i_hasta(j));
        EXCEPTION
          WHEN e_dml_errores THEN
            -- No se oculta nada: cada fila fallida se anota con su codigo Oracle para registrarla.
            FOR k IN 1 .. SQL%BULK_EXCEPTIONS.COUNT LOOP
              l_fallo(SQL%BULK_EXCEPTIONS(k).ERROR_INDEX) := SQL%BULK_EXCEPTIONS(k).ERROR_CODE;
            END LOOP;
        END;
        FOR j IN 1 .. l_n_ins LOOP
          IF l_fallo.EXISTS(j) THEN
            l_n_err := l_n_err + 1;
            l_e_stg(l_n_err) := l_i_stg(j);
            IF l_fallo(j) = 1 THEN
              l_e_code(l_n_err) := 'DUPLICADO_EXISTENTE';
              l_e_msg(l_n_err)  := SUBSTR('El codigo [' || l_i_code(j) || '] ya existe en el catalogo ' ||
                                           l_i_cat(j), 1, 400);
            ELSE
              l_e_code(l_n_err) := 'ERROR_INSERCION';
              l_e_msg(l_n_err)  := SUBSTR(SQLERRM(-l_fallo(j)), 1, 400);
            END IF;
          ELSE
            l_n_ok := l_n_ok + 1;
            l_o_stg(l_n_ok) := l_i_stg(j);
          END IF;
        END LOOP;
      END IF;
      -- 3. Rechazos y marcas de staging, tambien en bloque
      IF l_n_err > 0 THEN
        FORALL e IN 1 .. l_n_err
          INSERT INTO ttem_load_error (load_error_id, stg_id, load_batch, error_code, error_message)
          VALUES (seq_ttem_load_error.NEXTVAL, l_e_stg(e), p_load_batch, l_e_code(e), l_e_msg(e));
        FORALL e IN 1 .. l_n_err
          UPDATE ttem_item_stg SET processed_flag = 'E', processed_at = SYSDATE
           WHERE stg_id = l_e_stg(e);
      END IF;
      IF l_n_ok > 0 THEN
        FORALL o IN 1 .. l_n_ok
          UPDATE ttem_item_stg SET processed_flag = 'S', processed_at = SYSDATE
           WHERE stg_id = l_o_stg(o);
      END IF;
      l_total_ok  := l_total_ok  + l_n_ok;
      l_total_err := l_total_err + l_n_err;
    END LOOP;
    CLOSE c_stg;
    p_cargados   := l_total_ok;
    p_rechazados := l_total_err;
  EXCEPTION
    WHEN OTHERS THEN
      IF c_stg%ISOPEN THEN
        CLOSE c_stg;
      END IF;
      ROLLBACK TO sp_cargar_lote;
      p_cargados := 0;
      p_rechazados := 0;
      IF es_error_negocio(SQLCODE) THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_tecnico, 'cargar_lote: ' || SQLERRM, TRUE);
      END IF;
  END cargar_lote;
END pkg_ttem_load;
/
