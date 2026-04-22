package main

import (
	"log"
	"uacm-egreso/chaincode"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

func main() {
	assetChaincode, err := contractapi.NewChaincode(&chaincode.SmartContract{})
	if err != nil {
		log.Panicf("Error al crear el chaincode de la UACM: %v", err)
	}

	if err := assetChaincode.Start(); err != nil {
		log.Panicf("Error al iniciar el chaincode de la UACM: %v", err)
	}
}
