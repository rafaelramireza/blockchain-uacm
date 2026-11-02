
#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# CONSULTAR EXPEDIENTES POR ESTADO
#
# Consulta CouchDB directamente en modo de solo lectura.
# No modifica el chaincode ni el World State.
#
# Uso:
#   ./consultar_expedientes_estado.sh ESTADO
# ============================================================

ESTADOS_VALIDOS=(
    INSCRITO
    DOC_VALIDADO
    ACTIVO
    CERTIFICADO
    SS_EN_CURSO
    SS_LIBERADO
    TITULADO
)

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 ESTADO"
    printf 'Estados válidos:\n'
    printf '  %s\n' "${ESTADOS_VALIDOS[@]}"
    exit 1
fi

ESTADO="$1"
VALIDO=false

for estado_valido in "${ESTADOS_VALIDOS[@]}"; do
    if [[ "$ESTADO" == "$estado_valido" ]]; then
        VALIDO=true
        break
    fi
done

if [[ "$VALIDO" != true ]]; then
    echo "ERROR: estado no válido: $ESTADO"
    printf 'Estados válidos:\n'
    printf '  %s\n' "${ESTADOS_VALIDOS[@]}"
    exit 1
fi

# Configuración de CouchDB según compose-test-net.yaml.
CONTENEDOR="couchdb.registroescolar"
BASE_DATOS="uacmchannel_uacm"

export COUCHDB_USER="${COUCHDB_USER:-admin}"
export COUCHDB_PASSWORD="${COUCHDB_PASSWORD:-adminpw}"

echo
echo "============================================================"
echo "EXPEDIENTES EN ESTADO: $ESTADO"
echo "============================================================"
echo
echo "Consultando CouchDB en modo de solo lectura..."
echo

# Construir el selector JSON sin interpolar directamente el estado.
RESPUESTA=$(
    jq -n --arg estado "$ESTADO" '{
        selector: {
            docType: "EXPEDIENTE",
            estadoActual: $estado
        },
        fields: [
            "_id",
            "id",
            "estadoActual",
            "historialTransiciones"
        ],
        limit: 10000
    }' |
    docker exec -i \
        -e COUCHDB_USER \
        -e COUCHDB_PASSWORD \
        "$CONTENEDOR" \
        sh -c '
            curl -fsS \
                -u "$COUCHDB_USER:$COUCHDB_PASSWORD" \
                -H "Content-Type: application/json" \
                -X POST \
                "http://localhost:5984/'"$BASE_DATOS"'/_find" \
                -d @-
        '
)

# Verificar que la respuesta tenga la estructura esperada.
if ! jq -e '.docs | type == "array"' >/dev/null <<< "$RESPUESTA"; then
    echo "ERROR: CouchDB no devolvió una lista válida de documentos."
    exit 1
fi

# Mostrar el historial real de transiciones.
# Un campo ausente o nulo se presenta como lista vacía,
# únicamente para la salida; el documento no se modifica.
jq -r '
    "TOTAL DE EXPEDIENTES: \(.docs | length)",
    "",

    (
        .docs[] as $expediente |

        "MATRÍCULA: \($expediente.id // "(sin identificador)")",
        "Estado actual: \($expediente.estadoActual // "(sin estado)")",
        "------------------------------------------------------------",
        "HISTORIAL DE TRANSICIONES",

        (
            ($expediente.historialTransiciones // []) as $historial |

            if ($historial | type) != "array" then
                "   ERROR: el historial tiene un formato inesperado."
            elif ($historial | length) == 0 then
                "   No hay transiciones registradas."
            else
                (
                    $historial | to_entries[] |

                    "   Transición \(.key + 1)",
                    "      Evento:       \(.value.evento // "(no disponible)")",
                    "      Estado previo: \(.value.estadoAnterior // "(no disponible)")",
                    "      Estado nuevo:  \(.value.estadoNuevo // "(no disponible)")",
                    "      Emisor:        \(.value.emisor // "(no disponible)")",
                    "      Timestamp:     \(.value.timestamp // "(no disponible)")",
                    "      Hash:          \(.value.hash // "(no disponible)")",
                    "      TX ID:         \(.value.txId // "(no disponible)")",
                    ""
                )
            end
        ),

        "============================================================",
        ""
    )
' <<< "$RESPUESTA"
