FROM ruby:3.2-alpine AS builder

# Install build dependencies
RUN apk add --no-cache postgresql-dev build-base git

# Set working directory
WORKDIR /app

# Copy Gemfile for dependency installation
COPY Gemfile Gemfile.lock* ./
COPY bin/ bin/

# Install dependencies 
RUN bundle config set --local without 'development test' && \
    bundle install

# Copy the model_context_protocol gem code
COPY model_context_protocol/lib/ /app/lib/

# Copy the application code
COPY server.rb ./

FROM ruby:3.2-alpine

# Install runtime dependencies
RUN apk add --no-cache libpq

# Copy gems from builder stage
COPY --from=builder /usr/local/bundle/ /usr/local/bundle/

# Copy application from builder stage
COPY --from=builder /app /app

# Set working directory
WORKDIR /app

# Set database connection to use local database
ENV DATABASE_URL="postgresql://chadbuehrle:@host.docker.internal:5432/sample_Db"

# Make the server script executable
RUN chmod +x server.rb
RUN chmod +x bin/*

# Run the server
CMD ["ruby", "server.rb"]
