# ==========================================
# Example Dockerfile for a Node.js Agent
# Replace with Python/Go base image if needed
# ==========================================
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies needed for node-gyp and LiveKit native bindings
RUN apk add --no-cache python3 make g++

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies for build)
RUN npm install

# Copy application source
COPY . .

# Build application (if using TypeScript or a bundler)
# RUN npm run build

# ==========================================
# Production Image
# ==========================================
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm install --omit=dev

# Copy compiled source from builder (or source code if not building)
# COPY --from=builder /app/dist ./dist
# If no build step, just copy the source code:
COPY . .

# Expose any necessary ports (usually agents don't need inbound ports unless they expose a health check)
EXPOSE 8080

# Environment variables
ENV NODE_ENV=production

# Command to start the agent
# Adjust to `npm start` or the specific entry point for your agent
CMD ["node", "index.js"]
