'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class MyWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        // Caliper usa workerIndex para separar el trabajo entre sus hilos de ejecución
        const alumnoID = `ALUMNO${this.workerIndex}_${this.txIndex}`;
        const hashTitulo = `HASH_TITULO_AUDITADO_${this.txIndex}`;

        const request = {
            contractId: 'uacm-contract',
            contractFunction: 'TitularAlumno',
            invokerIdentity: '_Org2MSP_User1',
            contractArguments: [alumnoID, hashTitulo],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new MyWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;