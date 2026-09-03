package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// ConfirmarActivo registra la confirmación del estado ACTIVO
// y realiza la transición de DOC_VALIDADO a ACTIVO.
func (s *SmartContract) ConfirmarActivo(
	ctx contractapi.TransactionContextInterface,
	id string,
	hash string,
) error {

	// Validar parámetros
	if id == "" {
		return ErrIDVacio
	}

	if hash == "" {
		return ErrHashVacio
	}

	// Obtener expediente
	expediente, err := s.obtenerExpediente(ctx, id)
	if err != nil {
		return err
	}

	// La confirmación del estado ACTIVO solo puede realizarse
	// cuando el expediente está en DOC_VALIDADO.
	if expediente.EstadoActual != EstadoDocValidado {
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

	// Registrar evidencia de confirmación de ACTIVO
	agregarEvidencia(
		expediente,
		EvActivoConfirmado,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Realizar la transición
	expediente.EstadoActual = EstadoActivo

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
