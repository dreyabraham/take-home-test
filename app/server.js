const http = require("http");

const PORT = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  if (req.url === "/ready") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ready" }));
    return;
  }

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ message: "myapp-api is running" }));
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});