#!/usr/bin/env bash

set -euo pipefail

export FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"

# ============================================================
# PRUEBA - RECTIFICACIÓN BÁSICA
#
# Flujo:
#
# RegistrarInscripcion()
#        ↓
#     INSCRITO
#        ↓
# ValidarDocumentos()
#        ↓
#   DOC_VALIDADO
#        ↓
# ConfirmarActivo()
#        ↓
#      ACTIVO
#        ↓
# RectificarTransicion()
#        ↓
#   DOC_VALIDADO
#
# ============================================================

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 ##-###-####"
    echo "Ejemplo: $0 99-999-9999"
    exit 1
fi

MATRICULA="$1"

if [[ ! "$MATRICULA" =~ ^[0-9]{2}-[0-9]{3}-[0-9]{4}$ ]]; then
    echo "ERROR: la matrícula debe tener el formato ##-###-####"
    exit 1
fi

# ------------------------------------------------------------
# Configuración de Fabric
# ------------------------------------------------------------

TEST_NETWORK="$HOME/hyperledger/fabric-samples/test-network-4org"

CHAINCODE_NAME="uacm"
CHANNEL_NAME="uacmchannel"

ORDERER_ADDRESS="localhost:7050"
ORDERER_HOSTNAME="orderer.example.com"

ORDERER_CA="$TEST_NETWORK/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

REGISTRO_MSP="RegistroEscolarMSP"

REGISTRO_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/users/Admin@registroescolar.uacm.edu.mx/msp"

REGISTRO_PEER="peer0.registroescolar.uacm.edu.mx:7051"

REGISTRO_TLS="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/peers/peer0.registroescolar.uacm.edu.mx/tls/ca.crt"

SS_PEER="peer0.serviciosocial.uacm.edu.mx:8051"

SS_TLS="$TEST_NETWORK/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/peers/peer0.serviciosocial.uacm.edu.mx/tls/ca.crt"

CERT_PEER="peer0.certificacion.uacm.edu.mx:9051"

CERT_TLS="$TEST_NETWORK/organizations/peerOrganizations/certificacion.uacm.edu.mx/peers/peer0.certificacion.uacm.edu.mx/tls/ca.crt"

TIT_PEER="peer0.titulacion.uacm.edu.mx:10051"

TIT_TLS="$TEST_NETWORK/organizations/peerOrganizations/titulacion.uacm.edu.mx/peers/peer0.titulacion.uacm.edu.mx/tls/ca.crt"

# ------------------------------------------------------------
# Configurar identidad
# ------------------------------------------------------------

usar_identidad() {

    export CORE_PEER_LOCALMSPID="$1"
    export CORE_PEER_MSPCONFIGPATH="$2"
    export CORE_PEER_ADDRESS="$3"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_ROOTCERT_FILE="$4"

    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE
}

# ------------------------------------------------------------
# Invocar transacción
# ------------------------------------------------------------

invocar() {

    local funcion="$1"
    shift

    peer chaincode invoke \
        -o "$ORDERER_ADDRESS" \
        --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
        --tls \
        --cafile "$ORDERER_CA" \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        --peerAddresses "$REGISTRO_PEER" \
        --tlsRootCertFiles "$REGISTRO_TLS" \
        --peerAddresses "$SS_PEER" \
        --tlsRootCertFiles "$SS_TLS" \
        --peerAddresses "$CERT_PEER" \
        --tlsRootCertFiles "$CERT_TLS" \
        --peerAddresses "$TIT_PEER" \
        --tlsRootCertFiles "$TIT_TLS" \
        -c "{\"function\":\"$funcion\",\"Args\":[$(printf '"%s",' "$@" | sed 's/,$//')]}" \
        --waitForEvent
}

# ------------------------------------------------------------
# Consultar expediente
# ------------------------------------------------------------

consultar() {

    peer chaincode query \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$MATRICULA\"]}"
}

# ------------------------------------------------------------
# Obtener estado actual
# ------------------------------------------------------------

obtener_estado() {

    consultar | jq -r '.estadoActual'
}

# ------------------------------------------------------------
# Obtener TxID de una transición
# ------------------------------------------------------------

obtener_txid_transicion() {

    local evento="$1"

    consultar |
        jq -r --arg evento "$evento" '
            .historialTransiciones[]
            | select(.tipo == "TRANSICION" and .evento == $evento)
            | .txId
        ' |
        tail -n 1
}

# ============================================================
# INICIO
# ============================================================

echo
echo "============================================================"
echo "PRUEBA - RECTIFICACIÓN BÁSICA"
echo "============================================================"
echo
echo "Matrícula: $MATRICULA"
echo

# ------------------------------------------------------------
# 1. Registrar inscripción
# ------------------------------------------------------------

echo "[1/6] Registrando inscripción..."

usar_identidad \
    "$REGISTRO_MSP" \
    "$REGISTRO_MSP_PATH" \
    "$REGISTRO_PEER" \
    "$REGISTRO_TLS"

invocar "RegistrarInscripcion" "$MATRICULA"

echo "      OK"
echo

# ------------------------------------------------------------
# 2. Validar documentos
# ------------------------------------------------------------

echo "[2/6] Validando documentos..."

invocar "ValidarDocumentos" "$MATRICULA"

echo "      OK"
echo

# ------------------------------------------------------------
# 3. Confirmar ACTIVO
# ------------------------------------------------------------

echo "[3/6] Confirmando ACTIVO..."

invocar "ConfirmarActivo" "$MATRICULA"

echo "      OK"
echo

# ------------------------------------------------------------
# 4. Obtener TxID de ConfirmarActivo
# ------------------------------------------------------------

echo "[4/6] Obteniendo TxID de ACTIVO_CONFIRMADO..."

TXID_TRANSICION="$(
    obtener_txid_transicion "ACTIVO_CONFIRMADO"
)"

if [[ -z "$TXID_TRANSICION" || "$TXID_TRANSICION" == "null" ]]; then
    echo "ERROR: no se encontró la transición ACTIVO_CONFIRMADO."
    exit 1
fi

echo "      TxID: $TXID_TRANSICION"
echo

# ------------------------------------------------------------
# 5. Rectificar transición
# ------------------------------------------------------------

echo "[5/6] Rectificando transición..."

invocar \
    "RectificarTransicion" \
    "$MATRICULA" \
    "$TXID_TRANSICION"

echo "      OK"
echo

# ------------------------------------------------------------
# 6. Verificar resultado
# ------------------------------------------------------------

echo "[6/6] Verificando estado final..."

ESTADO_FINAL="$(obtener_estado)"

echo "      Estado actual: $ESTADO_FINAL"

if [[ "$ESTADO_FINAL" != "DOC_VALIDADO" ]]; then
    echo
    echo "RESULTADO: FAIL"
    echo "Se esperaba DOC_VALIDADO."
    exit 1
fi

echo
echo "============================================================"
echo "RESULTADO: PASS"
echo "============================================================"
echo
echo "La transición ACTIVO_CONFIRMADO fue rectificada correctamente."
echo "Estado restaurado: DOC_VALIDADO"
echo
