package chaincode

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/pkg/cid"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const (
	EstadoInscrito    = "INSCRITO"
	EstadoDocValidado = "DOC_VALIDADO"
	EstadoEgresado    = "EGRESADO"
	EstadoTitulado    = "TITULADO"

	EvInscripcion            = "INSCRIPCION"
	EvValidacionDocumental   = "VALIDACION_DOCUMENTAL"
	EvEgresoConfirmado       = "EGRESO_CONFIRMADO"
	EvCertificadoEmitido     = "CERTIFICADO_EMITIDO"
	EvServicioSocialIniciado = "SERVICIO_SOCIAL_INICIADO"
	EvServicioSocialLiberado = "SERVICIO_SOCIAL_LIBERADO"
	EvTitulacionRegistrada   = "TITULACION_REGISTRADA"
)

type HashEvidencia struct {
	Hash      string `json:"hash"`
	Timestamp string `json:"timestamp"`
	Emisor    string `json:"emisor"`
	TxID      string `json:"txId"`
}

type Expediente struct {
	DocType      string `json:"docType"`
	ID           string `json:"id"`
	EstadoActual string `json:"estadoActual"`
	Evidencias   map[string]HashEvidencia `json:"evidencias"`
}

type SmartContract struct {
	contractapi.Contract
}

func (s *SmartContract) validarOrg(ctx contractapi.TransactionContextInterface, mspEsperado string) error {
	clientMSP, err := cid.GetMSPID(ctx.GetStub())
	if err != nil {
		return fmt.Errorf("no fue posible obtener el MSP del invocador: %v", err)
	}
	if clientMSP != mspEsperado {
		return fmt.Errorf("la organización %s no está autorizada para ejecutar esta operación", clientMSP)
	}
	return nil
}

func obtenerTimestamp(ctx contractapi.TransactionContextInterface) string {
	ts, _ := ctx.GetStub().GetTxTimestamp()
	return time.Unix(ts.Seconds, int64(ts.Nanos)).Format(time.RFC3339)
}

func (s *SmartContract) agregarEvidencia(ctx contractapi.TransactionContextInterface, expediente *Expediente, clave, hash, emisor string) {
	expediente.Evidencias[clave] = HashEvidencia{
		Hash: hash, Timestamp: obtenerTimestamp(ctx), Emisor: emisor, TxID: ctx.GetStub().GetTxID(),
	}
}

func (s *SmartContract) guardarExpediente(ctx contractapi.TransactionContextInterface, expediente *Expediente) error {
	b, err := json.Marshal(expediente)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(expediente.ID, b)
}

func (s *SmartContract) RegistrarInscripcion(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil { return err }
	existe, err := s.ExpedienteExiste(ctx, id)
	if err != nil { return err }
	if existe { return fmt.Errorf("el expediente %s ya existe", id) }

	exp := Expediente{
		DocType: "expediente",
		ID: id,
		EstadoActual: EstadoInscrito,
		Evidencias: make(map[string]HashEvidencia),
	}
	s.agregarEvidencia(ctx, &exp, EvInscripcion, hash, "Org1MSP")
	return s.guardarExpediente(ctx, &exp)
}

func (s *SmartContract) ValidarDocumentos(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if exp.EstadoActual != EstadoInscrito { return fmt.Errorf("estado inválido") }
	exp.EstadoActual = EstadoDocValidado
	s.agregarEvidencia(ctx, exp, EvValidacionDocumental, hash, "Org1MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) ConfirmarEgreso(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if exp.EstadoActual != EstadoDocValidado { return fmt.Errorf("estado inválido") }
	exp.EstadoActual = EstadoEgresado
	s.agregarEvidencia(ctx, exp, EvEgresoConfirmado, hash, "Org1MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) EmitirCertificado(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if exp.EstadoActual != EstadoEgresado { return fmt.Errorf("estado inválido") }
	if _, ok := exp.Evidencias[EvCertificadoEmitido]; ok { return fmt.Errorf("certificado ya emitido") }
	s.agregarEvidencia(ctx, exp, EvCertificadoEmitido, hash, "Org2MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) IniciarServicioSocial(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if exp.EstadoActual != EstadoEgresado { return fmt.Errorf("estado inválido") }
	if _, ok := exp.Evidencias[EvServicioSocialIniciado]; ok { return fmt.Errorf("ya iniciado") }
	s.agregarEvidencia(ctx, exp, EvServicioSocialIniciado, hash, "Org1MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) LiberarServicioSocial(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org1MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if _, ok := exp.Evidencias[EvServicioSocialIniciado]; !ok { return fmt.Errorf("servicio social no iniciado") }
	if _, ok := exp.Evidencias[EvServicioSocialLiberado]; ok { return fmt.Errorf("ya liberado") }
	s.agregarEvidencia(ctx, exp, EvServicioSocialLiberado, hash, "Org1MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) RegistrarTitulacion(ctx contractapi.TransactionContextInterface, id, hash string) error {
	if err := s.validarOrg(ctx, "Org2MSP"); err != nil { return err }
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return err }
	if exp.EstadoActual != EstadoEgresado { return fmt.Errorf("estado inválido") }
	if _, ok := exp.Evidencias[EvCertificadoEmitido]; !ok { return fmt.Errorf("falta certificado") }
	if _, ok := exp.Evidencias[EvServicioSocialLiberado]; !ok { return fmt.Errorf("falta liberación de servicio social") }
	exp.EstadoActual = EstadoTitulado
	s.agregarEvidencia(ctx, exp, EvTitulacionRegistrada, hash, "Org2MSP")
	return s.guardarExpediente(ctx, exp)
}

func (s *SmartContract) ConsultarExpediente(ctx contractapi.TransactionContextInterface, id string) (*Expediente, error) {
	b, err := ctx.GetStub().GetState(id)
	if err != nil { return nil, err }
	if b == nil { return nil, fmt.Errorf("expediente no existe") }
	var exp Expediente
	if err := json.Unmarshal(b, &exp); err != nil { return nil, err }
	return &exp, nil
}

func (s *SmartContract) ExpedienteExiste(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	b, err := ctx.GetStub().GetState(id)
	return b != nil, err
}

func (s *SmartContract) ConsultarEstado(ctx contractapi.TransactionContextInterface, id string) (string, error) {
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return "", err }
	return exp.EstadoActual, nil
}

func (s *SmartContract) ConsultarEvidencias(ctx contractapi.TransactionContextInterface, id string) (map[string]HashEvidencia, error) {
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return nil, err }
	return exp.Evidencias, nil
}

func (s *SmartContract) VerificarEvidencia(ctx contractapi.TransactionContextInterface, id, evento string) (bool, error) {
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return false, err }
	_, ok := exp.Evidencias[evento]
	return ok, nil
}

func (s *SmartContract) ListarEventos(ctx contractapi.TransactionContextInterface, id string) ([]string, error) {
	exp, err := s.ConsultarExpediente(ctx, id)
	if err != nil { return nil, err }
	var eventos []string
	for k := range exp.Evidencias {
		eventos = append(eventos, k)
	}
	return eventos, nil
}
