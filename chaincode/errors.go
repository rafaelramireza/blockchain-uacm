package main

import "errors"

var (
	// Errores de validación
	ErrIDVacio   = errors.New("el identificador del expediente es obligatorio")
	ErrHashVacio = errors.New("el hash de la evidencia es obligatorio")

	// Errores de negocio
	ErrExpedienteNoExiste = errors.New("el expediente no existe")
)
