package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// EmitirCertificado registra la emisión del Certificado de Terminación
// de Estudios y realiza la transición a CERTIFICADO desde ACTIVO
// o SS_LIBERADO.
func (s *SmartContract) EmitirCertificado(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {

	// Validar parámetros
	if id == "" {
		return ErrIDVacio
	}

	// Obtener expediente
	expediente, err := s.obtenerExpediente(ctx, id)
	if err != nil {
		return err
	}

	// El certificado puede emitirse desde ACTIVO o cuando
	// el servicio social ya fue liberado.
	if expediente.EstadoActual != EstadoActivo &&
		expediente.EstadoActual != EstadoSSLiberado {
		return ErrEstadoInvalido
	}

	// El certificado solo puede estar vigente una vez.
	// Si una emisión anterior fue rectificada, puede volver a emitirse.
	if existeTransicionVigente(expediente, EvCertificadoEmitido) {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgCertificacion {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia
	agregarEvidencia(
		expediente,
		expediente.EstadoActual,
		EvCertificadoEmitido,
		EstadoCertificado,
		msp,
		timestamp,
		txID,
	)

	// Transición ACTIVO/SS_LIBERADO → CERTIFICADO.
	expediente.EstadoActual = EstadoCertificado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)

}
