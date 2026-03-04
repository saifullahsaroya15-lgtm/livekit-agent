# Self-hosted LiveKit + SIP on AWS EC2

This project deploys a **self-hosted LiveKit core server + SIP server** that:

- Is **publicly accessible** over HTTPS
- Can **receive inbound SIP calls**
- **Creates a LiveKit room** for each call
- **Dispatches the call to your existing agent** (you provide the agent; this stack only covers LiveKit core + SIP)

The SIP routing and dispatch behavior follows the LiveKit SIP docs and dispatch rules for agents \([inbound trunks][inbound-trunk-docs], [dispatch rules][dispatch-rule-docs], [telephony agents][agents-telephony-docs]\).

[inbound-trunk-docs]: https://docs.livekit.io/sip/trunk-inbound/
[dispatch-rule-docs]: https://docs.livekit.io/sip/dispatch-rule/
[agents-telephony-docs]: https://docs.livekit.io/agents/quickstarts/inbound-calls/

---

## 1. Architecture Overview

- **redis**: shared RPC/state bus between LiveKit core and SIP.
- **livekit**: the LiveKit core server (`livekit/livekit-server`).
- **sip**: LiveKit SIP server (`livekit/sip`) that terminates SIP and bridges it into LiveKit rooms.
- **caddy**: reverse proxy + automatic TLS via Let’s Encrypt, exposing LiveKit securely over `https://` and `wss://`.

SIP trunks (e.g., Twilio) connect to the **SIP service on port 5060**, and SIP dispatch rules create rooms and attach agents on inbound calls.

---

## 2. Files in this project

- `docker-compose.yml`: Base services (LiveKit, SIP, Redis) with **local-safe ports**.
- `docker-compose.local.yml`: Local overrides (exposes LiveKit on localhost).
- `docker-compose.prod.yml`: Production overrides (**Caddy TLS + required UDP port ranges**).
- `.env.example`: Template for required environment variables.
- `Caddyfile`: Caddy reverse-proxy and TLS configuration.
- `provision/inbound-trunk.example.json`: Sample inbound trunk config (phone number + constraints).
- `provision/dispatch-rule.example.json`: Sample dispatch rule mapping calls to rooms + agents.

---

## 3. Configure environment (.env)

Copy the example and edit:

```bash
cp .env.example .env
```

Set:

- **`LIVEKIT_PUBLIC_HOST`** – DNS name of your EC2 instance, e.g. `livekit.your-domain.com`.
- **`LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`** – API key/secret pair used by:
  - LiveKit server (to validate clients/agents).
  - SIP server (to talk to LiveKit).
  - **Your existing agent** (must be configured with the same key/secret and URL).
- **`ACME_EMAIL`** – Email for Let’s Encrypt.
- **Important**: `LIVEKIT_API_SECRET` must be **>= 32 characters** (LiveKit enforces this).

These correspond to LiveKit’s recommended env configuration \([server setup docs][server-setup-docs]\).

[server-setup-docs]: https://docs.livekit.io/home/self-hosting/server-setup/

---

## 4. Provisioning AWS EC2

1. **Create an EC2 instance**
   - OS: Ubuntu 22.04 LTS (recommended).
   - Instance type: at least `t3.medium` for non-trivial voice traffic.
   - Storage: 20 GB gp3 or higher.

2. **Assign a static IP**
   - Allocate an Elastic IP and attach it to the instance.

3. **Configure DNS**
   - In your DNS provider, create an `A` record:
     - Name: `livekit` (or whatever subdomain you want).
     - Value: the Elastic IP.
   - This must match `LIVEKIT_PUBLIC_HOST` in `.env`.

4. **Open required ports in the security group**

Open these inbound rules:

- **80/tcp** – HTTP (for Let’s Encrypt HTTP-01 challenge).
- **443/tcp** – HTTPS (Caddy → LiveKit).
- **7880/tcp, 7881/tcp** – (optional) direct LiveKit ports for debugging (can be closed in strict setups).
- **5060/tcp & 5060/udp** – SIP signaling.
- **10000-20000/udp** – SIP RTP media.
- **50000-60000/udp** – LiveKit WebRTC media.

### Production checklist (before you start)

- DNS `A` record for `LIVEKIT_PUBLIC_HOST` points to the server public IP
- Ports above are open **in cloud firewall + OS firewall**
- `LIVEKIT_API_SECRET` is **>= 32 chars**
- Your agent is configured to use:
  - `LIVEKIT_URL = wss://LIVEKIT_PUBLIC_HOST/`
  - same API key/secret
  - agent name matches `provision/dispatch-rule.example.json`

---

## 5. Install Docker & Docker Compose on EC2

SSH into the instance:

```bash
ssh ubuntu@livekit.your-domain.com
```

Install Docker (Ubuntu example):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
```

Log out and back in so the `ubuntu` user picks up Docker group membership.

---

## 6. Deploy this stack on EC2

1. **Copy project files to EC2**

   From your local machine:

   ```bash
   scp -r "Live Kit" ubuntu@livekit.your-domain.com:/opt/livekit
   ```

2. **Configure `.env` on EC2**

   ```bash
   cd /opt/livekit
   cp .env.example .env
   nano .env
   # set LIVEKIT_PUBLIC_HOST, LIVEKIT_API_KEY, LIVEKIT_API_SECRET, ACME_EMAIL
   ```

3. **Start the services**

   ```bash
   cd /opt/livekit
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   ```

4. **Verify**

   - Check containers:

     ```bash
     docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
     ```

   - Check Caddy logs (certificate + proxy):

     ```bash
     docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f caddy
     ```

   - Hit:
     - `https://LIVEKIT_PUBLIC_HOST/` → should return HTTP from LiveKit via Caddy.
     - `wss://LIVEKIT_PUBLIC_HOST/` → used by agents/clients.

---

## Local quickstart (Docker Desktop)

This is a **local sanity check** to ensure the containers start. It does **not** validate PSTN inbound SIP (that needs a public IP + open UDP ports).

1. Create a local env file:

```bash
cp .env.local.example .env
```

2. Start without Caddy (plain HTTP/WebSocket):

```bash
docker compose --env-file .env.local.example -f docker-compose.yml -f docker-compose.local.yml up -d
docker compose --env-file .env.local.example -f docker-compose.yml -f docker-compose.local.yml ps
```

3. Quick checks:

- LiveKit should listen on `http://localhost:7880`
- SIP service health should be reachable from inside the container network (see logs if needed):

```bash
docker compose --env-file .env.local.example -f docker-compose.yml -f docker-compose.local.yml logs -f livekit
docker compose --env-file .env.local.example -f docker-compose.yml -f docker-compose.local.yml logs -f sip
```

---

## 7. Configure SIP trunk and dispatch

Follow LiveKit’s SIP docs for **self-hosting the SIP server** \([SIP server docs][sip-server-docs]\) and **inbound trunks & dispatch rules** \([inbound-trunk-docs][inbound-trunk-docs], [dispatch-rule-docs][dispatch-rule-docs]\).

[sip-server-docs]: https://docs.livekit.io/home/self-hosting/sip-server/

### 7.0. Install and configure `lk` CLI (on the server)

Install:

```bash
curl -sSL https://get.livekit.io/cli | bash
```

Configure the CLI to talk to your LiveKit:

```bash
export LIVEKIT_URL="https://$LIVEKIT_PUBLIC_HOST"
export LIVEKIT_API_KEY="..."
export LIVEKIT_API_SECRET="..."
```

Then verify:

```bash
lk --help
```

### 7.1. Inbound trunk

- Edit `provision/inbound-trunk.example.json` and fill in:
  - Your **PSTN or SIP phone number**.
  - Any provider-specific metadata you want to store.
- Create the trunk using the `lk` CLI (recommended, repeatable):

```bash
lk sip inbound create provision/inbound-trunk.example.json
```

The `lk` CLI uses your LiveKit URL and API key/secret (same ones your agent uses).

### 7.2. Dispatch rule (room + agent)

- Edit `provision/dispatch-rule.example.json`:
  - `roomPrefix`: prefix to apply to auto-created rooms, e.g. `sip-call-`.
  - `agentName`: **must match the name of your deployed agent**.

Example call (HTTP):

```bash
lk sip dispatch create provision/dispatch-rule.example.json
```

Once the dispatch rule is in place, inbound calls that match the trunk will:

1. **Create a LiveKit room** with the given prefix.
2. Add the SIP caller as a participant.
3. **Dispatch the configured agent** (`agentName`) into the room, using the same LiveKit API key/secret and `wss://LIVEKIT_PUBLIC_HOST/` URL.

### 7.3. Verify end-to-end (production)

1. Confirm services are up:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

2. Confirm Caddy got a certificate and is proxying:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f caddy
```

3. Place an inbound call from your SIP provider to the configured number.

4. Watch SIP logs for the room name / participant join:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f sip
```

If the call reaches SIP but you get one-way/no audio, it’s almost always missing UDP ranges (RTP 10000-20000 or WebRTC 50000-60000) or the server is advertising the wrong public IP (set `LIVEKIT_RTC_NODE_IP` explicitly).

---

## 8. Point your existing agent to this LiveKit

Your agent (for example the LiveKit SIP agent example at `livekit-examples/livekit-sip-agent-example` \([GitHub repo][sip-agent-example]\)) should be configured with:

- `LIVEKIT_URL = wss://LIVEKIT_PUBLIC_HOST/`
- `LIVEKIT_API_KEY = LIVEKIT_API_KEY` (from `.env`)
- `LIVEKIT_API_SECRET = LIVEKIT_API_SECRET` (from `.env`)
- Agent name matching `agentName` in `provision/dispatch-rule.example.json`.

[sip-agent-example]: https://github.com/livekit-examples/livekit-sip-agent-example.git

This aligns with LiveKit’s telephony integration flow for agents \([agents telephony docs][agents-telephony-docs]\).

---

## 9. Acceptance Criteria mapping

- **Inbound SIP call reaches LiveKit server**  
  - Achieved by exposing SIP on `5060/tcp,udp` and pointing your SIP trunk provider at your EC2 public IP / domain.
- **Room is automatically created**  
  - Achieved by the SIP **dispatch rule** with `dispatchRuleIndividual.roomPrefix` (see `dispatch-rule.example.json` and [dispatch docs][dispatch-rule-docs]).
- **Call is dispatched to existing agent**  
  - Achieved by `roomConfig.agents[].agentName` referencing your agent’s name, per the [telephony integration docs][agents-telephony-docs].
- **Deployment and configuration docs**  
  - This README plus the sample configs provide the end-to-end guide for AWS EC2 deployment and LiveKit/SIP configuration.

#   l i v e k i t - a g e n t  
 