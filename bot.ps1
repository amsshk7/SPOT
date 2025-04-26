import discord
import json
import ccxt  # ✅ Required for Binance API (install using `pip install ccxt`)
import os
import asyncio
from flask import Flask, request

# ✅ Initialize Flask
app = Flask(__name__)

# ✅ Load environment variables securely
DISCORD_TOKEN = os.getenv("DISCORD_TOKEN")
DISCORD_CHANNEL_ID = int(os.getenv("DISCORD_CHANNEL_ID", "0"))
BINANCE_API_KEY = os.getenv("BINANCE_API_KEY")
BINANCE_SECRET = os.getenv("BINANCE_SECRET")

# ✅ Discord Bot Setup
intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

# ✅ Initialize Trade Log
trade_log = []

# ✅ Webhook Route - Handles TradingView Alerts
@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.json
        if not all(k in data for k in ["ticker", "side", "quantity"]):
            return {"error": "Invalid data format!"}, 400

        ticker, side, quantity = data["ticker"], data["side"].lower(), float(data["quantity"])

        if side not in ["buy", "sell"]:
            return {"error": "Invalid trade side! Must be 'buy' or 'sell'."}, 400

        trade_entry = f"{side.upper()} {quantity} {ticker}"
        trade_log.append(trade_entry)

        success = execute_trade(side, ticker, quantity)

        if success:
            asyncio.run_coroutine_threadsafe(send_trade_notification(trade_entry), client.loop)

        return {"status": "Trade executed"}, 200 if success else {"error": "Trade failed"}, 500

    except Exception as e:
        print(f"❌ Webhook error: {e}")
        return {"error": "Server error"}, 500

# ✅ Send Trade Details to Discord
async def send_trade_notification(message):
    if DISCORD_CHANNEL_ID:
        channel = client.get_channel(DISCORD_CHANNEL_ID)
        if channel:
            await channel.send(f"✅ Trade executed: {message}")
        else:
            print("❌ Discord channel not found!")

# ✅ Binance API Trade Execution
def execute_trade(side, ticker, quantity):
    try:
        exchange = ccxt.binance({
            'apiKey': BINANCE_API_KEY,
            'secret': BINANCE_SECRET,
        })

        balance = exchange.fetch_balance()
        quote_currency = "USDT"
        available_equity = balance[quote_currency]["free"]

        if quantity > available_equity:
            print(f"❌ Not enough balance: {available_equity} USDT")
            return False

        order = None
        if side == "buy":
            order = exchange.create_market_buy_order("DOGE/USDT", quantity)
        elif side == "sell":
            order = exchange.create_market_sell_order("DOGE/USDT", quantity)

        print(f"✅ {side.upper()} order placed: {order}")
        return True

    except ccxt.NetworkError as e:
        print(f"❌ Binance Network Error: {e}")
        return False
    except ccxt.ExchangeError as e:
        print(f"❌ Binance Exchange Error: {e}")
        return False

@client.event
async def on_ready():
    print(f"✅ Bot logged in as {client.user}")

@client.event
async def on_message(message):
    if message.author == client.user:
        return  # ✅ Ignore bot's own messages

    if message.content.lower() == "!last_trade":
        last_trade = trade_log[-1] if trade_log else "No trades recorded yet!"
        await message.channel.send(f"📌 Last Trade Entry: {last_trade}")

# ✅ Run Discord Bot
client.run(DISCORD_TOKEN)