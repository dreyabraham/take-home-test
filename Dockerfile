FROM node:20-alpine AS builder

WORKDIR /app
COPY app/server.js .

# Final stage — distroless has no shell, no package manager, minimal attack surface
FROM gcr.io/distroless/nodejs20-debian12

WORKDIR /app
COPY --from=builder /app/server.js .

EXPOSE 8080

CMD ["server.js"]