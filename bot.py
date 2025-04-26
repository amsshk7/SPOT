import threading
import configparser
import discord
import asyncio  
from binance.client import Client
from flask import Flask, request, jsonify

# Load config file
config = configparser.ConfigParser()
config.read("config.ini")

# Binance API setup
binance_client = Client(config["binance"]["api_key"], config["binance"]["api_secret"])

# Discord bot setup
intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

@client.event
async def on_ready():
    print(f'Logged in as {client.user}')

@client.event
async def on_message(message):
    if message.author == client.user:
        return  # Ignore bot’s own messages

    if message.content.lower() == "price":
        ticker = "DOGEUSDT"  # ✅ Updated default trading pair
        price = binance_client.get_symbol_ticker(symbol=ticker)["price"]
        await message.channel.send(f"Current {ticker} price: ${price}")

    elif message.content.lower() == "!info":
        await message.channel.send("I am a Binance trading bot! Send 'price' to get the latest DOGE price.")

# Webhook listener for TradingView alerts
app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    print(f"Received TradingView alert: {data}")  # ✅ Debugging log

    if "ticker" in data and "side" in data and "quantity" in data:
        if data["ticker"] != "DOGEUSDT":
            return jsonify({"error": "Incorrect trading pair, only DOGEUSDT allowed"})  # ✅ Restrict trading pair

        try:
            if data["side"] == "buy":
                order = binance_client.order_market_buy(symbol=data["ticker"], quantity=float(data["quantity"]))
            elif data["side"] == "sell":
                order = binance_client.order_market_sell(symbol=data["ticker"], quantity=float(data["quantity"]))

            # ✅ Log trade
            log_trade(order)
            
            # ✅ Notify Discord using `asyncio.create_task` instead of `asyncio.run()`
            discord_channel_id = 1364563657098526721  # Replace with your actual channel ID
            loop = asyncio.get_event_loop()
            loop.create_task(send_trade_notification(order, discord_channel_id))

            return jsonify({"status": "order executed", "order": order})
        except Exception as e:
            print(f"❌ Binance API Error: {e}")
            return jsonify({"error": str(e)})
    else:
        return jsonify({"error": "Invalid JSON format"})

def log_trade(order_data):
    """Log executed trades to a file."""
    with open("trade_log.txt", "a") as log_file:
        log_file.write(f"Order executed: {order_data}\n")

async def send_trade_notification(order_data, channel_id):
    """Send trade execution notifications to Discord."""
    channel = client.get_channel(channel_id)
    if not channel:
        print("❌ Discord channel not found. Double-check the ID.")
        return
    await channel.send(f"✅ Trade executed: {order_data}")

# ✅ Run Flask & Discord bot simultaneously using a daemon thread
def run_flask():
    app.run(host="0.0.0.0", port=80)

flask_thread = threading.Thread(target=run_flask, daemon=True)
flask_thread.start()

client.run(config["discord"]["token"])