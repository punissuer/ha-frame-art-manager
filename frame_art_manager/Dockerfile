ARG BUILD_FROM
FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Node.js dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    python3 \
    make \
    g++ \
    jq

# Set working directory
WORKDIR /app

# Copy package files
COPY app/package*.json ./

# Install Node dependencies
RUN npm ci --only=production

# Copy application files
COPY app/ ./

# Create run script
COPY run.sh /
RUN chmod a+x /run.sh

# Expose port
EXPOSE 8099

# Run the add-on
CMD [ "/run.sh" ]
