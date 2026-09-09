package main

import "errors"

var (
	// Errores de validación
	ErrIDVacio   = errors.New("el identificador del expediente es obligatorio")

	// Errores de negocio
	ErrExpedienteNoExiste = errors.New("el expediente no existe")
	ErrEstadoInvalido     = errors.New("el expediente no se encuentra en un estado válido para esta operación")
	ErrMSPNoAutorizado    = errors.New("la organización no está autorizada para ejecutar esta operación")

	ErrCertificadoPendiente    = errors.New("el certificado aún no ha sido registrado")
	ErrServicioSocialPendiente = errors.New("el servicio social aún no ha sido liberado")

	ErrTransicionNoExiste        = errors.New("la transición indicada no existe")
	ErrTransicionYaRectificada   = errors.New("la transición indicada ya fue rectificada")
	ErrRectificacionNoAutorizada = errors.New("la organización no está autorizada para rectificar esta transición")
	ErrTransicionNoRectificable  = errors.New("la transición no puede ser rectificada porque existen operaciones posteriores")
)
