import aiohttp_socks as asocks
import asyncio, os, json
import time, argparse, aiofiles

# --- configuration ---
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 5050
LOG_PATH = r"relay_log.txt"
MAX_ROUTE_LEN = 8
SAFE_MODE = False
ALLOWED_HOSTS = ["127.0.0.1", "localhost", ".onion"]
MAX_LOG_SIZE = 2_000_000
BACKUP_COUNT = 3

# --- helper functions ---

async def rotate_logs_if_needed():
    try:
        oldest = f"{LOG_PATH}.{BACKUP_COUNT}"
        if os.path.exists(oldest):
            os.remove(oldest)

        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG_SIZE:
            for i in range(BACKUP_COUNT - 1, 0, -1):
                older = f"{LOG_PATH}.{i}"
                newer = f"{LOG_PATH}.{i+1}"
                if os.path.exists(older):
                    os.rename(older, newer)
            os.rename(LOG_PATH, f"{LOG_PATH}.1")
    except Exception:
        print("[LOG ROTATE ERROR]")

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def parse_hostport(s: str):
    try:
        onion_route, port = s.rsplit(":", 1)
        return onion_route, int(port)
    except Exception:
        return None, None

async def log_event(line: str):
    try:
        await rotate_logs_if_needed()
        async with aiofiles.open(LOG_PATH, "a", encoding="utf-8") as f:
            await f.write(f"{now_iso()} {line}\n")
    except:
        print("[LOG ERROR]")

# --- async Relay Core ---
class RelayXAsync:
    def __init__(self, host=LISTEN_HOST, port=LISTEN_PORT, safe_mode=SAFE_MODE):
        self.host = host
        self.port = port
        self.safe_mode = safe_mode

    async def start(self):
        server = await asyncio.start_server(self._handle_conn, self.host, self.port)
        addr = server.sockets[0].getsockname()
        async with server:
            await server.serve_forever()

    async def _forward_to_next(self, onion_route, port, envelope):
        try:
            await log_event(onion_route)
            reader, writer = await asocks.open_connection(proxy_host="127.0.0.1",
                proxy_port=9050,
                host=onion_route,
                port=port
                )  # asocks is the name of aiohttp-socks
            writer.write((json.dumps(envelope) + "\n").encode())
            await writer.drain()
            await asyncio.sleep(0.05)
            writer.close()
            await writer.wait_closed()
            return True
        except Exception as e:
            await log_event("CONNECT_FAIL")
            return False


    async def _handle_conn(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            data = await asyncio.wait_for(reader.read(65536), timeout=5.0)
        except asyncio.TimeoutError:
            await log_event("TIMEOUT")
            writer.close()
            await writer.wait_closed()
            return

        if not data:
            writer.close()
            await writer.wait_closed()
            return

        try:
            envelope = json.loads(data.decode())
        except Exception as e:
            await log_event("BAD_JSON")
            writer.close()
            await writer.wait_closed()
            return

        route = envelope.get("route", [])
        payload = envelope.get("payload")
        from_id = envelope.get("from", "unknown")
        to_id = envelope.get("to", "unknown")

        if not isinstance(route, list):
            await log_event("BAD_ROUTE_FORMAT")
            return

        if len(route) > MAX_ROUTE_LEN:
            await log_event("ROUTE_TOO_LONG")
            return

        if len(route) == 0:
            await log_event("FINAL_DROP")
            return

        next_hop = route.pop(0)
        next_hop = next_hop.strip().replace("\n", "").replace("\r", "")
        onion_route, port = parse_hostport(next_hop)
        if onion_route is None or port is None:
            await log_event("INVALID_HOP")
            return

        if self.safe_mode and not onion_route.endswith(".onion"):
            await log_event("REJECT_FORWARD (not allowed in safe mode)")
            return

        envelope["route"] = route

        ok = await self._forward_to_next(onion_route, port, envelope)
        if ok:
            await log_event("FORWARDED")
        else:
            await log_event("FORWARD_FAILED")



# --- stuff showing up in the CLI ---
def parse_args():
    p = argparse.ArgumentParser(description="Relay Async - multi-hop forwarder")
    p.add_argument("--host", default=LISTEN_HOST)
    p.add_argument("--port", type=int, default=LISTEN_PORT)
    p.add_argument("--safe", action="store_true")
    p.add_argument("--log", action="store_true")
    p.add_argument("--allow", action="append")
    return p.parse_args()

async def main():
    global LOG_ENABLED, SAFE_MODE, ALLOWED_HOSTS
    args = parse_args()
    LOG_ENABLED = args.log
    SAFE_MODE = args.safe
    if args.allow:
        ALLOWED_HOSTS += args.allow

    relay = RelayXAsync(args.host, args.port, SAFE_MODE)
    await relay.start()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[RELAY_X ASYNC] Shutting down.")