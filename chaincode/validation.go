package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// ValidarDocumentos registra la validación documental del expediente
// y realiza la transición de INSCRITO a DOC_VALIDADO.
func (s *SmartContract) ValidarDocumentos(
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

	// Validar estado actual
	if expediente.EstadoActual != EstadoInscrito {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgRegistro {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia de la validación documental
	agregarEvidencia(
		expediente,
		EstadoInscrito,
		EvValidacionDocumental,
		EstadoDocValidado,
		msp,
		timestamp,
		txID,
	)

	// La validación documental no confirma todavía el estado ACTIVO.
	// El expediente queda en DOC_VALIDADO.
	expediente.EstadoActual = EstadoDocValidado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
