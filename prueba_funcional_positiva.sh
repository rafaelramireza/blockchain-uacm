#!/usr/bin/env bash
# Prueba funcional positiva MED-EC (red Fabric de cuatro organizaciones).
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/00_lib_pruebas_medec.sh"
[[ -f "$LIB" ]] || { echo "ERROR: no existe $LIB" >&2; exit 1; }
PREFIJO_MATRICULAS="${PREFIJO_MATRICULAS:-29-007}"
INICIO_MATRICULA="${INICIO_MATRICULA:-1}"
TOTAL=10
source "$LIB"
export PATH="$HOME/hyperledger/fabric-samples/bin:$PATH"
command -v peer >/dev/null && command -v jq >/dev/null && command -v sha256sum >/dev/null || { echo "ERROR: faltan peer, jq o sha256sum." >&2; exit 1; }
[[ "$PREFIJO_MATRICULAS" =~ ^[0-9]{2}-[0-9]{3}$ && "$INICIO_MATRICULA" =~ ^[0-9]+$ ]] || { echo "ERROR: prefijo NN-NNN o inicio inválido." >&2; exit 1; }
(( INICIO_MATRICULA + TOTAL - 1 <= 9999 )) || { echo "ERROR: el rango excede cuatro dígitos." >&2; exit 1; }
STAMP="$(date +%Y%m%d_%H%M%S)"; RUN_DIR="$SCRIPT_DIR/resultados/prueba_funcional_positiva_$STAMP"; mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/ejecucion.log"; CSV="$RUN_DIR/funcionales_positivas.csv"
exec > >(tee -a "$LOG") 2>&1
printf 'caso,matricula,operacion,estado_esperado,estado_obtenido,resultado,txid\n' > "$CSV"
matricula() { printf '%s-%04d' "$PREFIJO_MATRICULAS" "$((INICIO_MATRICULA + $1 - 1))"; }
identidad() { case "$1" in REGISTRO) usar_identidad "$REGISTRO_MSP" "$REGISTRO_MSP_PATH" "$REGISTRO_PEER" "$REGISTRO_TLS";; SS) usar_identidad "$SS_MSP" "$SS_MSP_PATH" "$SS_PEER" "$SS_TLS";; CERT) usar_identidad "$CERT_MSP" "$CERT_MSP_PATH" "$CERT_PEER" "$CERT_TLS";; TIT) usar_identidad "$TIT_MSP" "$TIT_MSP_PATH" "$TIT_PEER" "$TIT_TLS";; esac; }
invocar_ok() { local id="$1" fn="$2" org="$3"; identidad "$org"; invocar "$fn" "$id"; }
estado() { consultar "$1" | jq -er '.estadoActual'; }
verificar() { local actual; actual="$(estado "$1")"; echo "Estado $1: $actual (esperado $2)"; [[ "$actual" == "$2" ]]; }
pre_reg() { invocar_ok "$1" RegistrarInscripcion REGISTRO >/dev/null; }
pre_doc() { pre_reg "$1"; invocar_ok "$1" ValidarDocumentos REGISTRO >/dev/null; }
pre_activo() { pre_doc "$1"; invocar_ok "$1" ConfirmarActivo REGISTRO >/dev/null; }
pre_cert_sslib() { pre_activo "$1"; invocar_ok "$1" EmitirCertificado CERT >/dev/null; invocar_ok "$1" IniciarServicioSocial SS >/dev/null; invocar_ok "$1" LiberarServicioSocial SS >/dev/null; }
objetivo() {
  local n="$1" id="$2" fn="$3" org="$4" esperado="$5" evento="$6" txid actual
  invocar_ok "$id" "$fn" "$org" >/dev/null
  actual="$(estado "$id")"; [[ "$actual" == "$esperado" ]] || { echo "FAIL: $id quedó en $actual; se esperaba $esperado." >&2; return 1; }
  txid="$(obtener_txid_evento "$id" "$evento" || true)"
  [[ -n "$txid" && "$txid" != null ]] || { echo "ERROR: TXID no recuperado para $evento/$id." >&2; return 1; }
  printf '%s,%s,%s,%s,%s,PASS,%s\n' "$n" "$id" "$fn" "$esperado" "$actual" "$txid" >> "$CSV"
  echo "PASS caso $n: $fn / $id / $actual"
}
echo "PRUEBA FUNCIONAL POSITIVA | canal=$CHANNEL_NAME | chaincode=$CHAINCODE_NAME"
echo "Resultados: $RUN_DIR"
for ((i=1;i<=TOTAL;i++)); do id="$(matricula "$i")"; if consultar "$id" >/dev/null 2>&1; then echo "ERROR: $id ya existe; cambie PREFIJO_MATRICULAS o INICIO_MATRICULA." >&2; exit 1; fi; done
# Diez operaciones objetivo en diez matrículas consecutivas; los pasos previos son preparación.
id="$(matricula 1)"; objetivo 1 "$id" RegistrarInscripcion REGISTRO INSCRITO INSCRIPCION
id="$(matricula 2)"; pre_reg "$id"; objetivo 2 "$id" ValidarDocumentos REGISTRO DOC_VALIDADO VALIDACION_DOCUMENTAL
id="$(matricula 3)"; pre_doc "$id"; objetivo 3 "$id" ConfirmarActivo REGISTRO ACTIVO ACTIVO_CONFIRMADO
id="$(matricula 4)"; pre_activo "$id"; objetivo 4 "$id" EmitirCertificado CERT CERTIFICADO CERTIFICADO_EMITIDO
id="$(matricula 5)"; pre_activo "$id"; objetivo 5 "$id" IniciarServicioSocial SS SS_EN_CURSO SERVICIO_SOCIAL_INICIADO
id="$(matricula 6)"; pre_activo "$id"; invocar_ok "$id" IniciarServicioSocial SS >/dev/null; objetivo 6 "$id" LiberarServicioSocial SS SS_LIBERADO SERVICIO_SOCIAL_LIBERADO
id="$(matricula 7)"; pre_cert_sslib "$id"; objetivo 7 "$id" EmitirTitulo TIT TITULADO TITULACION_REGISTRADA
# Se evalúa otra emisión válida de título y después se rectifica esa última transición.
id="$(matricula 8)"; pre_cert_sslib "$id"; objetivo 8 "$id" EmitirTitulo TIT TITULADO TITULACION_REGISTRADA
txid_titulo="$(obtener_txid_evento "$id" TITULACION_REGISTRADA)"; identidad TIT; invocar RectificarTransicion "$id" "$txid_titulo" >/dev/null; verificar "$id" SS_LIBERADO
txid_rect="$(consultar "$id" | jq -er '[.historialTransiciones[] | select(.tipo=="RECTIFICACION") | .txId] | last')"
printf '8R,%s,RectificarTransicion,SS_LIBERADO,SS_LIBERADO,PASS,%s\n' "$id" "$txid_rect" >> "$CSV"
echo "PASS: RectificarTransicion restauró SS_LIBERADO."
id="$(matricula 9)"; pre_activo "$id"; objetivo 9 "$id" EmitirCertificado CERT CERTIFICADO CERTIFICADO_EMITIDO
id="$(matricula 10)"; pre_activo "$id"; invocar_ok "$id" IniciarServicioSocial SS >/dev/null; objetivo 10 "$id" LiberarServicioSocial SS SS_LIBERADO SERVICIO_SOCIAL_LIBERADO
filas="$(awk 'END{print NR-1}' "$CSV")"; fallidas="$(awk -F, 'NR>1 && $6!="PASS"{n++} END{print n+0}' "$CSV")"
echo "Filas de evidencia: $filas; fallidas: $fallidas"; echo "CSV: $CSV"; echo "Log: $LOG"
[[ "$filas" -eq 11 && "$fallidas" -eq 0 ]] || { echo "RESULTADO GLOBAL: FAIL" >&2; exit 1; }
echo "RESULTADO GLOBAL: PASS"
