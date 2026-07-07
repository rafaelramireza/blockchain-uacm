package chaincode

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/pkg/cid"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// Constantes para los estados de la Máquina de Estados Finitos (FSM)
const (
	EstadoInscrito    = "INSCRITO"
	EstadoDocValidado = "DOC_VALIDADO"
	EstadoSSEnCurso   = "SS_EN_CURSO"
	EstadoSSLiberado  = "SS_LIBERADO"
	EstadoCertificado = "CERTIFICADO"
	EstadoTitulado    = "TITULADO"
	EstadoRevocado    = "REVOCADO"
)

// HashEvidencia define la estructura de respaldo criptográfico off-chain
type HashEvidencia struct {
	Hash      string `json:"hash"`
	Timestamp string `json:"timestamp"`
	Emisor    string `json:"emisor"`
}

// Expediente representa el activo digital del estudiante dentro del World State (CouchDB)
type Expediente struct {
	DocType      string                   `json:"docType"` // Valor fijo: "expediente"
	ID           string                   `json:"id"`      // Corresponde a la matrícula del alumno
	EstadoActual string                   `json:"estadoActual"`
	Evidencias   map[string]HashEvidencia `json:"evidencias"`
}

// QueryFilter define la estructura segura para búsquedas indexadas en CouchDB (Evita Inyección)
type QueryFilter struct {
	EstadoActual string `json:"estadoActual,omitempty"`
	ID           string `json:"id,omitempty"`
}

// SmartContract define la estructura del contrato inteligente de la UACM
type SmartContract struct {
	contractapi.Contract
}

// validarOrg verifica de forma estricta la identidad del emisor mediante su MSPID
func (s *SmartContract) validarOrg(ctx contractapi.TransactionContextInterface, orgEsperada string) error {
	clientMSPID, err := cid.GetMSPID(ctx.GetStub())
	if err != nil {
		return fmt.Errorf("error al obtener MSPID del cliente: %v", err)
	}
	if clientMSPID != orgEsperada {
		return fmt.Errorf("acceso denegado: se requiere la identidad de %s", orgEsperada)
	}
	return nil
}

// getTxTimestampRFC3339 obtiene la marca de tiempo síncrona y determinista del canal
func (s *SmartContract) getTxTimestampRFC3339(ctx contractapi.TransactionContextInterface) (string, error) {
	txTimestamp, err := ctx.GetStub().GetTxTimestamp()
	if err != nil {
		return "", fmt.Errorf("error al obtener el timestamp del canal: %v", err)
	}
	return time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).UTC().Format(time.RFC3339), nil
}

// verificarIntegridadHitosPrevios valida de manera autónoma el orden secuencial de la FSM
func (s *SmartContract) verificarIntegridadHitosPrevios(expediente *Expediente) error {
	switch expediente.EstadoActual {
	case EstadoInscrito:
		if _, ok := expediente.Evidencias["INSCRIPCION"]; !ok {
			return fmt.Errorf("falta evidencia de inscripción")
		}
	case EstadoDocValidado:
		if _, ok := expediente.Evidencias["VALIDACION_DOC"]; !ok {
			return fmt.Errorf("falta evidencia de validación documental")
		}
	case EstadoSSEnCurso:
		if _, ok := expediente.Evidencias["INICIO_SS"]; !ok {
			return fmt.Errorf("falta evidencia de inicio de servicio social")
		}
	case EstadoSSLiberado:
		if _, ok := expediente.Evidencias["LIBERACION_SS"]; !ok {
			return fmt.Errorf("falta evidencia de liberación de servicio social")
		}
	case EstadoCertificado:
		if _, ok := expediente.Evidencias["CERTIFICACION"]; !ok {
			return fmt.Errorf("falta evidencia de certificación académica")
		}
	}
	return nil
}

// RegistrarInscripcion inicializa el expediente en el libro mayor (Gobernado por Org1MSP)
func (s *SmartContract) RegistrarInscripcion(ctx contractapi.TransactionContextInterface, matricula string, hashInscripcion string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	existe, err := s.ExpedienteExiste(ctx, matricula)
	if err != nil {
		return err
	}
	if existe {
		return fmt.Errorf("el expediente con matrícula %s ya se encuentra registrado", matricula)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente := &Expediente{
		DocType:      "expediente",
		ID:           matricula,
		EstadoActual: EstadoInscrito,
		Evidencias:   make(map[string]HashEvidencia),
	}

	expediente.Evidencias["INSCRIPCION"] = HashEvidencia{
		Hash:      hashInscripcion,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar expediente de inscripción: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// ValidarDocumentos avanza el flujo institucional tras validar la documentación soporte
func (s *SmartContract) ValidarDocumentos(ctx contractapi.TransactionContextInterface, matricula string, hashDocumental string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoInscrito {
		return fmt.Errorf("transición inválida: el expediente no se encuentra en estado INSCRITO")
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["VALIDACION_DOC"] = HashEvidencia{
		Hash:      hashDocumental,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}
	expediente.EstadoActual = EstadoDocValidado

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar validación de documentos: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// IniciarServicioSocial registra el comienzo de las actividades comunitarias obligatorias
func (s *SmartContract) IniciarServicioSocial(ctx contractapi.TransactionContextInterface, matricula string, hashInicioSS string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoDocValidado {
		return fmt.Errorf("transición inválida: los documentos no han sido validados")
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["INICIO_SS"] = HashEvidencia{
		Hash:      hashInicioSS,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}
	expediente.EstadoActual = EstadoSSEnCurso

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar inicio de servicio social: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// LiberarServicioSocial asienta la culminación satisfactoria del servicio social
func (s *SmartContract) LiberarServicioSocial(ctx contractapi.TransactionContextInterface, matricula string, hashLiberacionSS string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoSSEnCurso {
		return fmt.Errorf("transición inválida: el servicio social no se encuentra en curso")
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["LIBERACION_SS"] = HashEvidencia{
		Hash:      hashLiberacionSS,
		Timestamp: timeStr,
		Emisor:    "Org1MSP",
	}
	expediente.EstadoActual = EstadoSSLiberado

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar liberación de servicio social: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// GenerarCertificado emite el estatus certificado (Gobernado por Org2MSP, valida hitos previos)
func (s *SmartContract) GenerarCertificado(ctx contractapi.TransactionContextInterface, matricula string, hashCertificado string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoSSLiberado {
		return fmt.Errorf("transición inválida: se requiere la liberación del servicio social")
	}

	if err := s.verificarIntegridadHitosPrevios(expediente); err != nil {
		return fmt.Errorf("fallo de integridad en hitos previos: %v", err)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["CERTIFICACION"] = HashEvidencia{
		Hash:      hashCertificado,
		Timestamp: timeStr,
		Emisor:    "Org2MSP",
	}
	expediente.EstadoActual = EstadoCertificado

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar generación de certificado: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// RegistrarTitulacion consolida el hito terminal y finaliza el ciclo del expediente
func (s *SmartContract) RegistrarTitulacion(ctx contractapi.TransactionContextInterface, matricula string, hashTitulacion string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoCertificado {
		return fmt.Errorf("transición inválida: el expediente debe contar con certificación académica")
	}

	if err := s.verificarIntegridadHitosPrevios(expediente); err != nil {
		return fmt.Errorf("fallo de integridad en hitos de titulación: %v", err)
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["TITULACION"] = HashEvidencia{
		Hash:      hashTitulacion,
		Timestamp: timeStr,
		Emisor:    "Org2MSP",
	}
	expediente.EstadoActual = EstadoTitulado

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar registro de titulación: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// RevocarTitulo anula un título emitido bajo escenarios de fraude académico comprobado
func (s *SmartContract) RevocarTitulo(ctx contractapi.TransactionContextInterface, matricula string, motivo string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
		return err
	}

	expediente, err := s.ConsultarExpediente(ctx, matricula)
	if err != nil {
		return err
	}

	if expediente.EstadoActual != EstadoTitulado {
		return fmt.Errorf("operación denegada: solo se pueden revocar expedientes en estado TITULADO")
	}

	timeStr, err := s.getTxTimestampRFC3339(ctx)
	if err != nil {
		return err
	}

	expediente.Evidencias["REVOCACION"] = HashEvidencia{
		Hash:      fmt.Sprintf("REV_MOTIVO_%s", motivo),
		Timestamp: timeStr,
		Emisor:    "Org2MSP",
	}
	expediente.EstadoActual = EstadoRevocado

	expedienteJSON, err := json.Marshal(expediente)
	if err != nil {
		return fmt.Errorf("error al serializar revocación de título: %v", err)
	}

	return ctx.GetStub().PutState(matricula, expedienteJSON)
}

// ConsultarExpediente recupera el estado actual de un registro de forma directa
func (s *SmartContract) ConsultarExpediente(ctx contractapi.TransactionContextInterface, matricula string) (*Expediente, error) {
	expedienteJSON, err := ctx.GetStub().GetState(matricula)
	if err != nil {
		return nil, fmt.Errorf("error al leer el World State: %v", err)
	}
	if expedienteJSON == nil {
		return nil, fmt.Errorf("el expediente con matrícula %s no existe", matricula)
	}

	var expediente Expediente
	err = json.Unmarshal(expedienteJSON, &expediente)
	if err != nil {
		return nil, fmt.Errorf("error al deserializar el expediente: %v", err)
	}

	return &expediente, nil
}

// ConsultarHistorial audita los cambios históricos con control de accesos por identidad (CID)
func (s *SmartContract) ConsultarHistorial(ctx contractapi.TransactionContextInterface, matricula string) ([]string, error) {
	clientID, err := cid.GetID(ctx.GetStub())
	if err != nil {
		return nil, fmt.Errorf("error al verificar las credenciales del llamador: %v", err)
	}

	// Si el llamador no es el estudiante dueño de la matrícula, debe ser un administrador válido
	if clientID != matricula {
		if errOrg1 := s.validarOrg(ctx, "Org1MSP"); errOrg1 != nil {
			if errOrg2 := s.validarOrg(ctx, "Org2MSP"); errOrg2 != nil {
				return nil, fmt.Errorf("acceso denegado al historial de auditoría")
			}
		}
	}

	resultsIterator, err := ctx.GetStub().GetHistoryForKey(matricula)
	if err != nil {
		return nil, fmt.Errorf("error al recuperar el histórico de transacciones: %v", err)
	}
	defer resultsIterator.Close()

	var historial []string
	for resultsIterator.HasNext() {
		response, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		historial = append(historial, string(response.Value))
	}

	return historial, nil
}

// QueryExpedientesSeguro implementa un builder controlado para CouchDB, mitigando inyecciones
func (s *SmartContract) QueryExpedientesSeguro(ctx contractapi.TransactionContextInterface, filtro *QueryFilter) ([]*Expediente, error) {
	if errOrg1 := s.validarOrg(ctx, "Org1MSP"); errOrg1 != nil {
		if errOrg2 := s.validarOrg(ctx, "Org2MSP"); errOrg2 != nil {
			return nil, fmt.Errorf("acceso denegado para consultas generales")
		}
	}

	selector := map[string]interface{}{"docType": "expediente"}
	if filtro.EstadoActual != "" {
		selector["estadoActual"] = filtro.EstadoActual
	}
	if filtro.ID != "" {
		selector["id"] = filtro.ID
	}

	queryMap := map[string]interface{}{"selector": selector}
	queryBytes, err := json.Marshal(queryMap)
	if err != nil {
		return nil, fmt.Errorf("error al empaquetar filtros de consulta: %v", err)
	}

	resultsIterator, err := ctx.GetStub().GetQueryResult(string(queryBytes))
	if err != nil {
		return nil, fmt.Errorf("error al ejecutar consulta estructurada en CouchDB: %v", err)
	}
	defer resultsIterator.Close()

	var expedientes []*Expediente
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var expediente Expediente
		err = json.Unmarshal(queryResponse.Value, &expediente)
		if err != nil {
			return nil, err
		}
		expedientes = append(expedientes, &expediente)
	}

	return expedientes, nil
}

// ExpedienteExiste es una función auxiliar para verificar llaves sin descargar todo el payload
func (s *SmartContract) ExpedienteExiste(ctx contractapi.TransactionContextInterface, matricula string) (bool, error) {
	expedienteJSON, err := ctx.GetStub().GetState(matricula)
	if err != nil {
		return false, fmt.Errorf("error al consultar existencia en el ledger: %v", err)
	}
	return expedienteJSON != nil, nil
}
