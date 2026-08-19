#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain
# Simulación del Camino C del MED-EC
#
# Caso inválido:
# Se intenta registrar la titulación sin haber liberado el Servicio Social.
#
# Resultado esperado:
# El chaincode debe rechazar la operación.
# ================================================================================

set -e

#------------------------------------------------------------------------------
# Parámetros de entrada
#------------------------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo
    echo "Uso:"
    echo "    ./simular_camino_C.sh <MATRICULA>"

    echo
    echo "Ejemplo:"
    echo "    ./simular_camino_C.sh 11-011-0654"
    echo
    exit 1
fi

MATRICULA="$1"

echo "=============================================================="
echo "Simulación MED-EC - Camino C:INSCRITO
      ↓
DOCUMENTACIÓN_VALIDADA
      ↓
ACTIVO
      ↓
CERTIFICADO
      ↓
TITULACIÓN (Caso inválido)"
echo "Matrícula : $MATRICULA"
echo "=============================================================="

#------------------------------------------------------------------------------
# Evidencias Off-Chain
#------------------------------------------------------------------------------

HASH_INSCR=$(echo -n "${MATRICULA}_FOL-2026-INSCRIPCION" | sha256sum | awk '{print $1}')
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_EGRESO=$(echo -n "${MATRICULA}_FOL-2026-EGRESO" | sha256sum | awk '{print $1}')
HASH_CERT=$(echo -n "${MATRICULA}_FOL-2026-CERTIFICADO" | sha256sum | awk '{print $1}')
HASH_ACTA=$(echo -n "${MATRICULA}_FOL-2026-TITULACION" | sha256sum | awk '{print $1}')

#------------------------------------------------------------------------------
# Configuración Fabric
#------------------------------------------------------------------------------

NETWORK_DIR="/home/rafa/hyperledger/fabric-samples/test-network"

export PATH="/home/rafa/hyperledger/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="/home/rafa/hyperledger/fabric-samples/config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_ARGS="-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"

CHANNEL_ARGS="-C canal-uacm -n uacm-contract"

PEERS_ARGS="--peerAddresses localhost:7051 \
--tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
--peerAddresses localhost:9051 \
--tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

#------------------------------------------------------------------------------
# Organizaciones
#------------------------------------------------------------------------------

cargar_org1() {

    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:7051

}

cargar_org2() {

    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    export CORE_PEER_ADDRESS=localhost:9051

}

cd "$NETWORK_DIR"

echo
echo "========== ETAPA 1 =========="

cargar_org1

echo "CU-01 Registrar trayectoria"

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

echo
echo "========== ETAPA 2 =========="

cargar_org2

echo "CU-03 Confirmar egreso"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"ConfirmarEgreso\",\"$MATRICULA\",\"$HASH_EGRESO\"]}"

sleep 3

echo
echo "========== ETAPA 3 =========="

echo "CU-06 Emitir certificado"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"EmitirCertificado\",\"$MATRICULA\",\"$HASH_CERT\"]}"

sleep 3

echo
echo "========== ETAPA 4 =========="
echo "Intentando registrar la titulación sin cumplir todas las condiciones..."

echo "CU-07 Registrar titulación (debe fallar)"

set +e

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"RegistrarTitulacion\",\"$MATRICULA\",\"$HASH_ACTA\"]}"

RESULTADO=$?

set -e

echo
if [ $RESULTADO -eq 0 ]; then
    echo "ERROR: La titulación fue aceptada cuando debía rechazarse."
    exit 1
else
    echo "OK: El MED-EC rechazó correctamente la operación."
    echo "La trayectoria no cumplía las condiciones para titularse."
fi

echo
echo "========== EXPEDIENTE FINAL =========="

peer chaincode query \
$CHANNEL_ARGS \
-c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'