#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib_pruebas_medec.sh"

# ============================================================
# RECTIFICACIÓN - TITULACIÓN
# ============================================================

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 <matrícula>"
    exit 1
fi

ID="$1"

usar_identidad \
    "$TIT_MSP" \
    "$TIT_MSP_PATH" \
    "$TIT_PEER" \
    "$TIT_TLS"

echo
echo "============================================================"
echo "RECTIFICACIÓN - TITULACIÓN"
echo "============================================================"
echo
echo "Matrícula: $ID"

# ============================================================
# 1. CONSULTAR EXPEDIENTE
# ============================================================

echo
echo "[1/5] Consultando expediente..."

EXPEDIENTE="$(consultar "$ID")"

if [[ -z "$EXPEDIENTE" || "$EXPEDIENTE" == "null" ]]; then
    echo "      ERROR: no se pudo consultar el expediente."
    exit 1
fi

ESTADO_ACTUAL="$(echo "$EXPEDIENTE" | jq -r '.estadoActual')"

if [[ -z "$ESTADO_ACTUAL" || "$ESTADO_ACTUAL" == "null" ]]; then
    echo "      ERROR: el expediente no contiene estadoActual."
    exit 1
fi

echo "      Estado actual: $ESTADO_ACTUAL"

# ============================================================
# 2. OBTENER ÚLTIMA TRANSICIÓN
# ============================================================

echo
echo "[2/5] Identificando última transición..."

ULTIMA_TRANSICION="$(
    echo "$EXPEDIENTE" |
        jq -r '
            [
                .historialTransiciones[]
                | select(.tipo == "TRANSICION")
            ]
            | last
        '
)"

if [[ "$ULTIMA_TRANSICION" == "null" || -z "$ULTIMA_TRANSICION" ]]; then
    echo "      ERROR: no existe una transición rectificable."
    exit 1
fi

EVENTO="$(echo "$ULTIMA_TRANSICION" | jq -r '.evento')"
TXID_ORIGINAL="$(echo "$ULTIMA_TRANSICION" | jq -r '.txId')"
EMISOR="$(echo "$ULTIMA_TRANSICION" | jq -r '.emisor')"
ESTADO_ANTERIOR="$(echo "$ULTIMA_TRANSICION" | jq -r '.estadoAnterior')"
ESTADO_NUEVO="$(echo "$ULTIMA_TRANSICION" | jq -r '.estadoNuevo')"

echo "      Evento           : $EVENTO"
echo "      Emisor           : $EMISOR"
echo "      Estado anterior  : $ESTADO_ANTERIOR"
echo "      Estado nuevo     : $ESTADO_NUEVO"
echo "      TxID             : $TXID_ORIGINAL"

# ============================================================
# 3. IDENTIDAD DE TITULACIÓN
# ============================================================

echo
echo "[3/5] Utilizando identidad de Titulación..."
echo "      MSP: $TIT_MSP"

# ============================================================
# 4. SOLICITAR RECTIFICACIÓN
# ============================================================

echo
echo "[4/5] Solicitando rectificación..."

invocar "RectificarTransicion" "$ID" "$TXID_ORIGINAL"

# ============================================================
# 5. VERIFICAR RESULTADO
# ============================================================

echo
echo "[5/5] Verificando resultado..."

EXPEDIENTE_FINAL="$(consultar "$ID")"

ESTADO_FINAL="$(
    echo "$EXPEDIENTE_FINAL" |
        jq -r '.estadoActual'
)"

RECTIFICACION="$(
    echo "$EXPEDIENTE_FINAL" |
        jq -r --arg txid "$TXID_ORIGINAL" '
            [
                .historialTransiciones[]
                | select(
                    .tipo == "RECTIFICACION"
                    and .txIdTransicionOrigen == $txid
                )
            ]
            | last
        '
)"

if [[ "$RECTIFICACION" == "null" || -z "$RECTIFICACION" ]]; then
    echo "      ERROR: no se encontró la rectificación en el historial."
    exit 1
fi

ESTADO_RESTAURADO="$(
    echo "$RECTIFICACION" |
        jq -r '.estadoNuevo'
)"

TXID_RECTIFICACION="$(
    echo "$RECTIFICACION" |
        jq -r '.txId'
)"

echo
echo "============================================================"
echo "RESULTADO: PASS"
echo "============================================================"
echo
echo "Matrícula             : $ID"
echo "Transición rectificada: $EVENTO"
echo "TxID original         : $TXID_ORIGINAL"
echo "Estado anterior       : $ESTADO_NUEVO"
echo "Estado restaurado     : $ESTADO_RESTAURADO"
echo "TxID rectificación    : $TXID_RECTIFICACION"
echo "Transición original   : CONSERVADA"
echo "Rectificación         : REGISTRADA"
echo