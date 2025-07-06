import os
import json
import asyncio
import logging

from fastapi import FastAPI
from dotenv import load_dotenv
from paho.mqtt.client import Client
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.exc import SQLAlchemyError
from models import Base, Command  # Ensure models.py has Command with `name`, `raw_timings`, `learned_at`
from fastapi.responses import JSONResponse

# Load .env variables
load_dotenv()
DATABASE_URL = os.getenv("DB_URL")
MQTT_HOST = os.getenv("MQTT_HOST")
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASS = os.getenv("MQTT_PASS")

# Setup FastAPI app
app = FastAPI()

# Setup event loop
loop = asyncio.get_event_loop()

# Setup database
engine = create_async_engine(DATABASE_URL, echo=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

# Setup MQTT client
mqttc = Client("ir-backend")
mqttc.username_pw_set(MQTT_USER, MQTT_PASS)


# ----- MQTT CALLBACKS -----

def on_connect(client, userdata, flags, rc):
    print("[MQTT] Connected with result code", rc)
    topics = ["home/ac/save", "home/ac/list", "home/ac/erase_all","home/ac/delete_one", "home/ac/rename" ]
    for topic in topics:
        client.subscribe(topic)
        print(f"[MQTT] Subscribed to: {topic}")

def on_message(client, userdata, msg):
    try:
        payload = msg.payload.decode()
        print(f"[MQTT DEBUG] Topic: {msg.topic}")
        print(f"[MQTT DEBUG] Payload: {payload}")

        if msg.topic == "home/ac/save":
            data = json.loads(payload)
            name = data["name"]
            timings = data["timings"]

            print(f"[MQTT] Received save command: {name}, timings length = {len(timings)}")
            loop.create_task(store_command(name, timings))
            loop.create_task(republish_commands())

        elif msg.topic == "home/ac/list":
            loop.create_task(republish_commands())

        elif msg.topic == "home/ac/erase_all":
            loop.create_task(erase_all_commands())
        elif msg.topic == "home/ac/delete_one":
            loop.create_task(delete_command(json.loads(payload)["name"]))
        elif msg.topic == "home/ac/rename":
            loop.create_task(rename_command(json.loads(payload)))



    except Exception as e:
        logging.error(f"[MQTT ERROR] Failed to process message: {e}")


# ----- DATABASE ACTIONS -----

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        print("[DB] Initialized")

async def store_command(name: str, timings: list):
    try:
        async with SessionLocal() as session:
            async with session.begin():
                stmt = pg_insert(Command).values(
                    name=name,
                    raw_timings=timings
                ).on_conflict_do_update(
                    index_elements=["name"],
                    set_={
                        "raw_timings": timings,
                        "learned_at": func.now()
                    }
                )
                await session.execute(stmt)
                print(f"[DB] Stored/Updated command: {name}")
    except SQLAlchemyError as e:
        logging.error(f"[DB ERROR] Failed to store command: {e}")

async def republish_commands():
    try:
        async with SessionLocal() as session:
            result = await session.execute(select(Command))
            commands = result.scalars().all()
            payload = {cmd.name: cmd.raw_timings for cmd in commands}
            mqttc.publish("home/ac/available_cmds", json.dumps(payload))
            print(f"[MQTT] Published {len(payload)} commands")
    except Exception as e:
        logging.error(f"[MQTT ERROR] Failed to republish: {e}")

async def erase_all_commands():
    try:
        async with SessionLocal() as session:
            async with session.begin():
                await session.execute(Command.__table__.delete())
                print("[DB] ❌ All commands erased")
            await republish_commands()
    except Exception as e:
        logging.error(f"[DB ERROR] Erase all failed: {e}")

@app.get("/commands")
async def get_all_commands():
    async with SessionLocal() as session:
        result = await session.execute(select(Command))
        commands = result.scalars().all()
        return JSONResponse(content={
            "commands": [
                {"name": cmd.name, "timings": cmd.raw_timings}
                for cmd in commands
            ]
        })
async def delete_command(name: str):
    try:
        async with SessionLocal() as session:
            async with session.begin():
                await session.execute(
                    Command.__table__.delete().where(Command.name == name)
                )
                print(f"[DB] Deleted command: {name}")
        await republish_commands()
    except Exception as e:
        logging.error(f"[DB ERROR] Failed to delete {name}: {e}")
async def rename_command(data):
    try:
        old_name = data["old_name"]
        new_name = data["new_name"]
        

        async with SessionLocal() as session:
            async with session.begin():
                # Fetch existing command
                cmd = await session.get(Command, old_name)
                if not cmd:
                    print(f"[DB] Command '{old_name}' not found for rename")
                    return

                # Update name
                cmd.name = new_name
                await session.flush()
                print(f"[DB] Renamed '{old_name}' → '{new_name}'")

        await republish_commands()

    except Exception as e:
        logging.error(f"[DB ERROR] Rename failed: {e}")



# ----- FASTAPI STARTUP -----

@app.on_event("startup")
async def startup_event():
    await init_db()
    mqttc.on_connect = on_connect
    mqttc.on_message = on_message
    mqttc.connect(MQTT_HOST, 1883)
    mqttc.loop_start()
    print("[APP] FastAPI + MQTT ready.")
