#!/usr/bin/env bash
# Pruebas funcionales negativas MED-EC. Se exige el mensaje de negocio esperado
# y que la operación rechazada no modifique el expediente.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/00_lib_pruebas_medec.sh"
[[ -f "$LIB" ]] || { echo "ERROR: no existe $LIB" >&2; exit 1; }
PREFIJO_MATRICULAS="${PREFIJO_MATRICULAS:-29-008}"; INICIO_MATRICULA="${INICIO_MATRICULA:-1}"; TOTAL=7
source "$LIB"; export PATH="$HOME/hyperledger/fabric-samples/bin:$PATH"
command -v peer >/dev/null && command -v jq >/dev/null && command -v sha256sum >/dev/null || { echo "ERROR: faltan peer, jq o sha256sum." >&2; exit 1; }
[[ "$PREFIJO_MATRICULAS" =~ ^[0-9]{2}-[0-9]{3}$ && "$INICIO_MATRICULA" =~ ^[0-9]+$ ]] || { echo "ERROR: prefijo NN-NNN o inicio inválido." >&2; exit 1; }
(( INICIO_MATRICULA + TOTAL - 1 <= 9999 )) || { echo "ERROR: el rango excede cuatro dígitos." >&2; exit 1; }
STAMP="$(date +%Y%m%d_%H%M%S)"; RUN_DIR="$SCRIPT_DIR/resultados/prueba_funcional_negativa_$STAMP"; mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/ejecucion.log"; CSV="$RUN_DIR/funcionales_negativas.csv"; exec > >(tee -a "$LOG") 2>&1
printf 'escenario,matricula,operacion,causa_esperada,estado_antes,estado_despues,resultado\n' > "$CSV"
matricula() { printf '%s-%04d' "$PREFIJO_MATRICULAS" "$((INICIO_MATRICULA + $1 - 1))"; }
identidad() { case "$1" in REGISTRO) usar_identidad "$REGISTRO_MSP" "$REGISTRO_MSP_PATH" "$REGISTRO_PEER" "$REGISTRO_TLS";; SS) usar_identidad "$SS_MSP" "$SS_MSP_PATH" "$SS_PEER" "$SS_TLS";; CERT) usar_identidad "$CERT_MSP" "$CERT_MSP_PATH" "$CERT_PEER" "$CERT_TLS";; TIT) usar_identidad "$TIT_MSP" "$TIT_MSP_PATH" "$TIT_PEER" "$TIT_TLS";; esac; }
invocar_ok() { local id="$1" fn="$2" org="$3"; identidad "$org"; invocar "$fn" "$id"; }
estado() { consultar "$1" | jq -er '.estadoActual'; }
pre_reg() { invocar_ok "$1" RegistrarInscripcion REGISTRO >/dev/null; }
pre_doc() { pre_reg "$1"; invocar_ok "$1" ValidarDocumentos REGISTRO >/dev/null; }
pre_activo() { pre_doc "$1"; invocar_ok "$1" ConfirmarActivo REGISTRO >/dev/null; }
pre_cert() { pre_activo "$1"; invocar_ok "$1" EmitirCertificado CERT >/dev/null; }
pre_sslib() { pre_activo "$1"; invocar_ok "$1" IniciarServicioSocial SS >/dev/null; invocar_ok "$1" LiberarServicioSocial SS >/dev/null; }
rechazo() {
  local caso="$1" id="$2" fn="$3" org="$4" esperado="$5" antes="$6"
  local salida rc despues salida_normalizada esperado_normalizado

  shift 6
  identidad "$org"
  echo
  echo "Escenario $caso: $fn para $id; se espera: $esperado"

  set +e
  salida="$(invocar "$fn" "$id" "$@" 2>&1)"
  rc=$?
  set -e

  printf '%s\n' "$salida"

  if (( rc == 0 )); then
    echo "FAIL: la operación fue aceptada." >&2
    printf '%s,%s,%s,%s,%s,ACEPTADA,FAIL\n' \
      "$caso" "$id" "$fn" "$esperado" "$antes" >> "$CSV"
    return 1
  fi

  # Decodificar secuencias octales UTF-8 de la salida del CLI de Fabric.
  salida_normalizada="$(
    printf '%s' "$salida" |
      perl -pe 's/\\([0-7]{3})/chr(oct($1))/ge'
  )"

  esperado_normalizado="$esperado"

  if ! grep -Fq -- "$esperado_normalizado" <<< "$salida_normalizada"; then
    echo "FAIL: error distinto al esperado." >&2
    printf '%s,%s,%s,%s,%s,ERROR_DIFERENTE,FAIL\n' \
      "$caso" "$id" "$fn" "$esperado" "$antes" >> "$CSV"
    return 1
  fi

  if [[ "$antes" == NO_EXISTE ]]; then
    if consultar "$id" >/dev/null 2>&1; then
      echo "FAIL: se creó un expediente tras el rechazo." >&2
      return 1
    fi
    despues=NO_EXISTE
  else
    despues="$(estado "$id")"
    [[ "$despues" == "$antes" ]] || {
      echo "FAIL: el estado cambió a $despues." >&2
      return 1
    }
  fi

  printf '%s,%s,%s,%s,%s,%s,PASS\n' \
    "$caso" "$id" "$fn" "$esperado" "$antes" "$despues" >> "$CSV"

  echo "PASS: rechazo controlado; estado sin cambios ($despues)."
}
echo "PRUEBA FUNCIONAL NEGATIVA | canal=$CHANNEL_NAME | chaincode=$CHAINCODE_NAME"; echo "Resultados: $RUN_DIR"
for ((i=1;i<=TOTAL;i++)); do id="$(matricula "$i")"; if consultar "$id" >/dev/null 2>&1; then echo "ERROR: $id ya existe; cambie PREFIJO_MATRICULAS o INICIO_MATRICULA." >&2; exit 1; fi; done
# Escenario 1A: certificado presente, falta Servicio Social liberado.
id="$(matricula 1)"; pre_cert "$id"; rechazo 1A "$id" EmitirTitulo TIT "el servicio social aún no ha sido liberado" CERTIFICADO
# Escenario 1B: Servicio Social liberado, falta certificado.
id="$(matricula 2)"; pre_sslib "$id"; rechazo 1B "$id" EmitirTitulo TIT "el certificado aún no ha sido registrado" SS_LIBERADO
# Escenario 2: ConfirmarActivo desde INSCRITO.
id="$(matricula 3)"; pre_reg "$id"; rechazo 2 "$id" ConfirmarActivo REGISTRO "el expediente no se encuentra en un estado válido para esta operación" INSCRITO
# Escenario 3: duplicar ValidarDocumentos.
id="$(matricula 4)"; pre_doc "$id"; rechazo 3 "$id" ValidarDocumentos REGISTRO "el expediente no se encuentra en un estado válido para esta operación" DOC_VALIDADO
# Escenario 4: intentar registrar inscripción con identidad de Servicio Social.
id="$(matricula 5)"; rechazo 4 "$id" RegistrarInscripcion SS "la organización no está autorizada para ejecutar esta operación" NO_EXISTE
# Escenario 5: matrícula ya registrada.
id="$(matricula 6)"; pre_reg "$id"; rechazo 5 "$id" RegistrarInscripcion REGISTRO "el expediente $id ya existe" INSCRITO
# Escenario 6: rectificar validación documental después de ConfirmarActivo.
id="$(matricula 7)"; pre_doc "$id"; txid_validacion="$(obtener_txid_evento "$id" VALIDACION_DOCUMENTAL)"; [[ -n "$txid_validacion" && "$txid_validacion" != null ]]
invocar_ok "$id" ConfirmarActivo REGISTRO >/dev/null
rechazo 6 "$id" RectificarTransicion REGISTRO "la transición no puede ser rectificada porque existen operaciones posteriores" ACTIVO "$txid_validacion"
filas="$(awk 'END{print NR-1}' "$CSV")"; fallidas="$(awk -F, 'NR>1 && $7!="PASS"{n++} END{print n+0}' "$CSV")"
echo "Intentos registrados: $filas; fallidos: $fallidas"; echo "CSV: $CSV"; echo "Log: $LOG"
[[ "$filas" -eq 7 && "$fallidas" -eq 0 ]] || { echo "RESULTADO GLOBAL: FAIL" >&2; exit 1; }
echo "RESULTADO GLOBAL: PASS"
