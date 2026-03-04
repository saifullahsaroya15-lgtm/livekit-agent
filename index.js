// Dummy LiveKit Agent
console.log("LiveKit Agent Starting...");

// Keeps the Node.js process alive so the Docker container doesn't exit immediately
setInterval(() => {
  console.log("Agent is running...");
}, 60000);
