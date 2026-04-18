FROM nginx:alpine

# Copy the Mission Control app
COPY app/index.html /usr/share/nginx/html/index.html

# Copy custom nginx config for health check support
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Healthcheck — used by both ECS and EKS
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
