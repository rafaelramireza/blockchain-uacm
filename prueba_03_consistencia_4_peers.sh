#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1
SCRIPT_DIR="$PWD"

source "$SCRIPT_DIR/00_lib_pruebas_medec.sh"

# ============================================================
# CONFIGURACIÓN
# ============================================================

RESULTADOS_DIR="$SCRIPT_DIR/resultados"
mkdir -p "$RESULTADOS_DIR" || exit 1

# Matrícula exclusiva para la prueba 3.
MATRICULA="${MATRICULA_PRUEBA:-29-003-0001}"
ESTADO_ESPERADO="TITULADO"
TRANSICIONES_ESPERADAS=7

FECHA="$(date +%Y%m%d_%H%M%S_%N)"

CSV="$RESULTADOS_DIR/consistencia_4_peers_${FECHA}.csv"
LOG="$RESULTADOS_DIR/consistencia_4_peers_${FECHA}.log"

REGISTRO_JSON="$RESULTADOS_DIR/consistencia_registro_${FECHA}.json"
SS_JSON="$RESULTADOS_DIR/consistencia_ss_${FECHA}.json"
CERT_JSON="$RESULTADOS_DIR/consistencia_certificacion_${FECHA}.json"
TIT_JSON="$RESULTADOS_DIR/consistencia_titulacion_${FECHA}.json"

NORMALIZADO_REGISTRO="${REGISTRO_JSON%.json}_normalizado.json"
NORMALIZADO_SS="${SS_JSON%.json}_normalizado.json"
NORMALIZADO_CERT="${CERT_JSON%.json}_normalizado.json"
NORMALIZADO_TIT="${TIT_JSON%.json}_normalizado.json"

# Conservar el registro de toda la ejecución.
exec > >(tee -a "$LOG") 2>&1

fallar() {
    echo
    echo "============================================================"
    echo "RESULTADO FINAL: FAIL"
    echo "Motivo: $1"
    echo "Log: $LOG"
    echo "============================================================"
    exit 1
}


# Invoca conservando la identidad que configurar usar_identidad().
# Solicita propuestas a los cuatro peers y exige confirmación VALID.
invocar_con_cuatro_peers() {
    local funcion="$1"
    shift

    local args_json payload salida rc

    args_json="$(printf '%s\n' "$@" | jq -R -s -c 'split("\n")[:-1]')" ||
        return 1

    payload="$(jq -cn \
        --arg function "$funcion" \
        --argjson args "$args_json" \
        '{function:$function,Args:$args}')" ||
        return 1

    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE

    salida="$(peer chaincode invoke \
        -o "$ORDERER_ADDRESS" \
        --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
        --tls --cafile "$ORDERER_CA" \
        -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
        --peerAddresses "${PERFIL_PEER[REGISTRO]}" \
        --tlsRootCertFiles "${PERFIL_TLS[REGISTRO]}" \
        --peerAddresses "${PERFIL_PEER[SS]}" \
        --tlsRootCertFiles "${PERFIL_TLS[SS]}" \
        --peerAddresses "${PERFIL_PEER[CERT]}" \
        --tlsRootCertFiles "${PERFIL_TLS[CERT]}" \
        --peerAddresses "${PERFIL_PEER[TIT]}" \
        --tlsRootCertFiles "${PERFIL_TLS[TIT]}" \
        -c "$payload" \
        --waitForEvent 2>&1)"
    rc=$?

    printf '%s\n' "$salida"

    if [[ "$rc" -ne 0 ]]; then
        echo "ERROR: peer chaincode invoke terminó con código $rc."
        return 1
    fi

    local valid_count txid_count peer_count

    valid_count="$(grep -Fc 'committed with status (VALID)' <<< "$salida" || true)"
    txid_count="$(grep -oE 'txid \[[0-9a-f]{64}\]' <<< "$salida" |
        sort -u | wc -l)"
    peer_count="$(grep -oE 'at peer[^[:space:]]+' <<< "$salida" |
        sort -u | wc -l)"

    echo "Confirmaciones VALID: $valid_count"
    echo "Peers distintos      : $peer_count"
    echo "TxID distintos       : $txid_count"

    if [[ "$valid_count" -ne 4 || "$peer_count" -ne 4 || "$txid_count" -ne 1 ]]; then
        echo "ERROR: se esperaban cuatro confirmaciones VALID de cuatro peers distintos con un mismo TxID."
        return 1
    fi
}

# ============================================================
# VALIDACIONES PREVIAS
# ============================================================

command -v jq >/dev/null 2>&1 ||
    fallar "No está instalado jq."

echo "============================================================"
echo " PRUEBA 03: CONSISTENCIA DISTRIBUIDA ENTRE CUATRO PEERS"
echo "============================================================"
echo
echo "Matrícula             : $MATRICULA"
echo "Estado esperado       : $ESTADO_ESPERADO"
echo "Transiciones esperadas: $TRANSICIONES_ESPERADAS"
echo "CSV                   : $CSV"
echo "Log                   : $LOG"
echo

# El archivo CSV es exclusivo de esta ejecución.
echo "peer,estado_actual,num_transiciones,resultado" > "$CSV"

# Consulta directa y de solo lectura a CouchDB.
export COUCHDB_USER="${COUCHDB_USER:-admin}"
export COUCHDB_PASSWORD="${COUCHDB_PASSWORD:-adminpw}"

couchdb_consultar_matricula() {
    local contenedor="$1"
    local archivo="$2"
    local respuesta
    local cantidad

    respuesta="$(
        jq -n --arg id "$MATRICULA" '{
            selector: {
                docType: "EXPEDIENTE",
                id: $id
            },
            fields: [
                "id",
                "estadoActual",
                "historialTransiciones"
            ],
            limit: 2
        }' |
        docker exec -i \
            -e COUCHDB_USER \
            -e COUCHDB_PASSWORD \
            "$contenedor" \
            sh -c '
                curl -fsS \
                    -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
                    -H "Content-Type: application/json" \
                    -X POST \
                    "http://localhost:5984/uacmchannel_uacm/_find" \
                    -d @-
            '
    )" || return 2

    jq -e '.docs | type == "array"' \
        >/dev/null 2>&1 <<< "$respuesta" || return 2

    cantidad="$(jq -r '.docs | length' <<< "$respuesta")" ||
        return 2

    # 1 = expediente inexistente; 2 = error de consulta.
    [[ "$cantidad" -eq 0 ]] && return 1
    [[ "$cantidad" -eq 1 ]] || return 2

    jq -S '.docs[0] |
        {
            id,
            estadoActual,
            historialTransiciones
        }' <<< "$respuesta" > "$archivo" || return 2

    jq -e --arg id "$MATRICULA" '
        .id == $id and
        (.estadoActual | type == "string") and
        (.historialTransiciones | type == "array")
    ' "$archivo" >/dev/null 2>&1 || return 2

    return 0
}

command -v docker >/dev/null 2>&1 ||
    fallar "No está instalado Docker."

PRECHECK_JSON="$RESULTADOS_DIR/.precheck_consistencia_${FECHA}.json"

echo "Verificando que la matrícula no exista en las cuatro bases CouchDB..."

for contenedor in \
    "couchdb.registroescolar" \
    "couchdb.serviciosocial" \
    "couchdb.certificacion" \
    "couchdb.titulacion"; do

    echo "Comprobando $contenedor..."

    if couchdb_consultar_matricula "$contenedor" "$PRECHECK_JSON"; then
        rm -f "$PRECHECK_JSON"
        fallar "La matrícula $MATRICULA ya existe en $contenedor. Usa otra matrícula nueva."
    else
        rc=$?
        rm -f "$PRECHECK_JSON"

        if [[ "$rc" -eq 1 ]]; then
            echo "PASS: matrícula inexistente en $contenedor."
        else
            fallar "No se pudo comprobar $contenedor. Código: $rc."
        fi
    fi
done

# ============================================================
# 1. EJECUTAR LA TRAYECTORIA COMPLETA
# ============================================================

echo
echo "============================================================"
echo " EJECUCIÓN DE TRANSICIONES"
echo "============================================================"

ejecutar_transicion() {
    local numero="$1"
    local total="$2"
    local area="$3"
    local operacion="$4"
    local msp="$5"
    local msp_path="$6"
    local peer_host="$7"
    local tls="$8"

    echo
    echo "[$numero/$total] $area - $operacion"

    if ! usar_identidad "$msp" "$msp_path" "$peer_host" "$tls"; then
        fallar "No se pudo configurar la identidad para $operacion."
    fi

    local perfil_firmante
    case "$area" in
        "Registro Escolar") perfil_firmante="REGISTRO" ;;
        "Servicio Social") perfil_firmante="SS" ;;
        "Certificación") perfil_firmante="CERT" ;;
        "Titulación") perfil_firmante="TIT" ;;
        *) fallar "Área sin perfil firmante definido: $area." ;;
    esac

        local msp_esperado

    case "$perfil_firmante" in
        REGISTRO) msp_esperado="${PERFIL_MSP[REGISTRO]}" ;;
        SS)       msp_esperado="${PERFIL_MSP[SS]}" ;;
        CERT)     msp_esperado="${PERFIL_MSP[CERT]}" ;;
        TIT)      msp_esperado="${PERFIL_MSP[TIT]}" ;;
    esac

    if [[ "$msp" != "$msp_esperado" ]]; then
        fallar "El MSP configurado ($msp) no corresponde al perfil firmante $perfil_firmante."
    fi

    if invocar_con_cuatro_peers "$operacion" "$MATRICULA"; then
        echo "PASS: $operacion"
    else
        fallar "Falló $operacion. Revisa el log y el estado del expediente."
    fi
}

ejecutar_transicion 1 7 \
    "Registro Escolar" "RegistrarInscripcion" \
    "${PERFIL_MSP[REGISTRO]}" "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" "${PERFIL_TLS[REGISTRO]}"

ejecutar_transicion 2 7 \
    "Registro Escolar" "ValidarDocumentos" \
    "${PERFIL_MSP[REGISTRO]}" "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" "${PERFIL_TLS[REGISTRO]}"

ejecutar_transicion 3 7 \
    "Registro Escolar" "ConfirmarActivo" \
    "${PERFIL_MSP[REGISTRO]}" "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" "${PERFIL_TLS[REGISTRO]}"

ejecutar_transicion 4 7 \
    "Servicio Social" "IniciarServicioSocial" \
    "${PERFIL_MSP[SS]}" "${PERFIL_MSP_PATH[SS]}" \
    "${PERFIL_PEER[SS]}" "${PERFIL_TLS[SS]}"

ejecutar_transicion 5 7 \
    "Servicio Social" "LiberarServicioSocial" \
    "${PERFIL_MSP[SS]}" "${PERFIL_MSP_PATH[SS]}" \
    "${PERFIL_PEER[SS]}" "${PERFIL_TLS[SS]}"

ejecutar_transicion 6 7 \
    "Certificación" "EmitirCertificado" \
    "${PERFIL_MSP[CERT]}" "${PERFIL_MSP_PATH[CERT]}" \
    "${PERFIL_PEER[CERT]}" "${PERFIL_TLS[CERT]}"

ejecutar_transicion 7 7 \
    "Titulación" "EmitirTitulo" \
    "${PERFIL_MSP[TIT]}" "${PERFIL_MSP_PATH[TIT]}" \
    "${PERFIL_PEER[TIT]}" "${PERFIL_TLS[TIT]}"

# ============================================================
# 2. CONSULTAR CADA PEER
# ============================================================

consultar_peer() {
    local contenedor="$1"
    local archivo="$2"

    couchdb_consultar_matricula "$contenedor" "$archivo"
}

echo
echo "============================================================"
echo " CONSULTA DE LOS CUATRO PEERS"
echo "============================================================"

echo "[1/4] Registro Escolar"
consultar_peer "couchdb.registroescolar" "$REGISTRO_JSON" ||
    fallar "No se pudo consultar CouchDB de Registro Escolar."
echo "PASS"

echo "[2/4] Servicio Social"
consultar_peer "couchdb.serviciosocial" "$SS_JSON" ||
    fallar "No se pudo consultar CouchDB de Servicio Social."
echo "PASS"

echo "[3/4] Certificación"
consultar_peer "couchdb.certificacion" "$CERT_JSON" ||
    fallar "No se pudo consultar CouchDB de Certificación."
echo "PASS"

echo "[4/4] Titulación"
consultar_peer "couchdb.titulacion" "$TIT_JSON" ||
    fallar "No se pudo consultar CouchDB de Titulación."
echo "PASS"

# ============================================================
# 3. NORMALIZAR JSON
# ============================================================

echo
echo "Normalizando las respuestas JSON..."

jq -S -c . "$REGISTRO_JSON" > "$NORMALIZADO_REGISTRO" ||
    fallar "No se pudo normalizar el JSON de Registro Escolar."

jq -S -c . "$SS_JSON" > "$NORMALIZADO_SS" ||
    fallar "No se pudo normalizar el JSON de Servicio Social."

jq -S -c . "$CERT_JSON" > "$NORMALIZADO_CERT" ||
    fallar "No se pudo normalizar el JSON de Certificación."

jq -S -c . "$TIT_JSON" > "$NORMALIZADO_TIT" ||
    fallar "No se pudo normalizar el JSON de Titulación."

# ============================================================
# 4. COMPARAR RESPUESTAS
# ============================================================

echo
echo "============================================================"
echo " COMPARACIÓN DE ESTADO E HISTORIAL"
echo "============================================================"

REFERENCIA="$NORMALIZADO_REGISTRO"

for archivo in \
    "$NORMALIZADO_SS" \
    "$NORMALIZADO_CERT" \
    "$NORMALIZADO_TIT"; do

    if ! cmp -s "$REFERENCIA" "$archivo"; then
        echo "FAIL: las respuestas JSON normalizadas son diferentes."
        echo "Referencia: $REFERENCIA"
        echo "Diferencia: $archivo"
        diff -u "$REFERENCIA" "$archivo" || true
        fallar "Inconsistencia entre las réplicas."
    fi
done

echo "PASS: las cuatro respuestas JSON normalizadas son idénticas."

# ============================================================
# 5. VALIDAR ESTADO FINAL Y NÚMERO DE TRANSICIONES
# ============================================================

echo
echo "Validando el estado y el historial..."

ESTADO="$(jq -r '.estadoActual // empty' "$REGISTRO_JSON")"
NUM_TRANSICIONES="$(jq -r '.historialTransiciones | length' "$REGISTRO_JSON" 2>/dev/null)"

[[ "$ESTADO" == "$ESTADO_ESPERADO" ]] ||
    fallar "Estado final inesperado: $ESTADO."

[[ "$NUM_TRANSICIONES" =~ ^[0-9]+$ ]] ||
    fallar "No se pudo determinar el número de transiciones."

[[ "$NUM_TRANSICIONES" -eq "$TRANSICIONES_ESPERADAS" ]] ||
    fallar "Se esperaban $TRANSICIONES_ESPERADAS transiciones y se encontraron $NUM_TRANSICIONES."

echo "PASS: estado final = $ESTADO"
echo "PASS: número de transiciones = $NUM_TRANSICIONES"

# ============================================================
# 6. GENERAR CSV CON RESULTADOS POR PEER
# ============================================================

registrar_resultado_peer() {
    local nombre="$1"
    local archivo="$2"
    local estado transiciones resultado="PASS"

    estado="$(jq -r '.estadoActual // empty' "$archivo")" ||
        fallar "No se pudo leer el estado de $nombre."

    transiciones="$(jq -r '.historialTransiciones | length' "$archivo")" ||
        fallar "No se pudo leer el historial de $nombre."

    if [[ "$estado" != "$ESTADO_ESPERADO" ]] ||
       [[ "$transiciones" != "$TRANSICIONES_ESPERADAS" ]]; then
        resultado="FAIL"
    fi

    printf '%s,%s,%s,%s\n' \
        "$nombre" "$estado" "$transiciones" "$resultado" >> "$CSV"
}

registrar_resultado_peer "RegistroEscolarMSP" "$REGISTRO_JSON"
registrar_resultado_peer "ServicioSocialMSP" "$SS_JSON"
registrar_resultado_peer "CertificacionMSP" "$CERT_JSON"
registrar_resultado_peer "TitulacionMSP" "$TIT_JSON"

FILAS_RESULTADO="$(awk 'END { print NR - 1 }' "$CSV")"
FILAS_PASS="$(awk -F, 'NR > 1 && $4 == "PASS" { n++ } END { print n+0 }' "$CSV")"
FILAS_FAIL="$(awk -F, 'NR > 1 && $4 == "FAIL" { n++ } END { print n+0 }' "$CSV")"

[[ "$FILAS_RESULTADO" -eq 4 ]] ||
    fallar "El CSV debería contener cuatro resultados y contiene $FILAS_RESULTADO."

[[ "$FILAS_PASS" -eq 4 && "$FILAS_FAIL" -eq 0 ]] ||
    fallar "El CSV no confirma cuatro peers PASS (PASS=$FILAS_PASS, FAIL=$FILAS_FAIL)."

# ============================================================
# RESULTADO FINAL
# ============================================================

echo
echo "============================================================"
echo " RESULTADO FINAL: PASS"
echo "============================================================"
echo "Matrícula          : $MATRICULA"
echo "Estado final       : $ESTADO"
echo "Transiciones       : $NUM_TRANSICIONES"
echo "Peers comparados   : 4"
echo "Consistencia JSON  : PASS"
echo
echo "CSV de resultados:"
echo "$CSV"
echo
echo "JSON originales:"
echo "$REGISTRO_JSON"
echo "$SS_JSON"
echo "$CERT_JSON"
echo "$TIT_JSON"
echo
echo "JSON normalizados:"
echo "$NORMALIZADO_REGISTRO"
echo "$NORMALIZADO_SS"
echo "$NORMALIZADO_CERT"
echo "$NORMALIZADO_TIT"
echo
echo "Log:"
echo "$LOG"
echo "============================================================"
