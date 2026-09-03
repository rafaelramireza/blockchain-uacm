#!/usr/bin/env bash

set -euo pipefail
export FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"

# ============================================================
# CONSULTAR EXPEDIENTE
#
# Consulta únicamente el expediente indicado.
#
# No ejecuta ninguna transacción de modificación.
#
# Uso:
#   ./consultar_expediente.sh ##-###-####
#
# Ejemplo:
#   ./consultar_expediente.sh 13-011-1261
#
# ============================================================


# ------------------------------------------------------------
# Validar argumentos
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 ##-###-####"
    echo "Ejemplo: $0 13-011-1261"
    exit 1
fi

MATRICULA="$1"


# ------------------------------------------------------------
# Validar formato de matrícula
# ------------------------------------------------------------

if [[ ! "$MATRICULA" =~ ^[0-9]{2}-[0-9]{3}-[0-9]{4}$ ]]; then
    echo "ERROR: la matrícula debe tener el formato ##-###-####"
    echo "Ejemplo válido: 13-011-1261"
    exit 1
fi


# ------------------------------------------------------------
# Rutas de Hyperledger Fabric
# ------------------------------------------------------------

TEST_NETWORK="$HOME/hyperledger/fabric-samples/test-network-4org"

CHAINCODE_NAME="uacm"
CHANNEL_NAME="uacmchannel"


# ------------------------------------------------------------
# Organización: Registro Escolar
# ------------------------------------------------------------

REGISTRO_MSP="RegistroEscolarMSP"

REGISTRO_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/users/Admin@registroescolar.uacm.edu.mx/msp"

REGISTRO_PEER="peer0.registroescolar.uacm.edu.mx:7051"

REGISTRO_TLS="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/peers/peer0.registroescolar.uacm.edu.mx/tls/ca.crt"


# ============================================================
# CONFIGURAR IDENTIDAD
# ============================================================

export CORE_PEER_LOCALMSPID="$REGISTRO_MSP"
export CORE_PEER_MSPCONFIGPATH="$REGISTRO_MSP_PATH"
export CORE_PEER_ADDRESS="$REGISTRO_PEER"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE="$REGISTRO_TLS"

unset CORE_PEER_TLS_SERVERHOSTOVERRIDE


# ============================================================
# CONSULTAR EXPEDIENTE
# ============================================================

echo
echo "============================================================"
echo "CONSULTA DE EXPEDIENTE"
echo "============================================================"
echo
echo "Matrícula: $MATRICULA"
echo
echo "Consultando World State..."
echo


RESPUESTA=$(peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CHAINCODE_NAME" \
    -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$MATRICULA\"]}")

echo "$RESPUESTA" | jq .


echo
echo "============================================================"
echo "CONSULTA COMPLETADA"
echo "============================================================"
echo