package chaincode

import (
    "encoding/json"
    "fmt"
    "time"

    "github.com/hyperledger/fabric-chaincode-go/pkg/cid"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const (
    EstadoGlobalInscrito    = "INSCRITO"
    EstadoGlobalDocValidado = "DOC_VALIDADO"
    EstadoGlobalTitulado    = "TITULADO"
)

const (
    EstadoCertPendiente   = "PENDIENTE"
    EstadoCertCertificado = "CERTIFICADO"

    EstadoSSPendiente = "PENDIENTE"
    EstadoSSEnCurso   = "SS_EN_CURSO"
    EstadoSSLiberado  = "LIBERADO"
)

type HashEvidencia struct {
    Hash      string `json:"hash"`
    Timestamp string `json:"timestamp"`
    Emisor    string `json:"emisor"`
    TxID      string `json:"txId"`
}

type Expediente struct {
    DocType              string                   `json:"docType"`
    ID                   string                   `json:"id"`
    EstadoGlobal         string                   `json:"estadoGlobal"`
    EstadoCertificacion  string                   `json:"estadoCertificacion"`
    EstadoServicioSocial string                   `json:"estadoServicioSocial"`
    Evidencias           map[string]HashEvidencia `json:"evidencias"`
}

type SmartContract struct {
    contractapi.Contract
}

func (s *SmartContract) validarOrg(ctx contractapi.TransactionContextInterface, mspIDEsperado string) error {
    clientMSPID, err := cid.GetMSPID(ctx.GetStub())
    if err != nil {
        return fmt.Errorf("error al obtener material criptográfico del MSP: %v", err)
    }
    if clientMSPID != mspIDEsperado {
        return fmt.Errorf("autorización denegada: la organización %s no tiene competencia operativa para este evento (RN-10)", clientMSPID)
    }
    return nil
}

func (s *SmartContract) RegistrarInscripcion(ctx contractapi.TransactionContextInterface, id string, hashInscripcion string) error {
    if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
        return err
    }

    existe, err := s.ExpedienteExiste(ctx, id)
    if err != nil {
        return err
    }
    if existe {
        return fmt.Errorf("el identificador de expediente %s ya se encuentra registrado en la red", id)
    }

    // Estructura anonimizada pura (Criterio 4.5.1 de Minimización de Datos)
    expediente := Expediente{
        DocType:              "expediente",
        ID:                   id,
        EstadoGlobal:         EstadoGlobalInscrito,
        EstadoCertificacion:  EstadoCertPendiente,
        EstadoServicioSocial: EstadoSSPendiente,
        Evidencias:           make(map[string]HashEvidencia),
    }

    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["INSCRIPCION"] = HashEvidencia{
        Hash:      hashInscripcion,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org1MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) ValidarDocumentos(ctx contractapi.TransactionContextInterface, id string, hashDocumentos string) error {
    if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
        return err
    }

    expediente, err := s.ConsultarExpediente(ctx, id)
    if err != nil {
        return err
    }

    if expediente.EstadoGlobal != EstadoGlobalInscrito {
        return fmt.Errorf("transición rechazada por MED-EC: requiere estado global %s, el actual es %s (RN-02)", EstadoGlobalInscrito, expediente.EstadoGlobal)
    }

    expediente.EstadoGlobal = EstadoGlobalDocValidado
    
    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["VALIDACION_DOC"] = HashEvidencia{
        Hash:      hashDocumentos,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org1MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) IniciarServicioSocial(ctx contractapi.TransactionContextInterface, id string, hashAutorizacion string) error {
    if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
        return err
    }

    expediente, err := s.ConsultarExpediente(ctx, id)
    if err != nil {
        return err
    }

    if expediente.EstadoGlobal != EstadoGlobalDocValidado {
        return fmt.Errorf("transición inválida: el expediente debe estar en estado %s para iniciar Servicio Social (RN-04)", EstadoGlobalDocValidado)
    }

    expediente.EstadoServicioSocial = EstadoSSEnCurso
    
    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["INICIO_SS"] = HashEvidencia{
        Hash:      hashAutorizacion,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org1MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) LiberarServicioSocial(ctx contractapi.TransactionContextInterface, id string, hashLiberacion string) error {
    if err := s.validarOrg(ctx, "Org1MSP"); err != nil {
        return err
    }

    expediente, err := s.ConsultarExpediente(ctx, id)
    if err != nil {
        return err
    }

    if expediente.EstadoServicioSocial != EstadoSSEnCurso {
        return fmt.Errorf("transición rechazada: el subproceso debe estar %s, el estado actual es %s (RN-05)", EstadoSSEnCurso, expediente.EstadoServicioSocial)
    }

    expediente.EstadoServicioSocial = EstadoSSLiberado
    
    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["LIBERACION_SS"] = HashEvidencia{
        Hash:      hashLiberacion,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org1MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) RegistrarCertificacion(ctx contractapi.TransactionContextInterface, id string, hashCertificado string) error {
    if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
        return err
    }

    expediente, err := s.ConsultarExpediente(ctx, id)
    if err != nil {
        return err
    }

    if expediente.EstadoGlobal != EstadoGlobalDocValidado {
        return fmt.Errorf("transición inválida: el expediente debe estar en estado %s para recibir Certificación Académica", EstadoGlobalDocValidado)
    }

    expediente.EstadoCertificacion = EstadoCertCertificado
    
    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["CERTIFICACION"] = HashEvidencia{
        Hash:      hashCertificado,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org2MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) RegistrarTitulacion(ctx contractapi.TransactionContextInterface, id string, hashActa string) error {
    if err := s.validarOrg(ctx, "Org2MSP"); err != nil {
        return err
    }

    // Removido bloque mock artificial de Caliper para mantener rigor científico
    expediente, err := s.ConsultarExpediente(ctx, id)
    if err != nil {
        return err
    }

    // Validación estricta de Compuertas Lógicas Concurrentes (Rule RN-06 / RF-20)
    if expediente.EstadoGlobal != EstadoGlobalDocValidado {
        return fmt.Errorf("interbloqueo: el expediente debe estar en estado %s, actual: %s", EstadoGlobalDocValidado, expediente.EstadoGlobal)
    }
    if expediente.EstadoCertificacion != EstadoCertCertificado {
        return fmt.Errorf("interbloqueo: el subproceso de Certificación debe ser %s, actual: %s", EstadoCertCertificado, expediente.EstadoCertificacion)
    }
    if expediente.EstadoServicioSocial != EstadoSSLiberado {
        return fmt.Errorf("interbloqueo: el subproceso de Servicio Social debe ser %s, actual: %s", EstadoSSLiberado, expediente.EstadoServicioSocial)
    }

    hitosRequeridos := []string{"VALIDACION_DOC", "CERTIFICACION", "LIBERACION_SS"}
    for _, hito := range hitosRequeridos {
        if _, existe := expediente.Evidencias[hito]; !existe {
            return fmt.Errorf("falla de integridad: no se localizó la evidencia criptográfica del hito %s (RF-20)", hito)
        }
    }

    expediente.EstadoGlobal = EstadoGlobalTitulado
    
    txTimestamp, _ := ctx.GetStub().GetTxTimestamp()
    expediente.Evidencias["TITULACION"] = HashEvidencia{
        Hash:      hashActa,
        Timestamp: time.Unix(txTimestamp.Seconds, int64(txTimestamp.Nanos)).Format(time.RFC3339),
        Emisor:    "Org2MSP",
        TxID:      ctx.GetStub().GetTxID(),
    }

    expedienteJSON, _ := json.Marshal(expediente)
    return ctx.GetStub().PutState(id, expedienteJSON)
}

func (s *SmartContract) ConsultarExpediente(ctx contractapi.TransactionContextInterface, id string) (*Expediente, error) {
    expedienteJSON, err := ctx.GetStub().GetState(id)
    if err != nil {
        return nil, fmt.Errorf("error de lectura en World State: %v", err)
    }
    if expedienteJSON == nil {
        return nil, fmt.Errorf("el expediente académico %s no existe", id)
    }

    var expediente Expediente
    err = json.Unmarshal(expedienteJSON, &expediente)
    
    // Validación de Trazabilidad del Tipo de Documento CouchDB
    if expediente.DocType != "expediente" {
        return nil, fmt.Errorf("error de integridad: el documento localizado no corresponde al tipo expediente")
    }
    
    return &expediente, err
}

func (s *SmartContract) ExpedienteExiste(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
    expedienteJSON, err := ctx.GetStub().GetState(id)
    if err != nil {
        return false, err
    }
    return expedienteJSON != nil, nil
}