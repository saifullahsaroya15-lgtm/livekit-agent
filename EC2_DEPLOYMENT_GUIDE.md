# LiveKit + SIP Server Deployment Guide

This guide details the final manual steps required to launch your self-hosted LiveKit and SIP server on AWS EC2, and correctly route inbound SIP calls to your deployed agent.

Since sensitive credentials and domain information were not provided to the automated agent, please follow these steps to securely configure and deploy your infrastructure.

## Step 1: Prepare AWS EC2
1. Deploy an **Ubuntu 22.04 LTS** EC2 instance (e.g. `t3.medium`).
2. Attach an **Elastic IP** to the instance.
3. Configure your AWS Security Group to allow inbound traffic on:
   - `80` (TCP) - Let's Encrypt Automated HTTP-01 Challenges
   - `443` (TCP) - HTTPS (Caddy -> LiveKit)
   - `7880` (TCP) - LiveKit Web Socket/API Port
   - `5060` (UDP/TCP) - SIP Signaling from Provider
   - `10000 - 20000` (UDP) - Media (RTP)
   - `50000 - 60000` (UDP) - WebRTC (for Agents and Web Clients)

## Step 2: Configure Domain
In your DNS registrar (e.g. Route53, GoDaddy, Cloudflare), create an `A` record pointing to the EC2 Elastic IP address (e.g., `livekit.yourdomain.com`). Let's Encrypt requires this domain to be active to generate the SSL certificate.

## Step 3: Set GitHub Secrets for CI/CD Pipeline
In this repository, go to **Settings -> Secrets and variables -> Actions -> Repository secrets** and add:
- `HOST`: Your EC2 Elastic Public IP.
- `USERNAME`: Default for Ubuntu is `ubuntu`.
- `SSH_PRIVATE_KEY`: Your `.pem` SSH Private key to access the EC2 instance.

## Step 4: Configure Production `.env`
On the EC2 instance (or using GitHub Secrets if you prefer), create the `/opt/livekit/.env` file. You can base this off `.env.example`.

Ensure the following variables are set:
```bash
LIVEKIT_PUBLIC_HOST=livekit.yourdomain.com
LIVEKIT_API_KEY=your_deployed_agent_api_key
LIVEKIT_API_SECRET=your_deployed_agent_api_secret  # MUST BE >= 32 Characters
ACME_EMAIL=your-email@yourdomain.com
LIVEKIT_RTC_USE_EXTERNAL_IP=true
```
*(The `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` must be the exact same values your deployed agent uses to connect to LiveKit)*.

## Step 5: Trigger the Deployment Pipeline
Push any changes to the `main` branch or manually execute the **"Deploy LiveKit to EC2"** GitHub Action under the Actions tab.

This pipeline will SSH into your server, sync the configuration files, and execute `docker compose up -d`, launching:
- **Redis**
- **LiveKit Server**
- **LiveKit SIP Server**
- **Caddy (Reverse Proxy + TLS)**

## Step 6: Configure SIP Routing Rules
Once the stack is running, you must provision the LiveKit SIP trunk and Dispatch Rules so LiveKit knows what to do when your SIP Provider sends a call.

Install the LiveKit CLI (`lk`) locally or on your EC2 instance:
```bash
curl -sSL https://get.livekit.io/cli | bash
```

Export your credentials so the CLI can authenticate:
```bash
export LIVEKIT_URL="https://livekit.yourdomain.com"
export LIVEKIT_API_KEY="your_api_key"
export LIVEKIT_API_SECRET="your_api_secret"
```

### 1. Create the Trunk
Edit `provision/inbound-trunk.example.json` and replace the array under `numbers` with your actual SIP phone number (e.g., `["+15551234567"]`). 

Then run:
```bash
lk sip inbound create provision/inbound-trunk.example.json
```

### 2. Create the Dispatch Rule
Edit `provision/dispatch-rule.example.json` and ensure `"agentName": "..."` matches the exact name that your deployed agent registers with when it starts up.

Then run:
```bash
lk sip dispatch create provision/dispatch-rule.example.json
```

## Step 7: Verification
1. Call your configured SIP phone number.
2. View the logs on the server using `docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f sip`.
3. You should see a new LiveKit room (e.g., `sip-call-***`) automatically created, and the agent should join the room.
