#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain
# Simulación del Camino F del MED-EC
#
# Caso inválido:
# Se intenta emitir el título sin haber emitido el certificado.
#
# Resultado esperado:
# El chaincode debe rechazar la operación.
# ================================================================================

set -e

# ------------------------------------------------------------------------------
# Parámetros de entrada
# ------------------------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo
    echo "Uso:"
    echo "    ./simular_camino_F.sh <MATRICULA>"
    echo
    echo "Ejemplo:"
    echo "    ./simular_camino_F.sh 11-011-0654"
    echo
    exit 1
fi

MATRICULA="$1"

echo "================================================================================"
echo "Simulación MED-EC - Camino F"
echo
echo "INSCRITO"
echo "      ↓"
echo "DOC_VALIDADO"
echo "      ↓"
echo "ACTIVO"
echo "      ↓"
echo "SS_EN_CURSO"
echo "      ↓"
echo "SS_LIBERADO"
echo "      ↓"
echo "TITULADO (Caso inválido)"
echo
echo "Matrícula : $MATRICULA"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Evidencias
# ------------------------------------------------------------------------------

HASH_INSCR=$(echo -n "${MATRICULA}_FOL-2026-INSCRIPCION" | sha256sum | awk '{print $1}')
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_ACTIVO=$(echo -n "${MATRICULA}_FOL-2026-ACTIVO" | sha256sum | awk '{print $1}')
HASH_SS_INI=$(echo -n "${MATRICULA}_FOL-2026-SS-INICIO" | sha256sum | awk '{print $1}')
HASH_SS_LIB=$(echo -n "${MATRICULA}_FOL-2026-SS-LIBERADO" | sha256sum | awk '{print $1}')
HASH_TITULO=$(echo -n "${MATRICULA}_FOL-2026-TITULACION" | sha256sum | awk '{print $1}')

# ------------------------------------------------------------------------------
# Configuración Fabric
# ------------------------------------------------------------------------------

NETWORK_DIR="/home/rafa/hyperledger/fabric-samples/test-network"

export PATH="/home/rafa/hyperledger/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="/home/rafa/hyperledger/fabric-samples/config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_ARGS="-o localhost:7050 \
--ordererTLSHostnameOverride orderer.example.com \
--tls \
--cafile $NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"

CHANNEL_ARGS="-C canal-uacm -n uacm-contract"

PEERS_ARGS="\
--peerAddresses localhost:7051 \
--tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
--peerAddresses localhost:9051 \
--tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

# ------------------------------------------------------------------------------
# Organizaciones
# ------------------------------------------------------------------------------

cargar_org1() {
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:7051
}

cargar_org2() {
    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
    export CORE_PEER_ADDRESS=localhost:9051
}

cd "$NETWORK_DIR"

# ------------------------------------------------------------------------------
# ETAPA 1: Registro Escolar
# ------------------------------------------------------------------------------

cargar_org1

echo
echo "========== ETAPA 1: Registro Escolar =========="

echo "CU-01 Registrar trayectoria académica"

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"RegistrarInscripcion\",\"$MATRICULA\",\"$HASH_INSCR\"]}"

sleep 3

echo "CU-02 Validar documentación"

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"ValidarDocumentos\",\"$MATRICULA\",\"$HASH_DOCS\"]}"

sleep 3

# ------------------------------------------------------------------------------
# ETAPA 2: Confirmación de ACTIVO
# ------------------------------------------------------------------------------

cargar_org2

echo
echo "========== ETAPA 2: Confirmación de ACTIVO =========="

echo "CU-03 Confirmar activo"

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"ConfirmarActivo\",\"$MATRICULA\",\"$HASH_ACTIVO\"]}"

sleep 3

# ------------------------------------------------------------------------------
# ETAPA 3: Servicio Social
# ------------------------------------------------------------------------------

cargar_org1

echo
echo "========== ETAPA 3: Servicio Social =========="

echo "CU-04 Registrar inicio del Servicio Social"

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"IniciarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_INI\"]}"

sleep 3

echo "CU-05 Registrar liberación del Servicio Social"

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"LiberarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_LIB\"]}"

sleep 3

# ------------------------------------------------------------------------------
# ETAPA 4: Intento inválido de titulación
# ------------------------------------------------------------------------------

cargar_org2

echo
echo "========== ETAPA 4: Validación de titulación =========="

echo "CU-07 Emitir título (debe fallar)"
echo "El expediente tiene Servicio Social liberado, pero no cuenta con certificado emitido."

set +e

peer chaincode invoke \
    $ORDERER_ARGS \
    $CHANNEL_ARGS \
    $PEERS_ARGS \
    -c "{\"Args\":[\"EmitirTitulo\",\"$MATRICULA\",\"$HASH_TITULO\"]}"

RESULTADO=$?

set -e

echo

if [ $RESULTADO -eq 0 ]; then
    echo "ERROR: El título fue emitido cuando debía rechazarse."
    exit 1
else
    echo "OK: El MED-EC rechazó correctamente la operación."
    echo "No existe evidencia de CERTIFICADO_EMITIDO."
fi

# ------------------------------------------------------------------------------
# EXPEDIENTE FINAL
# ------------------------------------------------------------------------------

echo
echo "========== EXPEDIENTE FINAL =========="

peer chaincode query \
    $CHANNEL_ARGS \
    -c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'

echo
echo "Simulación finalizada."