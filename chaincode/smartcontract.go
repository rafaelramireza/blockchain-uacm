package chaincode

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/pkg/cid"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ============================================================================
// CONSTANTES DE ESTADO (MÁQUINA DE ESTADOS FINITOS)
// ============================================================================

const (
	EstadoInscrito      = "INSCRITO"
	EstadoDocsValidados = "DOC_VALIDADO"
	EstadoSSEnCurso     = "SS_EN_CURSO"
	EstadoSSLiberado    = "SS_LIBERADO"
	EstadoCertificado   = "CERTIFICADO"
	EstadoTitulado      = "TITULADO"
)

// ============================================================================
// ESTRUCTURAS DE DATOS (MODELO DE DOMINIO)
// ============================================================================

// HashEvidencia representa el registro inmutable de un hito administrativo.
// Almacena el identificador criptográfico del documento soporte y sus metadatos.
type HashEvidencia struct {
	Hash      string `json:"hash"`      // Hash SHA-256 del documento soporte (off-chain)
	Timestamp string `json:"timestamp"` // Fecha y hora de registro en formato RFC3339 UTC
	Emisor    string `json:"emisor"`    // Identificador MSP de la organización que valida
}

// Expediente define el activo digital del estudiante dentro del World State.
// Aplica el enfoque de minimización de datos al omitir Datos Personales (PII).
type Expediente struct {
	DocType      string                   `json:"docType"`      // Discriminador de tipo de documento ("expediente")
	ID           string                   `json:"id"`           // Clave Primaria: Matrícula oficial del estudiante
	EstadoActual string                   `json:"estadoActual"` // Estado operativo vigente en la FSM
	Evidencias   map[string]HashEvidencia `json:"evidencias"`   // Colección histórica de hitos acreditados
}

// SmartContract define el orquestador logicial para la validación de títulos.
type SmartContract struct {
	contractapi.Contract
}

// ============================================================================
// FUNCIONES AUXILIARES Y VALIDACIONES DE SEGURIDAD
// ============================================================================

// getTxTimestampRFC3339 extrae de manera determinista la marca de tiempo de la propuesta.
// Previene fallas de consenso multi-nodo al evitar el uso de relojes locales del Peer.
func (s *SmartContract) getTxTimestampRFC3339(ctx contractapi.TransactionContextInterface) (string, error) {
	txTimestamp, err := ctx.GetStub().GetTxTimestamp()
	if err != nil {
		return "", fmt.Errorf("error al obtener el timestamp del canal: %v", err)
	}
	return time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).UTC().Format(time.RFC3339), nil
}

// validarOrg verifica que el llamador de la transacción pertenezca al MSP requerido.
// Implementa el control de acceso basado en roles criptográficos de la red.
func (s *SmartContract) validarOrg(ctx contractapi.TransactionContextInterface, mspIDEsperado string) error {
	clientMSPID, err := cid.GetMSPID(ctx.GetStub())
	if err != nil {
		return fmt.Errorf("error al obtener MSPID: %v", err)
	}
	if clientMSPID != mspIDEsperado {
		return fmt.Errorf("autorizacion denegada: la organizacion %s no tiene permiso para esta accion", clientMSPID)
	}
	return nil
}

// verificarIntegridadHitosPrevios audita el expediente para asegurar la existencia de la cadena completa de bloques.
func (s *SmartContract) verificarIntegridadHitosPrevios(expediente *Expediente) error {
	hitos := []string{EstadoInscrito, EstadoDocsValidados, EstadoSSEnCurso, EstadoSSLiberado, EstadoCertificado}
	for _, hito := range hitos {
		evidencia, existe := expediente.Evidencias[hito]
		if !existe || evidencia.Hash == "" {
			return fmt.Errorf("falta hito obligatorio: %s", hito)
		}
	}
	return nil
}

// ============================================================================
// TRANSICIONES DE LA MÁQUINA DE ESTADOS (ESCRITURAS)
// ============================================================================

// RegistrarInscripcion da de alta un expediente nuevo en el World State.
// Asignado exclusivamente a la Coordinación de Registro Escolar (Org1MSP).
func (s *SmartContract) RegistrarInscripcion(ctx contractapi.TransactionContextInterface, id string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	existe, err := s.ExpedienteExiste(ctx, id)
	if err != nil {
		return err
	}
	if existe {
		return fmt.Errorf("el expediente del alumno %s ya existe", id)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente := Expediente{
		DocType:      "expediente",
		ID:           id,
		EstadoActual: EstadoInscrito,
		Evidencias:   make(map[string]HashEvidencia),
	}

	expediente.Evidencias[EstadoInscrito] = HashEvidencia{
		Hash:      "HASH_INICIAL_REGISTRO_SISTEMA",
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(id, expedienteJSON)
}

// ValidarDocumentos asienta el cotejo y validación de la documentación de ingreso física.
// Requiere que el estado previo sea estrictamente INSCRITO (Org1MSP).
func (s *SmartContract) ValidarDocumentos(ctx contractapi.TransactionContextInterface, id string, hashDocumentos string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, id)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoInscrito {
		return fmt.Errorf("transicion invalida: requiere %s, actual es %s", EstadoInscrito, expediente.EstadoActual)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.EstadoActual = EstadoDocsValidados
	expediente.Evidencias[EstadoDocsValidados] = HashEvidencia{
		Hash:      hashDocumentos,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(id, expedienteJSON)
}

// IniciarServicioSocial registra el inicio del Servicio Social en el sistema de control.
// Requiere que el estado previo sea estrictamente DOC_VALIDADO (Org1MSP).
func (s *SmartContract) IniciarServicioSocial(ctx contractapi.TransactionContextInterface, matricula string, hashAutorizacion string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoDocsValidados {
		return fmt.Errorf("transicion invalida: requiere %s, actual es %s", EstadoDocsValidados, expediente.EstadoActual)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.EstadoActual = EstadoSSEnCurso
	expediente.Evidencias[EstadoSSEnCurso] = HashEvidencia{
		Hash:      hashAutorizacion,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// LiberarServicioSocial asienta la constancia de terminación satisfactoria del Servicio Social.
// Requiere que el estado previo sea estrictamente SS_EN_CURSO (Org1MSP).
func (s *SmartContract) LiberarServicioSocial(ctx contractapi.TransactionContextInterface, id string, hashLiberacion string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, id)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoSSEnCurso {
		return fmt.Errorf("transicion invalida: requiere %s, actual es %s", EstadoSSEnCurso, expediente.EstadoActual)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.EstadoActual = EstadoSSLiberado
	expediente.Evidencias[EstadoSSLiberado] = HashEvidencia{
		Hash:      hashLiberacion,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(id, expedienteJSON)
}

// GenerarCertificado emite el certificado total de estudios tras cubrir el plan curricular.
// Conmuta la gobernanza hacia la Coordinación de Titulación de la UACM (Org2MSP).
func (s *SmartContract) GenerarCertificado(ctx contractapi.TransactionContextInterface, matricula string, hashCertificado string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoSSLiberado {
		return fmt.Errorf("error de flujo: requiere %s antes de certificar", EstadoSSLiberado)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.EstadoActual = EstadoCertificado
	expediente.Evidencias[EstadoCertificado] = HashEvidencia{
		Hash:      hashCertificado,
		Timestamp: timeStr,
		Emisor:    "Org2MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// RegistrarTitulacion cierra el ciclo de vida de la FSM al emitir el Grado Académico definitivo.
// Valida de manera obligatoria la integridad de la cadena completa de hitos (Org2MSP).
func (s *SmartContract) RegistrarTitulacion(ctx contractapi.TransactionContextInterface, matricula string, hashActa string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoCertificado {
		return fmt.Errorf("error de flujo: requiere %s, actual es %s", EstadoCertificado, expediente.EstadoActual)
	}

	if err := s.verificarIntegridadHitosPrevios(expediente); err != nil {
		return fmt.Errorf("FALLO DE SEGURIDAD: %v", err)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.EstadoActual = EstadoTitulado
	expediente.Evidencias[EstadoTitulado] = HashEvidencia{
		Hash:      hashActa,
		Timestamp: timeStr,
		Emisor:    "Org2MSP",
	}

	expedienteJSON, _ := json.Marshal(expediente)
	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// ============================================================================
// CANALES DE AUDITORÍA Y CONSULTA (LECTURAS)
// ============================================================================

// ConsultarHistorial recupera la traza histórica completa del expediente directamente del Ledger.
// Ejecuta un escaneo nativo inmutable mediante la API GetHistoryForKey.
func (s *SmartContract) ConsultarHistorial(ctx contractapi.TransactionContextInterface, id string) (string, error) {
	resultsIterator, err := ctx.GetStub().GetHistoryForKey(id)
	if err != nil {
		return "", fmt.Errorf("error al obtener el historial para la matricula %s: %v", id, err)
	}
	defer resultsIterator.Close()

	type HistoricoEntry struct {
		TxId      string      `json:"txId"`
		Value     *Expediente `json:"value"`
		Timestamp string      `json:"timestamp"`
		IsDelete  bool        `json:"isDelete"`
	}

	var records []HistoricoEntry
	for resultsIterator.HasNext() {
		response, err := resultsIterator.Next()
		if err != nil {
			return "", err
		}

		var expediente Expediente
		if !response.IsDelete {
			err = json.Unmarshal(response.Value, &expediente)
			if err != nil {
				return "", err
			}
		}

		txTimestamp := time.Unix(response.Timestamp.Seconds, int64(response.Timestamp.Nanos)).UTC().Format(time.RFC3339)

		record := HistoricoEntry{
			TxId:      response.TxId,
			Value:     &expediente,
			Timestamp: txTimestamp,
			IsDelete:  response.IsDelete,
		}
		records = append(records, record)
	}

	bytes, err := json.Marshal(records)
	if err != nil {
		return "", err
	}

	return string(bytes), nil
}

// ConsultarExpediente extrae el estado actual del alumno desde el World State (CouchDB).
func (s *SmartContract) ConsultarExpediente(ctx contractapi.TransactionContextInterface, id string) (*Expediente, error) {
	expedienteJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("fallo al leer: %v", err)
	}
	if expedienteJSON == nil {
		return nil, fmt.Errorf("el expediente %s no existe", id)
	}

	var expediente Expediente
	err = json.Unmarshal(expedienteJSON, &expediente)
	return &expediente, err
}

// ExpedienteExiste es una función de control que determina la presencia de un activo en el World State.
func (s *SmartContract) ExpedienteExiste(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	expedienteJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, fmt.Errorf("error al leer world state: %v", err)
	}
	return expedienteJSON != nil, nil
}

// QueryExpedientes ejecuta consultas ricas (Rich Queries) nativas sobre la base de datos de CouchDB.
func (s *SmartContract) QueryExpedientes(ctx contractapi.TransactionContextInterface, query string) ([]*Expediente, error) {
	resultsIterator, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var expedientes []*Expediente
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		var expediente Expediente
		_ = json.Unmarshal(queryResponse.Value, &expediente)
		expedientes = append(expedientes, &expediente)
	}
	return expedientes, nil
}
