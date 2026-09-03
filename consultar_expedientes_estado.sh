#!/usr/bin/env bash

set -euo pipefail
export FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"

# ============================================================
# CONSULTAR EXPEDIENTES POR ESTADO
#
# Consulta todos los expedientes cuyo estadoActual coincide
# con el estado proporcionado.
#
# Esta operación es únicamente de consulta.
# No modifica el World State.
#
# Uso:
#   ./consultar_expedientes_estado.sh ESTADO
#
# Ejemplos:
#   ./consultar_expedientes_estado.sh INSCRITO
#   ./consultar_expedientes_estado.sh DOC_VALIDADO
#   ./consultar_expedientes_estado.sh ACTIVO
#   ./consultar_expedientes_estado.sh CERTIFICADO
#   ./consultar_expedientes_estado.sh SS_EN_CURSO
#   ./consultar_expedientes_estado.sh SS_LIBERADO
#   ./consultar_expedientes_estado.sh TITULADO
#
# ============================================================


# ------------------------------------------------------------
# Validar argumentos
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 ESTADO"
    echo
    echo "Estados válidos:"
    echo "  INSCRITO"
    echo "  DOC_VALIDADO"
    echo "  ACTIVO"
    echo "  CERTIFICADO"
    echo "  SS_EN_CURSO"
    echo "  SS_LIBERADO"
    echo "  TITULADO"
    exit 1
fi

ESTADO="$1"


# ------------------------------------------------------------
# Validar estado
# ------------------------------------------------------------

case "$ESTADO" in

    INSCRITO|DOC_VALIDADO|ACTIVO|CERTIFICADO|SS_EN_CURSO|SS_LIBERADO|TITULADO)
        ;;

    *)
        echo "ERROR: estado no válido: $ESTADO"
        echo
        echo "Estados válidos:"
        echo "  INSCRITO"
        echo "  DOC_VALIDADO"
        echo "  ACTIVO"
        echo "  CERTIFICADO"
        echo "  SS_EN_CURSO"
        echo "  SS_LIBERADO"
        echo "  TITULADO"
        exit 1
        ;;

esac


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
# CONSULTA
# ============================================================

echo
echo "============================================================"
echo "EXPEDIENTES EN ESTADO: $ESTADO"
echo "============================================================"
echo
echo "Consultando World State..."
echo

RESPUESTA=$(peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CHAINCODE_NAME" \
    -c "{\"function\":\"ConsultarExpedientesPorEstado\",\"Args\":[\"$ESTADO\"]}")

echo "$RESPUESTA" | jq -r '
    "TOTAL DE EXPEDIENTES: \(length)",
    "",

    to_entries[] as $entrada |
    ($entrada.value) as $expediente |

    "EXPEDIENTE \($entrada.key + 1)",
    
    "------------------------------------------------------------",
    "Matrícula:      \($expediente.id)",
    "Estado actual:  \($expediente.estadoActual)",
    "",
    "EVIDENCIAS",
    "------------------------------------------------------------",

    (
        [
            "INSCRIPCION",
            "VALIDACION_DOCUMENTAL",
            "EGRESO_CONFIRMADO",
            "CERTIFICADO_EMITIDO",
            "SERVICIO_SOCIAL_INICIADO",
            "SERVICIO_SOCIAL_LIBERADO",
            "TITULACION_REGISTRADA"
        ]
        | .[] as $tipo
        | select($expediente.evidencias[$tipo] != null)
        | $expediente.evidencias[$tipo] as $evidencia
        | "\($tipo | if . == "EGRESO_CONFIRMADO" then "ACTIVO_CONFIRMADO" else . end)",
          "   Emisor:      \($evidencia.emisor)",
          "   Timestamp:   \($evidencia.timestamp)",
          "   Hash:        \($evidencia.hash)",
          "   TX ID:       \($evidencia.txId)",
          ""
    ),

    "============================================================",
    ""
'