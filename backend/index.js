exports.handler = async (event) => {
    return {
        statusCode: 200,
        headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        body: JSON.stringify({
            message: "API Serverless funcionando correctamente desde AWS Lambda",
            database_configured: !!process.env.DATABASE_URL,
            jwt_configured: !!process.env.JWT_SECRET,
            timestamp: new Date().toISOString()
        })
    };
};