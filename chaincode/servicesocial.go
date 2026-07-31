package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// IniciarServicioSocial registra el inicio del servicio social
// sin modificar el estado administrativo del expediente.
func (s *SmartContract) IniciarServicioSocial(
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

	// Validar estado actual
	if expediente.EstadoActual != EstadoEgresado {
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

	// Registrar evidencia
	agregarEvidencia(
		expediente,
		EvServicioSocialIniciado,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}

// LiberarServicioSocial registra la liberación del servicio social
// sin modificar el estado administrativo del expediente.
func (s *SmartContract) LiberarServicioSocial(
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

	// Validar estado actual
	if expediente.EstadoActual != EstadoEgresado {
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

	// Registrar evidencia
	agregarEvidencia(
		expediente,
		EvServicioSocialLiberado,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
