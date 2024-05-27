if (
    secrets.alpacaKey = "" ||
    secrets.alpacaSecret == ""
) {
    throw Error("Need Alpaca Key")
}
const alpacaRequest = Functions.makeHttpRequest({
    url: "https://paper-api.alpaca.markets/v2/account",
    headers: {
        accept: "application/json",
        'APCA-API-KEY-ID': secrets.alpacaKey,
        'APCA-API-SECRET_KEY': secrets.alpacaSecret
    }
})

const [response] = await Promise.all([alpacaRequest])
const portfolioBalance = response.data.portfolio_value
console.log('Alpaca Portfolio Balance: $${portfolioBalance}')

return Functions.encodeUint256(Math.round(portfolioBalance * 100))