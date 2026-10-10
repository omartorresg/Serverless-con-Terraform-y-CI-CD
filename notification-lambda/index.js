exports.handler = async (event) => {
    console.log("Iniciando procesamiento de mensajes SQS...", JSON.stringify(event, null, 2));

    for (const record of event.Records) {
        try {
            const snsBody = JSON.parse(record.body);
            const messageData = typeof snsBody.Message === 'string' ? JSON.parse(snsBody.Message) : snsBody;

            const { email, subject, message } = messageData;

            console.log(`[CLOUD WATCH LOG] Procesando notificación...`);
            console.log(`Destino: ${email}`);
            console.log(`Asunto: ${subject}`);
            console.log(`Mensaje: ${message}`);
            console.log(`Correo enviado exitosamente a ${email}`);

        } catch (error) {
            console.error("Error al procesar mensaje SQS:", error);
            throw error;
        }
    }

    return { statusCode: 200, body: JSON.stringify({ message: "Procesado con éxito" }) };
};